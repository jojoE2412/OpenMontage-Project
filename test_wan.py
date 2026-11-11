import os
from huggingface_hub import InferenceClient

token = os.environ.get("HF_TOKEN")

if not token:
    raise RuntimeError("HF_TOKEN belum ditemukan.")

client = InferenceClient(
    provider="fal-ai",
    api_key=token,
)

prompt = (
    "A cinematic sunrise over Mount Bromo, "
    "realistic landscape, soft morning light, "
    "slow camera movement"
)

print("Mengirim request ke Wan2.1...")
print("Prompt:", prompt)

video = client.text_to_video(
    prompt,
    model="Wan-AI/Wan2.1-T2V-1.3B",
)

output_file = "wan_test.mp4"

with open(output_file, "wb") as f:
    f.write(video)

print()
print("BERHASIL!")
print("Video tersimpan sebagai:", output_file)