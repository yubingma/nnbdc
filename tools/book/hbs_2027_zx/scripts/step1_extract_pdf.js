const fs = require('fs');
const path = require('path');
const pdf = require('pdf-parse');

const PROJECT_DIR = path.join(__dirname, '..');
const PDF_PATH = path.join(PROJECT_DIR, 'raw', '2027考研英语红宝书（正序版）A4默写版.pdf');
const OUTPUT_PATH = path.join(PROJECT_DIR, 'output', '2027_hbs_raw.txt');

async function extract() {
    console.log(`Starting extraction from: ${PDF_PATH}`);
    if (!fs.existsSync(PDF_PATH)) {
        console.error("Error: PDF file not found at " + PDF_PATH);
        return;
    }

    let dataBuffer = fs.readFileSync(PDF_PATH);

    try {
        const data = await pdf(dataBuffer);
        fs.writeFileSync(OUTPUT_PATH, data.text);
        console.log(`Success! Extracted ${data.numpages} pages.`);
        console.log(`Raw text saved to: ${OUTPUT_PATH}`);
    } catch (error) {
        console.error("Extraction failed:", error);
    }
}

extract();
