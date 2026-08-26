#!/usr/bin/env python3
import os
import sys
import argparse
import requests
import json
import time

# API Endpoints
TOKEN_URL = "https://connect-api.cloud.huawei.com/api/oauth2/v1/token"
PUBLISH_API_BASE = "https://connect-api.cloud.huawei.com/api/publish/v2"

import ssl
from requests.adapters import HTTPAdapter
from urllib3.util.ssl_ import create_urllib3_context

class CustomSSLAdapter(HTTPAdapter):
    def init_poolmanager(self, *args, **kwargs):
        context = create_urllib3_context()
        # Allow weaker ciphers/legacy versions if server is old
        context.set_ciphers('DEFAULT@SECLEVEL=1')
        kwargs['ssl_context'] = context
        return super(CustomSSLAdapter, self).init_poolmanager(*args, **kwargs)

def get_session():
    session = requests.Session()
    # Mount the custom adapter to the Huawei domain
    adapter = CustomSSLAdapter()
    session.mount("https://connect-api.cloud.huawei.com", adapter)
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    })
    return session

def get_access_token(client_id, client_secret):
    """
    Obtains an access token from Huawei Cloud.
    """
    headers = {
        "Content-Type": "application/json"
    }
    data = {
        "client_id": client_id,
        "client_secret": client_secret,
        "grant_type": "client_credentials"
    }
    
    print(f"Requesting access token for Client ID: {client_id}...")
    session = get_session()
    response = session.post(TOKEN_URL, json=data, headers=headers)
    
    if response.status_code == 200:
        result = response.json()
        print("Access token obtained successfully.")
        # Debug: Print token scope or type if available
        if 'scope' in result:
             print(f"Token Scope: {result['scope']}")
        return result.get("access_token")
    else:
        print(f"Failed to get access token. Status: {response.status_code}, Response: {response.text}")
        sys.exit(1)

def get_upload_url(access_token, app_id, client_id, suffix="apk"):
    """
    Get the upload URL for the application.
    """
    if str(app_id) == str(client_id):
        print("\n[WARNING] App ID and Client ID are identical. This is usually incorrect.")
        print("[WARNING] Client ID should come from 'Users and Permissions' -> 'API Client' in AppGallery Connect.")
        print("[WARNING] App ID comes from 'My Apps' -> 'App Information'.")
        print("[WARNING] Proceeding anyway...\n")

    url = f"{PUBLISH_API_BASE}/upload-url"
    
    # Try 1: standard client_id header
    headers = {
        "Authorization": f"Bearer {access_token}",
        "client_id": client_id
    }
    params = {
        "appId": app_id,
        "suffix": suffix
    }
    
    print(f"Getting upload URL for App ID: {app_id}...")
    session = get_session()
    response = session.get(url, params=params, headers=headers)
    
    # Check for specific "Client token auth failed" error (205524993)
    if response.status_code != 200:
        try:
            err_json = response.json()
            err_code = err_json.get("ret", {}).get("code")
            if err_code == 205524993:
                print(f"Attempt 1 failed with 'client token auth failed'. Retrying with 'clientId' header...")
                # Try 2: CamelCase clientId
                headers["clientId"] = client_id
                del headers["client_id"]
                response = session.get(url, params=params, headers=headers)
        except Exception:
            pass

    if response.status_code == 200:
        try:
            result = response.json()
        except Exception as e:
            print(f"Failed to parse JSON response: {e}, Response: {response.text}")
            sys.exit(1)

        if result.get("ret", {}).get("code") == 0:
            return result.get("uploadUrl"), result.get("authCode")
        else:
            print(f"Error getting upload URL: {result}")
            sys.exit(1)
    else:
        print(f"\n❌ Failed to get upload URL. HTTP Status: {response.status_code}")
        if response.status_code == 403:
            print("\n[403 Forbidden 排查指南]")
            print("1. 华为 AGC 中创建 API 客户端时，【项目 (Project)】必须选择 【N/A】（不要绑定到具体项目，否则调用发布 API 会被 403 拒绝）。")
            print("2. API 客户端的【角色 (Role)】必须具有【管理员】或【App 管理员】权限。")
            print("3. 确认当前 API 客户端（Client ID）属于该应用所在的企业团队账号，并且已授权访问该应用。")
        if response.text:
            print(f"Response: {response.text}")
        sys.exit(1)

def upload_file(upload_url, auth_code, file_path):
    """
    Uploads the file to the provided URL using streaming multipart upload with progress bar.
    """
    import os
    from requests_toolbelt import MultipartEncoder, MultipartEncoderMonitor
    from tqdm import tqdm

    file_name = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)
    print(f"Uploading file: {file_path} ({file_size / (1024 * 1024):.2f} MB)...")
    
    max_retries = 3
    for attempt in range(1, max_retries + 1):
        if attempt > 1:
            print(f"\nRetrying upload (attempt {attempt}/{max_retries})...")
            time.sleep(3)
        try:
            with open(file_path, 'rb') as f:
                encoder = MultipartEncoder(
                    fields={
                        'authCode': auth_code,
                        'fileCount': '1',
                        'file': (file_name, f, 'application/octet-stream')
                    }
                )
                
                with tqdm(total=encoder.len, unit='B', unit_scale=True, unit_divisor=1024, desc="Upload Progress") as pbar:
                    def callback(monitor):
                        pbar.update(monitor.bytes_read - pbar.n)

                    monitor = MultipartEncoderMonitor(encoder, callback)
                    headers = {
                        'Content-Type': monitor.content_type
                    }
                    
                    response = requests.post(
                        upload_url,
                        data=monitor,
                        headers=headers,
                        timeout=(30, 1800)  # 30s connect timeout, 30m read timeout
                    )

            if response.status_code == 200:
                try:
                    result = response.json()
                except Exception as e:
                    print(f"Failed to parse JSON response: {e}, Response: {response.text}")
                    sys.exit(1)

                result_content = result.get("result", {})
                if str(result_content.get("resultCode")) == "0" or result_content.get("UploadFileRsp", {}).get("ifSuccess") == 1:
                    print("\n✅ File uploaded successfully.")
                    return result_content.get("UploadFileRsp", {}).get("fileInfoList")[0]
                else:
                    print(f"\n❌ Error during upload: {result}")
                    sys.exit(1)
            else:
                print(f"\n❌ Upload failed. Status: {response.status_code}, Response: {response.text}")
                if attempt == max_retries:
                    sys.exit(1)
        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
            print(f"\n⚠️ Upload connection error on attempt {attempt}: {e}")
            if attempt == max_retries:
                print("\n[上传失败排查建议]")
                print("1. 如果您开启了本地代理（如 Clash/Surge 等 VPN/代理软件），请尝试临时关闭代理，或将华为域名加入直连规则（代理软件常会限制大文件 POST 长连接）。")
                print("2. 检查网络连接是否稳定。")
                sys.exit(1)

def update_app_file_info(access_token, app_id, client_id, file_info, file_name):
    """
    Updates the app file info to commit the upload.
    """
    url = f"{PUBLISH_API_BASE}/app-file-info"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "client_id": client_id
    }
    
    # Construct payload
    # file_info contains 'fileDestUlr', 'size', 'disposableURL' etc.
    # We need to map it to what the API expects.
    # Usually strictly: fileType, files: [{fileDestUrl, fileName, size}]
    
    payload = {
        "appId": app_id,
        "fileType": 5, # 5 for APK, 6 for RPK, 12 for AAB ??
        # Let's check file extension
        "files": [{
            "fileName": file_name,
            "fileDestUrl": file_info.get("fileDestUlr"), # Note spelling in some docs
            "size": str(file_info.get("size"))
        }]
    }
    
    # Correct fileType based on observation
    if file_name.endswith(".aab"):
        payload["fileType"] = 5 # Actually 5 is common for APK. AAB might be different. 
        # API Doc says: 5: APK, 6: RPK, 8: OB, 9: XAPK, 12: AAB
        payload["fileType"] = 12
    
    print(f"Updating app file info...")
    session = get_session()
    # The API requires appId in the query string according to errors and docs
    response = session.put(url, json=payload, headers=headers, params={'appId': app_id})
    
    if response.status_code == 200:
        try:
            result = response.json()
        except Exception as e:
            print(f"Failed to parse JSON response: {e}, Response: {response.text}")
            sys.exit(1)

        if result.get("ret", {}).get("code") == 0:
            print("App file info updated successfully.")
        else:
             print(f"Error updating app file info: {result}")
             sys.exit(1)
    else:
        print(f"Failed to update app file info. Status: {response.status_code}, Response: {response.text}")
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upload APK/AAB to Huawei AppGallery")
    parser.add_argument("--client-id", required=True, help="Huawei Connect API Client ID")
    parser.add_argument("--client-secret", required=True, help="Huawei Connect API Client Secret")
    parser.add_argument("--app-id", required=True, help="Huawei AppGallery App ID")
    parser.add_argument("--file", required=True, help="Path to the APK or AAB file to upload")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.file):
        print(f"File not found: {args.file}")
        sys.exit(1)

    # 1. Get Token
    token = get_access_token(args.client_id, args.client_secret)
    
    # 2. Get Upload URL
    suffix = args.file.split('.')[-1]
    upload_url, auth_code = get_upload_url(token, args.app_id, args.client_id, suffix)
    
    # 3. Upload File
    file_info = upload_file(upload_url, auth_code, args.file)
    
    # 4. Update App File Info
    file_name = os.path.basename(args.file)
    update_app_file_info(token, args.app_id, args.client_id, file_info, file_name)
    
    print("\n---------------------------------------------------")
    print("Upload complete! Please check the AppGallery Console to submit for review.")
