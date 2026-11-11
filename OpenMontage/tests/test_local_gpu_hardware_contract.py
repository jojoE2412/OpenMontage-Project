from backend import app as backend_app


def test_four_gigabyte_gpu_can_advertise_sequential_cogvideo_2b(
    monkeypatch,
):
    monkeypatch.setattr(backend_app, "_tool_contracts", lambda: [{
        "tool_id": "cogvideo_video",
        "capability_id": "video_generation",
        "provider_id": "cogvideo",
        "runtime": "local_gpu",
        "status": "available",
        "resource_profile": {"vram_mb": 12000},
        "models": [
            {"id": "cogvideo-5b", "vram_mb": 12000},
            {"id": "cogvideo-2b", "vram_mb": 4096},
        ],
    }])
    monkeypatch.setattr(backend_app, "detect_host_hardware", lambda: {
        "gpu": {"name": "NVIDIA GeForce GTX 1650", "vram_mb": 4096},
        "cuda": {"available": True},
    })

    hardware = backend_app.get_runtime_hardware()
    provider = hardware["local_video_providers"][0]

    assert provider["status"] == "ready"
    assert next(model for model in provider["models"] if model["model_id"] == "cogvideo-2b")["status"] == "ready"
    assert next(model for model in provider["models"] if model["model_id"] == "cogvideo-5b")["status"] == "unsupported_hardware"
