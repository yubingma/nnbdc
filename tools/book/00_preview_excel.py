import openpyxl
import sys

def preview_xlsx(file_path):
    try:
        wb = openpyxl.load_workbook(file_path, data_only=True)
        ws = wb.active
        print(f"Sheet Name: {ws.title}")
        for row_idx, row in enumerate(ws.iter_rows(max_row=10, values_only=True), 1):
            print(f"Row {row_idx}: {row}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    preview_xlsx('./雅思/彩色词汇中英版.xlsx')
