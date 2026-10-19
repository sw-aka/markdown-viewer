// Markdown -> HTML conversion that mirrors GitHub's rendering of .md files.
// Pure module (no DOM access) so it can be unit tested under Node.
// Sanitizing and post-render enrichment (Mermaid, math, maps, STL) live in
// sanitize.js and main.js.

import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import { full as emoji } from 'markdown-it-emoji';
import hljs from 'highlight.js';
import { load as loadYaml } from 'js-yaml';
import { octicons } from './octicons.js';

// Marks markup the renderer generated (copy buttons, math, diagrams, icons)
// with the per-render nonce, so sanitize.js can tell it from user HTML.
const trust = (env) => (env?.nonce ? ` data-mdv-nonce="${env.nonce}"` : '');
const icon = (name, env) => octicons[name].replace('<svg ', `<svg${trust(env)} `);

const ALERT_TYPES = ['note', 'tip', 'important', 'warning', 'caution'];
const ENRICHED_LANGS = new Set(['mermaid', 'geojson', 'topojson', 'stl']);

export function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Same algorithm as github-slugger, which GitHub uses for heading anchors.
export function slugify(text) {
  return text
    .toLowerCase()
    .trim()
    .replace(/[^\p{L}\p{M}\p{N}\p{Pc}\- ]/gu, '')
    .replace(/ /g, '-');
}

// Small, stable string hash used as a cache key for enriched blocks.
export function hash(text) {
  let h = 5381;
  for (let i = 0; i < text.length; i++) h = ((h << 5) + h + text.charCodeAt(i)) | 0;
  return (h >>> 0).toString(36);
}

// --- Raw HTML: GitHub strips style/class and namespaces id/name ---------------

// Tokenizes start tags the way the HTML parser does (attributes may be
// separated by whitespace or '/'), so nothing a browser would read as an
// attribute can slip past. Unterminated tags are escaped to text.
const DROPPED_TAGS = new Set(['svg', 'math']);
const RAW_TEXT_TAGS = new Set(['script', 'style', 'xmp', 'iframe', 'noembed', 'noframes', 'noscript', 'textarea', 'title']);

export function filterRawHtml(html) {
  let out = '';
  let i = 0;
  const isSpace = (c) => c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === '\f';
  const isLetter = (c) => /[a-zA-Z]/.test(c ?? '');

  // Parses a tag's name and attributes from just after '<' or '</'.
  // Returns null when the tag never closes.
  const parseTag = (from) => {
    let j = from;
    let tag = '';
    while (j < html.length && !isSpace(html[j]) && html[j] !== '/' && html[j] !== '>') tag += html[j++];
    const attrs = [];
    let selfClose = false;
    while (j < html.length) {
      const c = html[j];
      if (isSpace(c)) { j++; continue; }
      if (c === '/') { selfClose = html[j + 1] === '>'; j++; continue; }
      if (c === '>') return { tag, attrs, selfClose, end: j + 1 };
      let name = html[j++];
      while (j < html.length && !isSpace(html[j]) && !'/>='.includes(html[j])) name += html[j++];
      let k = j;
      while (k < html.length && isSpace(html[k])) k++;
      let value;
      if (html[k] === '=') {
        k++;
        while (k < html.length && isSpace(html[k])) k++;
        const q = html[k];
        if (q === '"' || q === "'") {
          const endQ = html.indexOf(q, k + 1);
          if (endQ < 0) return null;
          value = html.slice(k + 1, endQ);
          j = endQ + 1;
        } else {
          let v = '';
          while (k < html.length && !isSpace(html[k]) && html[k] !== '>') v += html[k++];
          value = v;
          j = k;
        }
      }
      attrs.push([name, value]);
    }
    return null;
  };

  while (i < html.length) {
    const lt = html.indexOf('<', i);
    if (lt < 0) {
      out += html.slice(i);
      break;
    }
    out += html.slice(i, lt);
    const next = html[lt + 1];

    // Comments, declarations and processing instructions are copied verbatim
    // up to where the HTML parser ends them, never re-scanned for tags.
    if (html.startsWith('<!--', lt)) {
      let end;
      if (html.startsWith('>', lt + 4)) end = lt + 5;
      else if (html.startsWith('->', lt + 4)) end = lt + 6;
      else {
        // The parser also ends a comment at '--!>'.
        const a = html.indexOf('-->', lt + 4);
        const b = html.indexOf('--!>', lt + 4);
        if (a < 0 && b < 0) end = html.length;
        else if (b < 0 || (a >= 0 && a < b)) end = a + 3;
        else end = b + 4;
      }
      out += html.slice(lt, end);
      i = end;
      continue;
    }
    if (next === '!' || next === '?') {
      const close = html.indexOf('>', lt);
      const end = close < 0 ? html.length : close + 1;
      out += html.slice(lt, end);
      i = end;
      continue;
    }

    // End tags: the parser reads (and ignores) attributes, so parse them
    // the same way and drop them.
    if (next === '/' && isLetter(html[lt + 2])) {
      const parsed = parseTag(lt + 2);
      if (!parsed) {
        out += '&lt;';
        i = lt + 1;
        continue;
      }
      if (!DROPPED_TAGS.has(parsed.tag.toLowerCase())) out += `</${parsed.tag}>`;
      i = parsed.end;
      continue;
    }

    if (!isLetter(next)) {
      out += '<';
      i = lt + 1;
      continue;
    }

    const parsed = parseTag(lt + 1);
    if (!parsed) {
      // Not a complete tag: show it as text rather than guess.
      out += '&lt;';
      i = lt + 1;
      continue;
    }
    // Raw <svg> and <math> are not supported (GitHub strips them). Drop just
    // the tags so their text stays and an unclosed one cannot swallow the rest
    // of the document.
    if (DROPPED_TAGS.has(parsed.tag.toLowerCase())) {
      i = parsed.end;
      continue;
    }
    const kept = [];
    for (const [name, rawValue] of parsed.attrs) {
      const lower = name.toLowerCase();
      if (lower === 'style' || lower === 'class' || lower.startsWith('on')) continue;
      let value = rawValue ?? '';
      if (rawValue === undefined && lower !== 'id' && lower !== 'name') {
        kept.push(name);
        continue;
      }
      if ((lower === 'id' || lower === 'name') && !value.startsWith('user-content-')) {
        value = `user-content-${value}`;
      }
      kept.push(`${name}="${value.replace(/"/g, '&quot;')}"`);
    }
    out += `<${parsed.tag}${kept.length ? ' ' + kept.join(' ') : ''}${parsed.selfClose ? ' /' : ''}>`;
    i = parsed.end;
    // Raw text and RCDATA elements: the parser reads their content as text up
    // to the matching end tag, so copy it verbatim instead of looking for tags.
    const lowerTag = parsed.tag.toLowerCase();
    if (lowerTag === 'plaintext') {
      out += html.slice(i);
      break;
    }
    if (RAW_TEXT_TAGS.has(lowerTag)) {
      const close = html.toLowerCase().indexOf(`</${lowerTag}`, i);
      const end = close < 0 ? html.length : close;
      out += html.slice(i, end);
      i = end;
    }
  }
  return out;
}

// --- Math: $inline$, $`inline`$, $$display$$ and ```math --------------------

function mathPlugin(md) {
  md.inline.ruler.after('escape', 'math_inline', (state, silent) => {
    const src = state.src;
    const start = state.pos;
    if (src.charCodeAt(start) !== 0x24 /* $ */) return false;

    // $`...`$ (GitHub's code-span-safe syntax)
    if (src[start + 1] === '`') {
      const end = src.indexOf('`$', start + 2);
      if (end < 0) return false;
      if (!silent) {
        const token = state.push('math_inline', 'span', 0);
        token.content = src.slice(start + 2, end);
      }
      state.pos = end + 2;
      return true;
    }

    // $$...$$ inside a paragraph renders as display math
    if (src[start + 1] === '$') {
      const end = src.indexOf('$$', start + 2);
      if (end < 0 || end === start + 2) return false;
      if (!silent) {
        const token = state.push('math_display', 'div', 0);
        token.content = src.slice(start + 2, end).trim();
      }
      state.pos = end + 2;
      return true;
    }

    // $...$: no whitespace just inside the delimiters, no digit right after.
    const next = src[start + 1];
    if (!next || /\s/.test(next)) return false;
    if (start > 0 && src[start - 1] === '\\') return false;
    let end = start + 1;
    while ((end = src.indexOf('$', end)) >= 0) {
      if (src[end - 1] !== '\\') break;
      end++;
    }
    if (end < 0) return false;
    if (/\s/.test(src[end - 1]) || /\d/.test(src[end + 1] || '')) return false;
    if (!silent) {
      const token = state.push('math_inline', 'span', 0);
      token.content = src.slice(start + 1, end);
    }
    state.pos = end + 1;
    return true;
  });

  md.block.ruler.before('fence', 'math_block', (state, startLine, endLine, silent) => {
    const lineStart = state.bMarks[startLine] + state.tShift[startLine];
    const lineEnd = state.eMarks[startLine];
    if (state.sCount[startLine] - state.blkIndent >= 4) return false;
    if (state.src.slice(lineStart, lineStart + 2) !== '$$') return false;

    const firstLine = state.src.slice(lineStart + 2, lineEnd);
    let content;
    let nextLine = startLine;
    if (firstLine.trim().endsWith('$$') && firstLine.trim().length >= 2) {
      content = firstLine.trim().slice(0, -2);
    } else {
      const lines = [firstLine];
      let found = false;
      while (++nextLine < endLine) {
        const s = state.bMarks[nextLine] + state.tShift[nextLine];
        const e = state.eMarks[nextLine];
        const text = state.src.slice(s, e);
        if (text.trim().endsWith('$$')) {
          lines.push(text.trim().slice(0, -2));
          found = true;
          break;
        }
        lines.push(state.src.slice(state.bMarks[nextLine], e));
      }
      if (!found) return false;
      content = lines.join('\n');
    }
    if (silent) return true;
    state.line = nextLine + 1;
    const token = state.push('math_block', 'div', 0);
    token.block = true;
    token.content = content.trim();
    token.map = [startLine, state.line];
    return true;
  });

  const renderMath = (display) => (tokens, idx, _options, env) => {
    const token = tokens[idx];
    const tag = display ? 'div' : 'span';
    const line = token.map ? ` data-line="${token.map[0]}"` : '';
    return `<${tag}${trust(env)} class="mdv-math${display ? ' mdv-math-display' : ''}" data-display="${display}"${line}>${escapeHtml(token.content)}</${tag}>${display && token.block ? '\n' : ''}`;
  };
  md.renderer.rules.math_inline = renderMath(false);
  md.renderer.rules.math_display = renderMath(true);
  md.renderer.rules.math_block = renderMath(true);
}

// --- Alerts: > [!NOTE] etc. (top-level blockquotes only, like GitHub) ------

function alertsPlugin(md) {
  md.core.ruler.after('block', 'github_alerts', (state) => {
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      const open = tokens[i];
      if (open.type !== 'blockquote_open' || open.level !== 0) continue;
      const paragraph = tokens[i + 1];
      const inline = tokens[i + 2];
      if (paragraph?.type !== 'paragraph_open' || inline?.type !== 'inline') continue;
      const match = inline.content.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(\n|$)/i);
      if (!match) continue;
      // Find the matching close at the same nesting level.
      let depth = 0;
      let j = i;
      for (; j < tokens.length; j++) {
        if (tokens[j].type === 'blockquote_open') depth++;
        if (tokens[j].type === 'blockquote_close' && --depth === 0) break;
      }
      const type = match[1].toLowerCase();
      inline.content = inline.content.slice(match[0].length);
      if (inline.content.trim() === '') {
        // Marker on its own paragraph: drop the now-empty paragraph.
        tokens.splice(i + 1, 3);
        j -= 3;
      }
      open.type = 'alert_open';
      open.meta = { type };
      tokens[j].type = 'alert_close';
    }
  });
  md.renderer.rules.alert_open = (tokens, idx, _options, env) => {
    const { type } = tokens[idx].meta;
    const title = type[0].toUpperCase() + type.slice(1);
    const line = tokens[idx].map ? ` data-line="${tokens[idx].map[0]}"` : '';
    return `<div class="markdown-alert markdown-alert-${type}" dir="auto"${line}><p class="markdown-alert-title" dir="auto">${icon(`alert_${type}`, env)}${title}</p>\n`;
  };
  md.renderer.rules.alert_close = () => '</div>\n';
}

// --- Headings with GitHub anchors -----------------------------------------

function headingsPlugin(md) {
  md.core.ruler.push('github_heading_ids', (state) => {
    const seen = new Map();
    for (let i = 0; i < state.tokens.length; i++) {
      const token = state.tokens[i];
      if (token.type !== 'heading_open') continue;
      const inline = state.tokens[i + 1];
      const text = inline.children
        .filter((t) => t.type === 'text' || t.type === 'code_inline' || t.type === 'emoji')
        .map((t) => t.content)
        .join('');
      let slug = slugify(text);
      const base = slug;
      let count = seen.get(base) ?? 0;
      while (seen.has(slug) && count > 0) slug = `${base}-${count++}`;
      if (seen.has(slug)) slug = `${base}-${count++}`;
      seen.set(base, count + (slug === base ? 1 : 0));
      seen.set(slug, seen.get(slug) ?? 1);
      token.meta = { slug, text };
    }
  });
  // The anchor sits inside the heading, the markup github-markdown-css styles
  // (hover shows the link icon in the left margin).
  md.renderer.rules.heading_open = (tokens, idx, _options, env) => {
    const token = tokens[idx];
    const { slug } = token.meta;
    const line = token.map ? ` data-line="${token.map[0]}"` : '';
    return `<${token.tag} tabindex="-1" dir="auto"${line}><a id="user-content-${escapeHtml(slug)}" class="anchor" aria-hidden="true" tabindex="-1" href="#${escapeHtml(slug)}">${icon('link', env)}</a>`;
  };
  md.renderer.rules.heading_close = (tokens, idx) => `</${tokens[idx].tag}>\n`;
}

// --- Code blocks ----------------------------------------------------------

function highlight(code, lang) {
  if (lang && hljs.getLanguage(lang)) {
    try {
      return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
    } catch {
      // fall through to plain text
    }
  }
  return escapeHtml(code);
}

 const copyButton = (env) =>
  `<div class="zeroclipboard-container"><button${trust(env)} class="mdv-copy ClipboardButton btn btn-invisible js-clipboard-copy m-2 p-0 d-flex flex-justify-center flex-items-center" type="button" aria-label="Copy" title="Copy">${icon('copy', env)}${icon('check', env)}</button></div>`;

function codePlugin(md) {
  md.renderer.rules.fence = (tokens, idx, _options, env) => {
    const token = tokens[idx];
    const info = token.info ? md.utils.unescapeAll(token.info).trim() : '';
    const lang = info.split(/\s+/)[0].toLowerCase();
    const line = token.map ? ` data-line="${token.map[0]}"` : '';
    const code = token.content;

    if (lang === 'math') {
      return `<div${trust(env)} class="mdv-math mdv-math-display" data-display="true"${line}>${escapeHtml(code.trim())}</div>\n`;
    }
    if (ENRICHED_LANGS.has(lang)) {
      return `<div${trust(env)} class="mdv-enrich mdv-${lang}" data-kind="${lang}" data-key="${hash(lang + '\n' + code)}"${line}><pre${trust(env)} class="mdv-enrich-source" hidden>${escapeHtml(code)}</pre></div>\n`;
    }
    if (lang) {
      const cls = escapeHtml(lang.replace(/[^\w+#-]/g, ''));
      return `<div class="highlight highlight-source-${cls} notranslate position-relative overflow-auto" dir="auto"${line}><pre><code class="hljs language-${cls}">${highlight(code, lang)}</code></pre>${copyButton(env)}</div>\n`;
    }
    return `<div class="snippet-clipboard-content notranslate position-relative overflow-auto"${line}><pre class="notranslate"><code>${escapeHtml(code)}</code></pre>${copyButton(env)}</div>\n`;
  };
  md.renderer.rules.code_block = (tokens, idx, _options, env) => {
    const token = tokens[idx];
    const line = token.map ? ` data-line="${token.map[0]}"` : '';
    return `<div class="snippet-clipboard-content notranslate position-relative overflow-auto"${line}><pre class="notranslate"><code>${escapeHtml(token.content)}</code></pre>${copyButton(env)}</div>\n`;
  };
}

// --- Footnotes in GitHub's markup ------------------------------------------

function footnoteMarkup(md) {
  const r = md.renderer.rules;
  r.footnote_ref = (tokens, idx) => {
    const id = tokens[idx].meta.id + 1;
    const label = escapeHtml(tokens[idx].meta.label ?? String(id));
    const sub = tokens[idx].meta.subId > 0 ? `-${tokens[idx].meta.subId}` : '';
    return `<sup><a href="#user-content-fn-${label}" id="user-content-fnref-${label}${sub}" data-footnote-ref="" aria-describedby="footnote-label">${id}</a></sup>`;
  };
  r.footnote_block_open = () =>
    '<section data-footnotes="" class="footnotes"><h2 id="footnote-label" class="sr-only" dir="auto">Footnotes</h2>\n<ol>\n';
  r.footnote_block_close = () => '</ol>\n</section>\n';
  r.footnote_open = (tokens, idx) => {
    const label = escapeHtml(tokens[idx].meta.label ?? String(tokens[idx].meta.id + 1));
    return `<li id="user-content-fn-${label}">\n`;
  };
  r.footnote_close = () => '</li>\n';
  r.footnote_anchor = (tokens, idx) => {
    const label = escapeHtml(tokens[idx].meta.label ?? String(tokens[idx].meta.id + 1));
    const sub = tokens[idx].meta.subId > 0 ? `-${tokens[idx].meta.subId}` : '';
    return ` <a href="#user-content-fnref-${label}${sub}" data-footnote-backref="" aria-label="Back to reference ${label}" class="data-footnote-backref">↩</a>`;
  };
}

// --- Source line mapping, table alignment, raw HTML filtering ---------------

function sourceMapPlugin(md) {
  md.core.ruler.push('mdv_source_lines', (state) => {
    for (const token of state.tokens) {
      if (token.map && token.nesting === 1 && token.type !== 'heading_open') {
        token.attrSet('data-line', String(token.map[0]));
      }
      if (token.type === 'th_open' || token.type === 'td_open') {
        const style = token.attrGet('style');
        if (style) {
          const align = style.match(/text-align:\s*(left|right|center)/);
          token.attrs = token.attrs.filter(([name]) => name !== 'style');
          if (align) token.attrSet('align', align[1]);
        }
      }
    }
  });
}

// Filters user-written HTML. Registered right after the inline rule, before
// the task-lists plugin inserts its own checkbox HTML tokens.
function rawHtmlPlugin(md) {
  md.core.ruler.after('inline', 'mdv_raw_html', (state) => {
    // Inline footnotes (^[...]) keep their tokens in env until footnote_tail.
    for (const note of state.env.footnotes?.list ?? []) {
      for (const child of note?.tokens ?? []) {
        if (child.type === 'html_inline') child.content = filterRawHtml(child.content);
      }
    }
    for (const token of state.tokens) {
      if (token.type === 'html_block') token.content = filterRawHtml(token.content);
      if (token.type === 'inline' && token.children) {
        for (const child of token.children) {
          if (child.type === 'html_inline') child.content = filterRawHtml(child.content);
        }
      }
    }
  });
}

function tablesPlugin(md) {
  const open = md.renderer.rules.table_open || ((t, i, o, e, self) => self.renderToken(t, i, o));
  const close = md.renderer.rules.table_close || ((t, i, o, e, self) => self.renderToken(t, i, o));
  md.renderer.rules.table_open = (...args) => `<markdown-accessiblity-table>${open(...args)}`;
  md.renderer.rules.table_close = (...args) => `${close(...args)}</markdown-accessiblity-table>`;
}

// GitHub autolinks www.example.com but not a bare example.com.
function autolinkPlugin(md) {
  md.core.ruler.after('linkify', 'github_autolinks', (state) => {
    for (const block of state.tokens) {
      if (block.type !== 'inline' || !block.children) continue;
      const out = [];
      const children = block.children;
      for (let i = 0; i < children.length; i++) {
        const t = children[i];
        if (t.type === 'link_open' && t.markup === 'linkify') {
          const text = children[i + 1]?.content ?? '';
          if (!/^(?:[a-z][a-z0-9+.-]*:|www\.)/i.test(text) && !text.includes('@')) {
            // Unwrap: keep the text token, drop the open/close pair.
            out.push(children[i + 1]);
            i += 2;
            continue;
          }
        }
        out.push(t);
      }
      block.children = out;
    }
  });
}

// --- Front matter: GitHub shows YAML front matter as a table ----------------

function renderYamlValue(value) {
  if (value === null || value === undefined) return '';
  if (Array.isArray(value)) {
    return `<table><tbody><tr>${value.map((v) => `<td><div>${renderYamlValue(v)}</div></td>`).join('')}</tr></tbody></table>`;
  }
  if (value instanceof Date) return escapeHtml(value.toISOString());
  if (typeof value === 'object') return renderYamlTable(value);
  return escapeHtml(String(value));
}

function renderYamlTable(obj) {
  const keys = Object.keys(obj);
  const head = keys.map((k) => `<th>${escapeHtml(k)}</th>`).join('');
  const body = keys.map((k) => `<td><div>${renderYamlValue(obj[k])}</div></td>`).join('');
  return `<table><thead><tr>${head}</tr></thead><tbody><tr>${body}</tr></tbody></table>`;
}

export function extractFrontMatter(source) {
  const match = source.match(/^---[ \t]*\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/);
  if (!match) return { body: source, html: '' };
  let data;
  try {
    data = loadYaml(match[1]);
  } catch {
    return { body: source, html: '' };
  }
  // Keep line numbers stable for scroll sync by blanking the block.
  const blank = '\n'.repeat(match[0].split('\n').length - 1);
  const body = blank + source.slice(match[0].length);
  if (!data || typeof data !== 'object' || Array.isArray(data)) return { body, html: '' };
  return { body, html: `<markdown-accessiblity-table data-line="0">${renderYamlTable(data)}</markdown-accessiblity-table>\n` };
}

// --- Public API -------------------------------------------------------------

export function createMarkdown() {
  const md = new MarkdownIt({ html: true, linkify: true, typographer: false, breaks: false });
  md.linkify.set({ fuzzyLink: true, fuzzyEmail: true });
  md.use(mathPlugin)
    .use(footnote)
    .use(taskLists, { enabled: false, label: false })
    .use(rawHtmlPlugin)
    .use(emoji)
    .use(alertsPlugin)
    .use(headingsPlugin)
    .use(codePlugin)
    .use(footnoteMarkup)
    .use(tablesPlugin)
    .use(autolinkPlugin)
    .use(sourceMapPlugin);
  md.disable('smartquotes');
  return md;
}

let shared;
export function renderMarkdown(source, { nonce } = {}) {
  shared ??= createMarkdown();
  // GitHub ignores a leading byte order mark.
  const text = source.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  const { body, html: frontMatter } = extractFrontMatter(text);
  return frontMatter + shared.render(body, { nonce });
}
