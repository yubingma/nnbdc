#!/usr/bin/env node
/**
 * 原型逐帧截图器 (用于生成演示视频)
 *
 * 复刻 design/ui/render_mockup_png.js 的统一真机模具注入逻辑，
 * 额外注入视频背景渐变，并通过 puppeteer-core + 系统 Chrome，
 * 对原型页面的 window.__setTime(t) 时间轴逐帧截图。
 *
 * 用法：
 *   node design/ui/capture_prototype_frames.js <html文件> <输出帧目录> <帧数> [帧率]
 */

const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const ROOT = path.resolve(__dirname, '..', '..');
const UI_DIR = path.join(ROOT, 'design', 'ui');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

// 从原渲染脚本中复用统一模具 CSS 与状态栏 HTML，避免重复维护
function extractConst(src, name) {
  const m = src.match(new RegExp('const ' + name + ' = `([\\s\\S]*?)`;'));
  if (!m) throw new Error('无法从 render_mockup_png.js 提取 ' + name);
  return m[1];
}

function injectMockup(fileName, opts) {
  return _injectMockup(fileName, opts);
}

function _injectMockup(fileName, opts) {
  const videoBg = opts && opts.videoBg !== false;
  const srcPath = path.join(UI_DIR, fileName);
  let content = fs.readFileSync(srcPath, 'utf8');

  const renderSrc = fs.readFileSync(path.join(UI_DIR, 'render_mockup_png.js'), 'utf8');
  const UNIFIED_CSS = extractConst(renderSrc, 'UNIFIED_CSS');
  const STATUS_BAR_HTML = extractConst(renderSrc, 'STATUS_BAR_HTML');

  // 视频专用：给 html 铺一个护眼绿渐变背景（body 在统一 CSS 里是透明的）
  const VIDEO_BG = videoBg ? `<style>html{ background: linear-gradient(165deg, #EAF5F1 0%, #DEEEE8 46%, #CBDDD5 100%) !important; } *,*::before,*::after{ animation-play-state: paused !important; }</style>` : '';

  content = content.replace('</head>', VIDEO_BG + UNIFIED_CSS + '</head>');

  const hasOriginalStatusBar = content.includes('status-bar');
  const containerRegex = /(<div class="(?:device-mockup|phone-container|phone-wrapper)"[^>]*>)/;
  const match = content.match(containerRegex);
  if (match) {
    const topElement = hasOriginalStatusBar
      ? `<div class="unified-dynamic-island"><div class="unified-camera-lens"></div></div>`
      : STATUS_BAR_HTML;

    const replacement = `
      <div class="unified-device-wrapper">
        <div class="unified-button unified-btn-action"></div>
        <div class="unified-button unified-btn-vol-up"></div>
        <div class="unified-button unified-btn-vol-down"></div>
        <div class="unified-button unified-btn-power"></div>
        ${match[1]}
          ${topElement}
          <div class="unified-home-indicator"></div>
      `;
    content = content.replace(match[1], replacement);
    const lastDivIdx = content.lastIndexOf('</div>');
    if (lastDivIdx !== -1) {
      content = content.slice(0, lastDivIdx) + '</div></div>' + content.slice(lastDivIdx + 6);
    }
  }

  const tmpPath = path.join('/tmp', `vid_${fileName}`);
  fs.writeFileSync(tmpPath, content);
  return tmpPath;
}

async function main() {
  const [htmlFile, outDir, framesArg, fpsArg] = process.argv.slice(2);
  const numFrames = parseInt(framesArg || '375', 10);
  const fps = parseInt(fpsArg || '25', 10);

  if (!htmlFile || !outDir) {
    console.error('用法: node capture_prototype_frames.js <html> <outDir> [帧数] [帧率]');
    process.exit(1);
  }

  fs.mkdirSync(outDir, { recursive: true });
  for (const f of fs.readdirSync(outDir)) {
    if (/\.png$/.test(f)) fs.unlinkSync(path.join(outDir, f));
  }

  const tmpFile = injectMockup(htmlFile);
  const url = 'file://' + tmpFile;

  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: true,
    userDataDir: path.join('/tmp', 'ppdc_vidprof'),
    args: ['--no-sandbox', '--disable-gpu', '--disable-software-rasterizer', '--disable-dev-shm-usage', '--disable-crash-reporter', '--disable-breakpad', '--hide-scrollbars', '--mute-audio'],
  });

  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 540, height: 960, deviceScaleFactor: 2 });
    await page.goto(url, { waitUntil: 'load' });

    const total = numFrames;
    for (let i = 0; i < total; i++) {
      const t = i / (total - 1);
      await page.evaluate((tt) => { window.__setTime(tt); }, t);
      const file = path.join(outDir, `frame_${String(i).padStart(4, '0')}.png`);
      await page.screenshot({ path: file });
      if (i % 30 === 0) {
        process.stdout.write(`\r[${Math.round((i + 1) / total * 100)}%] frame ${i + 1}/${total}`);
      }
    }
    process.stdout.write('\n');
    console.log(`✅ 已渲染 ${total} 帧 -> ${outDir} (fps=${fps})`);
  } finally {
    await browser.close();
  }
}

module.exports = { injectMockup };

if (require.main === module) {
  main().catch((e) => { console.error('❌ 渲染失败:', e); process.exit(1); });
}
