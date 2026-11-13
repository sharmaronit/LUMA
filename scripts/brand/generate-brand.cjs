// Luma brand: a silver "L" with a point of light, on near-black, and a silver
// "Luma" wordmark (Montserrat 600, outlined so no font is needed at runtime).
//
// Writes every logo file the app and website use:
//   android  drawable/luma_icon.xml, drawable/luma_banner.xml (manifest icon + TV banner)
//            mipmap-*/ic_launcher.png, drawable-*/ic_launcher_foreground.png (splash, adaptive icon)
//   assets   icon.png, icon-foreground.png, banner.png
//   docs     assets/luma-mark.svg, assets/luma-logo.svg, assets/icon.png
//
// Run: node scripts/brand/generate-brand.cjs   (needs fontkit and sharp)
const fontkit = require('fontkit'), fs = require('fs'), path = require('path'), sharp = require('sharp');
const ROOT = path.resolve(__dirname, '../..');
const RES = ROOT + '/android/app/src/main/res/';
const FONT = __dirname + '/fonts/Montserrat-Variable.ttf';

const BG = { center: '#2A2A30', mid: '#121215', edge: '#060607' };
const SILVER = [[0, '#FFFFFF'], [.45, '#C9C9CF'], [.7, '#8C8C94'], [1, '#E6E6EA']];
const WORD = [[0, '#FFFFFF'], [.42, '#DCDCE1'], [.78, '#8E8E96'], [1, '#C4C4CA']];
const GLOW = [[0, 1, .9], [.35, 1, .25], [1, 1, 0]]; // offset, white, alpha

// The mark, drawn in a 512 box.
const L = 'M190 146 V318 Q190 352 224 352 H334', STROKE = 26, DOT = [330, 168, 15], HALO = 58;

/* ---------- geometry helpers ---------- */
// Scale then translate absolute path commands (M L H V Q C Z only).
function xform(d, s, tx, ty) {
  return d.replace(/([MLHVCSQTZ])([^MLHVCSQTZ]*)/gi, (m, cmd, args) => {
    const n = args.trim() ? args.trim().split(/[\s,]+/).map(Number) : [];
    const C = cmd.toUpperCase();
    if (C === 'Z') return 'Z';
    if (C === 'H') return 'H' + n.map(v => (v * s + tx).toFixed(2)).join(' ');
    if (C === 'V') return 'V' + n.map(v => (v * s + ty).toFixed(2)).join(' ');
    return C + n.map((v, i) => (v * s + (i % 2 ? ty : tx)).toFixed(2)).join(' ');
  });
}
const circle = (cx, cy, r) => `M${(cx - r).toFixed(2)},${cy.toFixed(2)}a${r.toFixed(2)},${r.toFixed(2)} 0 1,0 ${(2 * r).toFixed(2)},0a${r.toFixed(2)},${r.toFixed(2)} 0 1,0 ${(-2 * r).toFixed(2)},0Z`;
const hex = (c, a = 1) => '#' + Math.round(a * 255).toString(16).padStart(2, '0').toUpperCase() + c.slice(1).toUpperCase();

function word(text, size) {
  let font = fontkit.openSync(FONT);
  font = font.getVariation({ wght: 600 });
  const scale = size / font.unitsPerEm, track = -.035 * size, run = font.layout(text);
  let x = 0, d = '', minY = 1e9, maxY = -1e9;
  run.glyphs.forEach((g, i) => {
    const p = g.path.scale(scale, -scale).translate(x, 0);
    d += p.toSVG();
    const bb = p.bbox; minY = Math.min(minY, bb.minY); maxY = Math.max(maxY, bb.maxY);
    x += run.positions[i].xAdvance * scale + (i < run.glyphs.length - 1 ? track : 0);
  });
  return { d, width: x, minY, maxY };
}

/* ---------- one scene description, rendered to SVG and to Android XML ---------- */
// mark(s, tx, ty): the L, halo and dot scaled by s and moved by (tx, ty).
function mark(s, tx, ty) {
  const [cx, cy, r] = DOT;
  return [
    { kind: 'stroke', d: xform(L, s, tx, ty), width: STROKE * s, grad: { type: 'linear', x1: 190 * s + tx, y1: 146 * s + ty, x2: 334 * s + tx, y2: 352 * s + ty, stops: SILVER } },
    { kind: 'fill', d: circle(cx * s + tx, cy * s + ty, HALO * s), grad: { type: 'radial', cx: cx * s + tx, cy: cy * s + ty, r: HALO * s, stops: GLOW.map(([o, , a]) => [o, '#FFFFFF', a]) } },
    { kind: 'fill', d: circle(cx * s + tx, cy * s + ty, r * s), color: '#FFFFFF' },
  ];
}
const background = (w, h) => ({ kind: 'fill', d: `M0,0h${w}v${h}h-${w}z`, grad: { type: 'radial', cx: w / 2, cy: h * .18, r: Math.max(w, h) * .95, stops: [[0, BG.center], [.55, BG.mid], [1, BG.edge]] } });

function svgOf(w, h, parts, { px = 1, rounded = 0, rim = false } = {}) {
  let defs = '', body = '', id = 0;
  for (const p of parts) {
    let paint = p.color || '#FFFFFF';
    if (p.grad) {
      const g = p.grad, gid = 'g' + id++;
      const stops = g.stops.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`).join('');
      defs += g.type === 'linear'
        ? `<linearGradient id="${gid}" gradientUnits="userSpaceOnUse" x1="${g.x1}" y1="${g.y1}" x2="${g.x2}" y2="${g.y2}">${stops}</linearGradient>`
        : `<radialGradient id="${gid}" gradientUnits="userSpaceOnUse" cx="${g.cx}" cy="${g.cy}" r="${g.r}">${stops}</radialGradient>`;
      paint = `url(#${gid})`;
    }
    body += p.kind === 'stroke'
      ? `<path d="${p.d}" fill="none" stroke="${paint}" stroke-width="${p.width}" stroke-linecap="round" stroke-linejoin="round"/>`
      : `<path d="${p.d}" fill="${paint}"/>`;
  }
  if (rounded) {
    defs += `<clipPath id="round"><rect width="${w}" height="${h}" rx="${rounded}"/></clipPath>`;
    defs += `<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".34"/><stop offset=".35" stop-color="#fff" stop-opacity=".06"/><stop offset="1" stop-color="#fff" stop-opacity=".12"/></linearGradient>`;
    body = `<g clip-path="url(#round)">${body}</g>` + (rim ? `<rect x="${w * .003}" y="${w * .003}" width="${w * .994}" height="${h * .994}" rx="${rounded * .99}" fill="none" stroke="url(#rim)" stroke-width="${w * .006}"/>` : '');
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w * px}" height="${h * px}" viewBox="0 0 ${w} ${h}"><defs>${defs}</defs>${body}</svg>`;
}

function xmlOf(w, h, parts, note) {
  const grad = (g) => {
    const items = g.stops.map(([o, c, a = 1]) => `     <item android:offset="${o}" android:color="${hex(c, a)}"/>`).join('\n');
    const head = g.type === 'linear'
      ? `<gradient android:type="linear" android:startX="${g.x1.toFixed(2)}" android:startY="${g.y1.toFixed(2)}" android:endX="${g.x2.toFixed(2)}" android:endY="${g.y2.toFixed(2)}">`
      : `<gradient android:type="radial" android:centerX="${g.cx.toFixed(2)}" android:centerY="${g.cy.toFixed(2)}" android:gradientRadius="${g.r.toFixed(2)}">`;
    return `    ${head}\n${items}\n    </gradient>`;
  };
  const body = parts.map(p => {
    const attr = p.kind === 'stroke' ? 'android:strokeColor' : 'android:fillColor';
    const extra = p.kind === 'stroke' ? ` android:strokeWidth="${p.width.toFixed(2)}" android:strokeLineCap="round" android:strokeLineJoin="round"` : '';
    if (!p.grad) return ` <path android:pathData="${p.d}" ${attr}="${hex(p.color)}"${extra}/>`;
    return ` <path android:pathData="${p.d}"${extra}>\n  <aapt:attr name="${attr}">\n${grad(p.grad)}\n  </aapt:attr>\n </path>`;
  }).join('\n');
  return `<?xml version="1.0" encoding="utf-8"?>
<!-- ${note}
     Generated by scripts/brand/generate-brand.cjs; edit that, not this file. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="${w}dp" android:height="${h}dp"
    android:viewportWidth="${w}" android:viewportHeight="${h}">
${body}
</vector>
`;
}

/* ---------- scenes ---------- */
// Square icon: the whole 512 design scaled to the box.
const iconParts = (w) => [background(w, w), ...mark(w / 512, 0, 0)];
// Adaptive foreground: mark only, kept inside the 66% safe zone.
const fgParts = (w) => { const s = w / 512 * .72, o = (w - 512 * s) / 2; return mark(s, o, o); };
// Lockup: mark beside the wordmark, centred in w x h.
function lockup(w, h, wordSize, withBg) {
  const wd = word('Luma', wordSize);
  const markH = (wd.maxY - wd.minY) * 1.25, s = markH / (352 + STROKE / 2 - (146 - STROKE / 2));
  const markW = (DOT[0] + HALO * .35 - (190 - STROKE / 2)) * s, gap = wordSize * .32;
  const total = markW + gap + wd.width, left = (w - total) / 2;
  const mx = left - (190 - STROKE / 2) * s, my = h / 2 - ((146 + 352) / 2) * s;
  const wx = left + markW + gap, wy = h / 2 - (wd.minY + wd.maxY) / 2;
  const wordPart = { kind: 'fill', d: xform(wd.d, 1, wx, wy), grad: { type: 'linear', x1: 0, y1: wd.minY + wy, x2: 0, y2: wd.maxY + wy, stops: WORD } };
  return [...(withBg ? [background(w, h)] : []), ...mark(s, mx, my), wordPart];
}

(async () => {
  const png = (svg, file) => sharp(Buffer.from(svg)).png().toFile(file);
  // Android vectors used by the manifest
  fs.writeFileSync(RES + 'drawable/luma_icon.xml', xmlOf(108, 108, iconParts(108), 'Luma icon: silver L with a point of light on near-black.'));
  fs.writeFileSync(RES + 'drawable/luma_banner.xml', xmlOf(320, 180, lockup(320, 180, 60, true), 'Luma TV banner: silver mark and Luma wordmark on near-black.'));
  // Launcher PNGs (splash screen and adaptive icon)
  const dens = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
  for (const [d, k] of Object.entries(dens)) {
    const s = Math.round(48 * k), f = Math.round(108 * k);
    await png(svgOf(512, 512, iconParts(512), { px: s / 512, rounded: 512 * .22 }), `${RES}mipmap-${d}/ic_launcher.png`);
    await png(svgOf(108, 108, fgParts(108), { px: f / 108 }), `${RES}drawable-${d}/ic_launcher_foreground.png`);
  }
  // Repo assets
  await png(svgOf(512, 512, iconParts(512), { px: 2 }), ROOT + '/assets/icon.png');
  await png(svgOf(512, 512, fgParts(512), { px: 2 }), ROOT + '/assets/icon-foreground.png');
  await png(svgOf(320, 180, lockup(320, 180, 60, true), { px: 4 }), ROOT + '/assets/banner.png');
  // Website
  const markSvg = svgOf(512, 512, iconParts(512), { rounded: 114, rim: true });
  fs.writeFileSync(ROOT + '/docs/assets/luma-mark.svg', markSvg);
  fs.writeFileSync(ROOT + '/docs/assets/luma-logo.svg', svgOf(560, 160, lockup(560, 160, 112, false)));
  await png(svgOf(512, 512, iconParts(512), { rounded: 114, rim: true }), ROOT + '/docs/assets/icon.png');
  await png(svgOf(1200, 630, lockup(1200, 630, 150, true)), ROOT + '/docs/assets/og.png');
  console.log('brand files written');
})();
