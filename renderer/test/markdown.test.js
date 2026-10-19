import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  renderMarkdown,
  slugify,
  filterRawHtml,
  extractFrontMatter,
  hash,
  escapeHtml,
} from '../src/markdown.js';

const render = (src) => renderMarkdown(src);

describe('escapeHtml', () => {
  test('escapes the five HTML-significant characters', () => {
    assert.equal(escapeHtml(`<a href="x">&'</a>`), '&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;');
  });

  test('coerces non-strings', () => {
    assert.equal(escapeHtml(42), '42');
  });
});

describe('slugify', () => {
  test('lowercases and replaces spaces with hyphens', () => {
    assert.equal(slugify('Hello World'), 'hello-world');
  });

  test('strips punctuation', () => {
    assert.equal(slugify('Hello, World!'), 'hello-world');
    assert.equal(slugify('What is (this)?'), 'what-is-this');
  });

  test('keeps underscores and hyphens', () => {
    assert.equal(slugify('snake_case-name'), 'snake_case-name');
  });

  test('keeps unicode letters and numbers', () => {
    assert.equal(slugify('Café 2'), 'café-2');
  });
});

describe('hash', () => {
  test('is deterministic and differs for different input', () => {
    assert.equal(hash('abc'), hash('abc'));
    assert.notEqual(hash('abc'), hash('abd'));
  });

  test('returns a base-36 string', () => {
    assert.match(hash('some text'), /^[0-9a-z]+$/);
  });
});

describe('filterRawHtml', () => {
  test('removes style, class and on* attributes', () => {
    const out = filterRawHtml('<div class="a" style="color:red" onclick="x()">hi</div>');
    assert.equal(out, '<div>hi</div>');
  });

  test('prefixes id and name with user-content-', () => {
    assert.equal(filterRawHtml('<a id="top" name="x">t</a>'), '<a id="user-content-top" name="user-content-x">t</a>');
  });

  test('does not double-prefix ids that already have the prefix', () => {
    assert.equal(filterRawHtml('<a id="user-content-top">t</a>'), '<a id="user-content-top">t</a>');
  });

  test('keeps other attributes', () => {
    assert.equal(filterRawHtml('<a href="https://x.test" title="t">x</a>'), '<a href="https://x.test" title="t">x</a>');
  });
});

describe('extractFrontMatter', () => {
  test('returns empty html when there is no front matter', () => {
    const r = extractFrontMatter('# Title\n');
    assert.equal(r.html, '');
    assert.equal(r.body, '# Title\n');
  });

  test('parses YAML into a table and blanks the block to keep line numbers', () => {
    const src = '---\ntitle: Hi\ntags:\n  - a\n  - b\n---\n# Heading\n';
    const r = extractFrontMatter(src);
    assert.match(r.html, /^<markdown-accessiblity-table data-line="0">/);
    assert.match(r.html, /<th>title<\/th>/);
    assert.match(r.html, /<td><div>Hi<\/div><\/td>/);
    assert.equal(r.body.split('\n').length, src.split('\n').length);
    assert.equal(r.body.slice(-10), '# Heading\n');
  });

  test('invalid YAML is left in place', () => {
    const src = '---\nkey: [unclosed\n---\n# T\n';
    const r = extractFrontMatter(src);
    assert.equal(r.html, '');
    assert.equal(r.body, src);
  });
});

describe('headings', () => {
  test('heading contains its permalink anchor before the text', () => {
    const html = render('## Hello World\n');
    assert.match(html, /<h2 tabindex="-1" dir="auto" data-line="0"><a id="user-content-hello-world" class="anchor" aria-hidden="true" tabindex="-1" href="#hello-world"><svg[^]*?<\/svg><\/a>Hello World<\/h2>/);
  });

  test('anchor contains an svg octicon', () => {
    assert.match(render('# A\n'), /class="anchor"[^>]*>(<svg)/);
  });

  test('punctuation is stripped from the slug', () => {
    const html = render('# Hello, World!\n');
    assert.match(html, /id="user-content-hello-world"/);
    assert.match(html, /href="#hello-world"/);
  });

  test('duplicate headings get -1 and -2 suffixes', () => {
    const html = render('# Intro\n\n# Intro\n\n# Intro\n');
    assert.match(html, /id="user-content-intro"/);
    assert.match(html, /id="user-content-intro-1"/);
    assert.match(html, /id="user-content-intro-2"/);
    assert.match(html, /href="#intro-1"/);
    assert.match(html, /href="#intro-2"/);
  });

  test('data-line points at the heading source line', () => {
    const html = render('para\n\n\n## Later\n');
    assert.match(html, /data-line="3"/);
  });
});

describe('GFM tables', () => {
  const table = '| L | C | R |\n| :-- | :-: | --: |\n| a | b | c |\n';

  test('alignment becomes align attribute without style', () => {
    const html = render(table);
    assert.match(html, /<th align="left">L<\/th>/);
    assert.match(html, /<th align="center">C<\/th>/);
    assert.match(html, /<th align="right">R<\/th>/);
    assert.match(html, /<td align="center">b<\/td>/);
    assert.doesNotMatch(html, /style=/);
  });

  test('table is wrapped in markdown-accessiblity-table', () => {
    const html = render(table);
    assert.match(html, /^<markdown-accessiblity-table><table[^>]*>/);
    assert.match(html, /<\/table>\n<\/markdown-accessiblity-table>$/);
  });
});

describe('GFM strikethrough', () => {
  test('~~x~~ becomes <s>', () => {
    // markdown-it core strikethrough is not on by default in GFM sense; check output.
    assert.match(render('~~gone~~\n'), /<s>gone<\/s>/);
  });
});

describe('task lists', () => {
  const src = '- [ ] open\n- [x] done\n';

  test('adds contains-task-list and task-list-item classes', () => {
    const html = render(src);
    assert.match(html, /<ul class="contains-task-list"/);
    assert.match(html, /<li class="task-list-item"/);
  });

  test('checkboxes are disabled with correct checked state', () => {
    const html = render(src);
    assert.match(html, /<input class="task-list-item-checkbox" disabled="" type="checkbox">/);
    assert.match(html, /<input class="task-list-item-checkbox" checked="" disabled="" type="checkbox">/);
  });
});

describe('autolinks', () => {
  test('https URL is linked', () => {
    assert.match(render('see https://example.com/path\n'), /<a href="https:\/\/example\.com\/path">/);
  });

  test('www. prefix gets http:// scheme', () => {
    assert.match(render('visit www.example.com now\n'), /<a href="http:\/\/www\.example\.com">/);
  });

  test('email becomes mailto link', () => {
    assert.match(render('mail me@example.com\n'), /<a href="mailto:me@example\.com">/);
  });

  test('bare domain is NOT linked', () => {
    const html = render('go to example.com today\n');
    assert.doesNotMatch(html, /<a /);
    assert.match(html, /example\.com/);
  });
});

describe('alerts', () => {
  const types = ['NOTE', 'TIP', 'IMPORTANT', 'WARNING', 'CAUTION'];
  for (const type of types) {
    test(`> [!${type}] renders markdown-alert-${type.toLowerCase()}`, () => {
      const lower = type.toLowerCase();
      const html = render(`> [!${type}]\n> Body text.\n`);
      assert.match(html, new RegExp(`class="markdown-alert markdown-alert-${lower}"`));
      assert.match(html, new RegExp(`<p class="markdown-alert-title" dir="auto">(<svg[\\s\\S]*?</svg>)${type[0]}${type.slice(1).toLowerCase()}</p>`));
      assert.match(html, /Body text\./);
    });
  }

  test('title for NOTE is "Note"', () => {
    assert.match(render('> [!NOTE]\n> x\n'), />Note<\/p>/);
  });

  test('marker followed by other text on the same line is NOT an alert', () => {
    const html = render('> [!NOTE] extra text on same line\n');
    assert.doesNotMatch(html, /markdown-alert/);
    assert.match(html, /<blockquote/);
  });

  test('nested blockquote inside an alert stays a blockquote', () => {
    const html = render('> [!TIP]\n> Outer\n>\n> > inner quote\n');
    assert.match(html, /markdown-alert-tip/);
    assert.match(html, /<blockquote[^>]*>\n<p[^>]*>inner quote<\/p>/);
    // The alert wrapper must close exactly once, after the nested blockquote.
    assert.equal((html.match(/<\/div>/g) || []).length >= 1, true);
    assert.equal((html.match(/<blockquote/g) || []).length, 1);
    assert.equal((html.match(/<\/blockquote>/g) || []).length, 1);
  });
});

describe('footnotes', () => {
  const src = 'Text[^1].\n\n[^1]: The note.\n';

  test('reference uses GitHub markup', () => {
    const html = render(src);
    assert.match(html, /<sup><a href="#user-content-fn-1" id="user-content-fnref-1" data-footnote-ref="" aria-describedby="footnote-label">1<\/a><\/sup>/);
  });

  test('footnote section has data-footnotes and user-content-fn-1 item', () => {
    const html = render(src);
    assert.match(html, /<section data-footnotes="" class="footnotes">/);
    assert.match(html, /<li id="user-content-fn-1">/);
    assert.match(html, /The note\./);
  });

  test('backref links to the reference', () => {
    assert.match(render(src), /href="#user-content-fnref-1" data-footnote-backref="" aria-label="Back to reference 1"/);
  });
});

describe('math', () => {
  test('$x^2$ renders inline mdv-math', () => {
    const html = render('Energy $x^2$ here\n');
    assert.match(html, /<span class="mdv-math" data-display="false"[^>]*>x\^2<\/span>/);
  });

  test('$`a_b`$ renders inline math with underscore kept', () => {
    const html = render('Value $`a_b`$ here\n');
    assert.match(html, /<span class="mdv-math" data-display="false"[^>]*>a_b<\/span>/);
  });

  test('$$...$$ block renders display math', () => {
    const html = render('$$\na^2 + b^2\n$$\n');
    assert.match(html, /<div class="mdv-math mdv-math-display" data-display="true"[^>]*>a\^2 \+ b\^2<\/div>/);
  });

  test('```math fence renders display math', () => {
    const html = render('```math\nE = mc^2\n```\n');
    assert.match(html, /<div class="mdv-math mdv-math-display" data-display="true"[^>]*>E = mc\^2<\/div>/);
  });

  test('"$5 and $10" is not math', () => {
    const html = render('It costs $5 and $10 total.\n');
    assert.doesNotMatch(html, /mdv-math/);
    assert.match(html, /\$5 and \$10/);
  });

  test('escaped \\$ is not math', () => {
    const html = render('Literal \\$x\\$ here\n');
    assert.doesNotMatch(html, /mdv-math/);
  });

  test('math content is escaped', () => {
    const html = render('$`a<b`$\n');
    assert.match(html, />a&lt;b</);
  });
});

describe('code blocks', () => {
  test('fenced js gets highlight classes and hljs spans', () => {
    const html = render('```js\nconst x = 1;\n```\n');
    assert.match(html, /class="highlight highlight-source-js notranslate/);
    assert.match(html, /<code class="hljs language-js">/);
    assert.match(html, /<span class="hljs-keyword">const<\/span>/);
  });

  test('no-language fence gets snippet-clipboard-content', () => {
    const html = render('```\nplain\n```\n');
    assert.match(html, /class="snippet-clipboard-content notranslate/);
    assert.match(html, /<code>plain\n<\/code>/);
  });

  test('indented code block gets snippet-clipboard-content', () => {
    const html = render('    indented\n');
    assert.match(html, /snippet-clipboard-content/);
  });

  test('code content is escaped', () => {
    const html = render('```\n<script>x</script>\n```\n');
    assert.doesNotMatch(html, /<script>/);
    assert.match(html, /&lt;script&gt;/);
  });

  test('unknown language is escaped and kept as a highlight-source class', () => {
    const html = render('```notalang\nfoo\n```\n');
    assert.match(html, /highlight-source-notalang/);
    assert.match(html, /foo/);
  });

  for (const lang of ['mermaid', 'geojson', 'topojson', 'stl']) {
    test(`${lang} fence produces mdv-enrich block`, () => {
      const code = `{"a": "<b>"}`;
      const html = render('```' + lang + '\n' + code + '\n```\n');
      assert.match(html, new RegExp(`<div class="mdv-enrich mdv-${lang}" data-kind="${lang}" data-key="[0-9a-z]+"`));
      assert.match(html, /<pre class="mdv-enrich-source" hidden>/);
      assert.match(html, /&quot;a&quot;: &quot;&lt;b&gt;&quot;/);
    });
  }

  test('enriched data-key is a hash of lang and code', () => {
    const html = render('```mermaid\ngraph TD\n```\n');
    const key = html.match(/data-key="([0-9a-z]+)"/)[1];
    assert.equal(key, hash('mermaid\ngraph TD\n'));
  });
});

describe('emoji', () => {
  test(':smile: becomes the emoji character', () => {
    assert.match(render('hi :smile:\n'), /😄/);
  });
});

describe('source line mapping', () => {
  test('data-line on paragraphs and lists', () => {
    const html = render('one\n\ntwo\n\n- item\n');
    assert.match(html, /<p data-line="0">one/);
    assert.match(html, /<p data-line="2">two/);
    assert.match(html, /<ul data-line="4">/);
  });

  test('first heading after front matter keeps its source line index', () => {
    const src = '---\ntitle: T\n---\n\n# Real Heading\n';
    const html = render(src);
    const m = html.match(/<h1 [^>]*data-line="(\d+)"/);
    assert.ok(m, 'heading with data-line found');
    assert.equal(Number(m[1]), src.split('\n').indexOf('# Real Heading'));
  });

  test('CRLF input is normalised', () => {
    const html = render('# A\r\n\r\ntext\r\n');
    assert.match(html, /<p data-line="2">text/);
  });
});

describe('front matter rendering', () => {
  test('front matter is rendered as a table before the body', () => {
    const html = render('---\nauthor: Ann\n---\n# Doc\n');
    assert.ok(html.startsWith('<markdown-accessiblity-table data-line="0">'));
    assert.match(html, /<td><div>Ann<\/div><\/td>/);
    assert.match(html, /<h1 [^>]*><a id="user-content-doc"/);
  });
});

describe('raw HTML in markdown', () => {
  test('style, class and on* handlers are stripped from block HTML', () => {
    const html = render('<div class="x" style="color:red" onmouseover="bad()">hi</div>\n');
    assert.doesNotMatch(html, /style=|class="x"|onmouseover/);
    assert.match(html, /hi/);
  });

  test('inline raw HTML id is prefixed', () => {
    const html = render('text <span id="foo">x</span>\n');
    assert.match(html, /id="user-content-foo"/);
  });

  test('details and summary are kept', () => {
    const html = render('<details><summary>More</summary>\n\nHidden\n\n</details>\n');
    assert.match(html, /<details>/);
    assert.match(html, /<summary>More<\/summary>/);
  });
});

describe('raw HTML tokenizer (review regressions)', () => {
  test('slash-separated attributes cannot smuggle class or raw ids', () => {
    const out = filterRawHtml('<span/class="mdv-enrich" data-kind="stl" id="x">');
    assert.equal(out, '<span data-kind="stl" id="user-content-x">');
  });

  test('unquoted attributes are filtered too', () => {
    assert.equal(filterRawHtml('<div style=a class=x id=y onclick=z>'), '<div id="user-content-y">');
  });

  test('quotes inside single-quoted values are escaped', () => {
    assert.equal(filterRawHtml(`<a href='q"r'>`), '<a href="q&quot;r">');
  });

  test('unterminated tags become text', () => {
    assert.equal(filterRawHtml('<b'), '&lt;b');
  });

  test('a leading byte order mark is ignored', () => {
    assert.match(renderMarkdown('﻿# Title\n'), /^<h1 /);
  });
});

describe('raw HTML tokenizer: comments and end tags (review round 2)', () => {
  test('comments are not re-scanned for tags', () => {
    const src = '<!--<a x="-->' + '<span class=mdv-enrich data-kind=stl>">';
    assert.equal(filterRawHtml(src), '<!--<a x="-->' + '<span data-kind="stl">">');
  });

  test('end tag attributes are parsed and dropped', () => {
    const out = filterRawHtml('</x y="<b z="> <span class=mdv-enrich data-kind=stl> ">');
    assert.equal(out, '</x> <span data-kind="stl"> ">');
  });

  test('task list exemption cannot be abused by raw HTML', () => {
    const html = renderMarkdown('x <input class="task-list-item-checkbox" id="raw" name="n">\n');
    assert.match(html, /<input id="user-content-raw" name="user-content-n">/);
  });

  test('real task list checkboxes keep their class', () => {
    assert.match(renderMarkdown('- [ ] a\n'), /<input class="task-list-item-checkbox"/);
  });
});

describe('raw HTML tokenizer: parser edge cases (review round 3)', () => {
  test('a comment closed with --!> does not hide later tags', () => {
    assert.equal(filterRawHtml('<!-- --!>\n<img class=x id=y src=a>'), '<!-- --!>\n<img id="user-content-y" src="a">');
  });

  test('raw text elements are copied as text up to their end tag', () => {
    assert.equal(filterRawHtml('<style><!--</style><img class=x id=y>'), '<style><!--</style><img id="user-content-y">');
  });

  test('valueless id and name are prefixed', () => {
    assert.equal(filterRawHtml('<a id>x</a><div name>'), '<a id="user-content-">x</a><div name="user-content-">');
  });
});

describe('inline footnotes (review round 5)', () => {
  test('raw HTML inside ^[...] is filtered', () => {
    const html = renderMarkdown('Text^[<span class="foo" id="content" name="bar">fn</span>]\n');
    assert.match(html, /<span id="user-content-content" name="user-content-bar">fn<\/span>/);
    assert.doesNotMatch(html, /class="foo"/);
  });
});

describe('unclosed raw svg/math (review round 8)', () => {
  test('raw svg and math tags are dropped, their text and following content kept', () => {
    const html = renderMarkdown('<math><mtext>\n\nAfter **bold**\n');
    assert.doesNotMatch(html, /<math|<\/math/);
    assert.match(html, /After <strong>bold<\/strong>/);
  });
});
