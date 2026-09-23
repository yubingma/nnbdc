#!/usr/bin/env node

/**
 * 华为应用市场（AppGallery）应用截图生成器
 *
 * 复用 design/ui/app_store_minimal_clean_preview.html 这套应用商店海报原型，
 * 切换为「9:16 画布 + 华为/主流安卓微孔模具 + 安卓状态栏（无 Home Bar）」，
 * 逐张输出全出血 450×800（9:16）PNG，可直接上传华为应用市场。
 *
 * 实现要点：
 * 1. 每次只显示一张海报并让画布正好等于卡片，截图即成品，不做任何裁切；
 * 2. 以 3 倍尺寸渲染后降采样，保证小字号在 450×800 上依然锐利；
 * 3. 关闭全部动画，保证每次渲染结果完全一致；
 * 4. Chrome 截完图不会自行退出，按进程组整体回收，避免残留进程拖慢机器。
 *
 * 用法：
 *   node design/ui/render_huawei_screens.js            # 默认 450×800（华为控制台建议尺寸）
 *   node design/ui/render_huawei_screens.js 1080 1920  # 同比例高清版
 */

const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');

const UI_DIR = __dirname;
const ROOT = path.resolve(__dirname, '..', '..');
const SRC_HTML = 'app_store_minimal_clean_preview.html';
const OUT_DIR = path.join(ROOT, 'devops', '应用上架资源', 'huawei');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

// 超采样倍率：以 3 倍尺寸渲染后降采样，保证小字号锐利
const SUPERSAMPLE = 3;
const CHROME_TIMEOUT_MS = 60000;

const CARDS = [
  { id: 'card-1', name: '01_脱口而出_成就拉满' },
  { id: 'card-2', name: '02_一词多义_一网打尽' },
  { id: 'card-3', name: '03_语音答题_开口成诵' },
  { id: 'card-4', name: '04_真迹默写_落笔生根' },
  { id: 'card-5', name: '05_临界重温_精准唤醒' },
  { id: 'card-6', name: '06_词单导入_随心定制' },
  { id: 'card-7', name: '07_记忆苍穹_点亮词海' },
];

// 只保留目标海报、铺满画布、去掉圆角与投影（商店截图必须是全出血矩形）
function buildExportCss(width, height) {
  return `
<style id="huawei-export-style">
  html, body {
    margin: 0 !important;
    padding: 0 !important;
    width: ${width}px !important;
    height: ${height}px !important;
    background: #FFFFFF !important;
    overflow: hidden !important;
  }
  *, *::before, *::after { animation: none !important; transition: none !important; }
  .top-bar { display: none !important; }
  .showcase-container {
    display: block !important;
    width: ${width}px !important;
    height: ${height}px !important;
    padding: 0 !important;
    margin: 0 !important;
  }
  .gallery-row {
    display: block !important;
    padding: 0 !important;
    margin: 0 !important;
    gap: 0 !important;
    max-width: none !important;
    overflow: visible !important;
    scroll-snap-type: none !important;
  }
  .poster-card { display: none !important; }
  .poster-card.hw-target {
    display: flex !important;
    border-radius: 0 !important;
    box-shadow: none !important;
  }
  .poster-card:hover { transform: none !important; }
</style>
`;
}

function buildCardHtml(cardId, width, height) {
  const src = fs.readFileSync(path.join(UI_DIR, SRC_HTML), 'utf8');

  // 剥离原型控制台脚本，改为固化华为参数，避免 localStorage / DOMContentLoaded 干扰
  const stripped = src.replace(/<script>[\s\S]*<\/script>\s*<\/body>/, '</body>');
  if (stripped === src) throw new Error('未能剥离原型控制台脚本，页面结构可能已变更');

  const base = `<base href="file://${UI_DIR}/">`;
  const renderScript = `
<script>
  document.documentElement.setAttribute('data-aspect', 'huawei');
  document.documentElement.setAttribute('data-device', 'punch');
  document.documentElement.setAttribute('data-palette', 'emerald');
  document.documentElement.setAttribute('data-banner', 'show');
  document.getElementById('${cardId}').classList.add('hw-target');
</script>
`;

  const html = stripped
    .replace('</head>', base + buildExportCss(width, height) + '</head>')
    .replace('</body>', renderScript + '</body>');

  const tmpPath = path.join('/tmp', `huawei_${cardId}.html`);
  fs.writeFileSync(tmpPath, html);
  return tmpPath;
}

function sleepSync(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function waitForFile(file, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastSize = -1;
  while (Date.now() < deadline) {
    if (fs.existsSync(file)) {
      const size = fs.statSync(file).size;
      if (size > 0 && size === lastSize) return;
      lastSize = size;
    }
    sleepSync(300);
  }
  throw new Error(`等待截图超时: ${file}`);
}

function shoot(htmlPath, outPng, width, height) {
  if (fs.existsSync(outPng)) fs.unlinkSync(outPng);

  const args = [
    '--headless',
    '--no-sandbox',
    `--user-data-dir=${path.join('/tmp', 'chrome_huawei_profile')}`,
    '--disable-gpu',
    '--disable-breakpad',
    '--disable-crash-reporter',
    '--hide-scrollbars',
    `--force-device-scale-factor=${SUPERSAMPLE}`,
    `--window-size=${width},${height}`,
    `--screenshot=${outPng}`,
    `file://${htmlPath}`,
  ];

  const child = spawn(CHROME, args, { detached: true, stdio: 'ignore' });
  try {
    waitForFile(outPng, CHROME_TIMEOUT_MS);
  } finally {
    try { process.kill(-child.pid, 'SIGKILL'); } catch (e) {}
  }
}

function renderCard(card, width, height) {
  const htmlPath = buildCardHtml(card.id, width, height);
  const rawPng = path.join('/tmp', `huawei_${card.id}_raw.png`);
  shoot(htmlPath, rawPng, width, height);

  const outPng = path.join(OUT_DIR, `${card.name}.png`);
  execSync(`sips -z ${height} ${width} "${rawPng}" --out "${outPng}" >/dev/null 2>&1`);
  fs.unlinkSync(rawPng);

  const dims = execSync(`sips -g pixelWidth -g pixelHeight "${outPng}"`).toString().match(/\d+/g).slice(-2);
  if (+dims[0] !== width || +dims[1] !== height) {
    throw new Error(`${card.name} 输出尺寸异常: ${dims.join('×')}`);
  }
  console.log(`✅ ${card.name}.png  ${dims[0]}×${dims[1]}  ${Math.round(fs.statSync(outPng).size / 1024)} KB`);
}

function main() {
  const width = parseInt(process.argv[2] || '450', 10);
  const height = parseInt(process.argv[3] || '800', 10);
  if (width * 16 !== height * 9) {
    console.error(`❌ ${width}×${height} 不是 9:16，华为应用市场会拒收`);
    process.exit(1);
  }
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });

  console.log(`🚀 渲染华为应用市场截图 ${width}×${height}（9:16）→ devops/应用上架资源/huawei/`);
  for (const card of CARDS) renderCard(card, width, height);
  console.log(`\n🎉 完成 ${CARDS.length} 张，可直接上传华为应用市场。`);
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    console.error('❌ 渲染失败:', err.message);
    process.exit(1);
  }
}
