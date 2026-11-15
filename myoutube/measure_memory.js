const { chromium } = require('playwright');

async function measureDesktopVsMobile() {
  const executablePath = 'C:\\Users\\Abhishek soni\\AppData\\Local\\ms-playwright\\chromium-1248\\chrome-win64\\chrome.exe';
  const browser = await chromium.launch({
    executablePath,
    headless: false,
    args: ['--no-sandbox', '--disable-gpu']
  });

  const page = await browser.newPage();
  
  console.log('[Measurement] Loading Desktop YouTube (www.youtube.com)...');
  await page.goto('https://www.youtube.com/?app=desktop', { waitUntil: 'networkidle', timeout: 35000 });
  await page.waitForTimeout(5000);
  
  const desktopMetrics = await page.evaluate(() => {
    return {
      usedJSHeapMB: Math.round(window.performance.memory.usedJSHeapSize / (1024 * 1024)),
      totalJSHeapMB: Math.round(window.performance.memory.totalJSHeapSize / (1024 * 1024)),
      domNodes: document.querySelectorAll('*').length
    };
  });
  console.log('Desktop YouTube Metrics:', desktopMetrics);

  console.log('[Measurement] Loading Mobile YouTube (m.youtube.com) with mobile UA...');
  const mobileContext = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36'
  });
  const mobilePage = await mobileContext.newPage();
  await mobilePage.goto('https://m.youtube.com/', { waitUntil: 'networkidle', timeout: 35000 });
  await mobilePage.waitForTimeout(5000);

  const mobileMetrics = await mobilePage.evaluate(() => {
    return {
      usedJSHeapMB: Math.round(window.performance.memory.usedJSHeapSize / (1024 * 1024)),
      totalJSHeapMB: Math.round(window.performance.memory.totalJSHeapSize / (1024 * 1024)),
      domNodes: document.querySelectorAll('*').length
    };
  });
  console.log('Mobile YouTube Metrics:', mobileMetrics);

  await browser.close();
}

measureDesktopVsMobile().catch(console.error);
