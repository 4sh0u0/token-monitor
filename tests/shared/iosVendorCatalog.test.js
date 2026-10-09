'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { OUTPUT_PATH, renderIosVendorCatalog } = require('../../scripts/sync-ios-vendors');
const { VENDOR_PRESENTATION } = require('../../src/shared/vendorPresentation');
const { LIMIT_PROVIDER_IDS } = require('../../src/shared/limits/providers');

// The iOS/watchOS Kit reads its vendor labels, colours and model→vendor rules
// from a generated Swift file. Like the Worker's vendored copies, it is only
// correct while it matches the shared tables it was rendered from.
test('the committed iOS vendor catalog matches the shared tables', () => {
  const committed = fs.readFileSync(OUTPUT_PATH, 'utf8');
  assert.equal(committed, renderIosVendorCatalog(), 'stale — run `npm run sync:ios-vendors`');
});

test('rendering is deterministic', () => {
  assert.equal(renderIosVendorCatalog(), renderIosVendorCatalog());
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
