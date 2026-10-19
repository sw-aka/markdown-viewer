import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import createDOMPurify from 'dompurify';
import { createSanitizer, resolveRelative } from '../src/sanitize.js';
import { renderMarkdown } from '../src/markdown.js';

const purify = createDOMPurify(new JSDOM('').window);
const sanitize = createSanitizer(purify);
const BASE = 'mdv://doc/Users/a/b/';

describe('resolveRelative', () => {
  test('resolves relative paths against baseURL', () => {
    assert.equal(resolveRelative('img/x.png', BASE), 'mdv://doc/Users/a/b/img/x.png');
  });

  test('leaves absolute https URLs alone', () => {
    assert.equal(resolveRelative('https://example.com/a.png', BASE), 'https://example.com/a.png');
  });

  test('leaves fragment-only URLs alone', () => {
    assert.equal(resolveRelative('#intro', BASE), '#intro');
  });

  test('returns the url unchanged without a baseURL', () => {
    assert.equal(resolveRelative('img/x.png', null), 'img/x.png');
  });
});

describe('sanitize: dangerous content', () => {
  test('removes script elements', () => {
    assert.doesNotMatch(sanitize('<p>a</p><script>alert(1)</script>'), /script/i);
  });

  test('removes style elements', () => {
    assert.doesNotMatch(sanitize('<style>p{color:red}</style><p>a</p>'), /<style/i);
  });

  test('removes iframe elements', () => {
    assert.doesNotMatch(sanitize('<iframe src="https://x.test"></iframe>'), /iframe/i);
  });

  test('removes style attributes', () => {
    assert.doesNotMatch(sanitize('<p style="color:red">a</p>'), /style=/);
  });

  test('removes javascript: hrefs', () => {
    const out = sanitize('<a href="javascript:alert(1)">x</a>');
    assert.doesNotMatch(out, /javascript:/i);
  });

  test('removes event handler attributes', () => {
    assert.doesNotMatch(sanitize('<img src="https://x.test/a.png" onerror="bad()">'), /onerror/);
  });
});

describe('sanitize: URL rewriting', () => {
  test('relative img src is resolved against baseURL', () => {
    const out = sanitize('<img src="img/x.png">', { baseURL: BASE });
    assert.match(out, /src="mdv:\/\/doc\/Users\/a\/b\/img\/x\.png"/);
  });

  test('absolute https img src is untouched', () => {
    const out = sanitize('<img src="https://example.com/a.png">', { baseURL: BASE });
    assert.match(out, /src="https:\/\/example\.com\/a\.png"/);
  });

  test('fragment href is untouched', () => {
    assert.match(sanitize('<a href="#frag">x</a>', { baseURL: BASE }), /href="#frag"/);
  });

  test('relative href is resolved against baseURL', () => {
    assert.match(sanitize('<a href="../c.md">x</a>', { baseURL: BASE }), /href="mdv:\/\/doc\/Users\/a\/c\.md"/);
  });

  test('srcset entries are resolved', () => {
    const out = sanitize('<img srcset="a.png 1x, b.png 2x" src="a.png">', { baseURL: BASE });
    assert.match(out, /srcset="mdv:\/\/doc\/Users\/a\/b\/a\.png 1x, mdv:\/\/doc\/Users\/a\/b\/b\.png 2x"/);
  });

  test('mdv: scheme is allowed', () => {
    assert.match(sanitize('<a href="mdv://doc/x">x</a>'), /href="mdv:\/\/doc\/x"/);
  });
});

describe('sanitize: inputs', () => {
  test('input elements are disabled', () => {
    const out = sanitize('<input type="checkbox" checked>');
    assert.match(out, /<input[^>]*disabled=""/);
    assert.match(out, /checked/);
  });

  test('forms and textareas are removed', () => {
    const out = sanitize('<form><textarea>x</textarea><select><option>a</option></select></form><p>ok</p>');
    assert.doesNotMatch(out, /<form|<textarea|<select|<option/);
    assert.match(out, /<p>ok<\/p>/);
  });
});

describe('sanitize: allowed markup', () => {
  test('svg inside a heading anchor survives', () => {
    const html = renderMarkdown('# Title\n', { nonce: 'n9' });
    const out = sanitize(html, { baseURL: BASE, nonce: 'n9' });
    assert.match(out, /<a id="user-content-title"[^>]*class="anchor"[^>]*>[\s\S]*<svg/);
    assert.match(out, /href="#title"/);
  });

  test('data-* attributes are kept', () => {
    const out = sanitize('<div data-line="4" data-kind="stl">x</div>');
    assert.match(out, /data-line="4"/);
    assert.match(out, /data-kind="stl"/);
  });

  test('markdown-accessiblity-table custom element is kept', () => {
    const out = sanitize('<markdown-accessiblity-table><table><tr><td>1</td></tr></table></markdown-accessiblity-table>');
    assert.match(out, /<markdown-accessiblity-table>/);
  });

  test('details and summary are kept', () => {
    const out = sanitize('<details><summary>S</summary>b</details>');
    assert.match(out, /<details><summary>S<\/summary>b<\/details>/);
  });

  test('footnote data attributes are kept', () => {
    const out = sanitize('<a href="#x" data-footnote-ref="">1</a>');
    assert.match(out, /data-footnote-ref=""/);
  });
});

describe('hook classes need the render nonce (review regressions)', () => {
  test('generated blocks keep their hook classes with the right nonce', async () => {
    const { renderMarkdown } = await import('../src/markdown.js');
    const html = renderMarkdown('```mermaid\ngraph TD; A-->B\n```\n\n$x$\n', { nonce: 'n1' });
    const out = sanitize(html, { nonce: 'n1' });
    assert.match(out, /class="mdv-enrich mdv-mermaid"/);
    assert.match(out, /class="mdv-math"/);
    assert.doesNotMatch(out, /data-mdv-nonce/);
  });

  test('user HTML cannot forge hook classes, even with a guessed nonce attribute', () => {
    const out = sanitize('<div class="mdv-enrich x" data-mdv-nonce="wrong" data-kind="stl">y</div>', { nonce: 'n1' });
    assert.doesNotMatch(out, /mdv-enrich/);
    assert.match(out, /class="x"/);
  });

  test('without a nonce no hook classes survive', () => {
    assert.doesNotMatch(sanitize('<span class="mdv-math" data-mdv-nonce="">x</span>'), /mdv-math/);
  });
});

describe('srcset candidates (review round 3)', () => {
  test('javascript: candidates are dropped from srcset', () => {
    const out = sanitize('<img srcset="a.png 1x, javascript:alert(1) 2x, JaVaScRiPt:x 3x" src="a.png">', { baseURL: 'mdv://doc/d/' });
    assert.match(out, /srcset="mdv:\/\/doc\/d\/a\.png 1x"/);
    assert.doesNotMatch(out, /javascript/i);
  });
});

describe('overlays (review round 6)', () => {
  test('popover attributes and dialog are removed', () => {
    const out = sanitize('<div popover id="ov">x</div><button popovertarget="ov" command="show-modal" commandfor="d">b</button><dialog open>d</dialog>');
    assert.doesNotMatch(out, /popover|command|<dialog/);
  });
});

describe('raw svg and math (review round 7)', () => {
  test('user <svg> and <math> are removed, renderer icons kept', () => {
    const src = '> [!NOTE]\n> hi\n\n<svg width="10" overflow="visible"><rect width="9999" height="9999"/></svg>\n\n<math><mpadded voffset="-300px"><mi>x</mi></mpadded></math>\n';
    const out = sanitize(renderMarkdown(src, { nonce: 'n9' }), { nonce: 'n9' });
    assert.doesNotMatch(out, /<rect|<math|mpadded/);
    assert.match(out, /<svg class="octicon octicon-info/);
  });

  test('a forged nonce on user svg does not help', () => {
    assert.doesNotMatch(sanitize('<svg data-mdv-nonce="guess"><rect/></svg>', { nonce: 'n9' }), /<svg/);
  });
});
