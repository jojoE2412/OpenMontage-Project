from __future__ import annotations

import sys
from types import ModuleType

from tools.base_tool import ToolStatus
from tools.video.huggingface_video import HuggingFaceVideo


def test_huggingface_provider_requires_backend_token(monkeypatch):
    monkeypatch.delenv("HF_TOKEN", raising=False)
    assert HuggingFaceVideo().get_status() == ToolStatus.UNAVAILABLE


def test_huggingface_video_saves_provider_bytes(monkeypatch, tmp_path):
    captured = {}

    class FakeClient:
        def __init__(self, **kwargs):
            captured["client"] = kwargs

        def text_to_video(self, prompt, **kwargs):
            captured["request"] = {"prompt": prompt, **kwargs}
            return b"video bytes"

    fake_module = ModuleType("huggingface_hub")
    fake_module.InferenceClient = FakeClient
    monkeypatch.setitem(sys.modules, "huggingface_hub", fake_module)
    monkeypatch.setenv("HF_TOKEN", "hf_test_token")
    output = tmp_path / "nested" / "result.mp4"

    result = HuggingFaceVideo().execute({
        "prompt": "A cinematic scene with a red train crossing a mountain bridge",
        "model": "Wan-AI/Wan2.2-TI2V-5B",
        "num_frames": 49,
        "guidance_scale": 5,
        "num_inference_steps": 20,
        "negative_prompt": "blurry",
        "seed": 42,
        "output_path": str(output),
    })

    assert result.success
    assert output.read_bytes() == b"video bytes"
    assert captured["client"]["provider"] == "fal-ai"
    assert captured["client"]["api_key"] == "hf_test_token"
    assert captured["request"]["num_frames"] == 49
    assert captured["request"]["negative_prompt"] == ["blurry"]
    assert "hf_test_token" not in str(result.data)
