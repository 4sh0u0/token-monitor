#!/usr/bin/env node
'use strict';

// Writes the iOS/watchOS Kit's vendor catalog (labels, brand and widget colours,
// the model→vendor rules, the icon asset names) and the vendor-icon asset
// catalogs from the shared tables, so the Swift side keeps no hand-maintained
// copy that could drift from the desktop:
//
//   src/shared/vendorPresentation.js   colours, the widget's dark-surface variants
//                                      and each mark's artwork file
//   src/shared/clientCatalog.js        tracked-client labels and ids
//   src/shared/limits/providers.js     AI Tool Limits provider labels and order
//   src/electron/renderer/usageCharts.js
//                                      modelVendorFor() rules and the fallback model palette
//   src/electron/renderer/styles.css   the masks that are not vendor marks (OS
//                                      marks, the project glyph) and the Limits
//                                      page's per-provider artwork overrides
//   assets/icons/*.svg                 the artwork itself
//
// The model rules are lifted pattern for pattern, the same way the macOS widget
// parity test reads them, because a resolver re-expressed by hand is exactly what
// drifted before. The artwork is copied into `VendorIcons.xcassets` in the app,
// widget and watch targets as template vector images (`vendor-<stem>`), after a
// deterministic sanitizing pass that keeps the alpha silhouette the desktop masks
// rows with while removing what Xcode's SVG renderer cannot draw (see
// sanitizeSvg()). Output is deterministic; tests/shared/iosVendorCatalog.test.js
// renders it in memory and fails when a committed file is stale.
//
//   npm run sync:ios-vendors            rewrite the Swift file and the asset catalogs
//   node scripts/sync-ios-vendors.js --check   exit 1 when any of them is stale

const fs = require('node:fs');
const path = require('node:path');
const { DEFAULT_VENDOR_COLOR, ROW_ICON_MASKS, VENDOR_PRESENTATION } = require('../src/shared/vendorPresentation');
const { CLIENT_IDS, CLIENT_LABELS } = require('../src/shared/clientCatalog');
const { LIMIT_PROVIDER_CATALOG } = require('../src/shared/limits/providers');

const ROOT = path.resolve(__dirname, '..');
const OUTPUT_PATH = path.join(
  ROOT, 'native', 'ios', 'TokenMonitorKit', 'Sources', 'TokenMonitorKit', 'VendorCatalog+Generated.swift'
);
const CHART_SOURCE_PATH = path.join(ROOT, 'src', 'electron', 'renderer', 'usageCharts.js');
const STYLES_PATH = path.join(ROOT, 'src', 'electron', 'renderer', 'styles.css');
const ICONS_DIR = path.join(ROOT, 'assets', 'icons');

// The targets that draw marks. The complications draw none, so they get no catalog.
const ICON_CATALOG_DIRS = ['TokenMonitor', 'TokenMonitorWidget', 'TokenMonitorWatch']
  .map((target) => path.join(ROOT, 'native', 'ios', target, 'VendorIcons.xcassets'));
const ICON_ASSET_PREFIX = 'vendor-';
// Masks styles.css installs that are not vendor marks. token-monitor.svg is a
// <text> Σ, which an asset catalog cannot draw: the app uses SF Symbol `sum`.
const EXTRA_ROW_ICON = /^(os-[a-z0-9]+|project)$/;
const SKIPPED_ROW_ICONS = new Set(['token-monitor']);
// Files the OS ignores in a catalog folder; never written, never stale.
const IGNORED_CATALOG_FILES = new Set(['.DS_Store']);

function normalizeHex(value) {
  const raw = String(value || '').trim().replace(/^#/, '').toLowerCase();
  if (/^[0-9a-f]{3}$/.test(raw)) return `#${raw.split('').map((digit) => digit + digit).join('')}`;
  if (/^[0-9a-f]{6}$/.test(raw)) return `#${raw}`;
  throw new Error(`unsupported colour ${JSON.stringify(value)}`);
}

function swiftString(value) {
  let out = '"';
  for (const char of String(value)) {
    const code = char.codePointAt(0);
    if (char === '\\') out += '\\\\';
    else if (char === '"') out += '\\"';
    else if (code < 0x20 || code === 0x7f) out += `\\u{${code.toString(16)}}`;
    else out += char;
  }
  return `${out}"`;
}

function swiftOptionalString(value) {
  return value === null || value === undefined ? 'nil' : swiftString(value);
}

// A raw string keeps each regex byte-identical to the JavaScript source.
function swiftRawString(value) {
  if (String(value).includes('"#')) throw new Error(`pattern cannot be a raw Swift string: ${value}`);
  return `#"${value}"#`;
}

function swiftDictionaryLines(name, entries) {
  if (entries.length === 0) return [`    static let ${name}: [String: String] = [:]`];
  return [
    `    static let ${name}: [String: String] = [`,
    ...entries.map(([key, value]) => `        ${swiftString(key)}: ${swiftString(value)},`),
    '    ]'
  ];
}

function sliceFunction(source, start, end) {
  const from = source.indexOf(start);
  if (from === -1) throw new Error(`could not find ${JSON.stringify(start)} — resolver shape changed`);
  const to = source.indexOf(end, from);
  if (to === -1) throw new Error(`could not find the end of ${JSON.stringify(start)}`);
  return source.slice(from, to);
}

function modelVendorRules(chartSource) {
  const body = sliceFunction(chartSource, 'function modelVendorFor(model) {', '\n  }\n');
  const rules = [...body.matchAll(/if \(\/(.+?)\/\.test\(name\)\) return '([^']+)';/g)]
    .map(([, pattern, vendor]) => ({ pattern, vendor }));
  const branches = (body.match(/\breturn '[^']+';/g) || []).length;
  // A branch written any other way would silently fall out of the Swift copy.
  if (rules.length === 0 || rules.length !== branches) {
    throw new Error(`parsed ${rules.length} of ${branches} modelVendorFor() rules — resolver shape changed`);
  }
  return rules;
}

function fallbackModelColors(chartSource) {
  const match = chartSource.match(/const fallbackModelColors = \[([^\]]+)\];/);
  if (!match) throw new Error('could not find fallbackModelColors in usageCharts.js');
  const colors = [...match[1].matchAll(/'([^']+)'/g)].map(([, hex]) => normalizeHex(hex));
  if (colors.length === 0) throw new Error('fallbackModelColors is empty');
  return colors;
}

function markLabel(entry) {
  if (entry.label) return entry.label;
  if (CLIENT_LABELS[entry.id]) return CLIENT_LABELS[entry.id];
  const provider = LIMIT_PROVIDER_CATALOG.find((candidate) => candidate.id === entry.id);
  return provider ? provider.label : null;
}

// ---------------------------------------------------------------------------
// Mask rules in styles.css
// ---------------------------------------------------------------------------

function maskUrl(selector, body) {
  const urls = [...body.matchAll(/(?:^|[\s;])(?:-webkit-)?mask-image\s*:\s*url\(\s*(['"]?)([^'")]+)\1\s*\)/g)]
    .map(([, , url]) => url.trim());
  if (urls.length === 0) return null;
  if (new Set(urls).size !== 1) throw new Error(`${selector} names more than one mask image: ${urls.join(', ')}`);
  return urls[0];
}

// The `.row-icon-<name>` masks styles.css declares itself (the vendor marks are
// installed at runtime by rowIconMasks.js from ROW_ICON_MASKS) and the Limits
// page's `.limit-icon.row-icon-<id>` overrides. URLs resolve against styles.css.
function stylesheetMasks(stylesSource) {
  const rowIcons = new Map();
  const limitIcons = new Map();
  const css = stylesSource.replace(/\/\*[\s\S]*?\*\//g, '');
  for (const [, rawSelector, body] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const selector = rawSelector.trim();
    const row = selector.match(/^\.row-icon-([a-z0-9-]+)$/);
    const limit = selector.match(/^\.limit-icon\.row-icon-([a-z0-9-]+)$/);
    if (!row && !limit) continue;
    const url = maskUrl(selector, body);
    if (!url) continue;
    const file = path.resolve(path.dirname(STYLES_PATH), url);
    const [table, name] = row ? [rowIcons, row[1]] : [limitIcons, limit[1]];
    if (table.has(name) && table.get(name) !== file) throw new Error(`${selector} is declared twice with different masks`);
    table.set(name, file);
  }
  return { rowIcons, limitIcons };
}

// ---------------------------------------------------------------------------
// SVG sanitizing
// ---------------------------------------------------------------------------

// What Xcode's SVG renderer draws reliably. Anything else rejects the file, and
// the mark falls back to a dot on iOS, rather than shipping artwork that renders
// differently from the desktop.
const ALLOWED_ELEMENTS = new Set([
  'svg', 'g', 'defs', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon',
  'linearGradient', 'radialGradient', 'stop', 'clipPath'
]);
const DROPPED_ELEMENTS = new Set(['title', 'desc', 'metadata']);
const SHAPE_ELEMENTS = new Set(['path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon']);
// CSS properties a `style` attribute may carry: SVG presentation attributes are
// kept as attributes, layout-only properties of the inline <svg> are dropped.
const PRESENTATION_PROPERTIES = new Set([
  'fill', 'fill-opacity', 'fill-rule', 'stroke', 'stroke-width', 'stroke-linecap', 'stroke-linejoin',
  'stroke-miterlimit', 'stroke-dasharray', 'stroke-dashoffset', 'stroke-opacity', 'opacity',
  'clip-rule', 'clip-path', 'color', 'display', 'visibility', 'stop-color', 'stop-opacity',
  'filter', 'mask'
]);
const IGNORED_STYLE_PROPERTIES = new Set(['flex', 'line-height']);
const WHITE = new Set(['#fff', '#ffffff', 'white']);
const FORBIDDEN_OUTPUT = [/currentColor/i, /1em/, /<filter/, /<mask/, /<text/, /<image/, /\sstyle=/];

class RejectedSvg extends Error {}

const TOKEN = new RegExp([
  '<!--[\\s\\S]*?-->',
  '<\\?[\\s\\S]*?\\?>',
  '<!DOCTYPE(?:[^>[]|\\[[^\\]]*\\])*>',
  '<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>',
  '<\\/([A-Za-z_][\\w:.-]*)\\s*>',
  '<([A-Za-z_][\\w:.-]*)((?:\\s+[A-Za-z_:][\\w:.-]*\\s*=\\s*(?:"[^"]*"|\'[^\']*\'))*)\\s*(\\/?)>',
  '([^<]+)'
].join('|'), 'g');

function parseAttributes(source) {
  return [...source.matchAll(/([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)]
    .map(([, name, double, single]) => [name, (double ?? single).replace(/\s+/g, ' ').trim()]);
}

// A deliberately small XML reader: elements, attributes and text, nothing else.
// Comments, the prolog and a DOCTYPE are dropped.
function parseSvg(source) {
  const root = { name: '#root', attrs: [], children: [] };
  const stack = [root];
  let offset = 0;
  for (const match of source.replace(/^\uFEFF/, '').matchAll(TOKEN)) {
    if (match.index !== offset) throw new Error(`unparseable markup at offset ${offset}`);
    offset = match.index + match[0].length;
    const [, cdata, closing, opening, attributes, selfClosing, text] = match;
    const parent = stack[stack.length - 1];
    if (closing) {
      if (stack.length === 1 || parent.name !== closing) throw new Error(`unbalanced </${closing}>`);
      stack.pop();
    } else if (opening) {
      const element = { name: opening, attrs: parseAttributes(attributes), children: [] };
      parent.children.push(element);
      if (!selfClosing) stack.push(element);
    } else if (cdata !== undefined || text !== undefined) {
      parent.children.push({ text: cdata ?? text });
    }
  }
  if (offset !== source.replace(/^\uFEFF/, '').length) throw new Error('unparseable trailing markup');
  if (stack.length !== 1) throw new Error(`unclosed <${stack[stack.length - 1].name}>`);
  const elements = root.children.filter((node) => node.name);
  if (elements.length !== 1 || elements[0].name !== 'svg') throw new Error('expected a single <svg> root');
  return elements[0];
}

function getAttr(element, name) {
  const found = element.attrs.find(([key]) => key === name);
  return found ? found[1] : undefined;
}

function setAttr(element, name, value) {
  const index = element.attrs.findIndex(([key]) => key === name);
  if (index === -1) element.attrs.push([name, value]);
  else element.attrs[index] = [name, value];
}

function removeAttrs(element, predicate) {
  element.attrs = element.attrs.filter(([key, value]) => !predicate(key, value));
}

function* walk(element) {
  yield element;
  for (const child of element.children) if (child.name) yield* walk(child);
}

// Inline declarations beat presentation attributes, so each becomes (or
// replaces) the attribute of the same name; proma and zed carry their fills and
// fill rules this way, so dropping the attribute would change the silhouette.
function inlineStyles(svg) {
  for (const element of walk(svg)) {
    const style = getAttr(element, 'style');
    if (style === undefined) continue;
    removeAttrs(element, (key) => key === 'style');
    for (const declaration of style.split(';')) {
      if (!declaration.trim()) continue;
      const colon = declaration.indexOf(':');
      const property = declaration.slice(0, colon).trim().toLowerCase();
      const value = declaration.slice(colon + 1).trim();
      if (colon === -1 || !value || /!important/i.test(value)) throw new RejectedSvg(`unsupported style declaration "${declaration.trim()}"`);
      if (IGNORED_STYLE_PROPERTIES.has(property)) continue;
      if (!PRESENTATION_PROPERTIES.has(property)) throw new RejectedSvg(`unsupported style property "${property}"`);
      setAttr(element, property, value);
    }
  }
}

function dropElements(element, predicate) {
  let dropped = 0;
  element.children = element.children.filter((child) => {
    if (child.name && predicate(child)) {
      dropped += 1;
      return false;
    }
    if (child.name) dropped += dropElements(child, predicate);
    return true;
  });
  return dropped;
}

function referencedId(value) {
  const match = /^url\(\s*['"]?#([^'")]+)['"]?\s*\)$/.exec(String(value || '').trim());
  return match ? match[1] : null;
}

// An SVG whose artwork is painted through a <mask> (antigravity: blurred colour
// blobs clipped to a white shape) is reduced to the mask's own shapes, painted
// opaque. As a template image only alpha matters, and the masked artwork covers
// the mask, so the silhouette is the mask's shape.
function flattenMask(svg, notes) {
  const masks = [...walk(svg)].filter((element) => element.name === 'mask');
  if (masks.length === 0) return;
  if (masks.length > 1) throw new RejectedSvg('more than one <mask>');
  const [mask] = masks;
  const id = getAttr(mask, 'id');
  if (getAttr(mask, 'maskContentUnits') === 'objectBoundingBox') throw new RejectedSvg('<mask> uses objectBoundingBox content units');
  const shapes = mask.children.filter((child) => child.name);
  if (shapes.length === 0) throw new RejectedSvg('empty <mask>');
  for (const shape of shapes) {
    const opacity = ['opacity', 'fill-opacity'].map((name) => getAttr(shape, name)).filter((value) => value !== undefined);
    if (!SHAPE_ELEMENTS.has(shape.name) || !WHITE.has(String(getAttr(shape, 'fill')).toLowerCase())
      || opacity.some((value) => Number(value) !== 1) || getAttr(shape, 'stroke') !== undefined) {
      throw new RejectedSvg('<mask> content is not opaque white shapes');
    }
    setAttr(shape, 'fill', '#000000');
  }
  const masked = [...walk(svg)].filter((element) => referencedId(getAttr(element, 'mask')) === id);
  if (masked.length !== 1) throw new RejectedSvg(`expected one element masked by #${id}`);
  if (getAttr(masked[0], 'transform') !== undefined) throw new RejectedSvg('masked element has a transform');
  dropElements(svg, (element) => element === mask);
  const replace = (parent) => {
    const index = parent.children.indexOf(masked[0]);
    if (index !== -1) parent.children.splice(index, 1, ...shapes);
    else parent.children.forEach((child) => child.name && replace(child));
  };
  replace(svg);
  notes.push('masked artwork replaced by the mask silhouette');
}

// Xcode sizes a vector image by the root's width/height. The desktop's are
// `1em` (sized by the row) or missing, so every icon gets a 24 pt box on its
// longer side with the viewBox's aspect ratio, which the row's
// `mask-size: contain` fits the same way. A small intrinsic size also keeps any
// bitmap Xcode derives from it small (ollama's viewBox is 724 × 952).
const ICON_POINT_SIZE = 24;

function normalizeRoot(svg) {
  const viewBox = getAttr(svg, 'viewBox');
  let box = null;
  if (viewBox !== undefined) {
    box = viewBox.split(/[\s,]+/).map(Number);
    if (box.length !== 4 || box.some((value) => !Number.isFinite(value)) || box[2] <= 0 || box[3] <= 0) {
      throw new RejectedSvg(`bad viewBox "${viewBox}"`);
    }
  }
  const absolute = ['width', 'height'].map((name) => {
    const value = getAttr(svg, name);
    return value !== undefined && /^(\d*\.)?\d+(px)?$/.test(value) ? Number(value.replace(/px$/, '')) : 0;
  });
  const [width, height] = absolute.every((value) => value > 0) ? absolute : box ? box.slice(2) : [0, 0];
  if (!width || !height) throw new RejectedSvg('neither a viewBox nor an absolute size to scale by');
  if (!box) box = [0, 0, width, height];
  const scale = ICON_POINT_SIZE / Math.max(width, height);
  const points = (value) => String(Number((value * scale).toFixed(3)));
  const usesXlink = [...walk(svg)].some((element) => element.attrs.some(([key]) => key.startsWith('xlink:')));
  const kept = svg.attrs.filter(([key]) => !['xmlns', 'xmlns:xlink', 'width', 'height', 'viewBox'].includes(key));
  svg.attrs = [
    ['xmlns', 'http://www.w3.org/2000/svg'],
    ...(usesXlink ? [['xmlns:xlink', 'http://www.w3.org/1999/xlink']] : []),
    ['width', points(width)],
    ['height', points(height)],
    ['viewBox', box.map(String).join(' ')],
    ...kept
  ];
}

// As a template image only alpha counts, so a gradient whose stops are all
// opaque paints exactly what a solid fill does; one renderer feature less.
function solidifyOpaqueGradients(svg, notes) {
  const gradients = new Map([...walk(svg)]
    .filter((element) => /^(linear|radial)Gradient$/.test(element.name) && getAttr(element, 'id'))
    .map((element) => [getAttr(element, 'id'), element]));
  const isOpaque = (gradient) => {
    const stops = gradient.children.filter((child) => child.name === 'stop');
    return stops.length > 0 && stops.every((stop) => ['stop-opacity', 'opacity']
      .every((name) => getAttr(stop, name) === undefined || Number(getAttr(stop, name)) === 1)
      && !/rgba|hsla|transparent/i.test(getAttr(stop, 'stop-color') || ''));
  };
  let solidified = 0;
  for (const element of walk(svg)) {
    for (const name of ['fill', 'stroke']) {
      const gradient = gradients.get(referencedId(getAttr(element, name)));
      if (gradient && isOpaque(gradient)) {
        setAttr(element, name, '#000000');
        solidified += 1;
      }
    }
  }
  if (solidified) notes.push(`${solidified} opaque gradient paint(s) made solid`);
}

const PATH_ARGUMENTS = { m: 2, l: 2, h: 1, v: 1, c: 6, s: 4, q: 4, t: 2, a: 7, z: 0 };
const PATH_NUMBER = /[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/y;

// Rewrites path data with every number and flag separated. The desktop artwork
// uses the minifier's shorthand (`a.5.5 0 110 1` packs both arc flags into
// `110`), which the SVG grammar allows but not every renderer reads; spelled
// out it means the same path everywhere. Malformed data rejects the file.
function normalizePathData(data) {
  const segments = [];
  let index = 0;
  let command = null;
  const skip = () => {
    while (index < data.length && /[\s,]/.test(data[index])) index += 1;
  };
  const number = () => {
    skip();
    PATH_NUMBER.lastIndex = index;
    const match = PATH_NUMBER.exec(data);
    if (!match) throw new RejectedSvg(`bad path data near "${data.slice(index, index + 12)}"`);
    index += match[0].length;
    return match[0];
  };
  const flag = () => {
    skip();
    if (data[index] !== '0' && data[index] !== '1') throw new RejectedSvg(`bad arc flag near "${data.slice(index, index + 12)}"`);
    index += 1;
    return data[index - 1];
  };
  for (skip(); index < data.length; skip()) {
    let letter = '';
    if (/[A-Za-z]/.test(data[index])) {
      letter = data[index];
      index += 1;
      if (PATH_ARGUMENTS[letter.toLowerCase()] === undefined) throw new RejectedSvg(`unknown path command "${letter}"`);
      command = letter;
    } else if (!command || /z/i.test(command)) {
      throw new RejectedSvg(`bad path data near "${data.slice(index, index + 12)}"`);
    }
    const kind = command.toLowerCase();
    const args = [];
    for (let position = 0; position < PATH_ARGUMENTS[kind]; position += 1) {
      args.push(kind === 'a' && (position === 3 || position === 4) ? flag() : number());
    }
    segments.push(`${letter}${args.join(' ')}`);
  }
  return segments.join(' ');
}

function serialize(element) {
  const attrs = element.attrs.map(([key, value]) => ` ${key}="${value.replace(/"/g, '&quot;')}"`).join('');
  const children = element.children.map(serialize).join('');
  return children ? `<${element.name}${attrs}>${children}</${element.name}>` : `<${element.name}${attrs}/>`;
}

// Turns a desktop mask SVG into a template image Xcode renders with the same
// alpha silhouette. Deterministic, dependency-free, and conservative: what it
// cannot keep faithful it rejects. Returns { svg, notes } or { rejected }.
function sanitizeSvg(source) {
  const notes = [];
  try {
    const svg = parseSvg(source);
    inlineStyles(svg);
    dropElements(svg, (element) => DROPPED_ELEMENTS.has(element.name));
    const filters = dropElements(svg, (element) => element.name === 'filter');
    let filtered = 0;
    for (const element of walk(svg)) {
      if (getAttr(element, 'filter') !== undefined) filtered += 1;
      removeAttrs(element, (key) => key === 'filter');
    }
    if (filters || filtered) notes.push(`dropped ${Math.max(filters, filtered)} filter effect(s)`);
    flattenMask(svg, notes);
    solidifyOpaqueGradients(svg, notes);
    for (const element of walk(svg)) {
      if (element.name === 'path' && getAttr(element, 'd') !== undefined) setAttr(element, 'd', normalizePathData(getAttr(element, 'd')));
    }
    for (const element of walk(svg)) {
      // Inert without a stylesheet or assistive technology; aria-labelledby
      // would point at the dropped <title>.
      removeAttrs(element, (key) => key === 'class' || key === 'role' || key === 'version' || key === 'xml:space'
        || key.startsWith('aria-') || key.startsWith('data-') || (key.startsWith('xmlns:') && key !== 'xmlns:xlink'));
      element.attrs = element.attrs.map(([key, value]) => [key, value.replace(/currentColor/gi, '#000000')]);
      element.children = element.children.filter((child) => {
        if (child.name) return true;
        if (child.text.trim()) throw new RejectedSvg(`text content in <${element.name}>`);
        return false;
      });
    }
    // Paint servers and clip paths nothing points at any more (the filtered
    // artwork's, or unused exports such as openclaw's gradients).
    const referenced = new Set();
    for (const element of walk(svg)) {
      for (const [key, value] of element.attrs) {
        for (const [, id] of value.matchAll(/url\(\s*['"]?#([^'")]+)['"]?\s*\)/g)) referenced.add(id);
        if (key === 'href' || key === 'xlink:href') referenced.add(value.replace(/^#/, ''));
      }
    }
    for (const defs of [...walk(svg)].filter((element) => element.name === 'defs')) {
      dropElements(defs, (element) => getAttr(element, 'id') !== undefined && !referenced.has(getAttr(element, 'id')));
    }
    dropElements(svg, (element) => element.name === 'defs' && element.children.length === 0);
    for (const element of walk(svg)) {
      if (!ALLOWED_ELEMENTS.has(element.name)) throw new RejectedSvg(`unsupported <${element.name}>`);
    }
    normalizeRoot(svg);
    const ids = new Set([...walk(svg)].map((element) => getAttr(element, 'id')).filter(Boolean));
    for (const element of walk(svg)) {
      for (const [key, value] of element.attrs) {
        for (const [, id] of value.matchAll(/url\(\s*['"]?#([^'")]+)['"]?\s*\)/g)) {
          if (!ids.has(id)) throw new RejectedSvg(`${key} references missing #${id}`);
        }
        if ((key === 'href' || key === 'xlink:href') && !ids.has(value.replace(/^#/, ''))) {
          throw new RejectedSvg(`${key} references ${value}`);
        }
      }
    }
    const output = `${serialize(svg)}\n`;
    const forbidden = FORBIDDEN_OUTPUT.find((pattern) => pattern.test(output));
    if (forbidden) throw new RejectedSvg(`the output still matches ${forbidden}`);
    return { svg: output, notes };
  } catch (error) {
    if (error instanceof RejectedSvg) return { rejected: error.message };
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Icon plan: which artwork ships under which asset name
// ---------------------------------------------------------------------------

// Code-unit order, so the output never depends on the machine's locale.
function byCodeUnit(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

function relativePath(file) {
  return path.relative(ROOT, file).split(path.sep).join('/');
}

function buildIconPlan({
  stylesSource = fs.readFileSync(STYLES_PATH, 'utf8'),
  readSvg = (file) => fs.readFileSync(file, 'utf8')
} = {}) {
  const assets = new Map(); // stem → { stem, source, svg, notes, rejected }
  const addAsset = (stem, file) => {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(stem)) throw new Error(`icon stem ${JSON.stringify(stem)} is not [a-z0-9-]`);
    const existing = assets.get(stem);
    if (existing) {
      if (existing.file !== file) throw new Error(`asset ${ICON_ASSET_PREFIX}${stem} would come from both ${existing.source} and ${relativePath(file)}`);
      return existing;
    }
    if (!fs.existsSync(file)) throw new Error(`${relativePath(file)} does not exist`);
    const asset = { stem, file, source: relativePath(file), ...sanitizeSvg(readSvg(file)) };
    assets.set(stem, asset);
    return asset;
  };
  const assetName = (asset) => (asset.rejected ? null : `${ICON_ASSET_PREFIX}${asset.stem}`);
  const iconFile = (stem) => path.join(ICONS_DIR, `${stem}.svg`);

  // Vendor marks: the `.row-icon-<id>` masks, `mask || icon || id`.
  const markAssets = [];
  for (const entry of VENDOR_PRESENTATION) {
    const name = assetName(addAsset(ROW_ICON_MASKS[entry.id], iconFile(ROW_ICON_MASKS[entry.id])));
    if (name) markAssets.push([entry.id, name]);
  }

  const { rowIcons, limitIcons } = stylesheetMasks(stylesSource);
  const limitOverrides = [];
  for (const [id, file] of [...limitIcons].sort(([a], [b]) => byCodeUnit(a, b))) {
    if (!ROW_ICON_MASKS[id]) throw new Error(`.limit-icon.row-icon-${id} overrides a mark vendorPresentation.js does not define`);
    const name = assetName(addAsset(path.basename(file, '.svg'), file));
    if (name) limitOverrides.push([id, name]);
  }

  const osAssets = [];
  let projectAsset = null;
  for (const [className, file] of [...rowIcons].sort(([a], [b]) => byCodeUnit(a, b))) {
    if (SKIPPED_ROW_ICONS.has(className) || ROW_ICON_MASKS[className]) continue;
    if (!EXTRA_ROW_ICON.test(className)) {
      throw new Error(`styles.css declares .row-icon-${className}; decide whether iOS ships it (sync-ios-vendors.js EXTRA_ROW_ICON)`);
    }
    const asset = addAsset(className, file);
    if (asset.rejected) throw new Error(`${asset.source} cannot be an iOS asset: ${asset.rejected}`);
    if (className === 'project') projectAsset = assetName(asset);
    else osAssets.push([className.replace(/^os-/, ''), assetName(asset)]);
  }
  if (!projectAsset) throw new Error('styles.css no longer declares .row-icon-project');

  const sortedAssets = [...assets.values()].sort((a, b) => byCodeUnit(a.stem, b.stem));
  return {
    assets: sortedAssets.filter((asset) => !asset.rejected),
    rejected: sortedAssets.filter((asset) => asset.rejected)
      .map(({ stem, source, rejected }) => ({ stem, source, reason: rejected })),
    markAssets,
    limitOverrides,
    osAssets,
    projectAsset
  };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderIosVendorCatalog({
  chartSource = fs.readFileSync(CHART_SOURCE_PATH, 'utf8'),
  iconPlan = buildIconPlan()
} = {}) {
  const lines = [
    '// @generated by scripts/sync-ios-vendors.js — DO NOT EDIT.',
    '// Sources: src/shared/vendorPresentation.js, src/shared/clientCatalog.js,',
    '// src/shared/limits/providers.js, modelVendorFor() in src/electron/renderer/usageCharts.js,',
    '// the mask rules in src/electron/renderer/styles.css and the artwork in assets/icons/.',
    '// Edit those, then run `npm run sync:ios-vendors`; tests/shared/iosVendorCatalog.test.js fails on drift.',
    '',
    'extension VendorCatalog {',
    `    static let generatedDefaultColorHex = ${swiftString(normalizeHex(DEFAULT_VENDOR_COLOR))}`,
    '',
    '    static let generatedMarks: [Mark] = ['
  ];
  for (const entry of VENDOR_PRESENTATION) {
    const brand = entry.color ? normalizeHex(entry.color) : null;
    const usesInk = entry.widgetInk === true;
    const widget = usesInk ? null : (entry.widgetColor ? normalizeHex(entry.widgetColor) : brand);
    lines.push(
      `        Mark(id: ${swiftString(entry.id)}, label: ${swiftOptionalString(markLabel(entry))}, `
      + `brandColorHex: ${swiftOptionalString(brand)}, widgetColorHex: ${swiftOptionalString(widget)}, `
      + `usesInk: ${usesInk}),`
    );
  }
  lines.push('    ]', '', '    static let generatedClientLabels: [String: String] = [');
  for (const [id, label] of Object.entries(CLIENT_LABELS)) {
    lines.push(`        ${swiftString(id)}: ${swiftString(label)},`);
  }
  lines.push('    ]', '', '    static let generatedTrackedClientIDs: [String] = [');
  for (const id of CLIENT_IDS) lines.push(`        ${swiftString(id)},`);
  lines.push('    ]', '', '    static let generatedLimitProviders: [LimitProviderInfo] = [');
  for (const provider of LIMIT_PROVIDER_CATALOG) {
    lines.push(
      `        LimitProviderInfo(id: ${swiftString(provider.id)}, label: ${swiftString(provider.label)}, `
      + `settingsLabel: ${swiftString(provider.settingsLabel || provider.label)}),`
    );
  }
  lines.push('    ]', '', '    static let generatedModelVendorRules: [ModelVendorRule] = [');
  for (const rule of modelVendorRules(chartSource)) {
    lines.push(`        ModelVendorRule(pattern: ${swiftRawString(rule.pattern)}, vendorID: ${swiftString(rule.vendor)}),`);
  }
  lines.push('    ]', '', '    static let generatedFallbackModelColorHexes: [String] = [');
  for (const hex of fallbackModelColors(chartSource)) lines.push(`        ${swiftString(hex)},`);
  lines.push(
    '    ]',
    '',
    '    // Image names in VendorIcons.xcassets (app, widget and watch targets).',
    '    // Mark id → its `.row-icon-<id>` artwork; a mark whose artwork was rejected is absent.',
    ...swiftDictionaryLines('generatedIconAssets', iconPlan.markAssets),
    '',
    '    // `.limit-icon.row-icon-<id>` rules: the Limits page draws these marks with other artwork.',
    ...swiftDictionaryLines('generatedLimitIconOverrides', iconPlan.limitOverrides),
    '',
    '    // `.row-icon-os-<key>` device marks, keyed like the desktop\'s osIconFor().',
    ...swiftDictionaryLines('generatedOSIconAssets', iconPlan.osAssets),
    '',
    `    static let generatedProjectIconAsset = ${swiftString(iconPlan.projectAsset)}`,
    '}',
    ''
  );
  return lines.join('\n');
}

// Xcode's own Contents.json style, so opening a catalog in Xcode leaves no diff.
function xcodeJson(value) {
  return `${JSON.stringify(value, null, 2).replace(/^(\s*"[^"]*"): /gm, '$1 : ')}\n`;
}

// Every file of the three VendorIcons.xcassets catalogs, keyed by repo-relative
// path. Identical across targets, so git stores each blob once.
function renderIosVendorIconCatalogs({ iconPlan = buildIconPlan() } = {}) {
  const files = {};
  for (const dir of ICON_CATALOG_DIRS) {
    const base = relativePath(dir);
    files[`${base}/Contents.json`] = xcodeJson({ info: { author: 'xcode', version: 1 } });
    for (const asset of iconPlan.assets) {
      const imageset = `${base}/${ICON_ASSET_PREFIX}${asset.stem}.imageset`;
      files[`${imageset}/Contents.json`] = xcodeJson({
        images: [{ filename: `${asset.stem}.svg`, idiom: 'universal' }],
        info: { author: 'xcode', version: 1 },
        properties: { 'preserves-vector-representation': true, 'template-rendering-intent': 'template' }
      });
      files[`${imageset}/${asset.stem}.svg`] = asset.svg;
    }
  }
  return files;
}

// Repo-relative paths of the files currently in the catalog folders.
function listIconCatalogFiles() {
  const files = [];
  const visit = (dir) => {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (IGNORED_CATALOG_FILES.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) visit(full);
      else files.push(relativePath(full));
    }
  };
  ICON_CATALOG_DIRS.forEach(visit);
  return files.sort(byCodeUnit);
}

function renderAll() {
  const iconPlan = buildIconPlan();
  return {
    iconPlan,
    files: {
      [relativePath(OUTPUT_PATH)]: renderIosVendorCatalog({ iconPlan }),
      ...renderIosVendorIconCatalogs({ iconPlan })
    }
  };
}

function removeEmptyDirs(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) removeEmptyDirs(path.join(dir, entry.name));
  }
  if (fs.readdirSync(dir).every((name) => IGNORED_CATALOG_FILES.has(name)) && !ICON_CATALOG_DIRS.includes(dir)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function main(argv) {
  const { iconPlan, files } = renderAll();
  for (const { source, reason } of iconPlan.rejected) {
    console.warn(`warning: ${source} is not shipped to iOS (${reason}); its marks fall back to a dot.`);
  }
  const stale = Object.entries(files)
    .filter(([rel, contents]) => {
      const full = path.join(ROOT, rel);
      return !fs.existsSync(full) || fs.readFileSync(full, 'utf8') !== contents;
    })
    .map(([rel]) => rel);
  const extra = listIconCatalogFiles().filter((rel) => !(rel in files));

  if (argv.includes('--check')) {
    if (stale.length || extra.length) {
      for (const rel of [...stale, ...extra]) console.error(`${rel} is ${rel in files ? 'stale' : 'not generated'}.`);
      console.error('Run `npm run sync:ios-vendors`.');
      process.exitCode = 1;
    }
    return;
  }
  if (!stale.length && !extra.length) {
    console.log('The iOS vendor catalog and icon assets are up to date.');
    return;
  }
  for (const rel of stale) {
    const full = path.join(ROOT, rel);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, files[rel]);
  }
  for (const rel of extra) fs.rmSync(path.join(ROOT, rel));
  ICON_CATALOG_DIRS.forEach(removeEmptyDirs);
  console.log(`Wrote ${stale.length} and removed ${extra.length} file(s) of the iOS vendor catalog and icon assets.`);
}

if (require.main === module) main(process.argv.slice(2));

module.exports = {
  ICON_ASSET_PREFIX,
  ICON_CATALOG_DIRS,
  OUTPUT_PATH,
  ROOT,
  buildIconPlan,
  listIconCatalogFiles,
  renderIosVendorCatalog,
  renderIosVendorIconCatalogs,
  sanitizeSvg
};
