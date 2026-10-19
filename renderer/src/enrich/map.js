// GeoJSON / TopoJSON code blocks render as an interactive map, like GitHub.
import L from 'leaflet';
import { feature } from 'topojson-client';

export function renderMap(el, source, kind, dark) {
  let data = JSON.parse(source);
  if (kind === 'topojson') {
    const objects = Object.values(data.objects ?? {});
    if (!objects.length) throw new Error('TopoJSON has no objects');
    data = {
      type: 'FeatureCollection',
      features: objects.flatMap((object) => {
        const f = feature(data, object);
        return f.type === 'FeatureCollection' ? f.features : [f];
      }),
    };
  }

  const container = document.createElement('div');
  container.className = 'mdv-map';
  el.replaceChildren(container);

  const map = L.map(container, { scrollWheelZoom: false, attributionControl: true });
  // Esri basemaps need no API key; pick the light or dark canvas to match.
  const service = dark ? 'Canvas/World_Dark_Gray_Base' : 'World_Street_Map';
  L.tileLayer(`https://server.arcgisonline.com/ArcGIS/rest/services/${service}/MapServer/tile/{z}/{y}/{x}`, {
    maxZoom: dark ? 16 : 19,
    attribution: 'Tiles &copy; Esri',
  }).addTo(map);

  const color = dark ? '#4493f8' : '#0969da';
  const layer = L.geoJSON(data, {
    style: () => ({ color, weight: 2, fillOpacity: 0.2 }),
    pointToLayer: (_feature, latlng) => L.circleMarker(latlng, { radius: 6, color, weight: 2, fillOpacity: 0.6 }),
    onEachFeature: (f, l) => {
      const props = f.properties && Object.entries(f.properties);
      if (props?.length) {
        const rows = props.map(([k, v]) => {
          const tr = document.createElement('tr');
          const th = document.createElement('th');
          const td = document.createElement('td');
          th.textContent = k;
          td.textContent = typeof v === 'object' ? JSON.stringify(v) : String(v);
          tr.append(th, td);
          return tr;
        });
        const table = document.createElement('table');
        table.append(...rows);
        l.bindPopup(table);
      }
    },
  }).addTo(map);

  const bounds = layer.getBounds();
  if (bounds.isValid()) map.fitBounds(bounds, { padding: [24, 24], maxZoom: 14 });
  else map.setView([0, 0], 1);
  // The container may have been laid out after creation.
  requestAnimationFrame(() => map.invalidateSize());
  return () => map.remove();
}
