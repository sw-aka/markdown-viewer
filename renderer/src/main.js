// Browser entry point loaded by the app's WKWebView (mdv://app/index.html).
// Swift calls window.mdv.render(markdown, options) and window.mdv.scrollToLine(line);
// the page reports back through window.webkit.messageHandlers.mdv.

import DOMPurify from 'dompurify';
import morphdom from 'morphdom';
import { renderMarkdown } from './markdown.js';
import { createSanitizer } from './sanitize.js';
import { renderMap } from './enrich/map.js';
import { renderSTL } from './enrich/stl.js';
import { addMermaidControls } from './enrich/mermaid-controls.js';

const sanitize = createSanitizer(DOMPurify);
const article = document.getElementById('content');
const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');

function post(message) {
  window.webkit?.messageHandlers?.mdv?.postMessage(message);
}

// --- Lazy loading of the large libraries ------------------------------------

const scripts = new Map();
function loadScript(src) {
  if (!scripts.has(src)) {
    scripts.set(src, new Promise((resolve, reject) => {
      const el = document.createElement('script');
      el.src = src;
      el.onload = resolve;
      el.onerror = () => reject(new Error(`Failed to load ${src}`));
      document.head.appendChild(el);
    }));
  }
  return scripts.get(src);
}

async function loadMathJax() {
  if (!window.MathJax?.tex2svgPromise) {
    window.MathJax = {
      tex: { packages: { '[+]': ['ams', 'newcommand', 'noerrors', 'noundefined'] } },
      svg: { fontCache: 'local' },
      startup: {
        typeset: false,
        ready() {
          // Drop the 'html' extension (\href, \class, \style, \cssId, \data),
          // which would put document-controlled links, classes and ids into the
          // page, and 'require'/'autoload' so \require{html} cannot bring it back.
          // The full build has every other extension preloaded.
          // 'action' (\mathtip, \texttip, \toggle) shows tooltips outside the
          // formula's box.
          const blocked = new Set(['html', 'require', 'autoload', 'action']);
          const tex = window.MathJax.config.tex;
          tex.packages = (Array.isArray(tex.packages) ? tex.packages : []).filter((name) => !blocked.has(name));
          window.MathJax.startup.defaultReady();
        },
      },
    };
    await loadScript('vendor/mathjax/tex-svg-full.js');
    await window.MathJax.startup.promise;
    // tex2svg output relies on MathJax's stylesheet (it hides the assistive
    // MathML copy and sizes the SVGs).
    document.head.appendChild(window.MathJax.svgStylesheet());
  }
  return window.MathJax;
}

let mermaidTheme = null;
async function loadMermaid() {
  await loadScript('vendor/mermaid.min.js');
  const theme = darkQuery.matches ? 'dark' : 'default';
  if (theme !== mermaidTheme) {
    window.mermaid.initialize({ startOnLoad: false, theme, securityLevel: 'strict' });
    mermaidTheme = theme;
  }
  return window.mermaid;
}

// --- Enrichment of rendered blocks ----------------------------------------------

function errorBox(title, message) {
  const box = document.createElement('div');
  box.className = 'flash flash-error mdv-error';
  const strong = document.createElement('strong');
  strong.textContent = title;
  const pre = document.createElement('pre');
  pre.textContent = message;
  box.append(strong, pre);
  return box;
}

// Map and STL viewers hold WebGL contexts / Leaflet maps; dispose them when
// their block is re-rendered or removed (WebKit caps live GL contexts).
const disposers = new Map();

function disposeViewer(el) {
  disposers.get(el)?.();
  disposers.delete(el);
}

function disposeDetachedViewers() {
  for (const el of [...disposers.keys()]) {
    if (!el.isConnected || !el.dataset.rendered) disposeViewer(el);
  }
}

// Classes the page's scripts act on; see sanitize.js.
const HOOK_CLASSES = ['mdv-enrich', 'mdv-enrich-source', 'mdv-math', 'mdv-math-display', 'mdv-copy'];

// Output from Mermaid and MathJax is inserted without DOMPurify. Diagram labels
// and class names come from the document, so strip anything that would make
// the page's own scripts act on it.
function scrubEmbedded(root) {
  for (const n of root.querySelectorAll('[class]')) {
    for (const name of HOOK_CLASSES) n.classList?.remove(name);
  }
  for (const n of root.querySelectorAll('[name]')) n.removeAttribute('name');
}

// Content rendered by Mermaid, MathJax, Leaflet or three.js never contains
// blocks for the page to process.
const EMBEDDED = '.mdv-mermaid-diagram, mjx-container, .mdv-map, .mdv-stl';
const isEmbedded = (el) => el.parentElement?.closest(EMBEDDED) != null;

let mermaidCounter = 0;
const renderers = {
  async mermaid(el, source) {
    const mermaid = await loadMermaid();
    // bindFunctions is not called: in strict mode it only wires up tooltips,
    // which Mermaid inserts into <body> with document-controlled markup.
    const { svg } = await mermaid.render(`mdv-mermaid-${++mermaidCounter}`, source);
    const wrapper = document.createElement('div');
    wrapper.className = 'mdv-mermaid-diagram';
    wrapper.innerHTML = svg;
    scrubEmbedded(wrapper);
    el.replaceChildren(wrapper);
    document.querySelectorAll('body > .mermaidTooltip').forEach((n) => n.remove());
    return addMermaidControls(el, wrapper);
  },
  geojson: (el, source) => renderMap(el, source, 'geojson', darkQuery.matches),
  topojson: (el, source) => renderMap(el, source, 'topojson', darkQuery.matches),
  stl: (el, source) => renderSTL(el, source, darkQuery.matches),
};

// Block sources, kept outside the DOM once the block's markup is replaced.
const sources = new WeakMap();

async function enrichBlock(el) {
  const kind = el.dataset.kind;
  // Fresh markup (new block, or morphdom reused the element for a changed
  // block) carries the source; re-renders of the same block use the cache.
  const fresh = el.querySelector(':scope > .mdv-enrich-source');
  if (fresh) sources.set(el, fresh.textContent);
  const source = sources.get(el) ?? '';
  disposeViewer(el);
  el.dataset.rendered = 'pending';
  try {
    const dispose = await renderers[kind](el, source);
    if (typeof dispose === 'function') disposers.set(el, dispose);
    el.dataset.rendered = 'true';
  } catch (error) {
    // Mermaid leaves stray error nodes in <body> on failure.
    document.querySelectorAll('body > [id^="dmdv-mermaid-"]').forEach((n) => n.remove());
    const label = { mermaid: 'Unable to render Mermaid diagram', geojson: 'Unable to render GeoJSON', topojson: 'Unable to render TopoJSON', stl: 'Unable to render STL' }[kind];
    el.replaceChildren(errorBox(label, String(error?.message ?? error)));
    el.dataset.rendered = 'error';
  }
}

async function typesetMath(el) {
  const tex = el.dataset.tex ?? el.textContent;
  el.dataset.tex = tex;
  el.dataset.rendered = 'pending';
  try {
    const MathJax = await loadMathJax();
    const node = await MathJax.tex2svgPromise(tex, { display: el.dataset.display === 'true' });
    // Defense in depth: math output never needs links, ids or classes from TeX.
    // TeX can set links, ids, classes and styles (\mmlToken, \bbox); MathJax's
    // own output needs none of them below the root <svg>, except glyph
    // references (<use xlink:href="#MJX-...">) and the ids they point to.
    const svgRoot = node.querySelector('svg');
    for (const n of node.querySelectorAll('*')) {
      if (n === svgRoot) continue;
      n.removeAttribute('href');
      n.removeAttribute('style');
      n.removeAttribute('class');
      if (n.id && !(n.tagName.toLowerCase() === 'path' && n.closest('defs'))) n.removeAttribute('id');
    }
    scrubEmbedded(node);
    el.replaceChildren(node);
    el.dataset.rendered = 'true';
  } catch (error) {
    el.textContent = tex;
    el.dataset.rendered = 'error';
  }
}

function enrich() {
  const jobs = [];
  for (const el of article.querySelectorAll('.mdv-enrich:not([data-rendered])')) {
    if (!isEmbedded(el)) jobs.push(enrichBlock(el));
  }
  for (const el of article.querySelectorAll('.mdv-math:not([data-rendered])')) {
    if (!isEmbedded(el)) jobs.push(typesetMath(el));
  }
  return Promise.all(jobs);
}

// --- Rendering -------------------------------------------------------------

let suppressScrollReportUntil = 0;
let lastOptions = {};
let lastMarkdown = '';

function render(markdown, options = {}) {
  lastMarkdown = markdown;
  lastOptions = options;
  const nonce = crypto.getRandomValues(new Uint32Array(4)).join('-');
  const html = sanitize(renderMarkdown(markdown, { nonce }), { baseURL: options.baseURL, nonce });
  // Height changes from re-rendering are not user scrolls.
  suppressScrollReportUntil = Date.now() + 300;
  const next = article.cloneNode(false);
  next.innerHTML = html;
  morphdom(article, next, {
    onBeforeElUpdated(fromEl, toEl) {
      // Keep already-rendered diagrams and equations whose source is unchanged.
      if (fromEl.classList?.contains('mdv-enrich') && fromEl.dataset.rendered && toEl.classList?.contains('mdv-enrich')) {
        if (fromEl.dataset.key === toEl.dataset.key) {
          if (toEl.dataset.line) fromEl.dataset.line = toEl.dataset.line;
          return false;
        }
      }
      if (fromEl.classList?.contains('mdv-math') && fromEl.dataset.rendered && toEl.classList?.contains('mdv-math')) {
        if (fromEl.dataset.tex === toEl.textContent && fromEl.dataset.display === toEl.dataset.display) {
          if (toEl.dataset.line) fromEl.dataset.line = toEl.dataset.line;
          return false;
        }
      }
      return true;
    },
  });
  document.body.classList.toggle('mdv-empty', markdown.trim() === '');
  disposeDetachedViewers();
  return enrich().then(() => {
    suppressScrollReportUntil = Date.now() + 300;
    post({ type: 'rendered' });
  });
}

// Re-render diagrams when the system appearance changes.
darkQuery.addEventListener('change', () => {
  for (const el of article.querySelectorAll('.mdv-enrich[data-rendered]')) {
    disposeViewer(el);
    delete el.dataset.rendered;
  }
  enrich();
});

// --- Scroll sync -------------------------------------------------------------

function lineElements() {
  return [...article.querySelectorAll('[data-line]')].filter((el) => el.offsetParent !== null);
}

function scrollToLine(line) {
  const elements = lineElements();
  if (!elements.length) return;
  let before = null;
  let after = null;
  for (const el of elements) {
    const l = Number(el.dataset.line);
    if (l <= line) before = el;
    else { after = el; break; }
  }
  const top = (el) => el.getBoundingClientRect().top + window.scrollY;
  let y = 0;
  if (before && after) {
    const l0 = Number(before.dataset.line);
    const l1 = Number(after.dataset.line);
    y = top(before) + ((line - l0) / (l1 - l0)) * (top(after) - top(before));
  } else if (before) {
    y = top(before);
  }
  suppressScrollReportUntil = Date.now() + 200;
  window.scrollTo({ top: Math.max(0, y - 16), behavior: 'instant' });
}

function topLine() {
  const elements = lineElements();
  const y = window.scrollY + 16;
  let line = 0;
  for (let i = 0; i < elements.length; i++) {
    const el = elements[i];
    const t = el.getBoundingClientRect().top + window.scrollY;
    if (t > y) {
      const prev = elements[i - 1];
      if (prev) {
        const pt = prev.getBoundingClientRect().top + window.scrollY;
        const l0 = Number(prev.dataset.line);
        const l1 = Number(el.dataset.line);
        line = l0 + ((y - pt) / Math.max(1, t - pt)) * (l1 - l0);
      }
      return line;
    }
    line = Number(el.dataset.line);
  }
  return line;
}

let scrollFrame = 0;
window.addEventListener('scroll', () => {
  if (Date.now() < suppressScrollReportUntil || scrollFrame) return;
  scrollFrame = requestAnimationFrame(() => {
    scrollFrame = 0;
    post({ type: 'scroll', line: topLine() });
  });
}, { passive: true });

// --- Links and copy buttons --------------------------------------------------

function scrollToFragment(fragment) {
  const id = decodeURIComponent(fragment);
  const target = document.getElementById(id) ?? document.getElementById(`user-content-${id}`);
  if (target) {
    target.scrollIntoView({ block: 'start' });
    return true;
  }
  return false;
}

document.addEventListener('click', (event) => {
  const copy = event.target.closest('.mdv-copy');
  if (copy && article.contains(copy) && !isEmbedded(copy)) {
    event.preventDefault();
    const code = copy.closest('.highlight, .snippet-clipboard-content')?.querySelector('pre');
    post({ type: 'copy', text: code?.innerText ?? '' });
    copy.classList.add('ClipboardButton--success');
    setTimeout(() => copy.classList.remove('ClipboardButton--success'), 2000);
    return;
  }
  const link = event.target.closest('a[href], area[href], a[*|href]');
  if (!link) return;
  event.preventDefault();
  // SVG links (Mermaid, MathJax \href) expose href as an SVGAnimatedString.
  const href = link.getAttribute('href') ?? link.getAttributeNS('http://www.w3.org/1999/xlink', 'href') ?? '';
  if (href.startsWith('#')) {
    scrollToFragment(href.slice(1));
    return;
  }
  try {
    post({ type: 'open', url: new URL(href, document.baseURI).href });
  } catch {
    // Not a valid URL: ignore the click.
  }
});

window.mdv = {
  render,
  scrollToLine,
  rerender: () => render(lastMarkdown, lastOptions),
};

post({ type: 'ready' });
