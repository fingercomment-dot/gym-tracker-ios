// Run with PLAYWRIGHT_MODULE pointing to @playwright/test when it is not installed here.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '@playwright/test');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../ios/WebApp');
const server = http.createServer((req, res) => {
  const file = path.resolve(root, '.' + (req.url === '/' ? '/index.html' : req.url));
  if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404).end(); return; }
    res.setHeader('Content-Type', file.endsWith('.html') ? 'text/html; charset=utf-8' : 'image/webp');
    res.end(data);
  });
});
(async () => {
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 393, height: 852 }, locale: 'ru-RU' });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    await page.getByRole('button', { name: 'Начать тренировку', exact: true }).waitFor();
    assert.equal(await page.locator('input[type=password]').count(), 0);
    await page.getByRole('button', { name: 'Настройки', exact: true }).click();
    await page.getByText('Скопировать все данные', { exact: true }).waitFor();
    await page.getByRole('button', { name: 'Сегодня', exact: true }).click();
    await page.getByRole('button', { name: 'Начать тренировку', exact: true }).click();
    await page.getByRole('button', { name: 'Пропустить', exact: true }).click();
    await page.waitForFunction(() => JSON.parse(localStorage.getItem('iron-diary.v1') || '{}').active?.current);
    await page.reload();
    await page.waitForFunction(() => JSON.parse(localStorage.getItem('iron-diary.v1') || '{}').active?.current);
    console.log('PASS: active workout survives reload');
    assert.deepEqual(errors, []);
    // Real iOS bridge: ready without Claude, seed recovery, native storage on mutation.
    const native = await browser.newPage();
    await native.addInitScript(() => {
      window.messages = [];
      window.__gymSavedState = JSON.stringify({ sessions: {}, settings: {}, metrics: { probe: { id: 'probe', date: '2026-11-17', weight: 75 } }, ui: {} });
      window.webkit = { messageHandlers: { gymNative: { postMessage: m => window.messages.push(m) } } };
    });
    await native.goto(`http://127.0.0.1:${server.address().port}`);
    await native.waitForFunction(() => window.messages.some(m => m.type === 'ready'));
    await native.evaluate(() => window.dispatchEvent(new Event('pagehide')));
    const saved = await native.evaluate(() => window.messages.filter(m => m.type === 'saveLocalState').at(-1));
    assert.equal(JSON.parse(saved.json).metrics.probe.weight, 75);
    console.log('PASS: standalone launch, Settings, workout entry, offline native ready, native state recovery/save');
  } finally { await browser.close(); server.close(); }
})().catch(e => { console.error(e); server.close(); process.exitCode = 1; });
