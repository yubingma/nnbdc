
import os
import urllib.request
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def download_file(url, dest_path):
    print(f"Downloading {url} to {dest_path}...")
    try:
        mirror_url = url.replace("huggingface.co", "hf-mirror.com")
        with urllib.request.urlopen(mirror_url, context=ctx) as response, open(dest_path, 'wb') as out_file:
            out_file.write(response.read())
        print("  - Done.")
        return True
    except Exception as e:
        print(f"  - Error downloading {url}: {e}")
        return False

# English Model Fix
en_name = "sherpa-onnx-streaming-zipformer-en-2023-06-26"
assets_dir = "/Volumes/ssd/nnbdc/app/android/app/src/main/assets"
en_dir = os.path.join(assets_dir, en_name)
en_base_url = f"https://huggingface.co/csukuangfj/{en_name}/resolve/main"

# Try non-int8 filenames
files = [
    "encoder-epoch-99-avg-1.onnx",
    "decoder-epoch-99-avg-1.onnx",
    "joiner-epoch-99-avg-1.onnx"
]

for f in files:
    dest = os.path.join(en_dir, f)
    if not os.path.exists(dest):
        success = download_file(f"{en_base_url}/{f}", dest)
        if not success:
            # Fallback: maybe it's not epoch 99? Try downloading README to check?
            pass
