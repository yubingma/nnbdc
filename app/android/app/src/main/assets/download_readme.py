
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
    except Exception as e:
        print(f"  - Error downloading {url}: {e}")

# Try to download README.md to check filenames
en_name = "sherpa-onnx-streaming-zipformer-en-2023-06-26"
assets_dir = "/Volumes/ssd/nnbdc/app/android/app/src/main/assets"
en_dir = os.path.join(assets_dir, en_name)
en_base_url = f"https://huggingface.co/csukuangfj/{en_name}/resolve/main"

download_file(f"{en_base_url}/README.md", os.path.join(en_dir, "README.md"))
