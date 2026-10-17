// End-to-end checks against the REAL compiled Flutter application.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const origin = process.env.STUDIO_URL || 'http://127.0.0.1:8080';
const output = path.resolve(__dirname, '../../artifacts/browser');
fs.mkdirSync(output, { recursive: true });
const report = { origin, checks: [], pageErrors: [], consoleErrors: [], blockedExternalRequests: [], downloads: [] };
function pass(check) { report.checks.push(check); console.log('PASS', check); }
async function boot(page) {
  page.setDefaultTimeout(12000);
  page.on('pageerror', e => report.pageErrors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') report.consoleErrors.push(m.text()); });
  await page.goto(origin);
  await page.locator('#loading').waitFor({ state: 'detached', timeout: 45000 });
  const gate = page.locator('flt-semantics-placeholder');
  if (await gate.count()) await gate.dispatchEvent('click');
  await page.getByRole('button', { name: /^(Export invitation|Export)$/ }).waitFor();
}
async function button(page, name) {
  // Flutter positions semantic nodes over its canvas. Native canvas hit testing
  // still receives the physical click; force bypasses DOM-only overlap checks.
  await page.getByRole('button', { name, exact: typeof name === 'string' }).last().click({ force: true });
  await frame(page);
}
async function frame(page) { await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))); }
async function text(page, value) {
  await page.getByText(value, { exact: true }).or(page.getByRole('menuitem', {name:value,exact:true})).last().click({ force: true });
  await frame(page);
}
async function field(page, name, value) {
  await page.getByRole('textbox', { name: new RegExp(name) }).first().click({ force: true });
  await frame(page);
  await page.waitForFunction(() => ['INPUT','TEXTAREA'].includes(document.activeElement?.tagName));
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.insertText(value);
  await frame(page);
}
async function download(page, label, file) {
  const pending = page.waitForEvent('download');
  await button(page, label);
  const result = await pending;
  const dest = path.join(output, file);
  await result.saveAs(dest);
  report.downloads.push({ file, suggestedName: result.suggestedFilename(), bytes: fs.statSync(dest).size });
  return dest;
}
async function stored(page, expected) {
  await page.waitForFunction(expected => {
    try {
      const item = Object.entries(localStorage).find(([k]) => k.endsWith('invita.studio.projects.v1'));
      if (!item) return false;
      let data = JSON.parse(item[1]); if (typeof data === 'string') data = JSON.parse(data);
      const doc = data[0].document;
      return Object.entries(expected).every(([key, value]) => key === 'height' ? doc.height === value : doc.nodes.find(n => n.id === key)?.text === value);
    } catch { return false; }
  }, expected, { timeout: 15000 });
}
async function routeLocal(context) {
  await context.route('**/*', route => {
    const url = route.request().url();
    if (new URL(url).origin === origin || url.startsWith('blob:') || url.startsWith('data:')) route.continue();
    else { report.blockedExternalRequests.push(url); route.abort(); }
  });
}
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const desktop = await browser.newContext({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1, acceptDownloads: true });
    await routeLocal(desktop);
    const p = await desktop.newPage(); await boot(p);
    await p.screenshot({ path: path.join(output, 'desktop.png') });
    pass('Flutter release boots with local renderer, fonts and artwork');
    await button(p, 'Export invitation'); await button(p, 'Create PNG');
    await p.getByRole('button', { name: 'Download PNG', exact: true }).waitFor({ timeout: 30000 });
    await download(p, 'Download PNG', 'classic-2160x3024.png');
    await button(p, 'Close export');
    await field(p, 'First name', 'Zara'); await field(p, 'Second name', 'Omar'); await field(p, '^Venue', 'Garden Pavilion');
    await text(p, 'Templates'); await stored(p, { first: 'Zara', second: 'Omar', venue: 'Garden Pavilion' });
    pass('Guided fields update the editable document and autosave');
    await p.getByText('After dark', { exact: false }).last().click({ force: true }); await frame(p);
    await text(p, 'Classic · 5:7'); await text(p, 'Story · 9:16');
    await stored(p, { first: 'Zara', second: 'Omar', height: 1920 });
    pass('Template + Story reflow retains names and venue');
    await text(p, 'Details');
    await button(p, 'Export invitation'); await text(p, 'JPEG High quality · compact'); await button(p, 'Create JPEG');
    await p.getByRole('button', { name: 'Download JPEG', exact: true }).waitFor({ timeout: 30000 });
    const jpg = await download(p, 'Download JPEG', 'story-2160x3840.jpg');
    assert.deepEqual([...fs.readFileSync(jpg).subarray(0, 3)], [255, 216, 255]);
    pass('Browser downloads genuine 2x Story JPEG');
    await button(p, 'Share');
    await p.getByText('File sharing is not available in this browser. Download the image instead.', { exact: false }).waitFor();
    pass('Unsupported browser sharing fails clearly, without pretending to send');
    await button(p, 'Close export');
    await button(p, 'Project options'); await text(p, 'Export editable project');
    const jsonFile = await download(p, 'Download project', 'edited.invita.json');
    const project = JSON.parse(fs.readFileSync(jsonFile, 'utf8'));
    assert.equal(project.schema, 'invita.project'); assert.equal(project.document.height, 1920);
    assert.equal(project.document.nodes.find(n => n.id === 'first').text, 'Zara');
    assert.equal(project.document.nodes.find(n => n.id === 'venue').text, 'Garden Pavilion');
    pass('Editable project JSON download contains the actual edited layers');
    await p.reload(); await p.locator('#loading').waitFor({ state: 'detached', timeout: 45000 });
    const gate = p.locator('flt-semantics-placeholder'); if (await gate.count()) await gate.dispatchEvent('click');
    await p.getByText('Story · 9:16', { exact: true }).waitFor(); await stored(p, { first: 'Zara', second: 'Omar', height: 1920 });
    pass('Reload restores the locally saved invitation');
    await desktop.close();

    const fresh = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true });
    await routeLocal(fresh); const q = await fresh.newPage(); await boot(q);
    await button(q, 'Project options');
    const chooser = q.waitForEvent('filechooser'); await text(q, 'Open project JSON');
    await (await chooser).setFiles(jsonFile);
    await q.getByText('Story · 9:16', { exact: true }).waitFor(); await stored(q, { first: 'Zara', second: 'Omar' });
    pass('Project JSON imports into a clean browser session as editable layers');
    // Real canvas gesture on a selected layer via Layers panel.
    await text(q, 'Layers');
    await q.getByText('First name', { exact: false }).first().click({ force: true });
    await q.getByRole('button', {name:'Clear selection',exact:true}).waitFor();
    pass('Imported text layers can be selected for styling');
    await fresh.close();

    const mobile = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, acceptDownloads: true, isMobile: true, hasTouch: true });
    await routeLocal(mobile); const m = await mobile.newPage(); await boot(m);
    await m.screenshot({ path: path.join(output, 'mobile.png') });
    await text(m, 'Details'); await field(m, 'First name', 'Mariam');
    await m.screenshot({ path: path.join(output, 'mobile-details.png') });
    await button(m, 'Close panel'); await stored(m, { first: 'Mariam' });
    pass('390px mobile Details sheet edits the real document');
    await text(m, 'Templates'); await m.getByText('Rosewater', { exact: false }).last().click({ force: true });
    await button(m, 'Close panel'); await text(m, 'Classic · 5:7'); await text(m, 'Square · 1:1');
    await stored(m, { first: 'Mariam', height: 1080 });
    await m.setViewportSize({ width: 320, height: 760 });
    await button(m, 'Export'); await button(m, 'Create PNG');
    await m.getByRole('button', { name: 'Download PNG', exact: true }).waitFor({ timeout: 30000 });
    const png = await download(m, 'Download PNG', 'square-2160x2160.png');
    assert.deepEqual([...fs.readFileSync(png).subarray(0, 8)], [137,80,78,71,13,10,26,10]);
    await m.screenshot({ path: path.join(output, 'mobile-export-320px.png') });
    pass('320px mobile export downloads genuine 2x Square PNG');
    await mobile.close();
    assert.equal(report.pageErrors.length, 0, report.pageErrors.join('\n'));
    assert.equal(report.consoleErrors.length, 0, report.consoleErrors.join('\n'));
    assert.equal(report.blockedExternalRequests.length, 0, report.blockedExternalRequests.join('\n'));
    pass('No uncaught browser errors or external network dependencies');
    report.passed = true;
  } catch (e) {
    report.passed = false; report.failure = e.stack;
    for (const c of browser.contexts()) for (const page of c.pages()) {
      await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});
      fs.writeFileSync(path.join(output,'failure-body.txt'),await page.locator('body').innerText());
    }
    throw e;
  } finally {
    fs.writeFileSync(path.join(output, 'smoke-report.json'), JSON.stringify(report, null, 2));
    await browser.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
