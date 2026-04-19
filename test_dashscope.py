#!/usr/bin/env python3
"""Test DashScope PDF -> Image -> OCR flow"""
import os
import base64
import urllib.request
import urllib.error
import json

API_KEY = os.environ.get("DASHSCOPE_API_KEY", "sk-85471cdc7ac24bd196a6ebb54e4c1cd0")
PDF_PATH = "/Volumes/ssd/downloads/book/星火英语高中英语词汇乱序版_20260419_124036.pdf"

def http_post(url, headers, data):
    req = urllib.request.Request(url, data=json.dumps(data).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())

def pdf_to_images(pdf_path, dpi=150):
    """Convert PDF pages to images using pdf2image or pypdfium2"""
    import pypdfium2
    
    pdf = pypdfium2.PdfDocument(pdf_path)
    images = []
    
    for page_idx in range(len(pdf)):
        page = pdf[page_idx]
        # Render page to bitmap
        bitmap = page.render(
            scale=dpi/72,
            rotation=0,
        )
        pil_img = bitmap.to_pil()
        images.append(pil_img)
        print(f"Rendered page {page_idx + 1}/{len(pdf)}")
    
    return images

def image_to_base64(pil_img, format="PNG"):
    import io
    buf = io.BytesIO()
    pil_img.save(buf, format=format)
    return base64.b64encode(buf.getvalue()).decode("utf-8")

def ocr_image(image):
    """Send image to Qwen-VL for OCR"""
    url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    
    # Convert image to base64
    img_b64 = image_to_base64(image)
    
    body = {
        "model": "qwen-vl-max",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/png;base64,{img_b64}"}
                    },
                    {
                        "type": "text",
                        "text": "请识别图片中的所有单词及其中文释义，按Markdown表格格式输出。不要遗漏任何单词。"
                    }
                ]
            }
        ]
    }
    
    status, result = http_post(url, headers, body)
    print(f"OCR status: {status}")
    if status != 200:
        print("Error:", result)
        return None
    
    choices = result.get("choices", [])
    if choices:
        return choices[0].get("message", {}).get("content")
    print("Full:", result)
    return None

def extract_text_local():
    try:
        import pdfplumber
        with pdfplumber.open(PDF_PATH) as pdf:
            text = ""
            for page in pdf.pages[:3]:
                page_text = page.extract_text()
                if page_text:
                    text += page_text + "\n"
            if text.strip():
                print(f"pdfplumber extracted {len(text)} chars")
                return text[:2000]
    except Exception as e:
        print(f"pdfplumber error: {e}")
    return None

if __name__ == "__main__":
    print("=" * 50)
    print("Step 1: Converting PDF to images...")
    images = pdf_to_images(PDF_PATH, dpi=200)
    print(f"Converted {len(images)} pages to images")
    
    print("=" * 50)
    print("Step 2: OCR first image with Qwen-VL...")
    result = ocr_image(images[0])
    
    if result:
        print("=" * 50)
        print("SUCCESS! First 1000 chars:")
        print(result[:1000])
    else:
        print("OCR failed!")

API_KEY = os.environ.get("DASHSCOPE_API_KEY", "sk-85471cdc7ac24bd196a6ebb54e4c1cd0")
PDF_PATH = "/Volumes/ssd/downloads/book/星火英语高中英语词汇乱序版_20260419_124036.pdf"

def upload_file(pdf_path):
    # Try compatible-mode endpoint first
    url = "https://dashscope.aliyuncs.com/compatible-mode/v1/files"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
    }
    boundary = "----FormBoundary123"
    body = f"--{boundary}\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nfile-extract\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"vocab.pdf\"\r\nContent-Type: application/pdf\r\n\r\n"
    with open(pdf_path, "rb") as f:
        body += f.read().decode("latin-1")
    body += f"\r\n--{boundary}--\r\n"
    headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    
    req = urllib.request.Request(url, data=body.encode(), headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        # Try native API if compatible-mode fails
        print("Compatible upload failed, trying native API...")
        url = "https://dashscope.aliyuncs.com/api/v1/files"
        req = urllib.request.Request(url, data=body.encode(), headers=headers)
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read().decode())
    
    print("Upload response:", result)
    
    file_id = None
    if "data" in result:
        uploaded_files = result["data"].get("uploaded_files", [])
        if uploaded_files:
            file_id = uploaded_files[0].get("file_id")
    if not file_id:
        file_id = result.get("id")
    
    print(f"File ID: {file_id}")
    return file_id

def parse_document_native(file_id):
    url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    body = {
        "model": "qwen-doc-turbo",
        "input": {
            "messages": [
                {"role": "system", "content": f"fileid://{file_id}"},
                {"role": "user", "content": "请解析该文档，将其中的所有表格以 Markdown 格式完整输出，不要遗漏任何单词。"}
            ]
        }
    }
    status, result = http_post(url, headers, body)
    print(f"Native API status: {status}")
    if status != 200:
        print("Native API error:", result)
        return None
    
    if "output" in result:
        choices = result["output"].get("choices", [])
        if choices:
            return choices[0].get("message", {}).get("content")
    print("Full response:", result)
    return None

def parse_with_qwen_doc(file_id):
    # Use qwen-doc-turbo with proper message format
    url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    body = {
        "model": "qwen-doc-turbo",
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "system", "content": f"fileid://{file_id}"},
            {"role": "user", "content": "列出文档中所有单词及其中文释义，以Markdown表格格式输出。"}
        ]
    }
    status, result = http_post(url, headers, body)
    print(f"qwen-doc-turbo status: {status}")
    if status != 200:
        print("Error:", result)
        return None
    
    choices = result.get("choices", [])
    if choices:
        return choices[0].get("message", {}).get("content")
    print("Full:", result)
    return None

def parse_with_qwen_ocr(file_id):
    # Fallback: use simple text send after file ID - text only
    url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    body = {
        "model": "qwen-vl-max",
        "messages": [
            {"role": "system", "content": "You are an OCR assistant."},
            {"role": "user", "content": f"fileid://{file_id}\n\n请识别并列出该文档中的所有单词。"}
        ]
    }
    status, result = http_post(url, headers, body)
    print(f"qwen-vl-max status: {status}")
    if status != 200:
        print("Error:", result)
        return None
    
    choices = result.get("choices", [])
    if choices:
        return choices[0].get("message", {}).get("content")
    print("Full:", result)
    return None

def test_text_api():
    url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    body = {
        "model": "qwen-plus",
        "input": {
            "messages": [
                {"role": "user", "content": "你好，请用一句话介绍自己"}
            ]
        }
    }
    status, result = http_post(url, headers, body)
    print(f"Text API status: {status}")
    if status != 200:
        print("Text API error:", result)
        return None
    
    if "output" in result:
        text = result["output"].get("text")
        if text:
            return text
        choices = result["output"].get("choices", [])
        if choices:
            return choices[0].get("message", {}).get("content")
    print("Full response:", result)
    return None

def parse_with_retry_ocr(file_id, max_retries=3, delay=2):
    import time
    for i in range(max_retries):
        print(f"OCR Attempt {i+1}/{max_retries}...")
        result = parse_with_qwen_ocr(file_id)
        if result:
            return result
        if i < max_retries - 1:
            print(f"Retrying in {delay}s...")
            time.sleep(delay)
    return None

def extract_text_local():
    # Try pdfplumber first
    try:
        import pdfplumber
        with pdfplumber.open(PDF_PATH) as pdf:
            text = ""
            for page in pdf.pages[:3]:  # First 3 pages
                page_text = page.extract_text()
                if page_text:
                    text += page_text + "\n"
            if text.strip():
                print(f"pdfplumber extracted {len(text)} chars")
                return text[:2000]
    except Exception as e:
        print(f"pdfplumber error: {e}")
    
    # Try pypdfium2
    try:
        import pypdfium2
        pdf = pypdfium2.PdfDocument(PDF_PATH)
        text = ""
        for i in range(min(3, len(pdf))):
            page = pdf[i]
            textpage = page.get_textpage()
            text += textpage.get_text_bounded() + "\n"
        if text.strip():
            print(f"pypdfium2 extracted {len(text)} chars")
            return text[:2000]
    except Exception as e:
        print(f"pypdfium2 error: {e}")
    
    return None

if __name__ == "__main__":
    print("=" * 50)
    print("Trying local PDF text extraction...")
    text = extract_text_local()
    if text:
        print("=" * 50)
        print("Local extraction SUCCESS! First 500 chars:")
        print(text[:500])
        print("\nDone - local extraction works!")
    else:
        print("Local extraction failed")