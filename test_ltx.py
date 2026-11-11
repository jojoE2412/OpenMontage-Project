import os
from huggingface_hub import InferenceClient

token = os.environ.get("HF_TOKEN")

if not token:
    raise RuntimeError("HF_TOKEN belum ditemukan.")

client = InferenceClient(
    provider="fal-ai",
    api_key=token,
)

print("Mengirim prompt ke LTX-Video...")

video = client.text_to_video(
    prompt="A cinematic sunrise over Mount Bromo, Indonesia, realistic landscape, soft golden morning light, slow camera movement",
    model="Lightricks/LTX-Video-0.9.7-distilled",
    num_inference_steps=8,
)

print(f"Video diterima: {len(video):,} bytes")

with open("ltx_test.mp4", "wb") as f:
    f.write(video)

print("Berhasil!")
print("File: ltx_test.mp4")