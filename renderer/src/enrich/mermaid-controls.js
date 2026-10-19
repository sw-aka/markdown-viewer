// Attach handlers only to our own buttons, never to document-controlled SVG.
export function addMermaidControls(host, diagram) {
  const svg = diagram.querySelector('svg');
  if (!svg) return;
  const viewer = document.createElement('div');
  viewer.className = 'mdv-diagram-viewer';
  const viewport = document.createElement('div');
  viewport.className = 'mdv-diagram-viewport';
  const box = svg.viewBox?.baseVal;
  if (box?.width > 0 && box?.height > 0) viewport.style.aspectRatio = `${box.width} / ${box.height}`;
  host.replaceChildren(viewer);
  viewport.append(diagram);
  viewer.append(viewport);
  let scale = 1, x = 0, y = 0;
  let dialog = null;
  let previousFocus = null;
  const paint = () => { diagram.style.transform = `translate(${x}px, ${y}px) scale(${scale})`; };
  const reset = () => { scale = 1; x = y = 0; paint(); };
  const zoom = (factor) => { scale = Math.min(8, Math.max(0.25, scale * factor)); paint(); };
  const button = (label, path, action, parent) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.title = label;
    b.setAttribute('aria-label', label);
    b.innerHTML = `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${path}"/></svg>`;
    b.addEventListener('click', action);
    parent.append(b);
    return b;
  };
  const top = document.createElement('div');
  top.className = 'mdv-diagram-controls mdv-diagram-top';
  viewer.append(top);
  const close = () => {
    if (!dialog) return;
    host.append(viewer);
    host.style.minHeight = '';
    dialog.close();
    dialog.remove();
    dialog = null;
    reset();
    previousFocus?.focus({ preventScroll: true });
  };
  button('Expand diagram', 'M3 12h18 M7 8l-4 4 4 4 M17 8l4 4-4 4', () => {
    if (dialog) { close(); return; }
    previousFocus = document.activeElement;
    host.style.minHeight = `${host.getBoundingClientRect().height}px`;
    dialog = document.createElement('dialog');
    dialog.className = 'markdown-body mdv-diagram-dialog';
    dialog.setAttribute('aria-label', 'Expanded Mermaid diagram');
    dialog.tabIndex = -1;
    dialog.autofocus = true;
    const dismiss = button('Close expanded diagram', 'M6 6l12 12 M18 6L6 18', close, dialog);
    dismiss.className = 'mdv-diagram-close';
    dialog.append(viewer);
    document.body.append(dialog);
    dialog.addEventListener('cancel', (event) => { event.preventDefault(); close(); });
    dialog.addEventListener('click', (event) => { if (event.target === dialog) close(); });
    reset();
    dialog.showModal();
    // Focus the dialog itself on opening, leaving the close button's focus
    // ring for keyboard navigation rather than pointer-triggered expansion.
    dialog.focus({ preventScroll: true });
  }, top);
  const controls = document.createElement('div');
  controls.className = 'mdv-diagram-controls mdv-diagram-navigation';
  viewer.append(controls);
  const commands = [
    ['Pan up', 'M6 14l6-6 6 6', () => { y += 60; paint(); }, 'up'],
    ['Zoom in', 'M10 4a6 6 0 1 0 0 12 6 6 0 0 0 0-12 M14.5 14.5L21 21 M7 10h6 M10 7v6', () => zoom(1.25), 'in'],
    ['Pan left', 'M14 6l-6 6 6 6', () => { x += 60; paint(); }, 'left'],
    ['Reset diagram', 'M20 7v5h-5 M20 12a8 8 0 1 0-2 6', reset, 'reset'],
    ['Pan right', 'M10 6l6 6-6 6', () => { x -= 60; paint(); }, 'right'],
    ['Pan down', 'M6 10l6 6 6-6', () => { y -= 60; paint(); }, 'down'],
    ['Zoom out', 'M10 4a6 6 0 1 0 0 12 6 6 0 0 0 0-12 M14.5 14.5L21 21 M7 10h6', () => zoom(0.8), 'out'],
  ];
  for (const [label, path, action, area] of commands) button(label, path, action, controls).style.gridArea = area;
  let drag = null;
  viewport.addEventListener('pointerdown', (event) => {
    if (event.button !== 0 || event.target.closest('a')) return;
    drag = { id: event.pointerId, x: event.clientX - x, y: event.clientY - y };
    viewport.setPointerCapture(event.pointerId);
    viewport.classList.add('mdv-dragging');
    event.preventDefault();
  });
  viewport.addEventListener('pointermove', (event) => {
    if (!drag || drag.id !== event.pointerId) return;
    x = event.clientX - drag.x; y = event.clientY - drag.y; paint();
  });
  const endDrag = () => { drag = null; viewport.classList.remove('mdv-dragging'); };
  viewport.addEventListener('lostpointercapture', endDrag);
  viewport.addEventListener('pointerup', endDrag);
  viewport.addEventListener('pointercancel', endDrag);
  return () => { previousFocus = null; close(); viewer.remove(); };
}
