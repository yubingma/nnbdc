
import os
import urllib.request
import ssl
import json

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# Query GitHub API for the file list in the specific tag
tag = "v1.10.30"
api_url = f"https://api.github.com/repos/k2-fsa/sherpa-onnx/contents/android/SherpaOnnx/sherpa-onnx/src/main/java/com/k2fsa/sherpa/onnx?ref={tag}"

print(f"Querying API: {api_url}")

try:
    req = urllib.request.Request(api_url)
    # req.add_header('Authorization', 'token YOUR_GITHUB_TOKEN') # Using public access
    with urllib.request.urlopen(req, context=ctx) as response:
        data = json.loads(response.read().decode())
        
    print(f"Found {len(data)} files.")
    
    dest_dir = os.path.join(os.environ['PPDC_SRC_DIR'], 'app/android/app/src/main/java/com/k2fsa/sherpa/onnx')
    os.makedirs(dest_dir, exist_ok=True)
    
    for item in data:
        if item['type'] == 'file' and item['name'].endswith('.java'):
            download_url = item['download_url']
            print(f"Downloading {item['name']}...")
            try:
                with urllib.request.urlopen(download_url, context=ctx) as r, open(os.path.join(dest_dir, item['name']), 'wb') as f:
                    f.write(r.read())
            except Exception as e:
                print(f"Failed to download {item['name']}: {e}")

except Exception as e:
    print(f"API Request Failed: {e}")
    # Fallback to fetching raw directly if API fails (rate limit etc)
