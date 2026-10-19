// STL code blocks (ASCII STL) render as an interactive 3D viewer, like GitHub.
import * as THREE from 'three';
import { STLLoader } from 'three/examples/jsm/loaders/STLLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';

export function renderSTL(el, source, dark) {
  const geometry = new STLLoader().parse(source);
  geometry.computeVertexNormals();
  geometry.center();
  geometry.computeBoundingSphere();
  const radius = geometry.boundingSphere?.radius || 1;

  const container = document.createElement('div');
  container.className = 'mdv-stl';
  el.replaceChildren(container);

  const width = container.clientWidth || 600;
  const height = container.clientHeight || 420;
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setPixelRatio(window.devicePixelRatio);
  renderer.setSize(width, height);
  container.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(45, width / height, radius / 100, radius * 100);
  camera.position.set(radius * 1.6, radius * 1.2, radius * 2.2);

  scene.add(new THREE.AmbientLight(0xffffff, dark ? 0.6 : 0.8));
  const light = new THREE.DirectionalLight(0xffffff, 1.6);
  light.position.set(1, 2, 3);
  scene.add(light);
  const back = new THREE.DirectionalLight(0xffffff, 0.6);
  back.position.set(-2, -1, -2);
  scene.add(back);

  const material = new THREE.MeshPhongMaterial({ color: dark ? 0x4493f8 : 0x0969da, specular: 0x222222, shininess: 40 });
  scene.add(new THREE.Mesh(geometry, material));

  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableZoom = true;

  // Render on demand instead of a continuous animation loop.
  const draw = () => renderer.render(scene, camera);
  controls.addEventListener('change', draw);
  draw();

  const resize = new ResizeObserver(() => {
    const w = container.clientWidth;
    const h = container.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    draw();
  });
  resize.observe(container);

  // Returned to main.js, which calls it when the block goes away.
  return () => {
    resize.disconnect();
    controls.dispose();
    geometry.dispose();
    material.dispose();
    renderer.dispose();
    renderer.forceContextLoss();
  };
}
