// HTML sanitizing modelled on GitHub's allowlist: no scripts, styles, frames,
// forms or event handlers. Relative URLs are rewritten against the open
// document's folder so local images and links resolve.

const FORBID_TAGS = [
  'script', 'style', 'iframe', 'frame', 'frameset', 'object', 'embed', 'applet',
  'form', 'textarea', 'select', 'option', 'link', 'meta', 'base', 'title', 'noscript',
  // Top-layer and open-by-default overlays (GitHub strips them too).
  'dialog',
];

const FORBID_ATTR = ['style', 'popover', 'popovertarget', 'popovertargetaction', 'command', 'commandfor'];

const SAFE_SRCSET_URL = /^(?:https?:|mdv:|data:image\/(?:png|gif|jpe?g|webp);)/i;
const ABSOLUTE_URL = /^(?:[a-z][a-z0-9+.-]*:|\/\/|#)/i;

export function resolveRelative(url, baseURL) {
  if (!baseURL || !url || ABSOLUTE_URL.test(url)) return url;
  try {
    return new URL(url, baseURL).href;
  } catch {
    return url;
  }
}

// Classes the app's scripts act on. Only markup the renderer generated (marked
// with this render's nonce) may carry them.
const HOOK_CLASSES = ['mdv-enrich', 'mdv-enrich-source', 'mdv-math', 'mdv-math-display', 'mdv-copy'];

export function createSanitizer(DOMPurify) {
  let baseURL = null;
  let nonce = null;

  // GitHub strips raw <svg> and <math>: they can draw outside their box. Only
  // the renderer's own icons (carrying the nonce) are kept.
  DOMPurify.addHook('uponSanitizeElement', (node, data) => {
    if ((data.tagName === 'svg' || data.tagName === 'math') && !(nonce && node.getAttribute?.('data-mdv-nonce') === nonce)) {
      node.remove();
    }
  });

  DOMPurify.addHook('afterSanitizeAttributes', (node) => {
    for (const attr of ['src', 'href', 'poster']) {
      if (node.hasAttribute?.(attr)) {
        node.setAttribute(attr, resolveRelative(node.getAttribute(attr), baseURL));
      }
    }
    if (node.hasAttribute?.('srcset')) {
      // DOMPurify checks srcset as one string; check each candidate's URL.
      const srcset = node.getAttribute('srcset')
        .split(',')
        .map((part) => {
          const [url, ...rest] = part.trim().split(/\s+/);
          return [resolveRelative(url, baseURL), ...rest].join(' ');
        })
        .filter((candidate) => SAFE_SRCSET_URL.test(candidate))
        .join(', ');
      if (srcset) node.setAttribute('srcset', srcset);
      else node.removeAttribute('srcset');
    }
    const trusted = nonce && node.getAttribute?.('data-mdv-nonce') === nonce;
    node.removeAttribute?.('data-mdv-nonce');
    if (!trusted && node.classList) {
      for (const name of HOOK_CLASSES) node.classList.remove(name);
      if (node.getAttribute('class') === '') node.removeAttribute('class');
    }

    // Task list checkboxes are read-only in rendered files.
    if (node.tagName === 'INPUT') node.setAttribute('disabled', '');
  });

  return (html, options = {}) => {
    baseURL = options.baseURL ?? null;
    nonce = options.nonce || null;
    return DOMPurify.sanitize(html, {
      FORBID_TAGS,
      FORBID_ATTR,
      ADD_TAGS: ['markdown-accessiblity-table'],
      ADD_ATTR: ['data-footnote-ref', 'data-footnote-backref', 'data-footnotes', 'aria-describedby', 'tabindex'],
      ALLOW_DATA_ATTR: true,
      // DOMPurify's default schemes plus mdv: (local files served by the app).
      ALLOWED_URI_REGEXP: /^(?:(?:(?:f|ht)tps?|mailto|tel|mdv):|[^a-z]|[a-z+.-]+(?:[^a-z+.\-:]|$))/i,
    });
  };
}
