// Generates Luma's original abstract "mesh gradient" wallpapers.
//
//   npm install sharp        (anywhere; point NODE_PATH at it if not local)
//   node scripts/generate-wallpapers.cjs [outDir=assets/wallpapers]
//
// Each wallpaper is a set of soft colour fields blended in linear light over a
// base colour, bent by a gentle sine warp so the shapes flow instead of
// sitting as round blobs. Seeded grain dithers the gradients so they do not
// band on 8-bit TV panels. Output is deterministic: 1920x1080 JPEG.
const path = require('node:path');
const sharp = require('sharp');

const W = 1920, H = 1080, ASPECT = W / H;
const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
const toLinear = c => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const toSrgb = c => (c <= 0.0031308 ? c * 12.92 : 1.055 * c ** (1 / 2.4) - 0.055);

// Small deterministic PRNG (mulberry32) for the grain.
function prng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// blobs: [x 0..1, y 0..1, radius, colour, strength]
const WALLPAPERS = [
  { file: 'luma-northern-glow', seed: 11, base: '#050a18', warp: [0.07, 1.1, 0.05, 1.7],
    blobs: [[0.18, 0.30, 0.34, '#0fd3a8', 0.9], [0.52, 0.12, 0.30, '#2f6bff', 1.0],
            [0.84, 0.36, 0.36, '#8a3ffc', 0.9], [0.62, 0.86, 0.40, '#06224f', 1.1],
            [0.10, 0.92, 0.30, '#04142e', 1.0]] },
  { file: 'luma-sunset-silk', seed: 23, base: '#120716', warp: [0.08, 0.9, 0.05, 1.4],
    blobs: [[0.80, 0.22, 0.36, '#ff7a3d', 1.0], [0.50, 0.40, 0.30, '#e8336d', 0.9],
            [0.16, 0.24, 0.38, '#5b2a9d', 1.0], [0.92, 0.70, 0.30, '#ffb86b', 0.6],
            [0.30, 0.90, 0.44, '#170a2b', 1.2]] },
  { file: 'luma-deep-ocean', seed: 37, base: '#020814', warp: [0.06, 1.3, 0.06, 1.1],
    blobs: [[0.28, 0.20, 0.36, '#0a4bd6', 1.0], [0.72, 0.34, 0.34, '#0bb5d9', 0.8],
            [0.50, 0.66, 0.30, '#0c2f8a', 0.9], [0.90, 0.88, 0.36, '#031233', 1.1],
            [0.08, 0.80, 0.34, '#02173d', 1.0]] },
  { file: 'luma-ember-night', seed: 41, base: '#0a0506', warp: [0.07, 1.0, 0.05, 1.8],
    blobs: [[0.76, 0.30, 0.32, '#d8321e', 0.9], [0.56, 0.52, 0.24, '#ff8a1f', 0.6],
            [0.26, 0.24, 0.38, '#5a0f22', 1.0], [0.18, 0.84, 0.40, '#12080c', 1.2],
            [0.92, 0.84, 0.30, '#3a0d10', 0.9]] },
  { file: 'luma-violet-haze', seed: 53, base: '#0d0720', warp: [0.08, 1.2, 0.06, 1.5],
    blobs: [[0.24, 0.26, 0.36, '#7c3aed', 1.0], [0.62, 0.20, 0.30, '#ec4899', 0.8],
            [0.86, 0.50, 0.34, '#3b82f6', 0.9], [0.44, 0.74, 0.34, '#4c1d95', 0.9],
            [0.08, 0.90, 0.32, '#0b0620', 1.1]] },
  { file: 'luma-emerald-dusk', seed: 67, base: '#03100c', warp: [0.07, 1.1, 0.05, 1.6],
    blobs: [[0.22, 0.28, 0.36, '#0f9d6c', 0.9], [0.60, 0.16, 0.30, '#16c79a', 0.6],
            [0.84, 0.40, 0.32, '#c9a227', 0.45], [0.52, 0.70, 0.38, '#06402f', 1.0],
            [0.12, 0.90, 0.34, '#031711', 1.1]] },
  { file: 'luma-graphite', seed: 71, base: '#0b0c0f', warp: [0.06, 0.8, 0.04, 1.3],
    blobs: [[0.30, 0.22, 0.42, '#3a4150', 0.9], [0.78, 0.30, 0.34, '#56637a', 0.6],
            [0.56, 0.62, 0.36, '#1d222b', 1.0], [0.10, 0.86, 0.36, '#0d0f13', 1.1],
            [0.94, 0.88, 0.32, '#232a36', 0.8]] },
  { file: 'luma-soft-dawn', seed: 89, base: '#c9c4e6', warp: [0.08, 1.0, 0.05, 1.5],
    blobs: [[0.20, 0.24, 0.38, '#ffc9a8', 1.0], [0.60, 0.16, 0.32, '#f7a8c8', 0.9],
            [0.88, 0.40, 0.36, '#a9c8ff', 1.0], [0.44, 0.72, 0.38, '#b9a7f0', 0.9],
            [0.10, 0.90, 0.34, '#8f9be0', 0.9]] },
];

function render(spec) {
  const base = hex(spec.base).map(toLinear);
  const blobs = spec.blobs.map(([x, y, r, colour, strength]) => ({
    x: x * ASPECT, y, inv: 1 / (2 * r * r), colour: hex(colour).map(toLinear), strength,
  }));
  const [a1, f1, a2, f2] = spec.warp;
  const random = prng(spec.seed);
  const p1 = random() * 6.283, p2 = random() * 6.283, p3 = random() * 6.283;
  const out = Buffer.alloc(W * H * 3);
  const TAU = Math.PI * 2;
  for (let py = 0; py < H; py++) {
    const v0 = py / H;
    for (let px = 0; px < W; px++) {
      const u0 = (px / W) * ASPECT;
      const u = u0 + a1 * Math.sin(TAU * f1 * v0 + p1) + a2 * Math.sin(TAU * f2 * (u0 * 0.6 + v0) + p2);
      const v = v0 + a1 * Math.sin(TAU * f1 * u0 * 0.7 + p3) + a2 * Math.sin(TAU * f2 * (u0 - v0 * 0.5) + p1);
      let weight = 0.22, r = base[0] * weight, g = base[1] * weight, b = base[2] * weight;
      for (const blob of blobs) {
        const dx = u - blob.x, dy = v - blob.y;
        const k = blob.strength * Math.exp(-(dx * dx + dy * dy) * blob.inv);
        weight += k; r += blob.colour[0] * k; g += blob.colour[1] * k; b += blob.colour[2] * k;
      }
      // Gentle vignette keeps the corners calm behind the top bar and dock.
      const cx = px / W - 0.5, cy = v0 - 0.5;
      const vignette = 1 - 0.30 * (cx * cx + cy * cy) * 2;
      const grain = (random() - 0.5) * (3 / 255);
      const i = (py * W + px) * 3;
      out[i] = Math.max(0, Math.min(255, Math.round((toSrgb((r / weight) * vignette) + grain) * 255)));
      out[i + 1] = Math.max(0, Math.min(255, Math.round((toSrgb((g / weight) * vignette) + grain) * 255)));
      out[i + 2] = Math.max(0, Math.min(255, Math.round((toSrgb((b / weight) * vignette) + grain) * 255)));
    }
  }
  return out;
}

(async () => {
  const outDir = process.argv[2] || path.join(__dirname, '..', 'assets', 'wallpapers');
  for (const spec of WALLPAPERS) {
    const file = path.join(outDir, `${spec.file}.jpg`);
    await sharp(render(spec), { raw: { width: W, height: H, channels: 3 } })
      .jpeg({ quality: 88, chromaSubsampling: '4:4:4', mozjpeg: true })
      .toFile(file);
    console.log(file);
  }
})().catch(error => { console.error(error); process.exit(1); });
