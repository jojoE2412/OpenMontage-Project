from __future__ import annotations

import threading
import re
import uuid
import logging
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import ValidationError

from backend.jobs import JobStore, VideoTrimJobRunner, process_video_job, store as legacy_store
from backend.hardware import detect_host_hardware
from backend.models import AudioEnhancementParameters, AudioTrimParameters, AudioVolumeParameters, CapabilityJobRequest, ColorGradeParameters, CropParameters, ImageGenerationParameters, Job, JobStatus, MusicGenerationParameters, PipelineJobRequest, RenderParameters, SpeedParameters, SubtitleBurnParameters, SubtitleGenerateParameters, TranscriptionParameters, TrimParameters, TtsGenerationParameters, UpscaleParameters, VideoGenerationParameters
from backend.storage import store

logger = logging.getLogger(__name__)


app = FastAPI(title="OpenMontage Mobile API", version="1.0.0")
interrupted_jobs = store.recover_interrupted_jobs()
if interrupted_jobs:
    logger.warning("Marked %s interrupted mobile job(s) as failed after restart", interrupted_jobs)
job_runner = VideoTrimJobRunner(store)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "api_version": "1.0.0"}


def _public_tool_contract(info: dict[str, Any]) -> dict[str, Any]:
    """Expose runtime capability metadata without local paths or setup secrets."""
    model_matrix = info.get("provider_matrix") or {}
    models = [
        {"id": model_id, **(details if isinstance(details, dict) else {})}
        for model_id, details in model_matrix.items()
    ]
    if not models:
        model_enum = (
            info.get("input_schema", {})
            .get("properties", {})
            .get("model", {})
            .get("enum", [])
        )
        models = [{"id": str(model_id)} for model_id in model_enum]
    return {
        "tool_id": info["name"],
        "capability_id": info["capability"],
        "provider_id": info["provider"],
        "runtime": info.get("runtime"),
        "status": info["status"],
        "operations": info.get("capabilities", []),
        "input_schema": info.get("input_schema", {}),
        "output_schema": info.get("output_schema", {}),
                "artifact_schema": info.get("artifact_schema", {}),
        "models": models,
        "supports": info.get("supports", {}),
        "resource_profile": info.get("resource_profile", {}),
        "install_instructions": info.get("install_instructions", ""),
    }


def _tool_contracts() -> list[dict[str, Any]]:
    from tools.tool_registry import registry

    return [
        _public_tool_contract(info)
        for group in registry.capability_catalog().values()
        for info in group
    ]


@app.get("/api/capabilities")
def list_capabilities() -> dict[str, Any]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for tool in _tool_contracts():
        grouped.setdefault(tool["capability_id"], []).append(tool)
    return {
        "items": [
            {
                "id": capability_id,
                "status": "available"
                if any(tool["status"] == "available" for tool in tools)
                else "unavailable",
                "provider_count": len(
                    {tool["provider_id"] for tool in tools if tool["provider_id"] != "selector"}
                ),
                "available_provider_count": len(
                    {
                        tool["provider_id"]
                        for tool in tools
                        if tool["provider_id"] != "selector" and tool["status"] == "available"
                    }
                ),
                "mobile_job_operations": _mobile_operations(capability_id, tools),
                "tools": tools,
            }
            for capability_id, tools in sorted(grouped.items())
        ]
    }


@app.get("/api/runtime/hardware")
def get_runtime_hardware() -> dict[str, Any]:
    hardware = detect_host_hardware()
    contracts = _tool_contracts()
    ltx = next((tool for tool in contracts if tool["tool_id"] == "ltx_video_local"), None)
    required_vram = (ltx or {}).get("resource_profile", {}).get("vram_mb")
    available_vram = hardware["gpu"].get("vram_mb")
    if required_vram and available_vram is not None and available_vram < required_vram:
        status = "unsupported_hardware"
        reason = f"LTX requires {required_vram} MB VRAM; this host reports {available_vram} MB."
    elif not hardware["cuda"]["available"]:
        status = "not_configured"
        reason = hardware["cuda"].get("reason") or "CUDA is not available to PyTorch on this host."
    elif ltx is None or ltx["status"] != "available":
        status = "not_configured"
        reason = "The OpenMontage LTX local tool is not available in the current runtime."
    else:
        status = "ready"
        reason = None
    local_tools = [tool for tool in contracts if tool.get("runtime") == "local_gpu" and tool["capability_id"] == "video_generation"]
    local_video_providers = []
    for tool in local_tools:
        available = hardware["gpu"].get("vram_mb")
        models = []
        for model in tool.get("models", []):
            minimum_vram = int(model.get("vram_mb") or tool.get("resource_profile", {}).get("vram_mb") or 0)
            if available is not None and available < minimum_vram:
                model_status = "unsupported_hardware"
            elif not hardware["cuda"].get("available") or tool["status"] != "available":
                model_status = "not_configured"
            else:
                model_status = "ready"
            models.append({"model_id": model["id"], "minimum_vram_mb": minimum_vram, "status": model_status})
        if not models:
            minimum_vram = int(tool.get("resource_profile", {}).get("vram_mb") or 0)
            if available is not None and available < minimum_vram:
                model_status = "unsupported_hardware"
            elif not hardware["cuda"].get("available") or tool["status"] != "available":
                model_status = "not_configured"
            else:
                model_status = "ready"
            models.append({"model_id": None, "minimum_vram_mb": minimum_vram, "status": model_status})
        minimum_vram = min(model["minimum_vram_mb"] for model in models)
        compatible = any(model["status"] == "ready" for model in models)
        provider_status = "ready" if compatible else "unsupported_hardware" if all(model["status"] == "unsupported_hardware" for model in models) else "not_configured"
        local_video_providers.append({
            "tool_id": tool["tool_id"],
            "provider_id": tool["provider_id"],
            "status": provider_status,
            "minimum_vram_mb": minimum_vram,
            "models": models,
        })
    return {
        **hardware,
        "local_video_providers": local_video_providers,
        "local_video_generation": {
            "tool_id": "ltx_video_local" if ltx else None,
            "provider_status": ltx["status"] if ltx else "not_registered",
            "required_vram_mb": required_vram,
            "status": status,
            "reason": reason,
        },
    }


def _mobile_operations(capability_id: str, tools: list[dict[str, Any]]) -> list[str]:
    if capability_id == "video_generation":
        for tool in tools:
            schema = tool.get("input_schema", {})
            properties = schema.get("properties", {})
            modes = properties.get("operation", {}).get("enum", [])
            if tool.get("status") == "available" and "prompt" in schema.get("required", []) and "output_path" in properties and any(mode in modes for mode in ("text_to_video", "image_to_video", "reference_to_video")):
                return ["generate"]
        return []
    if capability_id == "image_generation":
        for tool in tools:
            schema = tool.get("input_schema", {})
            properties = schema.get("properties", {})
            modes = properties.get("generation_mode", {}).get("enum", [])
            if tool.get("status") == "available" and "prompt" in schema.get("required", []) and "output_path" in properties and (not modes or "generate" in modes):
                return ["generate"]
        return []
    if capability_id == "tts":
        for tool in tools:
            schema = tool.get("input_schema", {})
            properties = schema.get("properties", {})
            formats = properties.get("response_format", {}).get("enum", []) or properties.get("format", {}).get("enum", [])
            if tool.get("status") == "available" and "text" in schema.get("required", []) and "output_path" in properties and (not formats or any(fmt in formats for fmt in ("mp3", "wav", "opus", "aac", "flac"))):
                return ["generate"]
        return []
    if capability_id == "music_generation":
        for tool in tools:
            schema = tool.get("input_schema", {})
            properties = schema.get("properties", {})
            if (tool.get("status") == "available"
                    and "prompt" in schema.get("required", [])
                    and "output_path" in properties):
                return ["generate"]
        return []
    if capability_id == "analysis":
        tool = next((item for item in tools if item["tool_id"] == "transcriber"), None)
        schema = tool.get("input_schema", {}) if tool else {}
        properties = schema.get("properties", {})
        if tool is not None and tool["status"] == "available" and "input_path" in schema.get("required", []) and "output_dir" in properties:
            return ["transcribe"]
        return []
    if capability_id == "subtitle":
        generator = next((tool for tool in tools if tool["tool_id"] == "subtitle_gen"), None)
        formats = generator.get("input_schema", {}).get("properties", {}).get("format", {}).get("enum", []) if generator else []
        if generator is not None and generator["status"] == "available" and {"srt", "vtt"}.issubset(set(formats)):
            return ["generate"]
        return []
    if capability_id == "audio_processing":
        enhancer = next((tool for tool in tools if tool["tool_id"] == "audio_enhance"), None)
        properties = enhancer.get("input_schema", {}).get("properties", {}) if enhancer else {}
        operations = []
        if enhancer is not None and enhancer["status"] == "available" and properties.get("preset", {}).get("enum"):
            operations.append("enhance")
        mixer = next((tool for tool in tools if tool["tool_id"] == "audio_mixer"), None)
        mixer_schema = mixer.get("input_schema", {}) if mixer else {}
        mixer_properties = mixer_schema.get("properties", {})
        mixer_operations = mixer_properties.get("operation", {}).get("enum", [])
        volume_schema = mixer_properties.get("tracks", {}).get("items", {}).get("properties", {}).get("volume", {})
        if mixer is not None and mixer["status"] == "available" and "mix" in mixer_operations and volume_schema.get("minimum") == 0 and volume_schema.get("maximum") == 1.0:
            operations.append("volume")
        if mixer is not None and mixer["status"] == "available" and "trim" in mixer_operations:
            operations.append("trim")
        return operations
    if capability_id == "enhancement":
        operations = []
        grader = next((tool for tool in tools if tool["tool_id"] == "color_grade"), None)
        properties = grader.get("input_schema", {}).get("properties", {}) if grader else {}
        if grader is not None and grader["status"] == "available" and properties.get("profile", {}).get("enum"):
            operations.append("color_grade")
        upscaler = next((tool for tool in tools if tool["tool_id"] == "upscale"), None)
        upscale_properties = upscaler.get("input_schema", {}).get("properties", {}) if upscaler else {}
        if upscaler is not None and upscaler["status"] == "available" and "input_path" in upscaler.get("input_schema", {}).get("required", []) and "output_path" in upscale_properties and upscale_properties.get("scale", {}).get("enum"):
            operations.append("upscale")
        return operations
    if capability_id != "video_post":
        return []
    operations = []
    compositor = next((tool for tool in tools if tool["tool_id"] == "video_compose"), None)
    compose_operations = compositor.get("input_schema", {}).get("properties", {}).get("operation", {}).get("enum", []) if compositor else []
    if compositor is not None and compositor["status"] == "available" and "burn_subtitles" in compose_operations:
        operations.append("burn_subtitles")
    stitcher = next((tool for tool in tools if tool["tool_id"] == "video_stitch"), None)
    stitch_operations = stitcher.get("input_schema", {}).get("properties", {}).get("operation", {}).get("enum", []) if stitcher else []
    if stitcher is not None and stitcher["status"] == "available" and "stitch" in stitch_operations:
        operations.append("render")
    trimmer = next(
        (tool for tool in tools if tool["tool_id"] == "video_trimmer"), None
    )
    if trimmer is not None and trimmer["status"] == "available":
        operation_enum = trimmer.get("input_schema", {}).get("properties", {}).get("operation", {}).get("enum", [])
        if "cut" in operation_enum:
            operations.append("trim")
        if "speed" in operation_enum:
            operations.append("speed")
    reframer = next((tool for tool in tools if tool["tool_id"] == "auto_reframe"), None)
    aspects = reframer.get("input_schema", {}).get("properties", {}).get("target_aspect", {}).get("enum", []) if reframer else []
    if reframer is not None and reframer["status"] == "available" and aspects:
        operations.append("crop")
    return operations


@app.get("/api/providers")
def list_providers(capability: str | None = None) -> dict[str, Any]:
    items = [
        tool
        for tool in _tool_contracts()
        if tool["provider_id"] != "selector"
        and (capability is None or tool["capability_id"] == capability)
    ]
    return {"items": items}


@app.get("/api/models")
def list_models(
    capability: str | None = None,
    provider: str | None = None,
    tool: str | None = None,
) -> dict[str, Any]:
    contracts = _tool_contracts()
    items = [
        {"capability_id": contract["capability_id"],
         "provider_id": contract["provider_id"],
         "tool_id": contract["tool_id"],
         "status": contract["status"],
         **model}
        for contract in contracts
        if contract["provider_id"] != "selector"
        and (capability is None or contract["capability_id"] == capability)
        and (provider is None or contract["provider_id"] == provider)
        and (tool is None or contract["tool_id"] == tool)
        for model in contract["models"]
    ]
    return {"items": items}


def _project_json(project: Any) -> dict[str, Any]:
    result = project.model_dump(mode="json", exclude={"workspace_path"})
    result["assets_url"] = f"/api/projects/{project.id}/assets"
    return result


def _asset_json(asset: Any) -> dict[str, Any]:
    return asset.model_dump(mode="json", exclude={"path"}) | {
        "file_url": f"/api/assets/{asset.id}/file",
    }


def _job_json(job: Job) -> dict[str, Any]:
    return job.model_dump(mode="json")


def _artifact_json(artifact: Any) -> dict[str, Any]:
    return artifact.model_dump(mode="json", exclude={"path"}) | {
        "download_url": f"/api/artifacts/{artifact.id}/file",
    }


@app.get("/api/projects")
def list_projects() -> dict[str, Any]:
    return {"items": [_project_json(project) for project in store.list_projects()]}


@app.post("/api/projects", status_code=201)
def create_project(payload: dict[str, Any]) -> dict[str, Any]:
    name = str(payload.get("name", "")).strip()
    if not name or len(name) > 120:
        raise HTTPException(status_code=422, detail="name must contain 1 to 120 characters")
    logger.info("Mobile project creation started")
    try:
        project = store.create_project(name)
    except Exception:
        logger.exception("Mobile project creation failed")
        raise HTTPException(status_code=500, detail="OpenMontage could not create the project") from None
    logger.info("Mobile project creation completed")
    return _project_json(project)


@app.get("/api/projects/{project_id}")
def get_project(project_id: str) -> dict[str, Any]:
    project = store.get_project(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="project not found")
    return _project_json(project)


_VIDEO_TYPES = {
    ".mp4": "video/mp4", ".mov": "video/quicktime", ".m4v": "video/x-m4v",
    ".mkv": "video/x-matroska", ".webm": "video/webm", ".avi": "video/x-msvideo",
}
_AUDIO_TYPES = {
    ".mp3": "audio/mpeg", ".wav": "audio/wav", ".m4a": "audio/mp4",
    ".aac": "audio/aac", ".flac": "audio/flac", ".ogg": "audio/ogg",
    ".opus": "audio/opus",
}
_IMAGE_TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}
_MAX_UPLOAD_BYTES = 500 * 1024 * 1024
_SAFE_NAME = re.compile(r"^[^/\\\x00-\x1f]{1,180}$")


@app.post("/api/projects/{project_id}/assets", status_code=201)
async def upload_asset(project_id: str, request: Request, filename: str) -> dict[str, Any]:
    workspace = store.project_workspace(project_id)
    if workspace is None:
        raise HTTPException(status_code=404, detail="project not found")
    if not _SAFE_NAME.fullmatch(filename) or filename in {".", ".."}:
        raise HTTPException(status_code=422, detail="filename is invalid")
    suffix = Path(filename).suffix.lower()
    media = _VIDEO_TYPES.get(suffix) or _AUDIO_TYPES.get(suffix) or _IMAGE_TYPES.get(suffix)
    if media is None:
        raise HTTPException(status_code=415, detail="unsupported media file type")
    asset_type, mime_type = (
        ("video", media) if suffix in _VIDEO_TYPES else
        ("audio", media) if suffix in _AUDIO_TYPES else
        ("image", media)
    )
    declared = request.headers.get("content-length")
    if declared:
        try:
            if int(declared) > _MAX_UPLOAD_BYTES:
                raise HTTPException(status_code=413, detail="media exceeds the 500 MB limit")
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="invalid content-length") from exc
    asset_id = f"asset-{uuid.uuid4().hex}"
    asset_dir = workspace / "assets" / asset_type
    asset_dir.mkdir(parents=True, exist_ok=True)
    destination = asset_dir / f"{asset_id}{Path(filename).suffix.lower()}"
    temporary = destination.with_suffix(destination.suffix + ".uploading")
    size = 0
    try:
        with temporary.open("wb") as output:
            async for chunk in request.stream():
                size += len(chunk)
                if size > _MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="media exceeds the 500 MB limit")
                output.write(chunk)
        if size == 0:
            raise HTTPException(status_code=400, detail="uploaded file is empty")
        from backend.openmontage_adapter import AdapterError, AdapterUnavailable, probe_audio, probe_image, probe_video
        try:
            if asset_type == "video":
                duration, media_info = probe_video(temporary)
            elif asset_type == "audio":
                duration, media_info = probe_audio(temporary)
            else:
                duration, media_info = probe_image(temporary)
        except AdapterUnavailable as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except AdapterError as exc:
            raise HTTPException(status_code=415, detail=str(exc)) from exc
        temporary.replace(destination)
        asset = store.add_asset(
            project_id=project_id, name=Path(filename).name, path=destination,
            mime_type=mime_type, duration=duration, metadata=media_info,
            asset_type=asset_type,
        )
        return _asset_json(asset)
    except HTTPException:
        temporary.unlink(missing_ok=True)
        raise
    except Exception as exc:
        temporary.unlink(missing_ok=True)
        logger.exception("Asset upload failed")
        raise HTTPException(status_code=500, detail="could not store uploaded media") from exc


@app.get("/api/projects/{project_id}/assets")
def list_assets(project_id: str) -> dict[str, Any]:
    if store.get_project(project_id) is None:
        raise HTTPException(status_code=404, detail="project not found")
    return {"items": [_asset_json(asset) for asset in store.list_assets(project_id)]}


@app.get("/api/assets/{asset_id}/file")
def get_asset_file(asset_id: str) -> FileResponse:
    asset = store.get_asset(asset_id)
    if asset is None:
        raise HTTPException(status_code=404, detail="asset not found")
    path = store.safe_media_path(asset.path, asset.project_id)
    if path is None:
        raise HTTPException(status_code=404, detail="asset file not found")
    return FileResponse(path, media_type=asset.mime_type, filename=asset.name)


@app.post("/api/projects/{project_id}/jobs", status_code=202)
def create_job(project_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    if store.get_project(project_id) is None:
        raise HTTPException(status_code=404, detail="project not found")
    if payload.get("type") == "pipeline":
        try:
            pipeline = PipelineJobRequest.model_validate(payload)
        except ValidationError as exc:
            raise HTTPException(status_code=422, detail=exc.errors(include_input=False, include_context=False)) from exc
        if pipeline.project_id != project_id:
            raise HTTPException(status_code=422, detail="project_id does not match URL")
        raise HTTPException(status_code=501, detail="pipeline job execution is not available in Phase 1")
    if payload.get("type") != "capability":
        raise HTTPException(status_code=422, detail="type must be capability or pipeline")
    try:
        capability = CapabilityJobRequest.model_validate(payload)
        if capability.capability == "video_post" and capability.operation == "trim":
            parameters = TrimParameters.model_validate(capability.parameters)
        elif capability.capability == "video_post" and capability.operation == "speed":
            parameters = SpeedParameters.model_validate(capability.parameters)
        elif capability.capability == "video_post" and capability.operation == "crop":
            parameters = CropParameters.model_validate(capability.parameters)
        elif capability.capability == "enhancement" and capability.operation == "color_grade":
            parameters = ColorGradeParameters.model_validate(capability.parameters)
        elif capability.capability == "audio_processing" and capability.operation == "enhance":
            parameters = AudioEnhancementParameters.model_validate(capability.parameters)
        elif capability.capability == "audio_processing" and capability.operation == "volume":
            parameters = AudioVolumeParameters.model_validate(capability.parameters)
        elif capability.capability == "audio_processing" and capability.operation == "trim":
            parameters = AudioTrimParameters.model_validate(capability.parameters)
        elif capability.capability == "video_generation" and capability.operation == "generate":
            parameters = VideoGenerationParameters.model_validate(capability.parameters)
        elif capability.capability == "image_generation" and capability.operation == "generate":
            parameters = ImageGenerationParameters.model_validate(capability.parameters)
        elif capability.capability == "tts" and capability.operation == "generate":
            parameters = TtsGenerationParameters.model_validate(capability.parameters)
        elif capability.capability == "music_generation" and capability.operation == "generate":
            parameters = MusicGenerationParameters.model_validate(capability.parameters)
        elif capability.capability == "analysis" and capability.operation == "transcribe":
            parameters = TranscriptionParameters.model_validate(capability.parameters)
        elif capability.capability == "enhancement" and capability.operation == "upscale":
            parameters = UpscaleParameters.model_validate(capability.parameters)
        elif capability.capability == "video_post" and capability.operation == "render":
            parameters = RenderParameters.model_validate(capability.parameters)
        elif capability.capability == "video_post" and capability.operation == "burn_subtitles":
            parameters = SubtitleBurnParameters.model_validate(capability.parameters)
        elif capability.capability == "subtitle" and capability.operation == "generate":
            parameters = SubtitleGenerateParameters.model_validate(capability.parameters)
        else:
            raise HTTPException(status_code=422, detail="unsupported capability operation")
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors(include_input=False, include_context=False)) from exc
    if capability.project_id != project_id:
        raise HTTPException(status_code=422, detail="project_id does not match URL")
    contracts = _tool_contracts()
    asset = None
    if capability.capability == "video_generation" and capability.operation == "generate":
        selected_tool = next((tool for tool in contracts if tool["tool_id"] == parameters.provider_tool_id), None)
        if selected_tool is None:
            raise HTTPException(status_code=503, detail="provider_not_configured")
        selected_models = selected_tool.get("models", [])
        selected_model = next(
            (model for model in selected_models if model["id"] == parameters.model_id),
            None,
        )
        minimum_vram = int(
            (selected_model or {}).get("vram_mb")
            or selected_tool.get("resource_profile", {}).get("vram_mb")
            or 0
        )
        if selected_tool["status"] != "available":
            if selected_tool.get("runtime") == "local_gpu" or parameters.provider_tool_id == "ltx_video_local":
                available_vram = detect_host_hardware().get("gpu", {}).get("vram_mb")
                if minimum_vram and available_vram is not None and available_vram < minimum_vram:
                    raise HTTPException(status_code=503, detail="unsupported_hardware")
                if not detect_host_hardware().get("cuda", {}).get("available"):
                    raise HTTPException(status_code=503, detail="local_gpu_not_configured")
            raise HTTPException(status_code=503, detail="provider_not_configured")
        if selected_tool.get("runtime") == "local_gpu":
            host = detect_host_hardware()
            available_vram = host.get("gpu", {}).get("vram_mb")
            if available_vram is not None and minimum_vram > available_vram:
                raise HTTPException(status_code=503, detail="unsupported_hardware")
            if not host.get("cuda", {}).get("available"):
                raise HTTPException(status_code=503, detail="local_gpu_not_configured")
        schema = selected_tool.get("input_schema", {})
        properties = schema.get("properties", {})
        supported_modes = properties.get("operation", {}).get("enum", [])
        if parameters.mode not in supported_modes:
            raise HTTPException(status_code=422, detail="Selected provider does not support this generation mode")
        if parameters.mode == "image_to_video" and not any(key in properties for key in ("reference_image_path", "image_path", "input_image_path")):
            raise HTTPException(status_code=422, detail="Selected provider does not accept a reference image")
        if parameters.mode == "reference_to_video" and not any(key in properties for key in ("reference_video_path", "input_video_path", "video_path", "video_paths")):
            raise HTTPException(status_code=422, detail="Selected provider does not accept a reference video file")
        ratio_values = properties.get("aspect_ratio", {}).get("enum")
        if ratio_values and parameters.aspect_ratio not in ratio_values:
            raise HTTPException(status_code=422, detail="Selected provider does not support this aspect ratio")
        duration_enum = properties.get("duration_hint", {}).get("enum")
        if duration_enum:
            duration_hint = f"{parameters.duration_seconds:g}s"
            if duration_hint not in duration_enum:
                raise HTTPException(status_code=422, detail="Selected provider does not support this duration")
        fps_enum = properties.get("fps", {}).get("enum")
        if fps_enum and parameters.fps is not None and parameters.fps not in fps_enum:
            raise HTTPException(status_code=422, detail="Selected provider does not support this frame rate")
        for parameter_name, parameter_value in (
            ("num_frames", parameters.num_frames),
            ("num_inference_steps", parameters.num_inference_steps),
            ("guidance_scale", capability.parameters.get("guidance_scale")),
        ):
            if parameter_value is None:
                continue
            limits = properties.get(parameter_name, {})
            if "minimum" in limits and parameter_value < limits["minimum"]:
                raise HTTPException(status_code=422, detail=f"{parameter_name} is below the selected provider minimum")
            if "maximum" in limits and parameter_value > limits["maximum"]:
                raise HTTPException(status_code=422, detail=f"{parameter_name} exceeds the selected provider maximum")
        if parameters.model_id:
            model_ids = [model["id"] for model in selected_models]
            if model_ids and parameters.model_id not in model_ids:
                raise HTTPException(status_code=422, detail="Selected model is not advertised by this provider")
            model_modes = (selected_model or {}).get("operations")
            if model_modes and parameters.mode not in model_modes:
                raise HTTPException(status_code=422, detail="Selected model does not support this generation mode")
    if capability.capability == "image_generation" and capability.operation == "generate":
        selected_tool = next((tool for tool in contracts if tool["tool_id"] == parameters.provider_tool_id), None)
        if selected_tool is None or selected_tool["status"] != "available":
            raise HTTPException(status_code=503, detail="provider_not_configured")
        properties = selected_tool.get("input_schema", {}).get("properties", {})
        if (parameters.reference_artifact_id or capability.input_asset_ids) and not any(key in properties for key in ("image_path", "image_paths", "image")):
            raise HTTPException(status_code=422, detail="Selected image provider does not accept a reference image")
        if parameters.model_id:
            models = selected_tool.get("models", [])
            model_ids = [model["id"] for model in models]
            if model_ids and parameters.model_id not in model_ids:
                raise HTTPException(status_code=422, detail="Selected model is not advertised by this provider")
            selected_model = next((model for model in models if model["id"] == parameters.model_id), None)
            model_operations = (selected_model or {}).get("operations")
            if model_operations and "generate" not in model_operations:
                raise HTTPException(status_code=422, detail="Selected model does not support image generation")
        schema_properties = selected_tool.get("input_schema", {}).get("properties", {})
        ratio_values = schema_properties.get("aspect_ratio", {}).get("enum")
        if ratio_values and parameters.aspect_ratio not in ratio_values:
            raise HTTPException(status_code=422, detail="Selected image provider does not support this aspect ratio")
        resolution_values = schema_properties.get("resolution", {}).get("enum")
        if resolution_values and parameters.resolution not in resolution_values:
            raise HTTPException(status_code=422, detail="Selected image provider does not support this resolution")
    if capability.capability == "tts" and capability.operation == "generate":
        selected_tool = next((tool for tool in contracts if tool["tool_id"] == parameters.provider_tool_id), None)
        if selected_tool is None or selected_tool["status"] != "available":
            raise HTTPException(status_code=503, detail="provider_not_configured")
        properties = selected_tool.get("input_schema", {}).get("properties", {})
        text_schema = properties.get("text", {})
        max_text_length = text_schema.get("maxLength")
        min_text_length = text_schema.get("minLength")
        if min_text_length is not None and len(parameters.text) < min_text_length:
            raise HTTPException(status_code=422, detail="TTS text is shorter than this provider allows")
        if max_text_length is not None and len(parameters.text) > max_text_length:
            raise HTTPException(status_code=422, detail="TTS text is longer than this provider allows")
        if capability.input_asset_ids:
            raise HTTPException(status_code=422, detail="TTS generation does not accept input assets")
        if parameters.model_id:
            models = selected_tool.get("models", [])
            model_ids = [model["id"] for model in models]
            if model_ids and parameters.model_id not in model_ids:
                raise HTTPException(status_code=422, detail="Selected TTS model is not advertised by this provider")
        for field, value in (("voice", parameters.voice), ("voice_id", parameters.voice_id), ("language_code", parameters.language_code), ("voice_language", parameters.voice_language), ("format", parameters.format), ("response_format", parameters.response_format)):
            allowed = properties.get(field, {}).get("enum")
            if value is not None and allowed and value not in allowed:
                raise HTTPException(status_code=422, detail=f"Selected TTS provider does not support this {field}")
        for field, value in (("speed", parameters.speed), ("speaking_rate", parameters.speaking_rate), ("voice_speed", parameters.voice_speed), ("pitch", parameters.pitch), ("length_scale", parameters.length_scale), ("sentence_silence", parameters.sentence_silence)):
            if value is None:
                continue
            schema = properties.get(field, {})
            if value < schema.get("minimum", value) or value > schema.get("maximum", value):
                raise HTTPException(status_code=422, detail=f"Selected TTS provider does not support this {field} value")
    if capability.capability == "music_generation" and capability.operation == "generate":
        selected_tool = next((tool for tool in contracts if tool["tool_id"] == parameters.provider_tool_id), None)
        if selected_tool is None or selected_tool["status"] != "available":
            raise HTTPException(status_code=503, detail="provider_not_configured")
        if capability.input_asset_ids:
            raise HTTPException(status_code=422, detail="Music generation does not accept input assets")
        schema = selected_tool.get("input_schema", {})
        properties = schema.get("properties", {})
        required = set(schema.get("required", []))
        prompt_schema = properties.get("prompt", {})
        if prompt_schema.get("minLength") is not None and len(parameters.prompt) < prompt_schema["minLength"]:
            raise HTTPException(status_code=422, detail="Music prompt is shorter than this provider allows")
        if prompt_schema.get("maxLength") is not None and len(parameters.prompt) > prompt_schema["maxLength"]:
            raise HTTPException(status_code=422, detail="Music prompt is longer than this provider allows")
        duration_field = "duration_seconds" if "duration_seconds" in properties else "duration" if "duration" in properties else None
        if duration_field in required and parameters.duration_seconds is None:
            raise HTTPException(status_code=422, detail="This music provider requires a target duration")
        if parameters.duration_seconds is not None:
            duration_schema = properties.get("duration_seconds") or properties.get("duration") or {}
            minimum = duration_schema.get("minimum")
            maximum = duration_schema.get("maximum")
            if minimum is not None and parameters.duration_seconds < minimum:
                raise HTTPException(status_code=422, detail="Music duration is shorter than this provider allows")
            if maximum is not None and parameters.duration_seconds > maximum:
                raise HTTPException(status_code=422, detail="Music duration is longer than this provider allows")
        for field, value in (("instrumental", parameters.instrumental), ("force_instrumental", parameters.force_instrumental), ("custom_mode", parameters.custom_mode), ("model", parameters.model), ("output_format", parameters.output_format), ("format", parameters.format)):
            allowed = properties.get(field, {}).get("enum")
            if value is not None and allowed and value not in allowed:
                raise HTTPException(status_code=422, detail=f"Selected music provider does not support this {field}")
        for field, value in (("style", parameters.style), ("title", parameters.title)):
            if value is None:
                continue
            field_schema = properties.get(field, {})
            if field_schema.get("maxLength") is not None and len(value) > field_schema["maxLength"]:
                raise HTTPException(status_code=422, detail=f"Music {field} is longer than this provider allows")
        if parameters.model_id:
            models = selected_tool.get("models", [])
            model_ids = [model["id"] for model in models]
            if model_ids and parameters.model_id not in model_ids:
                raise HTTPException(status_code=422, detail="Selected music model is not advertised by this provider")
    if capability.capability == "analysis" and capability.operation == "transcribe":
        selected_tool = next((tool for tool in contracts if tool["tool_id"] == parameters.provider_tool_id), None)
        if selected_tool is None or selected_tool["status"] != "available":
            raise HTTPException(status_code=503, detail="provider_not_configured")
        properties = selected_tool.get("input_schema", {}).get("properties", {})
        model_enum = properties.get("model_size", {}).get("enum", [])
        if model_enum and parameters.model_size not in model_enum:
            raise HTTPException(status_code=422, detail="Selected transcription model is not supported")
        if not capability.input_asset_ids:
            raise HTTPException(status_code=422, detail="Transcription requires one audio or video asset")
    if capability.capability == "enhancement" and capability.operation == "upscale":
        selected_tool = next((tool for tool in contracts if tool["tool_id"] == parameters.provider_tool_id), None)
        if selected_tool is None or selected_tool["status"] != "available":
            raise HTTPException(status_code=503, detail="provider_not_configured")
        properties = selected_tool.get("input_schema", {}).get("properties", {})
        scales = properties.get("scale", {}).get("enum", [])
        if scales and parameters.scale not in scales:
            raise HTTPException(status_code=422, detail="Selected upscaler does not support this scale")
        models = properties.get("model", {}).get("enum", [])
        if parameters.model_id and models and parameters.model_id not in models:
            raise HTTPException(status_code=422, detail="Selected upscale model is not supported")
        if len(capability.input_asset_ids) != 1:
            raise HTTPException(status_code=422, detail="Upscale requires exactly one image or video asset")
    if capability.operation not in _mobile_operations(capability.capability, contracts):
        raise HTTPException(status_code=503, detail="The requested OpenMontage tool is unavailable")
    if capability.capability == "enhancement" and capability.operation == "color_grade":
        grader = next((tool for tool in contracts if tool["tool_id"] == "color_grade"), None)
        profiles = (
            grader.get("input_schema", {}).get("properties", {}).get("profile", {}).get("enum", [])
            if grader else []
        )
        if parameters.profile not in profiles:
            raise HTTPException(status_code=422, detail="The selected color grade profile is not supported")
    if capability.capability == "video_post" and capability.operation == "crop":
        reframer = next((tool for tool in contracts if tool["tool_id"] == "auto_reframe"), None)
        aspects = reframer.get("input_schema", {}).get("properties", {}).get("target_aspect", {}).get("enum", []) if reframer else []
        if parameters.target_aspect not in aspects:
            raise HTTPException(status_code=422, detail="The selected crop aspect is not supported")
    if capability.capability == "audio_processing" and capability.operation == "enhance":
        enhancer = next((tool for tool in contracts if tool["tool_id"] == "audio_enhance"), None)
        presets = (
            enhancer.get("input_schema", {}).get("properties", {}).get("preset", {}).get("enum", [])
            if enhancer else []
        )
        if parameters.preset not in presets:
            raise HTTPException(status_code=422, detail="The selected audio enhancement preset is not supported")
    if capability.capability == "audio_processing" and capability.operation == "volume":
        mixer = next((tool for tool in contracts if tool["tool_id"] == "audio_mixer"), None)
        volume_schema = (
            mixer.get("input_schema", {}).get("properties", {}).get("tracks", {}).get("items", {}).get("properties", {}).get("volume", {})
            if mixer else {}
        )
        if not volume_schema or not volume_schema.get("minimum") == 0 or not volume_schema.get("maximum") == 1.0:
            raise HTTPException(status_code=503, detail="OpenMontage audio volume control is unavailable")
    if capability.capability == "audio_processing" and capability.operation == "trim":
        mixer = next((tool for tool in contracts if tool["tool_id"] == "audio_mixer"), None)
        operations = mixer.get("input_schema", {}).get("properties", {}).get("operation", {}).get("enum", []) if mixer else []
        if mixer is None or mixer["status"] != "available" or "trim" not in operations:
            raise HTTPException(status_code=503, detail="OpenMontage audio trim is unavailable")
    if capability.capability == "image_generation" and capability.operation == "generate":
        asset = None
        if parameters.reference_artifact_id:
            if capability.input_asset_ids:
                raise HTTPException(status_code=422, detail="Use one reference image asset or artifact, not both")
            reference = store.get_artifact(parameters.reference_artifact_id)
            if reference is None or reference.project_id != project_id or reference.type != "image":
                raise HTTPException(status_code=422, detail="reference_artifact_id must refer to an image artifact in this project")
        elif capability.input_asset_ids:
            if len(capability.input_asset_ids) != 1:
                raise HTTPException(status_code=422, detail="Image editing accepts exactly one reference image")
            asset = store.get_asset(capability.input_asset_ids[0])
            if asset is None or asset.project_id != project_id or asset.type != "image":
                raise HTTPException(status_code=422, detail="Reference image must be an image asset in this project")
    elif capability.capability == "video_generation" and capability.operation == "generate":
        if parameters.mode == "image_to_video":
            if parameters.reference_artifact_id:
                if capability.input_asset_ids:
                    raise HTTPException(status_code=422, detail="Use one reference image asset or artifact, not both")
                reference = store.get_artifact(parameters.reference_artifact_id)
                if reference is None or reference.project_id != project_id or reference.type != "image":
                    raise HTTPException(status_code=422, detail="reference_artifact_id must refer to an image artifact in this project")
            else:
                if len(capability.input_asset_ids) != 1:
                    raise HTTPException(status_code=422, detail="image_to_video requires exactly one reference image asset")
                asset = store.get_asset(capability.input_asset_ids[0])
                if asset is None or asset.project_id != project_id or asset.type != "image":
                    raise HTTPException(status_code=422, detail="reference image must be an image asset in this project")
        elif parameters.mode == "reference_to_video":
            if parameters.reference_artifact_id:
                if capability.input_asset_ids:
                    raise HTTPException(status_code=422, detail="Use one reference video asset or artifact, not both")
                reference = store.get_artifact(parameters.reference_artifact_id)
                if reference is None or reference.project_id != project_id or reference.type != "video":
                    raise HTTPException(status_code=422, detail="reference_artifact_id must refer to a video artifact in this project")
            else:
                if len(capability.input_asset_ids) != 1:
                    raise HTTPException(status_code=422, detail="reference_to_video requires exactly one reference video asset")
                asset = store.get_asset(capability.input_asset_ids[0])
                if asset is None or asset.project_id != project_id or asset.type != "video":
                    raise HTTPException(status_code=422, detail="reference_to_video requires a video asset in this project")
        elif capability.input_asset_ids:
            raise HTTPException(status_code=422, detail="text_to_video does not accept input assets")
    elif capability.capability == "subtitle" and capability.operation == "generate":
        generator = next((tool for tool in contracts if tool["tool_id"] == "subtitle_gen"), None)
        formats = generator.get("input_schema", {}).get("properties", {}).get("format", {}).get("enum", []) if generator else []
        if parameters.format not in formats:
            raise HTTPException(status_code=422, detail="The selected subtitle format is not supported")
        if capability.input_asset_ids:
            raise HTTPException(status_code=422, detail="Manual subtitle generation does not accept media assets")
        asset = None
    elif capability.capability == "tts" and capability.operation == "generate":
        if capability.input_asset_ids:
            raise HTTPException(status_code=422, detail="TTS generation does not accept media assets")
        asset = None
    elif capability.capability == "music_generation" and capability.operation == "generate":
        if capability.input_asset_ids:
            raise HTTPException(status_code=422, detail="Music generation does not accept media assets")
        asset = None
    elif capability.capability == "analysis" and capability.operation == "transcribe":
        if len(capability.input_asset_ids) != 1:
            raise HTTPException(status_code=422, detail="Transcription requires exactly one audio or video asset")
        asset = store.get_asset(capability.input_asset_ids[0])
        if asset is None or asset.project_id != project_id or asset.type not in {"audio", "video"}:
            raise HTTPException(status_code=422, detail="Transcription input must be an audio or video asset in this project")
    elif capability.capability == "enhancement" and capability.operation == "upscale":
        asset = store.get_asset(capability.input_asset_ids[0])
        if asset is None or asset.project_id != project_id or asset.type not in {"image", "video"}:
            raise HTTPException(status_code=422, detail="Upscale input must be an image or video asset in this project")
    elif capability.capability == "video_post" and capability.operation == "render":
        if len(capability.input_asset_ids) < 2 or len(capability.input_asset_ids) > 30:
            raise HTTPException(status_code=422, detail="render requires between 2 and 30 video assets")
        assets = [store.get_asset(asset_id) for asset_id in capability.input_asset_ids]
        if any(asset is None or asset.project_id != project_id or asset.type != "video" for asset in assets):
            raise HTTPException(status_code=422, detail="render inputs must be video assets in this project")
        asset = None
    elif capability.capability == "video_post" and capability.operation == "burn_subtitles":
        if len(capability.input_asset_ids) != 1:
            raise HTTPException(status_code=422, detail="burn_subtitles requires exactly one video asset")
        asset = store.get_asset(capability.input_asset_ids[0])
        if asset is None or asset.project_id != project_id or asset.type != "video":
            raise HTTPException(status_code=422, detail="burn_subtitles requires a video asset in this project")
        subtitle = store.get_artifact(parameters.subtitle_artifact_id)
        if subtitle is None or subtitle.project_id != project_id or subtitle.type != "subtitle":
            raise HTTPException(status_code=422, detail="subtitle_artifact_id must refer to a subtitle artifact in this project")
    else:
        if len(capability.input_asset_ids) != 1:
            raise HTTPException(status_code=422, detail=f"{capability.operation} requires exactly one input_asset_id")
        asset = store.get_asset(capability.input_asset_ids[0])
        if asset is None or asset.project_id != project_id:
            raise HTTPException(status_code=404, detail="input asset not found in this project")
        expected_asset_type = "audio" if capability.capability == "audio_processing" else "video"
        if asset.type != expected_asset_type:
            raise HTTPException(status_code=422, detail=f"This operation requires an {expected_asset_type} asset")
    if asset is not None and capability.capability == "video_post" and capability.operation == "trim" and parameters.end > (asset.duration or 0):
        raise HTTPException(status_code=422, detail="end must not exceed the video duration")
    request_input = capability.model_dump(mode="json")
    request_input["parameters"] = parameters.model_dump()
    job = store.create_job(
        project_id=project_id, capability=capability.capability, operation=capability.operation,
        request_input=request_input,
    )
    job_runner.submit(job.id)
    return _job_json(job)


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str) -> dict[str, Any]:
    job = store.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    return _job_json(job)


@app.post("/api/jobs/{job_id}/cancel")
def cancel_job(job_id: str) -> dict[str, Any]:
    job = store.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    if job.status in {JobStatus.completed, JobStatus.failed, JobStatus.cancelled}:
        raise HTTPException(status_code=409, detail=f"job is already {job.status.value}")
    if not job_runner.cancel_queued(job_id):
        raise HTTPException(status_code=409, detail="job is already running and cannot be cancelled")
    return _job_json(store.get_job(job_id))


@app.get("/api/jobs/{job_id}/artifacts")
def list_job_artifacts(job_id: str) -> dict[str, Any]:
    if store.get_job(job_id) is None:
        raise HTTPException(status_code=404, detail="job not found")
    return {"items": [_artifact_json(artifact) for artifact in store.list_artifacts(job_id)]}


@app.get("/api/artifacts/{artifact_id}/file")
def get_artifact_file(artifact_id: str) -> FileResponse:
    artifact = store.get_artifact(artifact_id)
    if artifact is None:
        raise HTTPException(status_code=404, detail="artifact not found")
    path = store.safe_media_path(artifact.path, artifact.project_id)
    if path is None:
        raise HTTPException(status_code=404, detail="artifact file not found")
    return FileResponse(path, media_type=artifact.mime_type, filename=path.name)


@app.post("/api/videos", deprecated=True, summary="LEGACY: synthetic compose demo")
def create_video_job(payload: dict) -> dict:
    title = str(payload.get("title") or "Untitled OpenMontage job")
    prompt = str(payload.get("prompt") or "")
    style = str(payload.get("style") or "Cinematic")
    duration = str(payload.get("duration") or "30s")

    if not prompt.strip():
        raise HTTPException(status_code=400, detail="prompt is required")

    job = legacy_store.create(title=title, prompt=prompt, style=style, duration=duration)
    thread = threading.Thread(target=process_video_job, args=(job,), daemon=True)
    thread.start()
    return {
        "job_id": job.job_id,
        "project_id": job.project_id,
        "status": job.status,
        "generation_mode": job.generation_mode,
        "adapter_note": job.adapter_note,
    }


@app.get("/api/videos/{job_id}", deprecated=True, summary="LEGACY: synthetic compose demo status")
def get_video_job(job_id: str) -> dict:
    job = legacy_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    response = job.to_api_dict()
    if job.status == "completed" and job.video_path:
        response["video_url"] = f"/api/videos/{job_id}/file"
    return response


@app.get("/api/videos/{job_id}/file", deprecated=True, summary="LEGACY: synthetic compose demo output")
def get_video_file(job_id: str) -> FileResponse:
    job = legacy_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    if not job.video_path:
        raise HTTPException(status_code=404, detail="video not ready")

    file_path = Path(job.video_path)
    if not file_path.is_file():
        raise HTTPException(status_code=404, detail="video file missing")

    return FileResponse(file_path, media_type="video/mp4", filename=file_path.name)
