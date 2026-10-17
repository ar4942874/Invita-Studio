// End-to-end checks for the photo-card workflow against the REAL build.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const assert = require('node:assert/strict');
const origin = process.env.STUDIO_URL || 'http://127.0.0.1:8080';
const output = path.resolve(__dirname, '../../artifacts/browser');
fs.mkdirSync(output, { recursive: true });
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const typeBuf = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(zlib.crc32(Buffer.concat([typeBuf, data])) >>> 0);
  return Buffer.concat([len, typeBuf, data, crc]);
}
function makePng(w, h) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = Buffer.alloc(h * (1 + w * 4));
  for (let y = 0; y < h; y++) {
    const off = y * (1 + w * 4);
    raw[off] = 0;
    for (let x = 0; x < w; x++) {
      const p = off + 1 + x * 4;
      raw[p] = 200; raw[p + 1] = 60; raw[p + 2] = 60; raw[p + 3] = 255;
    }
  }
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
const sample = path.join(output, 'sample.png');
fs.writeFileSync(sample, makePng(32, 32));
const errors = [];
const external = [];
const report = { origin, checks: [], pageErrors: errors, blockedExternalRequests: external };
let checks = 0;
const pass = (c) => { checks++; report.checks.push(c); console.log('PASS', c); };
async function boot(page) {
  page.setDefaultTimeout(15000);
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto(origin);
  await page.locator('#loading').waitFor({ state: 'detached', timeout: 45000 });
  const gate = page.locator('flt-semantics-placeholder');
  if (await gate.count()) await gate.dispatchEvent('click');
  await page.getByRole('button', { name: /^(Export invitation|Export)$/ }).waitFor();
}
async function frame(page) { await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))); }
async function button(page, name) {
  await page.getByRole('button', { name, exact: typeof name === 'string' }).last().click({ force: true });
  await frame(page);
}
async function text(page, value) {
  await page.getByText(value, { exact: true }).or(page.getByRole('menuitem', { name: value, exact: true })).last().click({ force: true });
  await frame(page);
}
function project(page) {
  return page.evaluate(() => {
    const item = Object.entries(localStorage).find(([k]) => k.endsWith('invita.studio.projects.v1'));
    if (!item) return null;
    let data = JSON.parse(item[1]);
    if (typeof data === 'string') data = JSON.parse(data);
    return data[0].document;
  });
}
async function storedPhoto(page) {
  await page.waitForFunction(() => {
    try {
      const item = Object.entries(localStorage).find(([k]) => k.endsWith('invita.studio.projects.v1'));
      if (!item) return false;
      let data = JSON.parse(item[1]); if (typeof data === 'string') data = JSON.parse(data);
      const node = data[0].document.nodes.find((n) => n.type === 'image');
      return !!node && String(node.assetId).startsWith('data:image/');
    } catch { return false; }
  }, null, { timeout: 15000 });
}
async function routeLocal(context) {
  await context.route('**/*', (route) => {
    const url = route.request().url();
    if (new URL(url).origin === origin || url.startsWith('blob:') || url.startsWith('data:')) route.continue();
    else { external.push(url); route.abort(); }
  });
}
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true });
    await routeLocal(context);
    const page = await context.newPage();
    await boot(page);
    await text(page, 'Layers');
    const chooser = page.waitForEvent('filechooser');
    await button(page, 'Photo');
    await (await chooser).setFiles(sample);
    await storedPhoto(page);
    const node = (await project(page)).nodes.find((n) => n.type === 'image');
    assert.ok(node, 'image node persisted');
    assert.ok(node.assetId.startsWith('data:image/jpeg;base64,'), 'stored as jpeg data url');
    assert.ok(node.zIndex > 0, 'photo is above the background');
    assert.ok(node.frame.width > 0 && node.frame.height > 0, 'photo has a frame');
    pass('Browser imports a local photo as an editable image layer');

    await page.getByText('Your photo').last().waitFor({ timeout: 15000 });
    pass('Photo inspector appears for the selected layer');

    await page.getByText('Contain').last().click({ force: true });
    await page.waitForFunction(() => {
      try {
        const item = Object.entries(localStorage).find(([k]) => k.endsWith('invita.studio.projects.v1'));
        let data = JSON.parse(item[1]); if (typeof data === 'string') data = JSON.parse(data);
        return data[0].document.nodes.find((n) => n.type === 'image')?.fit === 'contain';
      } catch { return false; }
    }, null, { timeout: 10000 });
    pass('Photo fill mode updates and persists');

    await text(page, 'Details');
    await button(page, 'Export invitation');
    await button(page, 'Create PNG');
    await page.getByRole('button', { name: 'Download PNG', exact: true }).waitFor({ timeout: 30000 });
    const pending = page.waitForEvent('download');
    await button(page, 'Download PNG');
    const saved = path.join(output, 'photo-export.png');
    await (await pending).saveAs(saved);
    assert.ok(fs.statSync(saved).size > 5000, 'png has content');
    pass('Export renders the photo into the PNG');
    await button(page, 'Close export');

    await button(page, 'Project options');
    await text(page, 'Export editable project');
    const dl = page.waitForEvent('download');
    await button(page, 'Download project');
    const jsonFile = path.join(output, 'photo.invita.json');
    await (await dl).saveAs(jsonFile);
    const envelope = JSON.parse(fs.readFileSync(jsonFile, 'utf8'));
    assert.ok(envelope.document.nodes.some((n) => n.type === 'image' && String(n.assetId).startsWith('data:image/')));
    pass('Exported project JSON embeds the photo layer');

    await page.reload();
    await page.locator('#loading').waitFor({ state: 'detached', timeout: 45000 });
    const gate = page.locator('flt-semantics-placeholder');
    if (await gate.count()) await gate.dispatchEvent('click');
    await page.getByRole('button', { name: /^(Export invitation|Export)$/ }).waitFor();
    await storedPhoto(page);
    pass('Reload restores the saved photo');

    assert.equal(errors.length, 0, `browser errors: ${errors.join(' | ')}`);
    assert.equal(external.length, 0, `external requests: ${external.join(' | ')}`);
    pass('No uncaught browser errors or external network dependencies');
    fs.writeFileSync(path.join(output, 'photo-report.json'), JSON.stringify(report, null, 2));
    console.log(`\n${checks} checks passed`);
  } finally {
    await browser.close();
  }
})().catch((e) => { console.error('FAIL', e.message); process.exit(1); });
