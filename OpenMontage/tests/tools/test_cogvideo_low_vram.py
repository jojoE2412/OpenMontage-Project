import sys
from types import ModuleType, SimpleNamespace

from tools.video import _shared
from tools.video._shared import COGVIDEO_VARIANTS


def test_cogvideo_2b_declares_short_low_vram_text_to_video_preset():
    variant = COGVIDEO_VARIANTS["cogvideo-2b"]
    assert variant["vram_mb"] == 4096
    assert variant["offload_strategy"] == "sequential_cpu"
    assert variant["operations"] == ["text_to_video"]
    assert (variant["default_width"], variant["default_height"]) == (480, 320)
    assert variant["default_num_frames"] == 49
    assert variant["duration_options"] == [2, 4, 6]


def test_sequential_cpu_offload_is_selected_for_low_vram_pipeline(monkeypatch):
    calls = []

    class FakePipeline:
        vae = None

        @classmethod
        def from_pretrained(cls, model_id, torch_dtype):
            calls.append(("load", model_id, torch_dtype))
            return cls()

        def enable_sequential_cpu_offload(self):
            calls.append(("sequential",))

        def enable_model_cpu_offload(self):
            calls.append(("model",))

    torch = ModuleType("torch")
    torch.bfloat16 = "bf16"
    torch.cuda = SimpleNamespace(is_bf16_supported=lambda: True)
    diffusers = ModuleType("diffusers")
    diffusers.CogVideoXPipeline = FakePipeline
    monkeypatch.setitem(sys.modules, "torch", torch)
    monkeypatch.setitem(sys.modules, "diffusers", diffusers)
    monkeypatch.setattr(_shared, "get_torch_device", lambda: "cuda")

    _shared.load_diffusers_pipeline(
        "CogVideoXPipeline",
        "THUDM/CogVideoX-2b",
        enable_offload=True,
        offload_strategy="sequential_cpu",
    )

    assert ("sequential",) in calls
    assert ("model",) not in calls
