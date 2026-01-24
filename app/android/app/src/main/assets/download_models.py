
import os
import urllib.request
import ssl

# Ignore SSL errors
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def download_file(url, dest_path):
    print(f"Downloading {url} to {dest_path}...")
    try:
        if os.path.exists(dest_path):
            print(f"  - File already exists: {dest_path}, skipping.")
            return
        
        # Use hf-mirror.com for better speed in CN
        mirror_url = url.replace("huggingface.co", "hf-mirror.com")
        
        with urllib.request.urlopen(mirror_url, context=ctx) as response, open(dest_path, 'wb') as out_file:
            out_file.write(response.read())
        print("  - Done.")
    except Exception as e:
        print(f"  - Error downloading {url}: {e}")

assets_dir = "/Volumes/ssd/nnbdc/app/android/app/src/main/assets"

# 1. Chinese Model
zh_name = "sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23"
zh_dir = os.path.join(assets_dir, zh_name)
os.makedirs(zh_dir, exist_ok=True)

zh_base_url = f"https://huggingface.co/csukuangfj/{zh_name}/resolve/main"
download_file(f"{zh_base_url}/tokens.txt", os.path.join(zh_dir, "tokens.txt"))
download_file(f"{zh_base_url}/encoder-epoch-99-avg-1.int8.onnx", os.path.join(zh_dir, "encoder-epoch-99-avg-1.int8.onnx"))
download_file(f"{zh_base_url}/decoder-epoch-99-avg-1.int8.onnx", os.path.join(zh_dir, "decoder-epoch-99-avg-1.int8.onnx"))
download_file(f"{zh_base_url}/joiner-epoch-99-avg-1.int8.onnx", os.path.join(zh_dir, "joiner-epoch-99-avg-1.int8.onnx"))

# 2. English Model
en_name = "sherpa-onnx-streaming-zipformer-en-2023-06-26"
en_dir = os.path.join(assets_dir, en_name)
os.makedirs(en_dir, exist_ok=True)

en_base_url = f"https://huggingface.co/csukuangfj/{en_name}/resolve/main"
download_file(f"{en_base_url}/tokens.txt", os.path.join(en_dir, "tokens.txt"))
download_file(f"{en_base_url}/encoder-epoch-99-avg-1.int8.onnx", os.path.join(en_dir, "encoder-epoch-99-avg-1.int8.onnx"))
download_file(f"{en_base_url}/decoder-epoch-99-avg-1.int8.onnx", os.path.join(en_dir, "decoder-epoch-99-avg-1.int8.onnx"))
download_file(f"{en_base_url}/joiner-epoch-99-avg-1.int8.onnx", os.path.join(en_dir, "joiner-epoch-99-avg-1.int8.onnx"))

print("\nAll downloads finished.")
