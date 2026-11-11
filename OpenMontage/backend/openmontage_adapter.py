from __future__ import annotations

import json
import logging
import shutil
import subprocess
from pathlib import Path
from typing import Any

from tools.video.video_trimmer import VideoTrimmer

logger = logging.getLogger(__name__)


class AdapterError(ValueError):
    """A safe, client-displayable OpenMontage tool error."""


class AdapterUnavailable(AdapterError):
    """A required local runtime executable is not configured on this host."""


def probe_video(path: Path) -> tuple[float, dict[str, Any]]:
    """Validate a media file and return duration plus safe technical metadata."""
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        raise AdapterUnavailable("FFprobe is not installed on the backend host.")
    try:
        result = subprocess.run(
            [ffprobe, "-v", "error", "-show_entries",
             "format=duration,format_name:stream=codec_type,codec_name,width,height",
             "-of", "json", str(path)],
            check=True, capture_output=True, text=True, timeout=30,
        )
        data = json.loads(result.stdout)
        duration = float(data.get("format", {}).get("duration", 0))
        if duration <= 0 or not any(s.get("codec_type") == "video" for s in data.get("streams", [])):
            raise AdapterError("The uploaded file does not contain a valid video stream.")
        return duration, {
            "format": data.get("format", {}).get("format_name"),
            "streams": data.get("streams", []),
        }
    except AdapterError:
        raise
    except (OSError, subprocess.SubprocessError, ValueError, json.JSONDecodeError) as exc:
        logger.warning("Input media probe failed: %s", exc)
        raise AdapterError("The uploaded file could not be read as a video.") from exc


def probe_audio(path: Path) -> tuple[float, dict[str, Any]]:
    """Validate an audio file and return duration plus safe technical metadata."""
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        raise AdapterUnavailable("FFprobe is not installed on the backend host.")
    try:
        result = subprocess.run(
            [ffprobe, "-v", "error", "-show_entries",
             "format=duration,format_name:stream=codec_type,codec_name,sample_rate,channels",
             "-of", "json", str(path)],
            check=True, capture_output=True, text=True, timeout=30,
        )
        data = json.loads(result.stdout)
        duration = float(data.get("format", {}).get("duration", 0))
        if duration <= 0 or not any(s.get("codec_type") == "audio" for s in data.get("streams", [])):
            raise AdapterError("The uploaded file does not contain a valid audio stream.")
        return duration, {
            "format": data.get("format", {}).get("format_name"),
            "streams": data.get("streams", []),
        }
    except AdapterError:
        raise
    except (OSError, subprocess.SubprocessError, ValueError, json.JSONDecodeError) as exc:
        logger.warning("Input audio probe failed: %s", exc)
        raise AdapterError("The uploaded file could not be read as audio.") from exc


def probe_image(path: Path) -> tuple[None, dict[str, Any]]:
    """Validate a raster image with Pillow and return safe dimensions/format."""
    try:
        from PIL import Image

        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            width, height = image.size
            image_format = image.format
        if width <= 0 or height <= 0 or width * height > 100_000_000:
            raise AdapterError("The image dimensions are invalid or exceed the 100-megapixel limit.")
        return None, {"format": image_format.lower() if image_format else None, "width": width, "height": height}
    except AdapterError:
        raise
    except ImportError as exc:
        raise AdapterUnavailable("Pillow is required to validate image uploads.") from exc
    except Exception as exc:
        logger.warning("Input image probe failed: %s", exc)
        raise AdapterError("The uploaded file could not be read as a valid image.") from exc


def trim_video(*, input_path: Path, output_path: Path, start: float, end: float) -> dict[str, Any]:
    """Map the mobile trim operation to OpenMontage's actual VideoTrimmer schema.

    The tool calls its executable operation `cut`; this API intentionally keeps
    the user-facing operation name `trim` and performs the explicit translation here.
    """
    if shutil.which("ffmpeg") is None:
        raise AdapterUnavailable("FFmpeg is not installed on the backend host.")
    input_path = input_path.resolve(strict=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result = VideoTrimmer().execute({
        "operation": "cut",
        "input_path": str(input_path),
        "output_path": str(output_path.resolve()),
        "start_seconds": start,
        "end_seconds": end,
        "codec": "libx264",
    })
    if not result.success:
        logger.warning("OpenMontage video_trimmer failed: %s", result.error)
        raise AdapterError("OpenMontage could not trim this video. Check the video and trim range.")
    if not output_path.is_file() or output_path.stat().st_size == 0:
        raise AdapterError("OpenMontage reported success but produced no video artifact.")
    duration, metadata = probe_video(output_path)
    return {
        "path": str(output_path.resolve()),
        "duration": duration,
        "metadata": metadata,
        "tool": "video_trimmer",
        "operation": "cut",
    }
