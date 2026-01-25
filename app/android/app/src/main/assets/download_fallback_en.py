
import os
import urllib.request
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def download_file(url, dest_path):
    print(f"Downloading {url} to {dest_path}...")
    try:
        if os.path.exists(dest_path):
            print("  - Exists, skipping.")
            return True
        mirror_url = url.replace("huggingface.co", "hf-mirror.com")
        with urllib.request.urlopen(mirror_url, context=ctx) as response, open(dest_path, 'wb') as out_file:
            out_file.write(response.read())
        print("  - Done.")
        return True
    except Exception as e:
        print(f"  - Error downloading {url}: {e}")
        return False

# Fallback English Model: 20M-2023-02-17
en_name = "sherpa-onnx-streaming-zipformer-en-20M-2023-02-17"
assets_dir = os.path.join(os.environ['PPDC_SRC_DIR'], 'app/android/app/src/main/assets')
en_dir = os.path.join(assets_dir, en_name)
os.makedirs(en_dir, exist_ok=True)
en_base_url = f"https://huggingface.co/csukuangfj/{en_name}/resolve/main"

files = [
    "tokens.txt",
    "encoder-epoch-99-avg-1.int8.onnx",
    "decoder-epoch-99-avg-1.int8.onnx",
    "joiner-epoch-99-avg-1.int8.onnx"
]

all_success = True
for f in files:
    if not download_file(f"{en_base_url}/{f}", os.path.join(en_dir, f)):
        all_success = False

if all_success:
    print("Fallback model downloaded successfully.")
else:
    print("Failed to download fallback model.")
