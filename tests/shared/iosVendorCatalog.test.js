'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {
  ICON_ASSET_PREFIX,
  ICON_CATALOG_DIRS,
  OUTPUT_PATH,
  ROOT,
  buildIconPlan,
  listIconCatalogFiles,
  renderIosVendorCatalog,
  renderIosVendorIconCatalogs,
  sanitizeSvg
} = require('../../scripts/sync-ios-vendors');
const { VENDOR_PRESENTATION } = require('../../src/shared/vendorPresentation');
const { LIMIT_PROVIDER_IDS } = require('../../src/shared/limits/providers');

// The iOS/watchOS Kit reads its vendor labels, colours, model→vendor rules and
// icon asset names from a generated Swift file, and the app, widget and watch
// targets ship the artwork as generated asset catalogs. Like the Worker's
// vendored copies, they are only correct while they match what they were
// rendered from.
test('the committed iOS vendor catalog matches the shared tables', () => {
  const committed = fs.readFileSync(OUTPUT_PATH, 'utf8');
  assert.equal(committed, renderIosVendorCatalog(), 'stale — run `npm run sync:ios-vendors`');
});

test('the committed VendorIcons.xcassets catalogs match the rendering, with no extra files', () => {
  const rendered = renderIosVendorIconCatalogs();
  assert.deepEqual(listIconCatalogFiles(), Object.keys(rendered).sort(), 'run `npm run sync:ios-vendors`');
  for (const [rel, contents] of Object.entries(rendered)) {
    assert.equal(fs.readFileSync(path.join(ROOT, rel), 'utf8'), contents, `${rel} is stale — run \`npm run sync:ios-vendors\``);
  }
});

test('rendering is deterministic', () => {
  assert.equal(renderIosVendorCatalog(), renderIosVendorCatalog());
  assert.deepEqual(renderIosVendorIconCatalogs(), renderIosVendorIconCatalogs());
});

test('every mark and limits provider reaches the Swift catalog', () => {
  const rendered = renderIosVendorCatalog();
  for (const { id } of VENDOR_PRESENTATION) {
    assert.match(rendered, new RegExp(`Mark\\(id: "${id}",`), id);
  }
  for (const id of LIMIT_PROVIDER_IDS) {
    assert.match(rendered, new RegExp(`LimitProviderInfo\\(id: "${id}",`), id);
  }
});

test('every mark maps to a shipped asset, and nothing falls back to a dot', () => {
  const plan = buildIconPlan();
  // A rejected file still works (its marks draw a dot on iOS), but it should be
  // a decision: fix the artwork, or list it here.
  assert.deepEqual(plan.rejected, []);
  const shipped = new Set(plan.assets.map((asset) => `${ICON_ASSET_PREFIX}${asset.stem}`));
  const markAssets = Object.fromEntries(plan.markAssets);
  for (const { id } of VENDOR_PRESENTATION) {
    assert.ok(shipped.has(markAssets[id]), `${id} → ${markAssets[id]}`);
  }
  assert.equal(markAssets.hermes, 'vendor-hermes-agent', 'icon wins over id');
  assert.equal(markAssets.grok, 'vendor-xai', 'mask wins over icon');
  assert.equal(markAssets.xai, 'vendor-grok');
  assert.deepEqual(plan.limitOverrides, [['grok', 'vendor-grok']], 'the Limits page draws grok.svg (styles.css)');
  assert.deepEqual(plan.osAssets, [['apple', 'vendor-os-apple'], ['linux', 'vendor-os-linux'], ['windows', 'vendor-os-windows']]);
  assert.equal(plan.projectAsset, 'vendor-project');
  for (const [, name] of [...plan.limitOverrides, ...plan.osAssets, ['project', plan.projectAsset]]) {
    assert.ok(shipped.has(name), name);
  }
  assert.ok(!shipped.has('vendor-token-monitor'), 'the Σ mark is SF Symbol `sum`, not an asset');
  assert.ok(![...shipped].some((name) => name.startsWith('vendor-tray-')), 'tray artwork is not a row mark');
});

test('the three catalogs are identical and every emitted SVG is renderer-safe', () => {
  const rendered = renderIosVendorIconCatalogs();
  const byTarget = ICON_CATALOG_DIRS.map((dir) => {
    const base = `${path.relative(ROOT, dir).split(path.sep).join('/')}/`;
    return Object.fromEntries(Object.entries(rendered)
      .filter(([rel]) => rel.startsWith(base))
      .map(([rel, contents]) => [rel.slice(base.length), contents]));
  });
  assert.equal(byTarget.length, 3);
  assert.deepEqual(byTarget[1], byTarget[0]);
  assert.deepEqual(byTarget[2], byTarget[0]);

  for (const [rel, contents] of Object.entries(byTarget[0])) {
    if (rel.endsWith('/Contents.json')) {
      const json = JSON.parse(contents);
      assert.deepEqual(json.properties, { 'preserves-vector-representation': true, 'template-rendering-intent': 'template' }, rel);
      assert.ok(byTarget[0][rel.replace('Contents.json', json.images[0].filename)], `${rel} names a missing file`);
      continue;
    }
    if (!rel.endsWith('.svg')) continue;
    for (const pattern of [/currentColor/i, /1em/, /<filter/, /<mask/, /<text/, /<image/, /\sstyle=/]) {
      assert.doesNotMatch(contents, pattern, rel);
    }
    assert.match(contents, /^<svg xmlns="http:\/\/www\.w3\.org\/2000\/svg"( xmlns:xlink="[^"]+")? width="[\d.]+" height="[\d.]+" viewBox="/, rel);
  }
});

test('sanitizing keeps the silhouette and removes what Xcode cannot draw', () => {
  const { svg, notes } = sanitizeSvg([
    '<?xml version="1.0"?><!-- comment -->',
    '<svg height="1em" width="1em" style="flex:none;line-height:1;fill-rule:evenodd" viewBox="0 0 48 24" fill="currentColor" role="img" aria-labelledby="t" xmlns="http://www.w3.org/2000/svg">',
    '  <title id="t">T</title><desc>D</desc>',
    '  <rect width="48" height="24" style="fill:none;"/>',
    '  <path d="M0 0h1v1z" filter="url(#f)" fill="url(#g)"/>',
    '  <path d="M2 0h1v1z" stroke="url(#h)"/>',
    '  <defs><filter id="f"><feGaussianBlur stdDeviation="1"/></filter>',
    '    <linearGradient id="g"><stop stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient>',
    '    <linearGradient id="h"><stop stop-color="#f00" stop-opacity=".5"/></linearGradient>',
    '    <linearGradient id="unused"><stop stop-color="#f00"/></linearGradient></defs>',
    '</svg>'
  ].join('\n'));
  assert.equal(svg, '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="12" viewBox="0 0 48 24" fill="#000000" fill-rule="evenodd">'
    + '<rect width="48" height="24" fill="none"/><path d="M0 0 h1 v1 z" fill="#000000"/><path d="M2 0 h1 v1 z" stroke="url(#h)"/>'
    + '<defs><linearGradient id="h"><stop stop-color="#f00" stop-opacity=".5"/></linearGradient></defs></svg>\n');
  assert.deepEqual(notes, ['dropped 1 filter effect(s)', '1 opaque gradient paint(s) made solid']);
});

test('artwork painted through a <mask> becomes the mask silhouette', () => {
  const { svg, notes } = sanitizeSvg(
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><mask id="m"><path d="M1 1h9v9z" fill="#fff"></path></mask>'
    + '<g mask="url(#m)"><g filter="url(#b)"><path d="M0 0h24v24H0z" fill="#FFE432"></path></g></g>'
    + '<defs><filter id="b"><feGaussianBlur stdDeviation="2"></feGaussianBlur></filter></defs></svg>'
  );
  assert.equal(svg, '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="M1 1 h9 v9 z" fill="#000000"/></svg>\n');
  assert.deepEqual(notes, ['dropped 1 filter effect(s)', 'masked artwork replaced by the mask silhouette']);
});

test('path data is spelled out, so shorthand arc flags read the same in every renderer', () => {
  const { svg } = sanitizeSvg('<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M21.846 0a1.923 1.923 0 110 3.846H20.15a.226.226 0 01-.227-.226V1.9-.5e-1zm1 2 3 4"/></svg>');
  assert.match(svg, / d="M21\.846 0 a1\.923 1\.923 0 1 1 0 3\.846 H20\.15 a\.226 \.226 0 0 1 -\.227 -\.226 V1\.9 -\.5e-1 z m1 2 3 4"/);
  assert.match(sanitizeSvg('<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M0 0a1 1 0 2 0 1 1"/></svg>').rejected, /arc flag/);
});

test('artwork the sanitizer cannot keep faithful is rejected, not shipped', () => {
  const wrap = (body, attrs = 'viewBox="0 0 24 24"') => `<svg ${attrs} xmlns="http://www.w3.org/2000/svg">${body}</svg>`;
  assert.match(sanitizeSvg(wrap('<text x="2" y="20">Σ</text>')).rejected, /<text>/);
  assert.match(sanitizeSvg(wrap('<image href="a.png" width="24" height="24"/>')).rejected, /<image>/);
  assert.match(sanitizeSvg(wrap('<path d="M0 0" style="mix-blend-mode:multiply"/>')).rejected, /mix-blend-mode/);
  assert.match(sanitizeSvg(wrap('<mask id="m"><path d="M0 0" fill="#808080"/></mask><g mask="url(#m)"/>')).rejected, /opaque white/);
  assert.match(sanitizeSvg(wrap('<path d="M0 0" fill="url(#missing)"/>')).rejected, /missing/);
  assert.match(sanitizeSvg(wrap('<path d="M0 0"/>', 'width="1em" height="1em"')).rejected, /viewBox/);
  assert.throws(() => sanitizeSvg('<svg><path></svg>'), /unbalanced/);
});

test('a new stylesheet mask that is not a vendor mark fails loudly', () => {
  const stylesSource = [
    fs.readFileSync(path.join(ROOT, 'src', 'electron', 'renderer', 'styles.css'), 'utf8'),
    '.row-icon-brand-new { mask-image: url(../../../assets/icons/claude.svg); }'
  ].join('\n');
  assert.throws(() => buildIconPlan({ stylesSource }), /\.row-icon-brand-new/);
});

test('a model resolver the generator cannot read fails loudly instead of dropping rules', () => {
  const chartSource = [
    '  function modelVendorFor(model) {',
    "    if (/claude/.test(name)) return 'claude';",
    "    if (name.includes('gpt')) return 'codex';",
    '    return null;',
    '  }',
    '',
    "  const fallbackModelColors = ['#6ab4f0'];"
  ].join('\n');
  assert.throws(() => renderIosVendorCatalog({ chartSource }), /resolver shape changed/);
});
