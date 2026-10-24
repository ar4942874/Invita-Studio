// End-to-end smoke test against the REAL compiled Flutter application.
//
// Covers the whole first-run path (guided start -> studio -> export), the
// catalogue grid, event settings, the invitation actions and draft duplication,
// on desktop and on a 390px/320px mobile viewport.
//
//   flutter build web --release --no-web-resources-cdn --no-wasm-dry-run -O1
//   python tool/serve.py --port 8080
//   node tool/browser/smoke.cjs
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const origin = process.env.STUDIO_URL || 'http://127.0.0.1:8080';
const output = path.resolve(__dirname, '../../artifacts/browser');
fs.mkdirSync(output, { recursive: true });
const report = {
  origin,
  checks: [],
  pageErrors: [],
  consoleErrors: [],
  blockedExternalRequests: [],
  downloads: [],
};
function pass(check) {
  report.checks.push(check);
  console.log('PASS', check);
}

async function boot(page) {
  page.setDefaultTimeout(15000);
  page.on('pageerror', (e) => report.pageErrors.push(e.message));
  page.on('console', (m) => {
    if (m.type() === 'error') report.consoleErrors.push(m.text());
  });
  await page.goto(origin);
  await page.locator('#loading').waitFor({ state: 'detached', timeout: 60000 });
  const gate = page.locator('flt-semantics-placeholder');
  if (await gate.count()) await gate.dispatchEvent('click');
  // The app opens on the guided start.
  await page.getByText('What are we celebrating?').first().waitFor();
}

/** Waits until any semantic node's label or text contains [needle].
 *
 * Flutter merges sibling text into a parent node's aria-label (e.g. the design
 * count and the "Surprise me" button share one group), so `getByText` alone
 * misses half the UI. This checks both representations.
 */
async function semantic(page, needle, timeout = 15000) {
  await page.waitForFunction(
    (needle) =>
      [...document.querySelectorAll('flt-semantics')].some((n) => {
        const label = n.getAttribute('aria-label') || '';
        return label.includes(needle) || (n.textContent || '').includes(needle);
      }),
    needle,
    { timeout }
  );
}

async function frame(page) {
  await page.evaluate(
    () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
  );
}

async function button(page, name) {
  // Flutter positions semantic nodes over its canvas; native canvas hit testing
  // still receives the physical click, so force bypasses DOM-only overlap checks.
  await page
    .getByRole('button', { name, exact: typeof name === 'string' })
    .last()
    .click({ force: true });
  await frame(page);
}

async function text(page, value) {
  await page
    .getByText(value, { exact: true })
    .or(page.getByRole('menuitem', { name: value, exact: true }))
    .last()
    .click({ force: true });
  await frame(page);
}

async function field(page, name, value) {
  await page
    .getByRole('textbox', { name: new RegExp(name) })
    .first()
    .click({ force: true });
  await frame(page);
  await page.waitForFunction(() =>
    ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)
  );
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
  report.downloads.push({
    file,
    suggestedName: result.suggestedFilename(),
    bytes: fs.statSync(dest).size,
  });
  return dest;
}

/** Reads the autosaved drafts out of the browser's local storage. */
function projects(page) {
  return page.evaluate(() => {
    const item = Object.entries(localStorage).find(([k]) =>
      k.endsWith('invita.studio.projects.v1')
    );
    if (!item) return [];
    let data = JSON.parse(item[1]);
    if (typeof data === 'string') data = JSON.parse(data);
    return data;
  });
}

async function stored(page, expected) {
  await page.waitForFunction(
    (expected) => {
      try {
        const item = Object.entries(localStorage).find(([k]) =>
          k.endsWith('invita.studio.projects.v1')
        );
        if (!item) return false;
        let data = JSON.parse(item[1]);
        if (typeof data === 'string') data = JSON.parse(data);
        const project = data[0];
        const doc = project.document;
        return Object.entries(expected).every(([key, value]) => {
          if (key === 'height') return doc.height === value;
          if (key === 'category') return project.category === value;
          return doc.nodes.find((n) => n.id === key)?.text === value;
        });
      } catch {
        return false;
      }
    },
    expected,
    { timeout: 15000 }
  );
}

async function routeLocal(context) {
  await context.route('**/*', (route) => {
    const url = route.request().url();
    if (
      new URL(url).origin === origin ||
      url.startsWith('blob:') ||
      url.startsWith('data:')
    ) {
      route.continue();
    } else {
      report.blockedExternalRequests.push(url);
      route.abort();
    }
  });
}

/** Closes the guided setup if it opened.
 *
 * A card created by the wizard opens the tour; the rest of this run drives the
 * editor itself, so the spotlight has to go. Returns whether it was showing.
 */
async function dismissTour(page) {
  const close = page.getByRole('button', { name: 'Close the guided setup' });
  if ((await close.count()) === 0) return false;
  await close.first().click({ force: true });
  await frame(page);
  return true;
}

/** Guided start: category -> details -> card -> studio. */
async function enterStudio(
  page,
  {
    category = 'Wedding',
    first = 'Zara',
    second = 'Omar',
    venue = 'Garden Pavilion',
    design = 'Botanical',
  } = {}
) {
  await page.getByText(new RegExp(`^${category}\\b`)).first().click({ force: true });
  await frame(page);
  await page.getByRole('textbox', { name: /First name/ }).first().waitFor();
  await field(page, 'First name', first);
  await field(page, 'Second name', second);
  await field(page, '^Venue', venue);
  await button(page, 'Choose a card');
  await page.getByRole('button', { name: 'Create invitation' }).waitFor();
  await page.getByText(new RegExp(`^${design},`)).first().click({ force: true });
  await frame(page);
  await button(page, 'Create invitation');
  await page.getByRole('button', { name: /^(Export invitation|Export)$/ }).waitFor();
  await dismissTour(page);
}

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    /* ------------------------------------------------ desktop */
    const desktop = await browser.newContext({
      viewport: { width: 1440, height: 1000 },
      deviceScaleFactor: 1,
      acceptDownloads: true,
    });
    await routeLocal(desktop);
    const p = await desktop.newPage();
    await boot(p);
    await p.screenshot({ path: path.join(output, 'desktop-home.png') });
    pass('Guided start boots with local renderer, fonts and artwork');

    await enterStudio(p);
    await p.screenshot({ path: path.join(output, 'desktop-studio.png') });
    await stored(p, { first: 'Zara', second: 'Omar', venue: 'Garden Pavilion' });
    pass('Wizard creates the project and opens the studio with those details');

    await button(p, 'Export invitation');
    await button(p, 'Create PNG');
    await p.getByRole('button', { name: 'Download PNG', exact: true }).waitFor({ timeout: 30000 });
    const png = await download(p, 'Download PNG', 'classic-2160x3024.png');
    assert.deepEqual([...fs.readFileSync(png).subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
    await button(p, 'Close export');
    pass('Classic 2x PNG downloads with a real PNG signature');

    // Catalogue: tabs, count, favourites.
    await text(p, 'Templates');
    await text(p, 'All designs');
    await semantic(p, '60 designs');
    await text(p, 'For you');
    await semantic(p, '10 designs');
    pass('Catalogue tabs switch between the celebration and all sixty designs');

    // The first tile is fully on screen; a clipped node at the bottom edge
    // would send the click into the tile body instead of the star.
    await p
      .getByRole('button', { name: 'Save to favourites', exact: true })
      .first()
      .click({ force: true });
    await frame(p);
    await semantic(p, 'Remove from favourites');
    await text(p, 'Favourites');
    await semantic(p, '1 design');
    await p.screenshot({ path: path.join(output, 'desktop-favourites.png') });
    await text(p, 'For you');
    pass('Starring a design moves it into Favourites');

    const designBefore = (await projects(p))[0].document.nodes.find(
      (n) => n.id === 'background'
    ).assetId;
    await button(p, 'Surprise me');
    await semantic(p, '10 designs');
    // Autosave is debounced by 650 ms, so wait for the stored background to
    // change rather than reading it immediately.
    await p.waitForFunction(
      (before) => {
        const item = Object.entries(localStorage).find(([k]) =>
          k.endsWith('invita.studio.projects.v1')
        );
        if (!item) return false;
        let data = JSON.parse(item[1]);
        if (typeof data === 'string') data = JSON.parse(data);
        const asset = data[0].document.nodes.find((n) => n.id === 'background')?.assetId;
        return !!asset && asset !== before;
      },
      designBefore,
      { timeout: 15000 }
    );
    pass('"Surprise me" applies a different design and autosaves it');

    // Format switch keeps the wording and persists.
    await text(p, 'Classic · 5:7');
    await text(p, 'Story · 9:16');
    await stored(p, { first: 'Zara', height: 1920 });
    pass('Story reflow keeps the names and autosaves');

    // Event settings: change the celebration after creation.
    await button(p, 'Project options');
    await text(p, 'Event settings');
    await semantic(p, 'CELEBRATION');
    await p.screenshot({ path: path.join(output, 'desktop-event-settings.png') });
    await text(p, 'Birthday');
    await button(p, 'Save changes');
    await stored(p, { category: 'birthday' });
    pass('Event settings changes the celebration and autosaves the category');

    // Invitation actions: pick a date, then the calendar/code actions appear.
    await button(p, 'Project options');
    await text(p, 'Invitation actions');
    await semantic(p, 'RSVP CODE');
    await button(p, 'Pick a date');
    await button(p, 'OK');
    await p.getByRole('button', { name: 'Save .ics', exact: true }).waitFor({ timeout: 15000 });
    await semantic(p, 'Google Calendar');
    await p.screenshot({ path: path.join(output, 'desktop-invite-actions.png') });
    // The sheet is a modal bottom sheet: Escape closes it like the barrier tap.
    await p.keyboard.press('Escape');
    await frame(p);
    pass('Date picker unlocks the .ics / Google Calendar actions and the RSVP code');

    // Duplicate draft.
    const before = (await projects(p)).length;
    await button(p, 'Project options');
    await text(p, 'Duplicate draft');
    await semantic(p, 'Duplicated');
    await p.waitForFunction(
      (count) => {
        const item = Object.entries(localStorage).find(([k]) =>
          k.endsWith('invita.studio.projects.v1')
        );
        if (!item) return false;
        let data = JSON.parse(item[1]);
        if (typeof data === 'string') data = JSON.parse(data);
        return data.length === count + 1;
      },
      before,
      { timeout: 15000 }
    );
    pass('Duplicate draft adds a second draft and reports it');

    // Editable project export.
    await button(p, 'Project options');
    await text(p, 'Export editable project');
    const jsonFile = await download(p, 'Download project', 'edited.invita.json');
    const project = JSON.parse(fs.readFileSync(jsonFile, 'utf8'));
    assert.equal(project.schema, 'invita.project');
    assert.equal(project.document.height, 1920);
    assert.equal(project.category, 'birthday');
    assert.equal(project.document.nodes.find((n) => n.id === 'first').text, 'Zara');
    pass('Project JSON export carries the edited layers, category and format');

    // Reload restores.
    await p.reload();
    await p.locator('#loading').waitFor({ state: 'detached', timeout: 60000 });
    const gate = p.locator('flt-semantics-placeholder');
    if (await gate.count()) await gate.dispatchEvent('click');
    await p.getByText('What are we celebrating?').first().waitFor();
    await semantic(p, 'Birthday · edited');
    pass('Reload restores the draft, its celebration and the relative edit time');
    await desktop.close();

    /* ------------------------------------------------ import into a clean session */
    const fresh = await browser.newContext({
      viewport: { width: 1440, height: 1000 },
      acceptDownloads: true,
    });
    await routeLocal(fresh);
    const q = await fresh.newPage();
    await boot(q);
    await q.getByText('Continue editing', { exact: true }).first().click({ force: true });
    await q.getByRole('button', { name: /^(Export invitation|Export)$/ }).waitFor();
    await button(q, 'Project options');
    const chooser = q.waitForEvent('filechooser');
    await text(q, 'Open project JSON');
    await (await chooser).setFiles(jsonFile);
    await q.getByText('Story · 9:16', { exact: true }).waitFor();
    await stored(q, { first: 'Zara' });
    pass('Project JSON imports into a clean session as editable layers');
    await fresh.close();

    /* ------------------------------------------------ mobile */
    const mobile = await browser.newContext({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 1,
      acceptDownloads: true,
      isMobile: true,
      hasTouch: true,
    });
    await routeLocal(mobile);
    const m = await mobile.newPage();
    await boot(m);
    await m.screenshot({ path: path.join(output, 'mobile-home.png') });
    await enterStudio(m, { first: 'Mariam', second: 'Yusuf', design: 'Petals' });
    await text(m, 'Details');
    await m.screenshot({ path: path.join(output, 'mobile-details.png') });
    await button(m, 'Close panel');
    await stored(m, { first: 'Mariam' });
    pass('390px mobile wizard + Details sheet edit the real document');

    await m.setViewportSize({ width: 320, height: 760 });
    await text(m, 'Classic · 5:7');
    await text(m, 'Square · 1:1');
    await stored(m, { height: 1080 });
    await button(m, 'Export');
    await button(m, 'Create PNG');
    await m.getByRole('button', { name: 'Download PNG', exact: true }).waitFor({ timeout: 30000 });
    const square = await download(m, 'Download PNG', 'square-2160x2160.png');
    assert.deepEqual([...fs.readFileSync(square).subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
    await m.screenshot({ path: path.join(output, 'mobile-export-320px.png') });
    pass('320px mobile export downloads a genuine 2x Square PNG');
    await mobile.close();

    assert.equal(report.pageErrors.length, 0, report.pageErrors.join('\n'));
    assert.equal(report.consoleErrors.length, 0, report.consoleErrors.join('\n'));
    assert.equal(
      report.blockedExternalRequests.length,
      0,
      report.blockedExternalRequests.join('\n')
    );
    pass('No uncaught browser errors or external network dependencies');
    report.passed = true;
  } catch (e) {
    report.passed = false;
    report.failure = e.stack;
    for (const c of browser.contexts())
      for (const page of c.pages()) {
        await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
        fs.writeFileSync(
          path.join(output, 'failure-body.txt'),
          await page.locator('body').innerText().catch(() => '')
        );
      }
    throw e;
  } finally {
    fs.writeFileSync(
      path.join(output, 'smoke-report.json'),
      JSON.stringify(report, null, 2)
    );
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
