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
    response = requests.post(TOKEN_URL, json=data, headers=headers)
    
    if response.status_code == 200:
        result = response.json()
        print("Access token obtained successfully.")
        return result.get("access_token")
    else:
        print(f"Failed to get access token. Status: {response.status_code}, Response: {response.text}")
        sys.exit(1)

def get_upload_url(access_token, app_id, client_id, suffix="apk"):
    """
    Get the upload URL for the application.
    """
    url = f"{PUBLISH_API_BASE}/upload-url"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "client_id": client_id
    }
    params = {
        "appId": app_id,
        "suffix": suffix
    }
    
    # Updated: some docs say client_id in header, some don't. 
    # Adding it to be safe, but primarily query params/body matter.
    
    print(f"Getting upload URL for App ID: {app_id}...")
    response = requests.get(url, params=params, headers=headers)
    
    if response.status_code == 200:
        result = response.json()
        if result.get("ret", {}).get("code") == 0:
            return result.get("uploadUrl"), result.get("authCode")
        else:
            print(f"Error getting upload URL: {result}")
            sys.exit(1)
    else:
        print(f"Failed to get upload URL. Status: {response.status_code}, Response: {response.text}")
        sys.exit(1)

def upload_file(upload_url, auth_code, file_path):
    """
    Uploads the file to the provided URL.
    """
    print(f"Uploading file: {file_path}...")
    
    # The file upload requires multipart/form-data
    # authCode needs to be part of the form data
    
    with open(file_path, 'rb') as f:
        files = {
            'file': f,
        }
        data = {
            'authCode': auth_code,
            'fileCount': 1
        }
        
        # Note: Do not set Content-Type header manually for multipart, access token not needed here usually
        response = requests.post(upload_url, files=files, data=data)
        
    if response.status_code == 200:
        result = response.json()
        if result.get("result", {}).get("result_code") == 0:
             print("File uploaded successfully.")
             return result.get("result", {}).get("UploadFileRsp", {}).get("fileInfoList")[0]
        else:
             print(f"Error during upload: {result}")
             sys.exit(1)
    else:
        print(f"Upload failed. Status: {response.status_code}, Response: {response.text}")
        sys.exit(1)

def update_app_file_info(access_token, app_id, client_id, file_info):
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
            "fileName": file_info.get("fileName"),
            "fileDestUrl": file_info.get("fileDestUlr"), # Note spelling in some docs
            "size": str(file_info.get("size"))
        }]
    }
    
    # Correct fileType based on observation
    if file_info.get("fileName", "").endswith(".aab"):
        payload["fileType"] = 5 # Actually 5 is common for APK. AAB might be different. 
        # API Doc says: 5: APK, 6: RPK, 8: OB, 9: XAPK, 12: AAB
        payload["fileType"] = 12
    
    print(f"Updating app file info...")
    response = requests.put(url, json=payload, headers=headers)
    
    if response.status_code == 200:
        result = response.json()
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
    update_app_file_info(token, args.app_id, args.client_id, file_info)
    
    print("\n---------------------------------------------------")
    print("Upload complete! Please check the AppGallery Console to submit for review.")
