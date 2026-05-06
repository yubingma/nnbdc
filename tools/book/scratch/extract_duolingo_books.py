import pdfplumber
import openpyxl
import re
import os
import hashlib

def get_md5(text):
    return hashlib.md5(text.encode('utf-8')).hexdigest()

def extract_pdf_words(pdf_path, output_txt):
    # Matches words followed by POS tag like vt. adj. n. etc.
    POS_PATTERN = r'\b([A-Za-z\-\']{2,})\s+(?:[a-z]{1,4}\.)'
    words = []
    seen = set()
    try:
        with pdfplumber.open(pdf_path) as pdf:
            for page in pdf.pages:
                text = page.extract_text()
                if text:
                    matches = re.findall(POS_PATTERN, text)
                    for m in matches:
                        m_lower = m.lower()
                        if m_lower not in seen:
                            seen.add(m_lower)
                            words.append(m)
        
        with open(output_txt, 'w', encoding='utf-8') as f:
            for w in words:
                f.write(w + "\n")
        print(f"✅ Extracted {len(words)} words from {os.path.basename(pdf_path)} -> {os.path.basename(output_txt)}")
    except Exception as e:
        print(f"❌ Error processing {pdf_path}: {e}")

def extract_excel_all_sheets(excel_path, output_dir):
    try:
        wb = openpyxl.load_workbook(excel_path, data_only=True)
        level_sheets = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']
        
        for sheet_name in wb.sheetnames:
            if sheet_name == '使用说明':
                continue
                
            ws = wb[sheet_name]
            # Identify columns
            header = [str(c.value).strip().lower() if c.value else "" for c in ws[1]]
            try:
                word_idx = header.index('base word')
            except ValueError:
                word_idx = 0
            
            try:
                topic_idx = header.index('topic')
            except ValueError:
                topic_idx = -1 # No topic column
            
            data = []
            seen = set()
            
            for row in ws.iter_rows(min_row=2, values_only=True):
                if row and row[word_idx]:
                    word = str(row[word_idx]).strip()
                    word_lower = word.lower()
                    if word_lower not in seen:
                        topic = str(row[topic_idx]).strip() if (topic_idx != -1 and topic_idx < len(row) and row[topic_idx]) else ""
                        seen.add(word_lower)
                        data.append({
                            'word': word,
                            'topic': topic,
                            'md5': get_md5(word_lower)
                        })
            
            # Sorting logic: Topic (primary), MD5 (secondary)
            data.sort(key=lambda x: (x['topic'], x['md5']))
            
            # Determine filename
            if sheet_name in level_sheets:
                fname = f"CERF等级词汇{sheet_name}.txt"
            else:
                fname = f"{sheet_name}.txt"
                
            output_txt = os.path.join(output_dir, fname)
            with open(output_txt, 'w', encoding='utf-8') as f:
                for item in data:
                    f.write(item['word'] + "\n")
            print(f"✅ Extracted {len(data)} entries from sheet {sheet_name} (Sorted by Topic & MD5) -> {fname}")
            
    except Exception as e:
        print(f"❌ Error processing {excel_path}: {e}")

if __name__ == "__main__":
    base_dir = "/Volumes/ssd/ppdc/tools/book/多邻国/"
    output_dir = "/Volumes/ssd/ppdc/tools/book/多邻国/extracted/"
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # 1. Process PDFs (Keeping original order as before)
    pdf_books = [
        "多邻国核心词汇初级.pdf",
        "多邻国核心词汇中级.pdf",
        "多邻国核心词汇专业.pdf"
    ]
    for book in pdf_books:
        input_path = os.path.join(base_dir, book)
        output_path = os.path.join(output_dir, book.replace('.pdf', '.txt'))
        extract_pdf_words(input_path, output_path)
        
    # 2. Process Excel
    excel_path = os.path.join(base_dir, "7.CEFR 7243词单词表-re.xlsx")
    extract_excel_all_sheets(excel_path, output_dir)
