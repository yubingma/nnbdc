#!/usr/bin/env python3
"""Hybrid PDF OCR: local first, then API for remaining"""
import os
import sys
import base64
import json
import urllib.request
import urllib.error

API_KEY = os.environ.get("DASHSCOPE_API_KEY", "sk-85471cdc7ac24bd196a6ebb54e4c1cd0")
PDF_PATH = "/Volumes/ssd/downloads/book/星火英语高中英语词汇乱序版_20260419_124036.pdf"

def http_post(url, headers, data):
    req = urllib.request.Request(url, data=json.dumps(data).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())

def extract_page_local(page):
    """Extract text from a single PDF page using pdfplumber"""
    try:
        import pdfplumber
        text = page.extract_text()
        return text.strip() if text else ""
    except:
        return ""

def pdf_to_images(pdf_path, dpi=150):
    """Convert PDF pages to images"""
    import pypdfium2
    pdf = pypdfium2.PdfDocument(pdf_path)
    images = []
    for page_idx in range(len(pdf)):
        page = pdf[page_idx]
        bitmap = page.render(scale=dpi/72, rotation=0)
        pil_img = bitmap.to_pil()
        images.append(pil_img)
    return images

def image_to_base64(pil_img):
    import io
    buf = io.BytesIO()
    pil_img.save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode("utf-8")

def ocr_image_api(image_b64):
    """OCR using qwen-vl-max API"""
    url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    body = {
        "model": "qwen-vl-max",
        "messages": [{
            "role": "user",
            "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{image_b64}"}},
                {"type": "text", "text": "请识别图片中的所有单词及其中文释义，按Markdown表格格式输出。"}
            ]
        }]
    }
    status, result = http_post(url, headers, body)
    if status != 200:
        print(f"API error: {result}")
        return None
    choices = result.get("choices", [])
    if choices:
        return choices[0].get("message", {}).get("content")
    return None

def parse_words_from_text(text):
    """Extract words from plain text - show what's extracted"""
    import re
    words = []
    
    # Show raw text for first page
    print(f"\n--- Raw text (first 500 chars) ---")
    print(text[:500] if text else "EMPTY")
    print(f"--- End raw text ---\n")
    
    # Try different patterns
    patterns = [
        r'(\d+)\s+(\w+)\s+([vnan]+\.[^,\n]+)',  # 1 make v. 做
        r'(\d+)\s+(\w+)\s+\.',              # simple: 1 make.
        r'(\w+)\s+([vnan]+\.[^,\n]+)',      # word meaning (no number)
    ]
    
    for pattern in patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        if matches:
            print(f"Pattern '{pattern[:30]}...': {len(matches)} matches")
            for m in matches[:3]:
                print(f"  {m}")
            for num, word, meaning in matches:
                words.append(f"{word} {meaning.strip()}")
            break
    
    return words

def parse_words_from_markdown(markdown):
    """Extract words from Markdown table"""
    import re
    words = []
    # Match Markdown table rows
    pattern = r'\|\s*\d+\s*\|\s*(\w+)\s*\|\s*([^|]+)\|'
    matches = re.findall(pattern, markdown)
    for word, meaning in matches:
        words.append(f"{word} {meaning.strip()}")
    return words

def hybrid_parse():
    """Hybrid: local pdfplumber first, API for failed pages"""
    import pdfplumber
    
    print("=" * 50)
    print("Hybrid PDF OCR: local + API fallback")
    print("=" * 50)
    
    # Open PDF
    with pdfplumber.open(PDF_PATH) as pdf:
        total_pages = len(pdf.pages)
        print(f"Total pages: {total_pages}")
        
        all_words = []
        local_count = 0
        api_count = 0
        
        for i in range(total_pages):
            page = pdf.pages[i]
            text = extract_page_local(page)
            
            # Check if local extraction is good (has enough words)
            word_count = len(text.split('\n')) if text else 0
            
            if text and word_count > 5:
                # Local extraction worked
                words = parse_words_from_text(text)
                if words:
                    all_words.extend(words)
                    local_count += 1
                    print(f"Page {i+1}: local ({len(words)} words)")
                    continue
            
            # Local failed, use API
            print(f"Page {i+1}: local failed, using API...")
            api_count += 1
            
            # Convert page to image
            images = pdf_to_images(PDF_PATH)
            img_b64 = image_to_base64(images[i])
            
            # OCR via API
            markdown = ocr_image_api(img_b64)
            if markdown:
                words = parse_words_from_markdown(markdown)
                all_words.extend(words)
                print(f"Page {i+1}: API ({len(words)} words)")
            else:
                print(f"Page {i+1}: API failed too")
        
        print("=" * 50)
        print(f"Results: {local_count} pages local, {api_count} pages API")
        print(f"Total words: {len(all_words)}")
        print("\nFirst 20 words:")
        for w in all_words[:20]:
            print(f"  {w}")

if __name__ == "__main__":
    hybrid_parse()