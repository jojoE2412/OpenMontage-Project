import os
import time

from huggingface_hub import InferenceClient
from huggingface_hub.inference._providers import get_provider_helper
from huggingface_hub.utils import get_session, hf_raise_for_status

token = os.environ.get("HF_TOKEN")

if not token:
    raise RuntimeError("HF_TOKEN belum ditemukan.")

model = "Wan-AI/Wan2.1-T2V-1.3B"

client = InferenceClient(
    provider="fal-ai",
    api_key=token,
)

helper = get_provider_helper(
    "fal-ai",
    task="text-to-video",
    model=model,
)

request_parameters = helper.prepare_request(
    inputs="A simple cinematic sunset over mountains",
    parameters={},
    headers=client.headers,
    model=model,
    api_key=client.token,
)

print("Mengirim request...")
response = client._inner_post(request_parameters)

response_dict = response
if isinstance(response, bytes):
    import json
    response_dict = json.loads(response)

print()
print("Request ID:", response_dict["request_id"])
print("Status awal:", response_dict["status"])

# Ini mengikuti logika FalAIQueueTask.get_response()
from urllib.parse import urlparse

request_id = response_dict["request_id"]

parsed_url = urlparse(request_parameters.url)

base_url = (
    f"{parsed_url.scheme}://{parsed_url.netloc}"
    f"{'/fal-ai' if parsed_url.netloc == 'router.huggingface.co' else ''}"
)

query_param = f"?{parsed_url.query}" if parsed_url.query else ""

model_id = urlparse(
    response_dict["response_url"]
).path

status_url = f"{base_url}{model_id}/status{query_param}"
result_url = f"{base_url}{model_id}{query_param}"

print()
print("Status URL:", status_url)
print("Result URL:", result_url)

status = response_dict.get("status")

print()
print("Menunggu proses...")

while status != "COMPLETED":

    time.sleep(0.5)

    status_response = get_session().get(
        status_url,
        headers=request_parameters.headers,
    )

    hf_raise_for_status(status_response)

    status_data = status_response.json()
    status = status_data.get("status")

    print("Status:", status)

    if status in ("FAILED", "CANCELLED"):
        print()
        print("GENERATION GAGAL:")
        print(status_data)
        raise SystemExit(1)

print()
print("Generation selesai.")
print("Mengambil response final...")

result_response = get_session().get(
    result_url,
    headers=request_parameters.headers,
)

hf_raise_for_status(result_response)

print()
print("========== RESPONSE FINAL ==========")
print(result_response.text)

print()
print("========== KEYS ==========")

try:
    result = result_response.json()
    print(list(result.keys()))
except Exception:
    print("Response bukan JSON.")