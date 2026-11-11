from __future__ import annotations

import shutil
import json
import io
import subprocess
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from backend import app as backend_app
from backend.jobs import VideoTrimJobRunner
from backend.models import JobStatus
from backend.storage import BackendStore
from tools.base_tool import ToolResult, ToolStatus


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None or shutil.which("ffprobe") is None:
        pytest.skip("FFmpeg and FFprobe are required for Phase 1 backend tests")
    projects = tmp_path / "projects"
    db = BackendStore(tmp_path / "mobile.sqlite3", projects_root=projects)
    monkeypatch.setattr(backend_app, "store", db)
    monkeypatch.setattr(backend_app, "job_runner", VideoTrimJobRunner(db))
    return TestClient(backend_app.app)


@pytest.fixture
def sample_video(tmp_path: Path) -> Path:
    path = tmp_path / "sample.mp4"
    subprocess.run(
        [shutil.which("ffmpeg") or "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
         "-f", "lavfi", "-i", "testsrc=size=160x120:rate=12:duration=2",
         "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(path)],
        check=True, capture_output=True,
    )
    return path


@pytest.fixture
def sample_audio(tmp_path: Path) -> Path:
    path = tmp_path / "sample.wav"
    subprocess.run(
        [shutil.which("ffmpeg") or "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
         "-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-c:a", "pcm_s16le", str(path)],
        check=True, capture_output=True,
    )
    return path


def _project(client: TestClient) -> str:
    response = client.post("/api/projects", json={"name": "Trim test"})
    assert response.status_code == 201, response.text
    project_id = response.json()["id"]
    assert "workspace_path" not in response.json()
    assert client.get("/api/projects").json()["items"][0]["id"] == project_id
    assert client.get(f"/api/projects/{project_id}").status_code == 200
    return project_id


def _upload(client: TestClient, project_id: str, sample_video: Path) -> str:
    response = client.post(
        f"/api/projects/{project_id}/assets?filename=sample.mp4",
        content=sample_video.read_bytes(),
        headers={"content-type": "application/octet-stream"},
    )
    assert response.status_code == 201, response.text
    asset = response.json()
    assert asset["type"] == "video"
    assert asset["duration"] == pytest.approx(2.0, abs=0.2)
    assert "path" not in asset
    assert client.get(f"/api/projects/{project_id}/assets").json()["items"]
    downloaded = client.get(asset["file_url"])
    assert downloaded.status_code == 200
    assert downloaded.content[:4] == b"\x00\x00\x00\x18" or b"ftyp" in downloaded.content[:16]
    return asset["id"]


def _video_trimmer_contract() -> dict:
    return {
        "tool_id": "video_trimmer", "capability_id": "video_post",
        "provider_id": "ffmpeg", "status": "available",
        "operations": ["cut", "speed_adjust", "concat"],
        "input_schema": {"properties": {"operation": {"enum": ["cut", "speed", "concat"]}}},
        "output_schema": {}, "artifact_schema": {}, "models": [],
        "supports": {}, "resource_profile": {},
    }


def test_health_and_project_crud(client: TestClient) -> None:
    assert client.get("/api/health").json()["status"] == "ok"
    project_id = _project(client)
    assert client.get(f"/api/projects/{project_id}").status_code == 200
    assert client.get("/api/projects/missing").status_code == 404


def test_runtime_hardware_reports_ltx_vram_limit(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(backend_app, "detect_host_hardware", lambda: {
        "cpu": {"name": "Test CPU", "logical_cores": 8},
        "ram_mb": 16384,
        "gpu": {"available": True, "name": "GTX 1650", "vram_mb": 4096, "driver_version": "test"},
        "cuda": {"available": True, "runtime_version": "test", "reason": None},
    })
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "ltx_video_local", "capability_id": "video_generation",
        "provider_id": "ltx", "status": "unavailable", "operations": ["text_to_video"],
        "input_schema": {}, "output_schema": {}, "artifact_schema": {}, "models": [],
        "supports": {}, "resource_profile": {"vram_mb": 12000},
    }])
    response = client.get("/api/runtime/hardware")
    assert response.status_code == 200
    diagnostics = response.json()
    assert diagnostics["gpu"]["vram_mb"] == 4096
    assert diagnostics["local_video_generation"]["required_vram_mb"] == 12000
    assert diagnostics["local_video_generation"]["status"] == "unsupported_hardware"


def test_crop_job_uses_openmontage_auto_reframe_and_returns_video_artifact(
    client: TestClient, sample_video: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "auto_reframe", "capability_id": "video_post",
        "provider_id": "ffmpeg", "status": "available",
        "operations": ["aspect_ratio_conversion", "center_crop"],
        "input_schema": {"properties": {"target_aspect": {"enum": ["portrait", "square", "landscape", "cinematic", "vertical_4_5"]}}},
        "output_schema": {}, "artifact_schema": {}, "models": [],
        "supports": {}, "resource_profile": {},
    }])
    project_id = _project(client)
    asset_id = _upload(client, project_id, sample_video)
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "video_post", "operation": "crop",
        "project_id": project_id, "input_asset_ids": [asset_id],
        "parameters": {"target_aspect": "square"},
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifact = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "video"
    assert artifact["metadata"]["tool"] == "auto_reframe"
    assert artifact["metadata"]["target_aspect"] == "square"
    media = client.get(artifact["download_url"])
    assert media.status_code == 200
    assert b"ftyp" in media.content[:16]


def test_project_render_uses_openmontage_video_stitch_and_returns_artifact(
    client: TestClient, sample_video: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "video_stitch", "capability_id": "video_post",
        "provider_id": "ffmpeg", "status": "available",
        "operations": ["validate", "stitch", "preview_stitch", "spatial"],
        "input_schema": {"properties": {"operation": {"enum": ["validate", "stitch", "preview_stitch", "spatial"]}}},
        "output_schema": {}, "artifact_schema": {}, "models": [],
        "supports": {}, "resource_profile": {},
    }])
    project_id = _project(client)
    first_id = _upload(client, project_id, sample_video)
    second_id = _upload(client, project_id, sample_video)
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "video_post", "operation": "render",
        "project_id": project_id, "input_asset_ids": [first_id, second_id],
        "parameters": {"transition": "cut"},
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifact = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "video"
    assert artifact["metadata"]["tool"] == "video_stitch"
    assert artifact["metadata"]["source_asset_ids"] == [first_id, second_id]
    media = client.get(artifact["download_url"])
    assert media.status_code == 200
    assert b"ftyp" in media.content[:16]


def test_subtitle_artifact_can_be_burned_into_project_video(
    client: TestClient, sample_video: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [
        {
            "tool_id": "subtitle_gen", "capability_id": "subtitle",
            "provider_id": "openmontage", "status": "available",
            "operations": ["generate_srt", "generate_vtt"],
            "input_schema": {"properties": {"format": {"enum": ["srt", "vtt"]}}},
            "output_schema": {}, "artifact_schema": {}, "models": [],
            "supports": {}, "resource_profile": {},
        },
        {
            "tool_id": "video_compose", "capability_id": "video_post",
            "provider_id": "ffmpeg", "status": "available",
            "operations": ["burn_subtitles"],
            "input_schema": {"properties": {"operation": {"enum": ["burn_subtitles"]}}},
            "output_schema": {}, "artifact_schema": {}, "models": [],
            "supports": {}, "resource_profile": {},
        },
    ])
    project_id = _project(client)
    video_id = _upload(client, project_id, sample_video)
    subtitle_response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "subtitle", "operation": "generate",
        "project_id": project_id, "input_asset_ids": [],
        "parameters": {"format": "srt", "segments": [{"text": "Hello OpenMontage", "start": 0, "end": 1}]},
    })
    assert subtitle_response.status_code == 202, subtitle_response.text
    subtitle_job_id = subtitle_response.json()["id"]
    subtitle_job = None
    for _ in range(100):
        subtitle_job = client.get(f"/api/jobs/{subtitle_job_id}").json()
        if subtitle_job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert subtitle_job and subtitle_job["status"] == "completed", subtitle_job
    subtitle_artifact = client.get(
        f"/api/jobs/{subtitle_job_id}/artifacts",
    ).json()["items"][0]

    burn_response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "video_post", "operation": "burn_subtitles",
        "project_id": project_id, "input_asset_ids": [video_id],
        "parameters": {"subtitle_artifact_id": subtitle_artifact["id"]},
    })
    assert burn_response.status_code == 202, burn_response.text
    burn_job_id = burn_response.json()["id"]
    burn_job = None
    for _ in range(100):
        burn_job = client.get(f"/api/jobs/{burn_job_id}").json()
        if burn_job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert burn_job and burn_job["status"] == "completed", burn_job
    artifact = client.get(f"/api/jobs/{burn_job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "video"
    assert artifact["metadata"]["tool"] == "video_compose"
    assert artifact["metadata"]["source_subtitle_artifact_id"] == subtitle_artifact["id"]
    media = client.get(artifact["download_url"])
    assert media.status_code == 200
    assert b"ftyp" in media.content[:16]


def test_subtitle_job_formats_manual_timed_cues_as_vtt_artifact(
    client: TestClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "subtitle_gen", "capability_id": "subtitle",
        "provider_id": "openmontage", "status": "available",
        "operations": ["generate_srt", "generate_vtt"],
        "input_schema": {"properties": {"format": {"enum": ["srt", "vtt", "json"]}}},
        "output_schema": {}, "artifact_schema": {}, "models": [],
        "supports": {}, "resource_profile": {},
    }])
    project_id = _project(client)
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "subtitle", "operation": "generate",
        "project_id": project_id, "input_asset_ids": [],
        "parameters": {
            "format": "vtt",
            "segments": [
                {"text": "Hello OpenMontage", "start": 0.0, "end": 1.8},
                {"text": "This is a timed subtitle", "start": 2.0, "end": 4.2},
            ],
        },
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifact = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "subtitle"
    assert artifact["mime_type"] == "text/vtt"
    assert artifact["metadata"]["format"] == "vtt"
    response = client.get(artifact["download_url"])
    assert response.status_code == 200
    assert response.text.startswith("WEBVTT")


def test_runtime_capability_provider_and_model_catalog(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        backend_app,
        "_tool_contracts",
        lambda: [
            {
                "tool_id": "ltx_video_local", "capability_id": "video_generation",
                "provider_id": "ltx", "status": "unavailable", "operations": ["text_to_video"],
                "input_schema": {}, "output_schema": {}, "artifact_schema": {},
                "models": [{"id": "ltx2-local", "name": "LTX-2 Local"}],
                "supports": {}, "resource_profile": {"vram_mb": 12000},
            },
            {
                "tool_id": "video_selector", "capability_id": "video_generation",
                "provider_id": "selector", "status": "unavailable", "operations": [],
                "input_schema": {}, "output_schema": {}, "artifact_schema": {},
                "models": [], "supports": {}, "resource_profile": {},
            },
            {
                "tool_id": "video_trimmer", "capability_id": "video_post",
                "provider_id": "ffmpeg", "status": "available", "operations": ["cut", "speed", "concat"],
                "input_schema": {"properties": {"operation": {"enum": ["cut", "speed", "concat"]}}},
                "output_schema": {}, "artifact_schema": {}, "models": [],
                "supports": {}, "resource_profile": {},
            },
            {
                "tool_id": "color_grade", "capability_id": "enhancement",
                "provider_id": "ffmpeg", "status": "available", "operations": ["grade_preset"],
                "input_schema": {"properties": {"profile": {"enum": ["cinematic_warm", "neutral"]}}},
                "output_schema": {}, "artifact_schema": {}, "models": [],
                "supports": {}, "resource_profile": {},
            },
        ],
    )
    capabilities = client.get("/api/capabilities").json()["items"]
    video = next(item for item in capabilities if item["id"] == "video_generation")
    assert video["status"] == "unavailable"
    assert video["provider_count"] == 1
    providers = client.get("/api/providers?capability=video_generation").json()["items"]
    assert [item["provider_id"] for item in providers] == ["ltx"]
    models = client.get("/api/models?capability=video_generation&provider=ltx").json()["items"]
    assert models[0]["id"] == "ltx2-local"
    assert models[0]["status"] == "unavailable"
    video_post = next(item for item in capabilities if item["id"] == "video_post")
    assert video_post["mobile_job_operations"] == ["trim", "speed"]
    enhancement = next(item for item in capabilities if item["id"] == "enhancement")
    assert enhancement["mobile_job_operations"] == ["color_grade"]


def test_upload_validation_rejects_traversal_and_non_video(client: TestClient) -> None:
    project_id = _project(client)
    assert client.post(f"/api/projects/{project_id}/assets?filename=..%2Fescape.mp4", content=b"x").status_code == 422
    assert client.post(f"/api/projects/{project_id}/assets?filename=notes.txt", content=b"x").status_code == 415
    assert client.post(f"/api/projects/{project_id}/assets?filename=bad.mp4", content=b"not video").status_code == 415


def test_image_asset_upload_validates_and_stores_backend_image(client: TestClient, tmp_path: Path) -> None:
    from PIL import Image

    image_path = tmp_path / "reference.png"
    Image.new("RGB", (32, 24), color=(40, 80, 160)).save(image_path)
    project_id = _project(client)
    response = client.post(
        f"/api/projects/{project_id}/assets?filename=reference.png",
        content=image_path.read_bytes(),
        headers={"content-type": "application/octet-stream"},
    )
    assert response.status_code == 201, response.text
    asset = response.json()
    assert asset["type"] == "image"
    assert asset["duration"] is None
    assert asset["metadata"] == {"format": "png", "width": 32, "height": 24}
    downloaded = client.get(asset["file_url"])
    assert downloaded.status_code == 200
    assert downloaded.content.startswith(b"\x89PNG")
    invalid = client.post(
        f"/api/projects/{project_id}/assets?filename=invalid.png",
        content=b"not a png",
        headers={"content-type": "application/octet-stream"},
    )
    assert invalid.status_code == 415


def test_trim_job_persists_and_downloads_valid_artifact(
    client: TestClient, sample_video: Path, tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [_video_trimmer_contract()])
    project_id = _project(client)
    asset_id = _upload(client, project_id, sample_video)
    response = client.post(
        f"/api/projects/{project_id}/jobs",
        json={
            "type": "capability", "capability": "video_post", "operation": "trim",
            "project_id": project_id, "input_asset_ids": [asset_id],
            "parameters": {"start": 0.25, "end": 1.5},
        },
    )
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    assert response.json()["status"] in {"queued", "running"}

    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    assert job["progress"] == 100

    artifacts = client.get(f"/api/jobs/{job_id}/artifacts")
    assert artifacts.status_code == 200
    artifact = artifacts.json()["items"][0]
    assert artifact["mime_type"] == "video/mp4"
    assert "path" not in artifact
    media = client.get(artifact["download_url"])
    assert media.status_code == 200
    assert b"ftyp" in media.content[:16]

    db = BackendStore(tmp_path / "mobile.sqlite3", projects_root=tmp_path / "projects")
    assert db.get_job(job_id).status.value == "completed"
    assert db.get_artifact(artifact["id"]).size == len(media.content)


def test_speed_job_uses_openmontage_tool_and_returns_video_artifact(
    client: TestClient, sample_video: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [_video_trimmer_contract()])
    project_id = _project(client)
    asset_id = _upload(client, project_id, sample_video)
    response = client.post(
        f"/api/projects/{project_id}/jobs",
        json={
            "type": "capability", "capability": "video_post", "operation": "speed",
            "project_id": project_id, "input_asset_ids": [asset_id],
            "parameters": {"speed_factor": 2.0},
        },
    )
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]

    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job

    artifacts = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"]
    assert len(artifacts) == 1
    artifact = artifacts[0]
    assert artifact["type"] == "video"
    assert artifact["metadata"]["operation"] == "speed"
    assert artifact["metadata"]["speed_factor"] == 2.0
    media = client.get(artifact["download_url"])
    assert media.status_code == 200
    assert b"ftyp" in media.content[:16]


def test_color_grade_job_uses_openmontage_tool_and_saves_project_artifact(
    client: TestClient, sample_video: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        backend_app,
        "_tool_contracts",
        lambda: [{
            "tool_id": "color_grade", "capability_id": "enhancement",
            "provider_id": "ffmpeg", "status": "available",
            "operations": ["grade_preset"],
            "input_schema": {"properties": {"profile": {
                "enum": ["cinematic_warm", "cinematic_cool", "neutral"],
            }}},
            "output_schema": {}, "artifact_schema": {}, "models": [],
            "supports": {}, "resource_profile": {},
        }],
    )
    project_id = _project(client)
    asset_id = _upload(client, project_id, sample_video)
    response = client.post(
        f"/api/projects/{project_id}/jobs",
        json={
            "type": "capability", "capability": "enhancement",
            "operation": "color_grade", "project_id": project_id,
            "input_asset_ids": [asset_id],
            "parameters": {"profile": "cinematic_warm", "intensity": 0.8},
        },
    )
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifacts = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"]
    assert len(artifacts) == 1
    artifact = artifacts[0]
    assert artifact["type"] == "video"
    assert artifact["metadata"]["tool"] == "color_grade"
    assert artifact["metadata"]["profile"] == "cinematic_warm"
    media = client.get(artifact["download_url"])
    assert media.status_code == 200
    assert b"ftyp" in media.content[:16]


def test_audio_enhancement_uploads_source_and_returns_audio_artifact(
    client: TestClient, sample_audio: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    presets = ["clean_speech", "noise_reduce", "normalize_only", "podcast", "broadcast", "voice_clarity"]
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "audio_enhance", "capability_id": "audio_processing",
        "provider_id": "ffmpeg", "status": "available", "operations": ["speech_cleanup"],
        "input_schema": {"properties": {"preset": {"enum": presets}}},
        "output_schema": {}, "artifact_schema": {}, "models": [],
        "supports": {}, "resource_profile": {},
    }])
    project_id = _project(client)
    upload = client.post(
        f"/api/projects/{project_id}/assets?filename=sample.wav",
        content=sample_audio.read_bytes(),
        headers={"content-type": "application/octet-stream"},
    )
    assert upload.status_code == 201, upload.text
    asset = upload.json()
    assert asset["type"] == "audio"
    assert asset["duration"] == pytest.approx(2.0, abs=0.2)
    job_response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "audio_processing", "operation": "enhance",
        "project_id": project_id, "input_asset_ids": [asset["id"]],
        "parameters": {"preset": "clean_speech"},
    })
    assert job_response.status_code == 202, job_response.text
    job_id = job_response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifacts = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"]
    assert len(artifacts) == 1
    artifact = artifacts[0]
    assert artifact["type"] == "audio"
    assert artifact["mime_type"] == "audio/mp4"
    assert artifact["metadata"]["tool"] == "audio_enhance"
    media = client.get(artifact["download_url"])
    assert media.status_code == 200
    assert b"ftyp" in media.content[:16]


def test_audio_volume_job_uses_openmontage_mixer_and_returns_audio_artifact(
    client: TestClient, sample_audio: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "audio_mixer", "capability_id": "audio_processing",
        "provider_id": "ffmpeg", "status": "available", "operations": ["mix"],
        "input_schema": {"properties": {
            "operation": {"enum": ["mix"]},
            "tracks": {"items": {"properties": {"volume": {"minimum": 0, "maximum": 1.0}}}},
        }},
        "output_schema": {}, "artifact_schema": {}, "models": [],
        "supports": {}, "resource_profile": {},
    }])
    project_id = _project(client)
    upload = client.post(
        f"/api/projects/{project_id}/assets?filename=sample.wav",
        content=sample_audio.read_bytes(),
        headers={"content-type": "application/octet-stream"},
    )
    assert upload.status_code == 201, upload.text
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "audio_processing", "operation": "volume",
        "project_id": project_id, "input_asset_ids": [upload.json()["id"]],
        "parameters": {"volume": 0.5},
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifact = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "audio"
    assert artifact["mime_type"] == "audio/wav"
    assert artifact["metadata"]["tool"] == "audio_mixer"
    assert artifact["metadata"]["volume"] == 0.5
    assert client.get(artifact["download_url"]).status_code == 200


def test_audio_trim_job_uses_openmontage_mixer_and_returns_trimmed_artifact(
    client: TestClient, sample_audio: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "audio_mixer", "capability_id": "audio_processing",
        "provider_id": "ffmpeg", "status": "available", "operations": ["trim"],
        "input_schema": {"properties": {"operation": {"enum": ["trim"]}}},
        "output_schema": {}, "artifact_schema": {}, "models": [],
        "supports": {}, "resource_profile": {},
    }])
    project_id = _project(client)
    upload = client.post(
        f"/api/projects/{project_id}/assets?filename=sample.wav",
        content=sample_audio.read_bytes(),
        headers={"content-type": "application/octet-stream"},
    )
    assert upload.status_code == 201, upload.text
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "audio_processing", "operation": "trim",
        "project_id": project_id, "input_asset_ids": [upload.json()["id"]],
        "parameters": {"start_seconds": 0.25, "end_seconds": 1.25},
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifact = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "audio"
    assert artifact["mime_type"] == "audio/wav"
    assert artifact["metadata"]["tool"] == "audio_mixer"
    assert artifact["metadata"]["trim"] == {"start_seconds": 0.25, "end_seconds": 1.25}
    assert 0.9 <= artifact["metadata"]["duration"] <= 1.1
    assert client.get(artifact["download_url"]).status_code == 200


def test_video_generation_job_executes_selected_openmontage_tool(
    client: TestClient, sample_video: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    schema = {
        "type": "object",
        "required": ["prompt"],
        "properties": {
            "prompt": {"type": "string"},
            "operation": {"type": "string", "enum": ["text_to_video", "image_to_video"]},
            "aspect_ratio": {"type": "string", "enum": ["16:9", "9:16", "1:1"]},
            "duration_hint": {"type": "string", "enum": ["1s", "2s", "3s", "4s", "5s", "8s"]},
            "fps": {"type": "integer", "enum": [24, 30]},
            "output_path": {"type": "string"},
        },
    }
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "test_video_generator", "capability_id": "video_generation",
        "provider_id": "test", "status": "available",
        "operations": ["text_to_video", "image_to_video"],
        "input_schema": schema, "output_schema": {}, "artifact_schema": {},
        "models": [{"id": "test-v1"}], "supports": {}, "resource_profile": {},
    }])

    captured_inputs: dict[str, object] = {}

    class FakeGenerator:
        input_schema = schema

        def get_status(self) -> ToolStatus:
            return ToolStatus.AVAILABLE

        def execute(self, inputs: dict[str, object]) -> ToolResult:
            captured_inputs.update(inputs)
            output_path = Path(str(inputs["output_path"]))
            shutil.copyfile(sample_video, output_path)
            return ToolResult(success=True, data={"output": str(output_path)}, artifacts=[str(output_path)])

    from tools.tool_registry import registry
    monkeypatch.setattr(registry, "get", lambda name: FakeGenerator() if name == "test_video_generator" else None)

    project_id = _project(client)
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "video_generation", "operation": "generate",
        "project_id": project_id, "input_asset_ids": [],
        "parameters": {
            "provider_tool_id": "test_video_generator", "model_id": "test-v1",
            "prompt": "A calm ocean sunset over the horizon", "mode": "text_to_video",
            "aspect_ratio": "16:9", "duration_seconds": 2, "fps": 30,
        },
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifacts = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"]
    assert len(artifacts) == 1
    artifact = artifacts[0]
    assert artifact["type"] == "video"
    assert artifact["metadata"]["provider_tool_id"] == "test_video_generator"
    assert artifact["metadata"]["model_id"] == "test-v1"
    assert captured_inputs["fps"] == 30
    assert client.get(artifact["download_url"]).status_code == 200


def test_video_generation_reports_provider_not_configured_without_creating_job(
    client: TestClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "ltx_video_modal", "capability_id": "video_generation",
        "provider_id": "ltx-modal", "status": "unavailable",
        "operations": ["text_to_video", "image_to_video"],
        "input_schema": {
            "type": "object", "required": ["prompt"],
            "properties": {
                "prompt": {"type": "string"},
                "operation": {"type": "string", "enum": ["text_to_video", "image_to_video"]},
                "output_path": {"type": "string"},
            },
        },
        "output_schema": {}, "artifact_schema": {}, "models": [],
        "supports": {}, "resource_profile": {},
    }])
    project_id = _project(client)
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "video_generation", "operation": "generate",
        "project_id": project_id, "input_asset_ids": [],
        "parameters": {
            "provider_tool_id": "ltx_video_modal",
            "prompt": "A calm ocean sunset over the horizon",
            "mode": "text_to_video", "aspect_ratio": "16:9", "duration_seconds": 5,
        },
    })
    assert response.status_code == 503
    assert response.json()["detail"] == "provider_not_configured"


def test_local_ltx_reports_unsupported_hardware_without_creating_job(
    client: TestClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "ltx_video_local", "capability_id": "video_generation",
        "provider_id": "ltx", "status": "unavailable",
        "operations": ["text_to_video", "image_to_video"],
        "input_schema": {
            "type": "object", "required": ["prompt"],
            "properties": {
                "prompt": {"type": "string"},
                "operation": {"type": "string", "enum": ["text_to_video", "image_to_video"]},
                "output_path": {"type": "string"},
            },
        },
        "output_schema": {}, "artifact_schema": {}, "models": [],
        "supports": {}, "resource_profile": {"vram_mb": 12000},
    }])
    monkeypatch.setattr(backend_app, "detect_host_hardware", lambda: {
        "gpu": {"name": "NVIDIA GeForce GTX 1650", "vram_mb": 4096},
        "cuda": {"available": False},
    })
    project_id = _project(client)
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "video_generation", "operation": "generate",
        "project_id": project_id, "input_asset_ids": [],
        "parameters": {
            "provider_tool_id": "ltx_video_local",
            "prompt": "A calm ocean sunset over the horizon",
            "mode": "text_to_video", "duration_seconds": 5,
        },
    })
    assert response.status_code == 503
    assert response.json()["detail"] == "unsupported_hardware"


def test_reference_video_generation_executes_and_saves_video_artifact(
    client: TestClient, sample_video: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    schema = {
        "type": "object", "required": ["prompt"],
        "properties": {
            "prompt": {"type": "string"},
            "operation": {"type": "string", "enum": ["text_to_video", "reference_to_video"]},
            "reference_video_path": {"type": "string"},
            "output_path": {"type": "string"},
        },
    }
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "test_reference_video_generator", "capability_id": "video_generation",
        "provider_id": "test", "status": "available",
        "operations": ["text_to_video", "reference_to_video"],
        "input_schema": schema, "output_schema": {}, "artifact_schema": {},
        "models": [], "supports": {}, "resource_profile": {},
    }])
    captured_inputs: dict[str, object] = {}

    class FakeGenerator:
        input_schema = schema

        def get_status(self) -> ToolStatus:
            return ToolStatus.AVAILABLE

        def execute(self, inputs: dict[str, object]) -> ToolResult:
            captured_inputs.update(inputs)
            output_path = Path(str(inputs["output_path"]))
            shutil.copyfile(sample_video, output_path)
            return ToolResult(success=True, data={"output": str(output_path)}, artifacts=[str(output_path)])

    from tools.tool_registry import registry
    monkeypatch.setattr(registry, "get", lambda name: FakeGenerator() if name == "test_reference_video_generator" else None)

    project_id = _project(client)
    reference_video_id = _upload(client, project_id, sample_video)
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "video_generation", "operation": "generate",
        "project_id": project_id, "input_asset_ids": [reference_video_id],
        "parameters": {
            "provider_tool_id": "test_reference_video_generator",
            "prompt": "Continue the clip with a slow camera pan",
            "mode": "reference_to_video", "duration_seconds": 2,
        },
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifact = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "video"
    assert artifact["metadata"]["mode"] == "reference_to_video"
    assert Path(str(captured_inputs["reference_video_path"])).is_file()
    assert client.get(artifact["download_url"]).status_code == 200


def test_image_generation_job_executes_selected_openmontage_tool(
    client: TestClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    schema = {
        "type": "object", "required": ["prompt"],
        "properties": {
            "prompt": {"type": "string"},
            "aspect_ratio": {"type": "string", "enum": ["1:1", "16:9"]},
            "output_path": {"type": "string"},
        },
    }
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "test_image_generator", "capability_id": "image_generation",
        "provider_id": "test", "status": "available", "operations": ["generate"],
        "input_schema": schema, "output_schema": {}, "artifact_schema": {},
        "models": [], "supports": {}, "resource_profile": {},
    }])

    class FakeImageGenerator:
        input_schema = schema

        def get_status(self) -> ToolStatus:
            return ToolStatus.AVAILABLE

        def execute(self, inputs: dict[str, object]) -> ToolResult:
            from PIL import Image
            output_path = Path(str(inputs["output_path"]))
            Image.new("RGB", (32, 24), color=(30, 100, 200)).save(output_path)
            return ToolResult(success=True, data={"output": str(output_path)}, artifacts=[str(output_path)])

    from tools.tool_registry import registry
    monkeypatch.setattr(registry, "get", lambda name: FakeImageGenerator() if name == "test_image_generator" else None)

    project_id = _project(client)
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "image_generation", "operation": "generate",
        "project_id": project_id, "input_asset_ids": [],
        "parameters": {
            "provider_tool_id": "test_image_generator", "prompt": "A blue mountain lake at sunrise",
            "aspect_ratio": "1:1", "resolution": "1024",
        },
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifacts = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"]
    assert len(artifacts) == 1
    artifact = artifacts[0]
    assert artifact["type"] == "image"
    assert artifact["mime_type"] == "image/png"
    assert artifact["metadata"]["width"] == 32
    assert artifact["metadata"]["height"] == 24
    assert artifact["metadata"]["provider_tool_id"] == "test_image_generator"
    assert client.get(artifact["download_url"]).status_code == 200


def test_tts_job_executes_selected_openmontage_tool(
    client: TestClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    schema = {
        "type": "object", "required": ["text"],
        "properties": {
            "text": {"type": "string"}, "voice": {"type": "string", "enum": ["alloy"]},
            "speed": {"type": "number"}, "output_path": {"type": "string"},
        },
    }
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "test_tts", "capability_id": "tts", "provider_id": "test",
        "status": "available", "operations": ["text_to_speech"],
        "input_schema": schema, "output_schema": {}, "artifact_schema": {},
        "models": [], "supports": {}, "resource_profile": {},
    }])
    captured_inputs: dict[str, object] = {}

    class FakeTts:
        input_schema = schema

        def get_status(self) -> ToolStatus:
            return ToolStatus.AVAILABLE

        def execute(self, inputs: dict[str, object]) -> ToolResult:
            import wave
            captured_inputs.update(inputs)
            output_path = Path(str(inputs["output_path"]))
            with wave.open(str(output_path), "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(8000)
                wav_file.writeframes(b"\x00\x00" * 8000)
            return ToolResult(success=True, data={"output": str(output_path)}, artifacts=[str(output_path)])

    from tools.tool_registry import registry
    monkeypatch.setattr(registry, "get", lambda name: FakeTts() if name == "test_tts" else None)

    project_id = _project(client)
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "tts", "operation": "generate",
        "project_id": project_id, "input_asset_ids": [],
        "parameters": {
            "provider_tool_id": "test_tts", "text": "Hello from OpenMontage.",
            "voice": "alloy", "speed": 1.2,
        },
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifact = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "audio"
    assert artifact["mime_type"] == "audio/wav"
    assert artifact["metadata"]["provider_tool_id"] == "test_tts"
    assert captured_inputs["text"] == "Hello from OpenMontage."
    assert captured_inputs["voice"] == "alloy"
    assert captured_inputs["speed"] == 1.2
    assert client.get(artifact["download_url"]).status_code == 200


def test_music_generation_job_executes_selected_openmontage_tool(
    client: TestClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    schema = {
        "type": "object", "required": ["prompt", "duration_seconds"],
        "properties": {
            "prompt": {"type": "string"},
            "duration_seconds": {"type": "number", "minimum": 3, "maximum": 60},
            "force_instrumental": {"type": "boolean", "default": True},
            "output_format": {"type": "string", "enum": ["wav"], "default": "wav"},
            "output_path": {"type": "string"},
        },
    }
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "test_music", "capability_id": "music_generation", "provider_id": "test",
        "status": "available", "operations": ["generate_background_music"],
        "input_schema": schema, "output_schema": {}, "artifact_schema": {},
        "models": [], "supports": {}, "resource_profile": {},
    }])
    captured_inputs: dict[str, object] = {}

    class FakeMusic:
        input_schema = schema

        def get_status(self) -> ToolStatus:
            return ToolStatus.AVAILABLE

        def execute(self, inputs: dict[str, object]) -> ToolResult:
            import wave
            captured_inputs.update(inputs)
            output_path = Path(str(inputs["output_path"]))
            with wave.open(str(output_path), "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(8000)
                wav_file.writeframes(b"\x00\x00" * 8000)
            return ToolResult(success=True, data={"output": str(output_path)}, artifacts=[str(output_path)])

    from tools.tool_registry import registry
    monkeypatch.setattr(registry, "get", lambda name: FakeMusic() if name == "test_music" else None)

    project_id = _project(client)
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "music_generation", "operation": "generate",
        "project_id": project_id, "input_asset_ids": [],
        "parameters": {
            "provider_tool_id": "test_music", "prompt": "Warm piano and soft strings",
            "duration_seconds": 12, "force_instrumental": True,
        },
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifact = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "audio"
    assert artifact["mime_type"] == "audio/wav"
    assert artifact["metadata"]["provider_tool_id"] == "test_music"
    assert captured_inputs["prompt"] == "Warm piano and soft strings"
    assert captured_inputs["duration_seconds"] == 12
    assert captured_inputs["force_instrumental"] is True
    assert client.get(artifact["download_url"]).status_code == 200


def test_transcription_job_creates_structured_transcript_artifact(
    client: TestClient, sample_video: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    schema = {
        "type": "object", "required": ["input_path"],
        "properties": {
            "input_path": {"type": "string"}, "output_dir": {"type": "string"},
            "model_size": {"type": "string", "enum": ["tiny", "base", "small"]},
            "language": {"type": "string"}, "diarize": {"type": "boolean"},
        },
    }
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "transcriber", "capability_id": "analysis", "provider_id": "whisperx",
        "status": "available", "operations": ["transcribe"],
        "input_schema": schema, "output_schema": {}, "artifact_schema": {},
        "models": [{"id": "tiny"}, {"id": "base"}, {"id": "small"}],
        "supports": {}, "resource_profile": {},
    }])

    class FakeTranscriber:
        input_schema = schema

        def get_status(self) -> ToolStatus:
            return ToolStatus.AVAILABLE

        def execute(self, inputs: dict[str, object]) -> ToolResult:
            output_dir = Path(str(inputs["output_dir"]))
            output_dir.mkdir(parents=True, exist_ok=True)
            output_path = output_dir / "sample_transcript.json"
            result = {
                "segments": [{"start": 0.0, "end": 1.25, "text": " Hello world."}],
                "word_timestamps": [], "language": "en", "duration_seconds": 2.0,
                "model_size": inputs["model_size"],
            }
            output_path.write_text(json.dumps(result), encoding="utf-8")
            return ToolResult(success=True, data={**result, "output": str(output_path)}, artifacts=[str(output_path)])

    from tools.tool_registry import registry
    monkeypatch.setattr(registry, "get", lambda name: FakeTranscriber() if name == "transcriber" else None)
    project_id = _project(client)
    upload = client.post(
        f"/api/projects/{project_id}/assets?filename=sample.mp4",
        content=sample_video.read_bytes(), headers={"Content-Type": "video/mp4"},
    )
    assert upload.status_code == 201, upload.text
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "analysis", "operation": "transcribe",
        "project_id": project_id, "input_asset_ids": [upload.json()["id"]],
        "parameters": {"provider_tool_id": "transcriber", "model_size": "tiny"},
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifact = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "transcript"
    assert artifact["mime_type"] == "application/json"
    assert artifact["metadata"]["provider_tool_id"] == "transcriber"
    transcript = client.get(artifact["download_url"]).json()
    assert transcript["segments"] == [{"start": 0.0, "end": 1.25, "text": " Hello world."}]


def test_image_upscale_job_creates_an_image_artifact(
    client: TestClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    from PIL import Image

    schema = {
        "type": "object", "required": ["input_path"],
        "properties": {
            "input_path": {"type": "string"}, "output_path": {"type": "string"},
            "scale": {"type": "integer", "enum": [2, 4]},
            "model": {"type": "string", "enum": ["test-model"], "default": "test-model"},
            "face_enhance": {"type": "boolean"},
            "denoise_strength": {"type": "number", "minimum": 0, "maximum": 1},
        },
    }
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "upscale", "capability_id": "enhancement", "provider_id": "test",
        "status": "available", "operations": ["image_upscale", "video_upscale"],
        "input_schema": schema, "output_schema": {}, "artifact_schema": {},
        "models": [{"id": "test-model"}], "supports": {}, "resource_profile": {},
    }])
    captured_inputs: dict[str, object] = {}

    class FakeUpscaler:
        input_schema = schema

        def get_status(self) -> ToolStatus:
            return ToolStatus.AVAILABLE

        def execute(self, inputs: dict[str, object]) -> ToolResult:
            captured_inputs.update(inputs)
            output_path = Path(str(inputs["output_path"]))
            Image.new("RGB", (64, 48), color=(50, 120, 180)).save(output_path)
            return ToolResult(success=True, data={"output": str(output_path), "model": inputs["model"]}, artifacts=[str(output_path)])

    from tools.tool_registry import registry
    monkeypatch.setattr(registry, "get", lambda name: FakeUpscaler() if name == "upscale" else None)
    from PIL import Image as PilImage
    image_buffer = io.BytesIO()
    PilImage.new("RGB", (32, 24), color=(10, 30, 50)).save(image_buffer, format="PNG")
    project_id = _project(client)
    uploaded = client.post(
        f"/api/projects/{project_id}/assets?filename=source.png",
        content=image_buffer.getvalue(), headers={"content-type": "application/octet-stream"},
    )
    assert uploaded.status_code == 201, uploaded.text
    response = client.post(f"/api/projects/{project_id}/jobs", json={
        "type": "capability", "capability": "enhancement", "operation": "upscale",
        "project_id": project_id, "input_asset_ids": [uploaded.json()["id"]],
        "parameters": {"provider_tool_id": "upscale", "scale": 2, "model_id": "test-model"},
    })
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    job = None
    for _ in range(100):
        job = client.get(f"/api/jobs/{job_id}").json()
        if job["status"] in {"completed", "failed"}:
            break
        time.sleep(0.1)
    assert job and job["status"] == "completed", job
    artifact = client.get(f"/api/jobs/{job_id}/artifacts").json()["items"][0]
    assert artifact["type"] == "image"
    assert artifact["mime_type"] == "image/png"
    assert artifact["metadata"]["scale"] == 2
    assert captured_inputs["scale"] == 2
    assert client.get(artifact["download_url"]).status_code == 200


def test_job_validation_and_not_found(client: TestClient) -> None:
    project_id = _project(client)
    assert client.get("/api/jobs/missing").status_code == 404
    assert client.get("/api/jobs/missing/artifacts").status_code == 404
    assert client.get("/api/artifacts/missing/file").status_code == 404
    assert client.post(
        f"/api/projects/{project_id}/jobs",
        json={"type": "capability", "capability": "video_post", "operation": "trim",
              "project_id": project_id, "input_asset_ids": ["missing"],
              "parameters": {"start": 0, "end": 1}},
    ).status_code == 404
    assert client.post(
        f"/api/projects/{project_id}/jobs",
        json={"type": "capability", "capability": "video_post", "operation": "trim",
              "project_id": project_id, "input_asset_ids": [],
              "parameters": {"start": 2, "end": 1}},
    ).status_code == 422
    assert client.post(
        f"/api/projects/{project_id}/jobs",
        json={"type": "pipeline", "pipeline_id": "cinematic", "project_id": project_id},
    ).status_code == 501


def test_restart_marks_an_interrupted_job_failed(tmp_path: Path) -> None:
    database = tmp_path / "mobile.sqlite3"
    projects = tmp_path / "projects"
    first = BackendStore(database, projects_root=projects)
    project = first.create_project("Interrupted job")
    job = first.create_job(
        project_id=project.id, capability="video_post", operation="trim",
        request_input={"input_asset_ids": [], "parameters": {}},
    )
    first.update_job(job.id, status=JobStatus.running, current_step="processing")

    after_restart = BackendStore(database, projects_root=projects)
    assert after_restart.recover_interrupted_jobs() == 1
    recovered = after_restart.get_job(job.id)
    assert recovered.status == JobStatus.failed
    assert recovered.error == "Backend restarted before this job completed."
