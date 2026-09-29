#!/usr/bin/env node

/**
 * 应用商店截图生成器（App Store iPhone 6.5" / App Store iPad 13" / 华为应用市场 / 横排概览图）
 *
 * 四路产物，共用同一套暖橙视觉语言（苹果与华为同一份原型，iPad 是宽屏版原型）：
 *   apple    1242×2688（9:19.5）→ design/ui/png/app_store_iphone_6.5/
 *   ipad     2048×2732（3:4）   → design/ui/png/app_store_ipad_13/
 *   huawei   450×800（9:16）   → devops/应用上架资源/huawei/
 *   overview 7 张横排概览图     → design/ui/png/app_store_minimal_clean_overview.png
 *
 * 实现要点：
 * 1. 每次只显示一张海报并让画布正好等于卡片，截图即成品，不做任何裁切；
 * 2. 小尺寸产物（华为 450×800）以 3 倍渲染后降采样，保证小字号锐利；
 *    App Store 尺寸本身就是 3.18 倍交付尺寸，直接以交付分辨率渲染，不放大不缩水；
 * 3. 关闭全部动画，保证每次渲染结果完全一致；
 * 4. Chrome 截完图不会自行退出，按进程组整体回收，避免残留进程拖慢机器。
 *
 * 用法：
 *   node design/ui/render_app_store_screens.js            # apple + ipad + huawei 全部
 *   node design/ui/render_app_store_screens.js apple
 *   node design/ui/render_app_store_screens.js ipad
 *   node design/ui/render_app_store_screens.js huawei
 *   node design/ui/render_app_store_screens.js overview
 */

const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');

const UI_DIR = __dirname;
const ROOT = path.resolve(__dirname, '..', '..');
const SRC_PHONE_HTML = 'app_store_minimal_clean_preview.html';
const SRC_IPAD_HTML = 'app_store_ipad_preview.html';
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const HUAWEI_SUPERSAMPLE = 3;
// 原型 --phone-width/--phone-height 的固化值，导出时要按回设计尺寸
const PHONE_WIDTH = 324;
const PHONE_HEIGHT = 692;
const CHROME_TIMEOUT_MS = 60000;
const OVERVIEW_GAP = 22;
const OVERVIEW_MARGIN = 24;

// 海报面（文案/横幅）固定为商店交付态，与原型控制台的默认值一致
const POSTER_ATTRS = `
  document.documentElement.setAttribute('data-copy', 'a');
  document.documentElement.setAttribute('data-banner', 'show');
`;

const TARGETS = {
  apple: {
    srcHtml: SRC_PHONE_HTML,
    width: 1242,
    height: 2688,
    // 海报原型在 9:19.5 下的版面尺寸就是 390×844，放大 3.18 倍正好是 App Store 交付尺寸
    canvasWidth: 390,
    canvasHeight: 844,
    aspect: 'apple',
    device: 'pure',
    outDir: path.join(UI_DIR, 'png', 'app_store_iphone_6.5'),
  },
  ipad: {
    srcHtml: SRC_IPAD_HTML,
    width: 2048,
    height: 2732,
    // iPad 13" 版面就是 1024×1366，正好 2 倍交付
    canvasWidth: 1024,
    canvasHeight: 1366,
    aspect: 'ipad',
    device: 'ipad',
    outDir: path.join(UI_DIR, 'png', 'app_store_ipad_13'),
  },
  huawei: {
    srcHtml: SRC_PHONE_HTML,
    width: 450,
    height: 800,
    canvasWidth: 450,
    canvasHeight: 800,
    aspect: 'huawei',
    device: 'punch',
    outDir: path.join(ROOT, 'devops', '应用上架资源', 'huawei'),
  },
};

const CARDS = [
  { id: 'card-1', name: '01_脱口而出_说得出才算记住' },
  { id: 'card-2', name: '02_一词多义_读懂它的全部' },
  { id: 'card-3', name: '03_语音答题_说出口才算读懂' },
  { id: 'card-4', name: '04_真迹默写_手写一遍属于你' },
  { id: 'card-5', name: '05_临界重温_快遗忘时提醒' },
  { id: 'card-6', name: '06_词单导入_一分钟安顿好' },
  { id: 'card-7', name: '07_核心意象_串起所有释义' },
];

/// 原型 HTML 去掉控制台脚本后的骨架：商店导出必须固化参数，不能受 localStorage 干扰。
/// base 必须插在 <head> 之后、海报自身 <style> 之前 —— 行内样式表的相对 URL 是按
/// 「解析到该 <style> 时的 base」解析的；插到 </head> 前会让样式表里的
/// url('assets/...') 落到临时文件所在目录（曾经因此静默渲染出一张空白圆心）。
function readStrippedHtml(srcHtml) {
  const src = fs.readFileSync(path.join(UI_DIR, srcHtml), 'utf8');
  const stripped = src.replace(/<script>[\s\S]*<\/script>\s*<\/body>/, '</body>');
  // iPad 原型本来就没有控制台脚本；有脚本却剥不掉，才是页面结构变了
  if (stripped === src && src.includes('<script')) {
    throw new Error(`未能剥离 ${srcHtml} 的控制台脚本，页面结构可能已变更`);
  }
  return stripped.replace('<head>', `<head><base href="file://${UI_DIR}/">`);
}

function writeTempHtml(srcHtml, tag, exportCss, bootScript) {
  const html = readStrippedHtml(srcHtml)
    .replace('</head>', `<style id="export-style">${exportCss}</style></head>`)
    .replace('</body>', `<script>${bootScript}</script></body>`);
  const tmpPath = path.join('/tmp', `appstore_${tag}.html`);
  fs.writeFileSync(tmpPath, html);
  return tmpPath;
}

// 只保留目标海报、铺满画布、去掉圆角与投影（商店截图必须是全出血矩形）
function cardExportCss(width, height) {
  return `
  html, body {
    margin: 0 !important; padding: 0 !important;
    width: ${width}px !important; height: ${height}px !important;
    background: #12100E !important; overflow: hidden !important;
  }
  *, *::before, *::after { animation: none !important; transition: none !important; }
  .top-bar { display: none !important; }
  .showcase-container { display: block !important; width: ${width}px !important; height: ${height}px !important; padding: 0 !important; margin: 0 !important; }
  .gallery-row { display: block !important; padding: 0 !important; margin: 0 !important; gap: 0 !important; max-width: none !important; overflow: visible !important; scroll-snap-type: none !important; }
  .poster-card { display: none !important; }
  .poster-card.export-target {
    display: flex !important;
    border-radius: 0 !important;
    box-shadow: none !important;
  }
  .poster-card:hover { transform: none !important; }
  /* 导出画布是固定尺寸的海报，不是手机视口。390 宽的窗口会命中原型里的
     @media (max-width:600px) 移动端兜底，把卡片压成 780 高、机身缩到 290×620，
     成品因此底部露出 64px 页面底色、机身还小一圈 —— 必须在这里按掉。 */
  .poster-card.export-target {
    width: ${width}px !important;
    max-width: none !important;
    height: ${height}px !important;
  }
  html:not([data-aspect="huawei"]) .device-chassis {
    width: ${PHONE_WIDTH}px !important;
    height: ${PHONE_HEIGHT}px !important;
  }
`;
}

// 7 张横排铺开，仅用于人工审阅整体观感；透明底，圆角与投影保留
function overviewExportCss(width, height) {
  return `
  html, body {
    margin: 0 !important; padding: 0 !important;
    width: ${width}px !important; height: ${height}px !important;
    background: transparent !important; overflow: hidden !important;
  }
  *, *::before, *::after { animation: none !important; transition: none !important; }
  .top-bar { display: none !important; }
  .showcase-container { padding: ${OVERVIEW_MARGIN}px !important; display: block !important; }
  .gallery-row { display: flex !important; gap: ${OVERVIEW_GAP}px !important; padding: 0 !important; margin: 0 !important; overflow: visible !important; max-width: none !important; scroll-snap-type: none !important; }
  .poster-card:hover { transform: none !important; }
`;
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

function shoot(htmlPath, outPng, width, height, scaleFactor, transparent) {
  if (fs.existsSync(outPng)) fs.unlinkSync(outPng);

  const args = [
    '--headless',
    '--no-sandbox',
    `--user-data-dir=${path.join('/tmp', 'chrome_appstore_profile')}`,
    '--disable-gpu',
    '--disable-breakpad',
    '--disable-crash-reporter',
    '--hide-scrollbars',
    // 虚拟时间预算：等图片解码、字体就位后再截图。
    // 少了它，大图（意象图 1.2MB）会在解码完成前被截走，静默产出空白圆心。
    '--virtual-time-budget=5000',
    `--force-device-scale-factor=${scaleFactor}`,
    `--window-size=${width},${height}`,
    `--screenshot=${outPng}`,
  ];
  if (transparent) args.push('--default-background-color=00000000');
  args.push(`file://${htmlPath}`);

  const child = spawn(CHROME, args, { detached: true, stdio: 'ignore' });
  try {
    waitForFile(outPng, CHROME_TIMEOUT_MS);
  } finally {
    try { process.kill(-child.pid, 'SIGKILL'); } catch (e) {}
  }
}

/// 渲染一张商店截图；scale 为「交付尺寸 ÷ 版面尺寸」。
/// 华为 450×800 版面即交付尺寸，故以 3 倍渲染再降采样换取小字号锐利；
/// App Store 版面只有 390×844，直接以 3.18 倍交付分辨率渲染，不放大不缩水。
function renderCard(target, card, scale) {
  const { width, height, canvasWidth, canvasHeight, aspect, device, outDir } = target;
  const bootScript = `
    document.documentElement.setAttribute('data-aspect', '${aspect}');
    document.documentElement.setAttribute('data-device', '${device}');
    ${POSTER_ATTRS}
    document.getElementById('${card.id}').classList.add('export-target');
  `;
  const htmlPath = writeTempHtml(target.srcHtml, `${aspect}_${card.id}`, cardExportCss(canvasWidth, canvasHeight), bootScript);
  const rawPng = path.join('/tmp', `appstore_${aspect}_${card.id}_raw.png`);
  shoot(htmlPath, rawPng, canvasWidth, canvasHeight, scale, false);

  const outPng = path.join(outDir, `${card.name}.png`);
  fs.copyFileSync(rawPng, outPng);
  fs.unlinkSync(rawPng);

  // Chrome 的截图尺寸取决于版面尺寸 × 缩放比，可能差 1px；商店对尺寸是硬要求，这里归一化
  const size = () => execSync(`sips -g pixelWidth -g pixelHeight "${outPng}"`).toString().match(/\d+/g).slice(-2).map(Number);
  let [w, h] = size();
  if (w !== width || h !== height) {
    execSync(`sips -z ${height} ${width} "${outPng}" >/dev/null 2>&1`);
    [w, h] = size();
  }
  if (w !== width || h !== height) {
    throw new Error(`${card.name} 输出尺寸异常: ${w}×${h}，期望 ${width}×${height}`);
  }
  // 页面脚本一旦抛错，海报会整张不显示、截出一张纯底色图（曾静默产出过 15KB 空图），
  // 尺寸校验拦不住这种失败，再用一个体积下限兜住。
  const kb = Math.round(fs.statSync(outPng).size / 1024);
  if (kb < 60) throw new Error(`${card.name} 只有 ${kb} KB，疑似整张海报未渲染`);
  console.log(`✅ ${card.name}.png  ${w}×${h}  ${kb} KB`);
}

function renderTarget(target, scale) {
  if (!fs.existsSync(target.outDir)) fs.mkdirSync(target.outDir, { recursive: true });
  console.log(`🚀 渲染 ${target.width}×${target.height}（版面 ${target.canvasWidth}×${target.canvasHeight} × ${scale.toFixed(4)}）→ ${path.relative(ROOT, target.outDir)}/`);
  for (const card of CARDS) renderCard(target, card, scale);
}

/// 横排概览图：手机与 iPad 各出一张，供人工审阅整体观感
function renderOverview() {
  const jobs = [
    { srcHtml: SRC_PHONE_HTML, cardW: 390, cardH: 844, out: 'app_store_minimal_clean_overview.png' },
    { srcHtml: SRC_IPAD_HTML, cardW: 1024, cardH: 1366, out: 'app_store_ipad_overview.png' },
  ];
  for (const job of jobs) {
    const scale = 2;
    const width = CARDS.length * job.cardW + (CARDS.length - 1) * OVERVIEW_GAP + OVERVIEW_MARGIN * 2;
    const height = job.cardH + OVERVIEW_MARGIN * 2;
    const outPng = path.join(UI_DIR, 'png', job.out);
    const htmlPath = writeTempHtml(job.srcHtml, `overview_${job.cardW}`, overviewExportCss(width, height), POSTER_ATTRS);
    shoot(htmlPath, outPng, width, height, scale, true);
    console.log(`✅ 概览图 ${job.out}  ${width * scale}×${height * scale}  ${Math.round(fs.statSync(outPng).size / 1024)} KB`);
  }
}

function main() {
  const what = (process.argv[2] || 'all').toLowerCase();
  const jobs = {
    apple: () => renderTarget(TARGETS.apple, TARGETS.apple.width / TARGETS.apple.canvasWidth),
    ipad: () => renderTarget(TARGETS.ipad, TARGETS.ipad.width / TARGETS.ipad.canvasWidth),
    huawei: () => renderTarget(TARGETS.huawei, HUAWEI_SUPERSAMPLE),
    overview: renderOverview,
  };
  if (what === 'all') {
    Object.values(jobs).forEach((run) => run());
  } else if (jobs[what]) {
    jobs[what]();
  } else {
    console.error(`❌ 未知目标「${what}」，可选：all / apple / ipad / huawei / overview`);
    process.exit(1);
  }
  console.log('\n🎉 完成。');
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    console.error('❌ 渲染失败:', err.message);
    process.exit(1);
  }
}
