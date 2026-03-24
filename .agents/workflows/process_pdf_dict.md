---
description: How to process a new English Vocabulary PDF into a clean TXT dictionary
---

# PDF to pure TXT Vocabulary Extraction Workflow

When the USER asks you to extract words from a new PDF vocabulary book or process a new PDF dictionary, you **MUST** strictly follow this "Human-in-the-loop" defensive pipeline. Do not attempt to use general NLP models to automatically split or fix words blindly, as this produces destructive errors (e.g. changing `HongKong` to `honking` or splitting legitimate British words).

The necessary tool scripts for this workflow are natively prepared and permanently located at: 
`/Volumes/ssd/ppdc/tools/book/pdf_pipeline/`

## Phase 1: Physical Extraction (`01_extract_raw.py`)

1. Determine the PDF format (is it a pure sequence like `1. word`, or a Table PDF?). If it's a table PDF, modify the `pdfplumber.extract_tables` logic appropriately, otherwise use the default regex based extractor logic inside `01_extract_raw.py`.
2. Update the `PDF_PATH` and `OUTPUT_TXT` variables in `/Volumes/ssd/ppdc/tools/book/pdf_pipeline/01_extract_raw.py` or use the CLI.
3. Auto-run the python script using CLI.
4. Check its output logging for any `missing sequence numbers`, which tells if the physical formatting broke the regex structure. The script also automatically removes POS tags (adj., n., v.) and completely strips everything starting from standard parentheses `()`, `[]`, or Chinese characters.
5. Provide the USER with the extracted count.

## Phase 2: Scout Errors / Read-Only Audit (`02_scout_errors.py`)

1. Before running, ensure you have the output from Phase 1.
2. Auto-run `python /Volumes/ssd/ppdc/tools/book/pdf_pipeline/02_scout_errors.py <input.txt> <report.txt>`.
3. This step does **NOT** modify any TXT. It only reads the file, runs `wordninja` and `pyspellchecker` on words absent from the standard NLTK dictionary, and exports its findings to the report file.
4. Use `view_file` tool to read the generated report.

## Phase 3: Human Whitelist Vetting

1. Display the contents of the report nicely to the USER.
2. Remind the USER that `wordninja` and `SpellChecker` are just dumb algorithms proposing changes. Ask the USER to explicitly tell you *which ones* of the suspect list are genuinely valid corrections (e.g., `federa` -> `federal`, `bringhometo` -> `bring home to`). They should explicitly ignore British variations (like `waggon`) or proper nouns (`HongKong`).
3. WAIT for the USER's confirmation.

## Phase 4: Apply Curated Fixes (`03_apply_fixes.py`)

1. Take the confirmed subset of fixes from the USER.
2. Edit `/Volumes/ssd/ppdc/tools/book/pdf_pipeline/03_apply_fixes.py`, and populate the `MY_WHITELIST = {}` python dictionary with ONLY the USER-approved typo fixes mappings.
3. Auto-run `python /Volumes/ssd/ppdc/tools/book/pdf_pipeline/03_apply_fixes.py <input.txt> <final.txt>`.
4. Tell the USER the final perfect TXT file is ready for database consumption.
