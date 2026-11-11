from __future__ import annotations

import shutil
import subprocess
import threading
import uuid
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from lib.checkpoint import init_project
from tools.video.video_compose import VideoCompose
from tools.video.video_trimmer import VideoTrimmer
from tools.video.auto_reframe import AutoReframe
from tools.video.video_stitch import VideoStitch
from tools.enhancement.color_grade import ColorGrade
from tools.audio.audio_enhance import AudioEnhance
from tools.audio.audio_mixer import AudioMixer
from tools.subtitle.subtitle_gen import SubtitleGen
from backend.models import JobStatus
from backend.openmontage_adapter import AdapterError, probe_audio, probe_video, trim_video
from backend.storage import BackendStore


@dataclass
class VideoJob:
    job_id: str
    project_id: str
    title: str
    prompt: str
    style: str
    duration: str
    status: str = "queued"
    progress: int = 0
    current_step: str = "Queued"
    project_dir: str | None = None
    video_path: str | None = None
    error: str | None = None
    generation_mode: str = "mvp-local-compose"
    adapter_note: str = (
        "This backend adapter runs the deterministic local compose proof; the full semantic OpenMontage agent pipeline is orchestrated by the AI agent and is not exposed as a direct programmatic runner."
    )
    created_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def to_api_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "job_id": self.job_id,
            "project_id": self.project_id,
            "status": self.status,
            "progress": self.progress,
            "current_step": self.current_step,
            "generation_mode": self.generation_mode,
            "adapter_note": self.adapter_note,
        }
        if self.video_path:
            payload["video_url"] = f"/api/videos/{self.job_id}/file"
        if self.error:
            payload["error"] = self.error
        return payload


class JobStore:
    def __init__(self) -> None:
        self._jobs: dict[str, VideoJob] = {}
        self._lock = threading.Lock()

    def create(self, *, title: str, prompt: str, style: str, duration: str) -> VideoJob:
        project_id = f"video-{uuid.uuid4().hex[:12]}"
        job = VideoJob(
            job_id=uuid.uuid4().hex,
            project_id=project_id,
            title=title,
            prompt=prompt,
            style=style,
            duration=duration,
        )
        with self._lock:
            self._jobs[job.job_id] = job
        return job

    def get(self, job_id: str) -> VideoJob | None:
        with self._lock:
            return self._jobs.get(job_id)

    def update(self, job_id: str, **kwargs: Any) -> VideoJob | None:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                return None
            for key, value in kwargs.items():
                setattr(job, key, value)
            return job


store = JobStore()


def _update_job(job: VideoJob, *, status: str | None = None, progress: int | None = None, current_step: str | None = None, **extra: Any) -> None:
    if status is not None:
        job.status = status
    if progress is not None:
        job.progress = progress
    if current_step is not None:
        job.current_step = current_step
    for key, value in extra.items():
        setattr(job, key, value)


def _run_command(command: list[str], *, cwd: Path | None = None) -> None:
    subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)


def process_video_job(job: VideoJob) -> None:
    """MVP local pipeline: project setup -> synthetic local media -> VideoCompose -> final.mp4.

    This intentionally does not claim a full AI pipeline. It exercises the programmatic path that
    the repository already proves works: init_project() + local FFmpeg fixture + VideoCompose.
    """
    try:
        _update_job(job, status="initializing", progress=10, current_step="Initializing OpenMontage project")
        project_dir = init_project(
            job.project_id,
            title=job.title,
            pipeline_type="animated-explainer",
        )
        _update_job(job, project_dir=str(project_dir))

        if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
            raise RuntimeError("ffmpeg/ffprobe is not available on PATH")

        _update_job(job, status="processing", progress=35, current_step="Creating local media fixture")
        fixture = project_dir / "assets" / "video" / "fixture.mp4"
        final_video = project_dir / "renders" / "final.mp4"
        _run_command([
            "ffmpeg", "-y",
            "-f", "lavfi", "-i", "color=c=navy:s=640x360:d=2:r=30",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest", str(fixture),
        ])

        _update_job(job, status="rendering", progress=75, current_step="Rendering video")
        result = VideoCompose().execute({
            "operation": "compose",
            "edit_decisions": {
                "cuts": [{
                    "source": str(fixture),
                    "in_seconds": 0,
                    "out_seconds": 2,
                    "speed": 1.0,
                }],
            },
            "output_path": str(final_video),
            "codec": "libx264",
            "crf": 23,
            "preset": "fast",
        })
        if not result.success or not final_video.is_file():
            raise RuntimeError(result.error or "VideoCompose did not create final.mp4")

        _update_job(job, status="completed", progress=100, current_step="Completed", video_path=str(final_video))
    except Exception as exc:  # pragma: no cover - this is runtime path validation
        _update_job(job, status="failed", progress=100, current_step="Failed", error=str(exc))


class VideoTrimJobRunner:
    """Persistent job lifecycle for the first real mobile capability."""

    def __init__(self, backend_store: BackendStore) -> None:
        self.store = backend_store
        self._executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="om-video-trim")
        self._futures: dict[str, Future[None]] = {}
        self._lock = threading.Lock()

    def submit(self, job_id: str) -> None:
        future = self._executor.submit(self._run, job_id)
        with self._lock:
            self._futures[job_id] = future
        future.add_done_callback(lambda _: self._forget(job_id))

    def _forget(self, job_id: str) -> None:
        with self._lock:
            self._futures.pop(job_id, None)

    def cancel_queued(self, job_id: str) -> bool:
        with self._lock:
            future = self._futures.get(job_id)
        if future is None or not future.cancel():
            return False
        self.store.update_job(
            job_id, status=JobStatus.cancelled, current_step="cancelled",
            completed_at=datetime.now(timezone.utc),
        )
        return True

    def _run(self, job_id: str) -> None:
        job = self.store.get_job(job_id)
        if job is None or job.status != JobStatus.queued:
            return
        now = datetime.now(timezone.utc)
        self.store.update_job(
            job_id, status=JobStatus.running, progress=25,
            current_step="validating_input", started_at=now,
        )
        try:
            asset_ids = job.input.get("input_asset_ids", [])
            is_subtitle_job = job.capability == "subtitle" and job.operation == "generate"
            is_render_job = job.capability == "video_post" and job.operation == "render"
            is_burn_subtitles_job = job.capability == "video_post" and job.operation == "burn_subtitles"
            is_audio_job = job.capability == "audio_processing"
            is_tts_job = job.capability == "tts" and job.operation == "generate"
            is_music_job = job.capability == "music_generation" and job.operation == "generate"
            is_transcription_job = job.capability == "analysis" and job.operation == "transcribe"
            is_video_generation_job = job.capability == "video_generation" and job.operation == "generate"
            is_image_generation_job = job.capability == "image_generation" and job.operation == "generate"
            is_upscale_job = job.capability == "enhancement" and job.operation == "upscale"
            asset = None
            input_path = None
            render_paths: list[Path] = []
            if is_render_job:
                if len(asset_ids) < 2 or len(asset_ids) > 30:
                    raise AdapterError("Render requires between 2 and 30 video assets.")
                for asset_id in asset_ids:
                    render_asset = self.store.get_asset(str(asset_id))
                    if render_asset is None or render_asset.project_id != job.project_id or render_asset.type != "video":
                        raise AdapterError("Every render input must be a video asset in this project.")
                    render_path = self.store.safe_media_path(render_asset.path, job.project_id)
                    if render_path is None:
                        raise AdapterError("A selected render input is unavailable in this project.")
                    render_paths.append(render_path)
            elif is_video_generation_job and job.input.get("parameters", {}).get("mode") == "image_to_video":
                params = job.input.get("parameters", {})
                if params.get("reference_artifact_id"):
                    if asset_ids:
                        raise AdapterError("Provide a reference asset or artifact, not both.")
                    reference = self.store.get_artifact(str(params["reference_artifact_id"]))
                    if reference is None or reference.project_id != job.project_id or reference.type != "image":
                        raise AdapterError("The selected reference image artifact is unavailable in this project.")
                    input_path = self.store.safe_media_path(reference.path, job.project_id)
                else:
                    if len(asset_ids) != 1:
                        raise AdapterError("Image-to-video requires one reference image asset.")
                    asset = self.store.get_asset(str(asset_ids[0]))
                    if asset is None or asset.project_id != job.project_id or asset.type != "image":
                        raise AdapterError("The selected reference image is unavailable in this project.")
                    input_path = self.store.safe_media_path(asset.path, job.project_id)
                if input_path is None:
                    raise AdapterError("The selected reference image is unavailable in this project.")
            elif is_video_generation_job and job.input.get("parameters", {}).get("mode") == "reference_to_video":
                params = job.input.get("parameters", {})
                if params.get("reference_artifact_id"):
                    if asset_ids:
                        raise AdapterError("Provide a reference video asset or artifact, not both.")
                    reference = self.store.get_artifact(str(params["reference_artifact_id"]))
                    if reference is None or reference.project_id != job.project_id or reference.type != "video":
                        raise AdapterError("The selected reference video artifact is unavailable in this project.")
                    input_path = self.store.safe_media_path(reference.path, job.project_id)
                else:
                    if len(asset_ids) != 1:
                        raise AdapterError("Reference-to-video requires one video asset.")
                    asset = self.store.get_asset(str(asset_ids[0]))
                    if asset is None or asset.project_id != job.project_id or asset.type != "video":
                        raise AdapterError("The selected reference video is unavailable in this project.")
                    input_path = self.store.safe_media_path(asset.path, job.project_id)
                if input_path is None:
                    raise AdapterError("The selected reference video is unavailable in this project.")
            elif is_video_generation_job:
                if asset_ids:
                    raise AdapterError("Text-to-video does not accept input assets.")
            elif is_image_generation_job and job.input.get("parameters", {}).get("reference_artifact_id"):
                params = job.input.get("parameters", {})
                if asset_ids:
                    raise AdapterError("Provide a reference asset or artifact, not both.")
                reference = self.store.get_artifact(str(params["reference_artifact_id"]))
                if reference is None or reference.project_id != job.project_id or reference.type != "image":
                    raise AdapterError("The selected reference image artifact is unavailable in this project.")
                input_path = self.store.safe_media_path(reference.path, job.project_id)
                if input_path is None:
                    raise AdapterError("The selected reference image artifact is unavailable in this project.")
            elif is_image_generation_job and asset_ids:
                if len(asset_ids) != 1:
                    raise AdapterError("Image editing accepts exactly one reference image.")
                asset = self.store.get_asset(str(asset_ids[0]))
                if asset is None or asset.project_id != job.project_id or asset.type != "image":
                    raise AdapterError("The selected reference image is unavailable in this project.")
                input_path = self.store.safe_media_path(asset.path, job.project_id)
                if input_path is None:
                    raise AdapterError("The selected reference image is unavailable in this project.")
            elif is_upscale_job:
                if len(asset_ids) != 1:
                    raise AdapterError("Upscale requires exactly one image or video asset.")
                asset = self.store.get_asset(str(asset_ids[0]))
                if asset is None or asset.project_id != job.project_id or asset.type not in {"image", "video"}:
                    raise AdapterError("Upscale input must be an image or video asset in this project.")
                input_path = self.store.safe_media_path(asset.path, job.project_id)
                if input_path is None:
                    raise AdapterError("The selected upscale input is unavailable in this project.")
            elif is_image_generation_job:
                if asset_ids:
                    raise AdapterError("Text-to-image does not accept input assets.")
            elif is_tts_job:
                if asset_ids:
                    raise AdapterError("TTS generation does not accept input assets.")
            elif is_music_job:
                if asset_ids:
                    raise AdapterError("Music generation does not accept input assets.")
            elif not is_subtitle_job:
                if len(asset_ids) != 1:
                    raise AdapterError("This operation requires exactly one input asset.")
                asset = self.store.get_asset(str(asset_ids[0]))
                if asset is None or asset.project_id != job.project_id:
                    raise AdapterError("The selected input asset is unavailable in this project.")
                expected_type = "audio" if is_audio_job else "video"
                if not (is_transcription_job and asset.type in {"audio", "video"}) and not (is_upscale_job and asset.type in {"image", "video"}) and asset.type != expected_type:
                    raise AdapterError(f"This operation requires a {expected_type} asset.")
                input_path = self.store.safe_media_path(asset.path, job.project_id)
                if input_path is None:
                    raise AdapterError("The selected input asset is unavailable in this project.")
            params = job.input.get("parameters", {})
            workspace = self.store.project_workspace(job.project_id)
            if workspace is None:
                raise AdapterError("The project workspace is unavailable.")
            output_dir = workspace / "artifacts" / "jobs" / job_id
            output_dir.mkdir(parents=True, exist_ok=True)
            self.store.update_job(job_id, progress=50, current_step="processing")
            if is_transcription_job:
                from tools.tool_registry import registry

                provider_tool_id = str(params["provider_tool_id"])
                registry.ensure_discovered()
                provider_tool = registry.get(provider_tool_id)
                if provider_tool is None or provider_tool.get_status().value != "available":
                    raise AdapterError("provider_not_configured")
                transcript_dir = output_dir / "transcription"
                transcript_dir.mkdir(parents=True, exist_ok=True)
                inputs = {
                    "input_path": str(input_path),
                    "model_size": params.get("model_size", "base"),
                    "language": params.get("language"),
                    "diarize": bool(params.get("diarize", False)),
                    "output_dir": str(transcript_dir),
                }
                properties = provider_tool.input_schema.get("properties", {})
                inputs = {key: value for key, value in inputs.items() if key in properties and value is not None}
                try:
                    tool_result = provider_tool.execute(inputs)
                except Exception as exc:
                    import logging
                    logging.getLogger(__name__).exception("Transcription provider %s failed", provider_tool_id)
                    raise AdapterError("transcription_failed") from exc
                returned = [Path(str(path)) for path in (tool_result.artifacts or [])]
                returned_output = (tool_result.data or {}).get("output")
                output = Path(str(returned_output)) if returned_output else next(
                    (path for path in returned if path.is_file()), transcript_dir / "transcript.json",
                )
                try:
                    output.resolve().relative_to(output_dir.resolve())
                except ValueError as exc:
                    raise AdapterError("transcription_failed") from exc
                if not tool_result.success or not output.is_file():
                    raise AdapterError(tool_result.error or "transcription_failed")
                result_data = dict(tool_result.data or {})
                result_data["tool"] = provider_tool_id
                operation_metadata = {
                    "provider_tool_id": provider_tool_id,
                    "model_size": params.get("model_size", "base"),
                    "language": result_data.get("language", params.get("language")),
                }
            if is_tts_job:
                from tools.tool_registry import registry

                provider_tool_id = str(params["provider_tool_id"])
                registry.ensure_discovered()
                provider_tool = registry.get(provider_tool_id)
                if provider_tool is None or provider_tool.get_status().value != "available":
                    raise AdapterError("provider_not_configured")
                schema_properties = provider_tool.input_schema.get("properties", {})
                requested_format = params.get("response_format") or params.get("format")
                format_schema = schema_properties.get("response_format") or schema_properties.get("format") or {}
                allowed_formats = format_schema.get("enum", [])
                default_format = format_schema.get("default")
                if requested_format not in allowed_formats:
                    requested_format = default_format if default_format in allowed_formats else next(
                        (item for item in ("mp3", "wav", "opus", "aac", "flac") if item in allowed_formats),
                        requested_format or "wav",
                    )
                legacy_format_schema = schema_properties.get("format", {})
                legacy_formats = legacy_format_schema.get("enum", [])
                legacy_format = requested_format if not legacy_formats or requested_format in legacy_formats else legacy_format_schema.get("default")
                extension = "ogg" if requested_format == "opus" else str(requested_format or "wav")
                tts_output_path = output_dir / f"generated_speech.{extension}"
                aliases = {
                    "model": params.get("model_id"),
                    "model_id": params.get("model_id"),
                    "text": params.get("text"),
                    "output_path": str(tts_output_path),
                    "format": legacy_format,
                    "response_format": requested_format,
                }
                for field in ("voice", "voice_id", "speaker_id", "language_code", "voice_language", "speed", "speaking_rate", "voice_speed", "pitch", "instructions", "length_scale", "sentence_silence"):
                    aliases[field] = params.get(field)
                generation_inputs = {key: value for key, value in aliases.items() if key in schema_properties and value is not None}
                try:
                    tool_result = provider_tool.execute(generation_inputs)
                except Exception as exc:
                    import logging
                    logging.getLogger(__name__).exception("TTS provider %s failed", provider_tool_id)
                    raise AdapterError("generation_failed") from exc
                returned_artifacts = [Path(str(path)) for path in (tool_result.artifacts or [])]
                returned_output = (tool_result.data or {}).get("output")
                output = Path(str(returned_output)) if returned_output else next(
                    (path for path in returned_artifacts if path.is_file()), tts_output_path,
                )
                try:
                    output.resolve().relative_to(output_dir.resolve())
                except ValueError as exc:
                    raise AdapterError("generation_failed") from exc
                if not tool_result.success or not output.is_file():
                    raise AdapterError("generation_failed")
                try:
                    duration, _ = probe_audio(output)
                except Exception as exc:
                    raise AdapterError("generation_failed") from exc
                result_data = {"duration": duration, "tool": provider_tool_id}
                operation_metadata = {
                    "provider_tool_id": provider_tool_id,
                    "model_id": params.get("model_id"),
                    "format": output.suffix.lower().lstrip("."),
                }
            if is_music_job:
                from tools.tool_registry import registry

                provider_tool_id = str(params["provider_tool_id"])
                registry.ensure_discovered()
                provider_tool = registry.get(provider_tool_id)
                if provider_tool is None or provider_tool.get_status().value != "available":
                    raise AdapterError("provider_not_configured")
                properties = provider_tool.input_schema.get("properties", {})
                params_duration = params.get("duration_seconds")
                duration_value = params_duration
                if duration_value is None:
                    duration_value = (properties.get("duration_seconds") or properties.get("duration") or {}).get("default")
                format_property = properties.get("output_format") or properties.get("format") or {}
                format_values = format_property.get("enum", [])
                requested_format = params.get("output_format") or params.get("format") or format_property.get("default")
                music_format = requested_format if requested_format in {"mp3", "wav", "ogg", "opus", "flac"} else next((value for value in format_values if value in {"mp3", "wav", "ogg", "opus", "flac"}), "mp3")
                extension = "ogg" if music_format == "opus" else music_format
                music_output_path = output_dir / f"generated_music.{extension}"
                values = {
                    "prompt": params.get("prompt"),
                    "duration_seconds": duration_value,
                    "duration": duration_value,
                    "output_format": requested_format,
                    "format": requested_format,
                    "output_path": str(music_output_path),
                    "model": params.get("model") or params.get("model_id"),
                    "model_id": params.get("model_id"),
                    "instrumental": params.get("instrumental"),
                    "force_instrumental": params.get("force_instrumental"),
                    "custom_mode": params.get("custom_mode"),
                    "style": params.get("style"),
                    "title": params.get("title"),
                    "track_index": params.get("track_index"),
                }
                for key, schema in properties.items():
                    if key in values and values[key] is None and "default" in schema:
                        values[key] = schema["default"]
                generation_inputs = {key: value for key, value in values.items() if key in properties and value is not None}
                missing = [key for key in provider_tool.input_schema.get("required", []) if key not in generation_inputs]
                if missing:
                    raise AdapterError("The selected music provider requires additional inputs that are not supported by the mobile form.")
                if "output_path" not in properties:
                    raise AdapterError("The selected music provider cannot create a downloadable audio artifact.")
                try:
                    tool_result = provider_tool.execute(generation_inputs)
                except Exception as exc:
                    import logging
                    logging.getLogger(__name__).exception("Music provider %s failed", provider_tool_id)
                    raise AdapterError("music_generation_failed") from exc
                returned_artifacts = [Path(str(path)) for path in (tool_result.artifacts or [])]
                returned_output = (tool_result.data or {}).get("output") or (tool_result.data or {}).get("output_path")
                output = Path(str(returned_output)) if returned_output else next(
                    (path for path in returned_artifacts if path.is_file()), music_output_path,
                )
                try:
                    output.resolve().relative_to(output_dir.resolve())
                except ValueError as exc:
                    raise AdapterError("music_generation_failed") from exc
                if not tool_result.success or not output.is_file():
                    raise AdapterError("music_generation_failed")
                try:
                    duration, _ = probe_audio(output)
                except Exception as exc:
                    raise AdapterError("music_generation_failed") from exc
                result_data = {"duration": duration, "tool": provider_tool_id}
                operation_metadata = {
                    "provider_tool_id": provider_tool_id,
                    "model_id": params.get("model_id") or params.get("model"),
                    "format": output.suffix.lower().lstrip("."),
                }
            if is_upscale_job:
                from tools.tool_registry import registry

                provider_tool_id = str(params["provider_tool_id"])
                registry.ensure_discovered()
                provider_tool = registry.get(provider_tool_id)
                if provider_tool is None or provider_tool.get_status().value != "available":
                    raise AdapterError("provider_not_configured")
                properties = provider_tool.input_schema.get("properties", {})
                media_type = "image" if asset.type == "image" else "video"
                suffix = input_path.suffix.lower()
                upscale_output = output_dir / f"upscaled{suffix}"
                values = {
                    "input_path": str(input_path), "output_path": str(upscale_output),
                    "scale": params.get("scale", 4), "model": params.get("model_id"),
                    "face_enhance": params.get("face_enhance", False),
                    "denoise_strength": params.get("denoise_strength", 0.5),
                }
                if "model" in properties and "enum" in properties["model"] and values["model"] not in properties["model"]["enum"]:
                    values["model"] = properties["model"].get("default") or properties["model"]["enum"][0]
                inputs = {key: value for key, value in values.items() if key in properties and value is not None}
                try:
                    tool_result = provider_tool.execute(inputs)
                except Exception as exc:
                    import logging
                    logging.getLogger(__name__).exception("Upscale provider %s failed", provider_tool_id)
                    raise AdapterError("upscale_failed") from exc
                returned = [Path(str(path)) for path in (tool_result.artifacts or [])]
                returned_output = (tool_result.data or {}).get("output")
                output = Path(str(returned_output)) if returned_output else next(
                    (path for path in returned if path.is_file()), upscale_output,
                )
                try:
                    output.resolve().relative_to(output_dir.resolve())
                except ValueError as exc:
                    raise AdapterError("upscale_failed") from exc
                if not tool_result.success or not output.is_file():
                    raise AdapterError(tool_result.error or "upscale_failed")
                details = (tool_result.data or {})
                if media_type == "video":
                    duration, _ = probe_video(output)
                    result_data = {"duration": duration, "tool": provider_tool_id, "media_type": media_type}
                else:
                    from PIL import Image
                    try:
                        with Image.open(output) as image:
                            image.verify()
                            width, height = image.size
                    except Exception as exc:
                        raise AdapterError("upscale_failed") from exc
                    result_data = {"width": width, "height": height, "tool": provider_tool_id, "media_type": media_type}
                operation_metadata = {
                    "provider_tool_id": provider_tool_id,
                    "scale": params.get("scale", 4),
                    "model_id": details.get("model", params.get("model_id")),
                    "source_asset_id": asset.id,
                }
            elif is_tts_job or is_music_job or is_transcription_job:
                pass
            elif is_image_generation_job:
                from tools.tool_registry import registry

                provider_tool_id = str(params["provider_tool_id"])
                registry.ensure_discovered()
                provider_tool = registry.get(provider_tool_id)
                if provider_tool is None or provider_tool.get_status().value != "available":
                    raise AdapterError("provider_not_configured")
                schema_properties = provider_tool.input_schema.get("properties", {})
                image_output_path = output_dir / "generated_image.png"
                generation_inputs: dict[str, Any] = {
                    "prompt": params["prompt"],
                    "negative_prompt": params.get("negative_prompt"),
                    "aspect_ratio": params.get("aspect_ratio"),
                    "resolution": params.get("resolution"),
                    "width": params.get("width"),
                    "height": params.get("height"),
                    "seed": params.get("seed"),
                    "model": params.get("model_id"),
                    "model_name": params.get("model_id"),
                    "generation_mode": "edit" if input_path is not None else "generate",
                    "image_path": str(input_path) if input_path is not None else None,
                    "image_paths": [str(input_path)] if input_path is not None else None,
                    "output_path": str(image_output_path),
                }
                if "size" in schema_properties:
                    size_enum = schema_properties["size"].get("enum", [])
                    requested_size = {
                        "1:1": "1024x1024",
                        "16:9": "1536x1024",
                        "9:16": "1024x1536",
                    }.get(str(params.get("aspect_ratio")), "auto")
                    generation_inputs["size"] = requested_size if requested_size in size_enum else schema_properties["size"].get("default", "auto")
                if "model" in schema_properties and "enum" in schema_properties["model"]:
                    model_enum = schema_properties["model"]["enum"]
                    if generation_inputs["model"] not in model_enum:
                        generation_inputs["model"] = schema_properties["model"].get("default", model_enum[0] if model_enum else None)
                generation_inputs = {
                    key: value for key, value in generation_inputs.items()
                    if key in schema_properties and value is not None
                }
                try:
                    tool_result = provider_tool.execute(generation_inputs)
                except Exception as exc:
                    import logging
                    logging.getLogger(__name__).exception("Image generation provider %s failed", provider_tool_id)
                    raise AdapterError("generation_failed") from exc
                returned_artifacts = [Path(str(path)) for path in (tool_result.artifacts or [])]
                returned_output = (tool_result.data or {}).get("output")
                output = Path(str(returned_output)) if returned_output else next(
                    (path for path in returned_artifacts if path.is_file()), image_output_path,
                )
                try:
                    output.resolve().relative_to(output_dir.resolve())
                except ValueError as exc:
                    raise AdapterError("generation_failed") from exc
                if not tool_result.success or not output.is_file():
                    raise AdapterError("generation_failed")
                try:
                    from PIL import Image
                    with Image.open(output) as image:
                        image.verify()
                        width, height = image.size
                except Exception as exc:
                    raise AdapterError("generation_failed") from exc
                result_data = {"width": width, "height": height, "tool": provider_tool_id}
                operation_metadata = {
                    "provider_tool_id": provider_tool_id,
                    "model_id": params.get("model_id"),
                    **({"reference_artifact_id": params["reference_artifact_id"]} if params.get("reference_artifact_id") else {}),
                }
            elif is_video_generation_job:
                from tools.tool_registry import registry

                provider_tool_id = str(params["provider_tool_id"])
                registry.ensure_discovered()
                provider_tool = registry.get(provider_tool_id)
                if provider_tool is None or provider_tool.get_status().value != "available":
                    raise AdapterError("provider_not_configured")
                schema_properties = provider_tool.input_schema.get("properties", {})
                generation_inputs: dict[str, Any] = {
                    "prompt": params["prompt"],
                    "operation": params["mode"],
                    "aspect_ratio": params["aspect_ratio"],
                    "width": params.get("width"),
                    "height": params.get("height"),
                    "num_frames": params.get("num_frames"),
                    "fps": params.get("fps"),
                    "num_inference_steps": params.get("num_inference_steps"),
                    "guidance_scale": params.get("guidance_scale"),
                    "seed": params.get("seed"),
                    "negative_prompt": params.get("negative_prompt"),
                    "model_variant": params.get("model_id"),
                    "model": params.get("model_id"),
                    "duration_hint": f"{float(params['duration_seconds']):g}s",
                    "enable_model_offload": True,
                    "output_path": str(output_dir / "generated_video.mp4"),
                }
                if input_path is not None and params["mode"] == "image_to_video":
                    generation_inputs["reference_image_path"] = str(input_path)
                if input_path is not None and params["mode"] == "reference_to_video":
                    for field in ("reference_video_path", "input_video_path", "video_path"):
                        if field in schema_properties:
                            generation_inputs[field] = str(input_path)
                    if "video_paths" in schema_properties:
                        generation_inputs["video_paths"] = [str(input_path)]
                generation_inputs = {
                    key: value for key, value in generation_inputs.items()
                    if key in schema_properties and value is not None
                }
                try:
                    tool_result = provider_tool.execute(generation_inputs)
                except Exception as exc:
                    import logging
                    logging.getLogger(__name__).exception("Video generation provider %s failed", provider_tool_id)
                    raise AdapterError("generation_failed") from exc
                returned_artifacts = [Path(str(path)) for path in (tool_result.artifacts or [])]
                returned_output = (tool_result.data or {}).get("output")
                output = Path(str(returned_output)) if returned_output else next(
                    (path for path in returned_artifacts if path.is_file()),
                    Path(generation_inputs["output_path"]),
                )
                try:
                    output.resolve().relative_to(output_dir.resolve())
                except ValueError as exc:
                    raise AdapterError("generation_failed") from exc
                if not tool_result.success or not output.is_file():
                    raise AdapterError("generation_failed")
                output_duration, _ = probe_video(output)
                result_data = {"duration": output_duration, "tool": provider_tool_id}
                operation_metadata = {
                    "provider_tool_id": provider_tool_id,
                    "model_id": params.get("model_id"),
                    "mode": params["mode"],
                    **({"reference_artifact_id": params["reference_artifact_id"]} if params.get("reference_artifact_id") else {}),
                }
            elif is_render_job:
                output = output_dir / "rendered.mp4"
                tool_result = VideoStitch().execute({
                    "operation": "stitch",
                    "clips": [str(path) for path in render_paths],
                    "output_path": str(output),
                    "transition": str(params.get("transition", "cut")),
                    "transition_duration": float(params.get("transition_duration", 0.5)),
                    "auto_normalize": bool(params.get("auto_normalize", True)),
                    "target_resolution": str(params.get("target_resolution", "1920x1080")),
                    "target_fps": int(params.get("target_fps", 30)),
                    "codec": "libx264",
                })
                if not tool_result.success or not output.is_file():
                    raise AdapterError(tool_result.error or "OpenMontage video stitching failed.")
                output_duration, _ = probe_video(output)
                result_data = {"duration": output_duration, "tool": "video_stitch"}
                operation_metadata = {
                    "source_asset_ids": [str(asset_id) for asset_id in asset_ids],
                    "transition": str(params.get("transition", "cut")),
                }
            elif is_burn_subtitles_job:
                subtitle_artifact = self.store.get_artifact(str(params["subtitle_artifact_id"]))
                if subtitle_artifact is None or subtitle_artifact.project_id != job.project_id or subtitle_artifact.type != "subtitle":
                    raise AdapterError("The selected subtitle artifact is unavailable in this project.")
                subtitle_path = self.store.safe_media_path(subtitle_artifact.path, job.project_id)
                if subtitle_path is None:
                    raise AdapterError("The selected subtitle file is unavailable in this project.")
                output = output_dir / "subtitled.mp4"
                tool_result = VideoCompose().execute({
                    "operation": "burn_subtitles",
                    "input_path": str(input_path),
                    "subtitle_path": str(subtitle_path),
                    "output_path": str(output),
                    "codec": "libx264",
                    "crf": 20,
                })
                returned_path = Path((tool_result.data or {}).get("output", str(output)))
                if not tool_result.success or not returned_path.is_file():
                    raise AdapterError(tool_result.error or "OpenMontage subtitle burn failed.")
                output = returned_path
                output_duration, _ = probe_video(output)
                result_data = {"duration": output_duration, "tool": "video_compose"}
                operation_metadata = {
                    "source_subtitle_artifact_id": subtitle_artifact.id,
                    "subtitle_burned": True,
                }
            elif is_subtitle_job:
                subtitle_format = str(params["format"])
                output = output_dir / f"subtitles.{subtitle_format}"
                tool_result = SubtitleGen().execute({
                    "segments": params["segments"],
                    "format": subtitle_format,
                    "max_chars_per_line": params.get("max_chars_per_line", 42),
                    "max_words_per_cue": params.get("max_words_per_cue", 8),
                    "output_path": str(output),
                })
                if not tool_result.success or not output.is_file():
                    raise AdapterError(tool_result.error or "Subtitle generation failed.")
                result_data = {
                    "duration": max(float(segment["end"]) for segment in params["segments"]),
                    "tool": "subtitle_gen",
                    **(tool_result.data or {}),
                }
                operation_metadata = {"format": subtitle_format}
            elif job.capability == "video_post" and job.operation == "trim":
                start = float(params["start"])
                end = float(params["end"])
                duration, _ = probe_video(input_path)
                if end > duration:
                    raise AdapterError("The trim end must not exceed the video duration.")
                output = output_dir / "trimmed.mp4"
                result_data = trim_video(
                    input_path=input_path, output_path=output, start=start, end=end,
                )
                operation_metadata = {"trim": {"start": start, "end": end}}
            elif job.operation == "speed":
                speed_factor = float(params["speed_factor"])
                output = output_dir / "speed_adjusted.mp4"
                tool_result = VideoTrimmer().execute({
                    "operation": "speed",
                    "input_path": str(input_path),
                    "output_path": str(output),
                    "speed_factor": speed_factor,
                    "codec": "libx264",
                })
                if not tool_result.success or not output.is_file():
                    raise AdapterError(tool_result.error or "Video speed adjustment failed.")
                output_duration, _ = probe_video(output)
                result_data = {"duration": output_duration, "tool": "video_trimmer"}
                operation_metadata = {"speed_factor": speed_factor}
            elif job.capability == "video_post" and job.operation == "crop":
                target_aspect = str(params["target_aspect"])
                output = output_dir / "reframed.mp4"
                tool_result = AutoReframe().execute({
                    "input_path": str(input_path),
                    "output_path": str(output),
                    "target_aspect": target_aspect,
                    "codec": "libx264",
                    "crf": 20,
                })
                if not tool_result.success:
                    raise AdapterError(tool_result.error or "Video reframing failed.")
                returned_path = Path((tool_result.data or {}).get("output", str(output)))
                if returned_path.is_file():
                    output = returned_path
                if not output.is_file():
                    raise AdapterError("AutoReframe did not create a video artifact.")
                output_duration, _ = probe_video(output)
                result_data = {"duration": output_duration, "tool": "auto_reframe"}
                operation_metadata = {
                    "target_aspect": target_aspect,
                    "method": (tool_result.data or {}).get("method", "already_matches"),
                }
            elif job.capability == "enhancement" and job.operation == "color_grade":
                profile = str(params["profile"])
                intensity = float(params.get("intensity", 1.0))
                output = output_dir / "color_graded.mp4"
                tool_result = ColorGrade().execute({
                    "input_path": str(input_path),
                    "output_path": str(output),
                    "profile": profile,
                    "intensity": intensity,
                    "codec": "libx264",
                    "crf": 20,
                })
                if not tool_result.success or not output.is_file():
                    raise AdapterError(tool_result.error or "Color grading failed.")
                output_duration, _ = probe_video(output)
                result_data = {"duration": output_duration, "tool": "color_grade"}
                operation_metadata = {"profile": profile, "intensity": intensity}
            elif is_audio_job and job.operation == "enhance":
                preset = str(params["preset"])
                output = output_dir / "enhanced_audio.m4a"
                tool_result = AudioEnhance().execute({
                    "input_path": str(input_path),
                    "output_path": str(output),
                    "preset": preset,
                    "audio_codec": "aac",
                    "bitrate": "192k",
                })
                if not tool_result.success or not output.is_file():
                    raise AdapterError(tool_result.error or "Audio enhancement failed.")
                output_duration, _ = probe_audio(output)
                result_data = {"duration": output_duration, "tool": "audio_enhance"}
                operation_metadata = {"preset": preset}
            elif is_audio_job and job.operation == "volume":
                volume = float(params["volume"])
                output = output_dir / "adjusted_volume.wav"
                tool_result = AudioMixer().execute({
                    "operation": "mix",
                    "tracks": [{"path": str(input_path), "role": "primary", "volume": volume}],
                    "normalize": False,
                    "output_path": str(output),
                })
                if not tool_result.success or not output.is_file():
                    raise AdapterError(tool_result.error or "Audio volume adjustment failed.")
                output_duration, _ = probe_audio(output)
                result_data = {"duration": output_duration, "tool": "audio_mixer"}
                operation_metadata = {"volume": volume}
            elif is_audio_job and job.operation == "trim":
                start_seconds = float(params["start_seconds"])
                end_seconds = float(params["end_seconds"])
                source_duration, _ = probe_audio(input_path)
                if start_seconds < 0 or end_seconds <= start_seconds or end_seconds > source_duration:
                    raise AdapterError("The audio trim range must be within the source duration.")
                output = output_dir / "trimmed_audio.wav"
                tool_result = AudioMixer().execute({
                    "operation": "trim",
                    "input_path": str(input_path),
                    "start_seconds": start_seconds,
                    "end_seconds": end_seconds,
                    "output_path": str(output),
                })
                if not tool_result.success or not output.is_file():
                    raise AdapterError(tool_result.error or "Audio trim failed.")
                output_duration, _ = probe_audio(output)
                result_data = {"duration": output_duration, "tool": "audio_mixer"}
                operation_metadata = {"trim": {"start_seconds": start_seconds, "end_seconds": end_seconds}}
            else:
                raise AdapterError("Unsupported video editing operation.")
            self.store.update_job(job_id, progress=75, current_step="creating_artifact")
            artifact = self.store.add_artifact(
                project_id=job.project_id, job_id=job_id, path=output,
                mime_type=("text/vtt" if params["format"] == "vtt" else "application/x-subrip") if is_subtitle_job else "application/json" if is_transcription_job else ("audio/wav" if job.operation in {"volume", "trim"} else "audio/mp4") if is_audio_job else ("audio/mpeg" if output.suffix.lower() == ".mp3" else "audio/ogg" if output.suffix.lower() in {".ogg", ".opus"} else "audio/aac" if output.suffix.lower() == ".aac" else "audio/flac" if output.suffix.lower() == ".flac" else "audio/wav") if is_tts_job or is_music_job else ("image/jpeg" if output.suffix.lower() in {".jpg", ".jpeg"} else "image/webp" if output.suffix.lower() == ".webp" else "image/png") if is_image_generation_job or (is_upscale_job and result_data.get("media_type") == "image") else "video/mp4",
                metadata={
                    "duration": result_data.get("duration"),
                    "width": result_data.get("width"),
                    "height": result_data.get("height"),
                    "format": params["format"] if is_subtitle_job else "json" if is_transcription_job else "wav" if job.operation in {"volume", "trim"} else "m4a" if is_audio_job else output.suffix.lower().lstrip(".") if is_tts_job or is_music_job or is_image_generation_job or is_upscale_job else "mp4",
                    **({"source_asset_id": asset.id} if asset is not None else {}),
                    "operation": job.operation,
                    "tool": result_data["tool"], **operation_metadata,
                },
                artifact_type="subtitle" if is_subtitle_job else "transcript" if is_transcription_job else "audio" if is_audio_job or is_tts_job or is_music_job else "image" if is_image_generation_job or (is_upscale_job and result_data.get("media_type") == "image") else "video",
            )
            self.store.update_job(
                job_id, status=JobStatus.completed, progress=100,
                current_step="completed", completed_at=datetime.now(timezone.utc),
                output_artifact_ids=[artifact.id],
            )
        except AdapterError as exc:
            self.store.update_job(
                job_id, status=JobStatus.failed, progress=100,
                current_step="failed", completed_at=datetime.now(timezone.utc),
                error=str(exc),
            )
        except Exception:
            # Keep local filesystem paths and process details out of client responses.
            import logging
            logging.getLogger(__name__).exception("Media processing job %s failed", job_id)
            self.store.update_job(
                job_id, status=JobStatus.failed, progress=100,
                current_step="failed", completed_at=datetime.now(timezone.utc),
                error="Video processing failed. Check the uploaded video and try again.",
            )
