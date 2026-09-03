#!/usr/bin/env node

/**
 * 统一原型界面真机高清透明 PNG 生成器 (Unified Device Mockup Generator)
 * 
 * 功能：
 * 1. 自动为 HTML 移动端原型套上统一规范的 iPhone 旗舰真机外壳模具（深空钛金属中框 + 侧边按键 + 灵动岛 + Home Bar）
 * 2. 手机壳外侧背景 100% 透明 (Alpha = 0)，免抠图
 * 3. 支持 Retina 2x 高清输出至 design/ui/png/ 目录
 * 4. 支持同步自动导入至 macOS 系统相册 (Photos.app)
 * 
 * 用法：
 * - 渲染全部原型：node design/ui/render_mockup_png.js --all
 * - 渲染单个原型：node design/ui/render_mockup_png.js review_distribution_preview.html
 * - 渲染并自动同步到 Mac 相册：node design/ui/render_mockup_png.js --all --import-photos
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const UI_DIR = path.resolve(__dirname);
const PNG_DIR = path.join(UI_DIR, 'png');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

if (!fs.existsSync(PNG_DIR)) {
  fs.mkdirSync(PNG_DIR, { recursive: true });
}

// 统一真机模具样式 (深空钛金属微中框 + 优雅阴影 + 灵动岛 + Home Bar)
const UNIFIED_CSS = `
<style id="unified-chassis-style">
  body {
    background: transparent !important;
    margin: 0 !important;
    padding: 24px 20px 30px !important;
    display: flex !important;
    flex-direction: column !important;
    align-items: center !important;
    justify-content: center !important;
    min-height: 100vh !important;
    height: 100vh !important;
    overflow: hidden !important;
  }
  .designer-toolbar, .toolbar, .preview-header, .design-notes, .theme-toggle-fab, .modal-overlay, .modal-backdrop {
    display: none !important;
  }
  body > *:not(.phone-container):not(.device-mockup):not(.phone-wrapper):not(.device-wrapper):not(.unified-device-wrapper) {
    display: none !important;
  }
  .unified-device-wrapper {
    position: relative !important;
    margin: 0 auto !important;
    flex-shrink: 0 !important;
  }
  .unified-button {
    position: absolute !important;
    background: #252D29 !important;
    border-radius: 3px !important;
    z-index: 0 !important;
  }
  .unified-btn-action { left: -13px !important; top: 105px !important; width: 4px !important; height: 28px !important; }
  .unified-btn-vol-up { left: -13px !important; top: 148px !important; width: 4px !important; height: 48px !important; }
  .unified-btn-vol-down { left: -13px !important; top: 206px !important; width: 4px !important; height: 48px !important; }
  .unified-btn-power { right: -13px !important; top: 160px !important; width: 4px !important; height: 68px !important; }

  .phone-container, .device-mockup, .phone-wrapper {
    width: 393px !important;
    max-width: 393px !important;
    height: 852px !important;
    max-height: 852px !important;
    border-radius: 54px !important;
    border: 3.5px solid #000000 !important;
    box-shadow: 
      0 0 0 11px #1A211E,
      0 0 0 12.5px rgba(255, 255, 255, 0.16),
      0 0 0 13.5px rgba(0, 0, 0, 0.35),
      0 30px 70px -12px rgba(10, 30, 24, 0.35),
      0 12px 30px -6px rgba(0, 0, 0, 0.2) !important;
    overflow: hidden !important;
    position: relative !important;
    display: flex !important;
    flex-direction: column !important;
    z-index: 1 !important;
    box-sizing: border-box !important;
  }
  .unified-status-bar {
    height: 44px !important;
    min-height: 44px !important;
    padding: 0 24px !important;
    display: flex !important;
    justify-content: space-between !important;
    align-items: center !important;
    background: transparent !important;
    position: relative !important;
    z-index: 60 !important;
    color: inherit !important;
    font-size: 13.5px !important;
    font-weight: 700 !important;
    letter-spacing: -0.2px !important;
    flex-shrink: 0 !important;
  }
  .unified-dynamic-island {
    position: absolute !important;
    left: 50% !important;
    top: 10px !important;
    transform: translateX(-50%) !important;
    width: 112px !important;
    height: 28px !important;
    background: #000000 !important;
    border-radius: 18px !important;
    display: flex !important;
    align-items: center !important;
    justify-content: flex-end !important;
    padding-right: 11px !important;
    box-shadow: 0 0 1px 1px rgba(255, 255, 255, 0.08) inset !important;
    z-index: 100 !important;
    pointer-events: none !important;
  }
  .unified-camera-lens {
    width: 10px !important;
    height: 10px !important;
    border-radius: 50% !important;
    background: radial-gradient(circle at 35% 35%, #18273A 0%, #080D14 80%) !important;
    box-shadow: 0 0 1px 1px rgba(255, 255, 255, 0.15) !important;
  }
  .unified-status-icons {
    display: flex !important;
    align-items: center !important;
    gap: 6px !important;
  }
  .unified-home-indicator {
    position: absolute !important;
    bottom: 8px !important;
    left: 50% !important;
    transform: translateX(-50%) !important;
    width: 134px !important;
    height: 5px !important;
    background: #000000 !important;
    opacity: 0.28 !important;
    border-radius: 100px !important;
    z-index: 90 !important;
    pointer-events: none !important;
  }
</style>
`;

const STATUS_BAR_HTML = `
  <div class="unified-status-bar">
    <span>9:41</span>
    <div class="unified-dynamic-island"><div class="unified-camera-lens"></div></div>
    <div class="unified-status-icons">
      <svg width="15" height="11" viewBox="0 0 17 12" fill="currentColor">
        <rect x="0" y="8" width="2.5" height="4" rx="0.8"/>
        <rect x="4.5" y="5.5" width="2.5" height="6.5" rx="0.8"/>
        <rect x="9" y="3" width="2.5" height="9" rx="0.8"/>
        <rect x="13.5" y="0" width="2.5" height="12" rx="0.8"/>
      </svg>
      <span style="font-size: 11px; font-weight: 800; letter-spacing: -0.3px;">5G</span>
      <svg width="22" height="11" viewBox="0 0 24 12" fill="none" stroke="currentColor" stroke-width="1.8">
        <rect x="0.9" y="0.9" width="19.2" height="10.2" rx="3.5"/>
        <rect x="2.5" y="2.5" width="13" height="7" rx="1.8" fill="currentColor"/>
        <path d="M22 4.5v3" stroke-linecap="round"/>
      </svg>
    </div>
  </div>
`;

function renderFile(fileName, shouldImportToPhotos = false) {
  const baseName = fileName.replace('.html', '');
  const srcPath = path.join(UI_DIR, fileName);
  const outPng = path.join(PNG_DIR, `${baseName}.png`);

  if (!fs.existsSync(srcPath)) {
    console.error(`❌ 文件不存在: ${srcPath}`);
    return false;
  }

  let targetUrl;
  if (baseName === 'review_distribution_preview') {
    targetUrl = `file://${srcPath}?transparent=1`;
  } else {
    let content = fs.readFileSync(srcPath, 'utf8');
    content = content.replace('</head>', UNIFIED_CSS + '</head>');

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

    const tmpPath = path.join('/tmp', `unified_render_${baseName}.html`);
    fs.writeFileSync(tmpPath, content);
    targetUrl = `file://${tmpPath}`;
  }

  try {
    execSync(`"${CHROME}" \
      --headless \
      --disable-gpu \
      --hide-scrollbars \
      --default-background-color=00000000 \
      --force-device-scale-factor=2 \
      --window-size=460,940 \
      --screenshot="${outPng}" \
      "${targetUrl}" 2>/dev/null`);

    const stats = fs.statSync(outPng);
    console.log(`✅ [完成] ${baseName}.png (${Math.round(stats.size / 1024)} KB) -> design/ui/png/${baseName}.png`);

    if (shouldImportToPhotos) {
      try {
        execSync(`osascript -e 'tell application "Photos" to import POSIX file "${outPng}"'`);
        console.log(`   📸 已自动同步导入至 Mac 系统相册`);
      } catch (photoErr) {
        console.warn(`   ⚠️ 导入相册略过: ${photoErr.message}`);
      }
    }
    return true;
  } catch (err) {
    console.error(`❌ 渲染失败: ${fileName}`, err.message);
    return false;
  }
}

// CLI 处理
const args = process.argv.slice(2);
const shouldImport = args.includes('--import-photos') || args.includes('-p');
const isAll = args.includes('--all') || args.length === 0;

if (isAll) {
  const files = fs.readdirSync(UI_DIR).filter(f => f.endsWith('.html'));
  console.log(`🚀 开始批量使用统一模具生成全部 ${files.length} 个原型真机图...`);
  let successCount = 0;
  files.forEach(f => {
    if (renderFile(f, shouldImport)) successCount++;
  });
  console.log(`\n🎉 全部处理完成！成功生成: ${successCount}/${files.length} 张统一真机图。`);
  console.log(`📂 输出目录: ${PNG_DIR}`);
} else {
  const targetFiles = args.filter(a => !a.startsWith('-'));
  targetFiles.forEach(f => {
    const fileName = f.endsWith('.html') ? f : `${f}.html`;
    renderFile(fileName, shouldImport);
  });
}
