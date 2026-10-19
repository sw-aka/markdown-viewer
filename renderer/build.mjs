// Bundles the renderer into the app's resources. Run `npm run build` after
// changing anything under src/ and commit the output (the Xcode build does
// not run Node).
import { build } from 'esbuild';
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const out = join(root, '..', 'MarkdownViewer', 'Resources', 'Renderer');
const mod = (p) => join(root, 'node_modules', p);

rmSync(out, { recursive: true, force: true });
mkdirSync(join(out, 'vendor', 'mathjax'), { recursive: true });

await build({
  entryPoints: [join(root, 'src', 'main.js')],
  bundle: true,
  minify: true,
  format: 'iife',
  target: 'safari18',
  outfile: join(out, 'renderer.js'),
  legalComments: 'none',
  logLevel: 'warning',
});

const read = (p) => readFileSync(p, 'utf8');
const css = [
  '/* github-markdown-css (MIT) */',
  read(mod('github-markdown-css/github-markdown.css')),
  '/* highlight.js GitHub themes (BSD-3-Clause) */',
  `@media (prefers-color-scheme: light) {\n${read(mod('highlight.js/styles/github.css'))}\n}`,
  `@media (prefers-color-scheme: dark) {\n${read(mod('highlight.js/styles/github-dark.css'))}\n}`,
  '/* Leaflet (BSD-2-Clause) */',
  read(mod('leaflet/dist/leaflet.css')),
  read(join(root, 'src', 'app.css')),
].join('\n');
writeFileSync(join(out, 'renderer.css'), css);

cpSync(join(root, 'src', 'index.html'), join(out, 'index.html'));
cpSync(mod('mermaid/dist/mermaid.min.js'), join(out, 'vendor', 'mermaid.min.js'));
cpSync(mod('mathjax/es5/tex-svg-full.js'), join(out, 'vendor', 'mathjax', 'tex-svg-full.js'));

console.log(`Renderer written to ${out}`);
