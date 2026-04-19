#!/usr/bin/env python3
"""Local PDF OCR using pypdfium2 + tesseract"""
import os
import sys
import subprocess

PDF_PATH = "/Volumes/ssd/downloads/book/星火英语高中英语词汇乱序版_20260419_124036.pdf"
DPI = 200  # High quality for text

def pdf_page_to_image(page_num, dpi=DPI):
    """Convert one PDF page to image using pypdfium2"""
    import pypdfium2
    pdf = pypdfium2.PdfDocument(PDF_PATH)
    page = pdf[page_num]
    bitmap = page.render(scale=dpi/72, rotation=0)
    pil_img = bitmap.to_pil()
    return pil_img

def ocr_tesseract(image):
    """OCR image using tesseract command line"""
    import io
    buf = io.BytesIO()
    image.save(buf, "PNG")
    buf.seek(0)
    
    # Call tesseract
    result = subprocess.run(
        ["tesseract", "-", "-", "-l", "eng+chi_sim"],
        input=buf.read(),
        capture_output=True,
        text=False
    )
    return result.stdout.decode('utf-8')

def main():
    print("=" * 60)
    print("PDF -> Image -> Tesseract OCR")
    print("=" * 60)
    
    # Test first 3 pages
    for i in range(3):
        print(f"\n--- Page {i+1} ---")
        
        # Convert to image
        img = pdf_page_to_image(i)
        print(f"Image size: {img.size}")
        
        # OCR
        text = ocr_tesseract(img)
        print(f"OCR result ({len(text)} chars):")
        print(text[:500] if text else "EMPTY")
    
    print("\nDone!")

if __name__ == "__main__":
    main()