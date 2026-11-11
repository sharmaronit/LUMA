// Luma
// Copyright (C) 2026 Ronit Sharma
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Cuts the foreground strip used by the "Depth" clock out of a wallpaper.
//
//   npm install sharp        (anywhere; point NODE_PATH at it if not local)
//   node scripts/generate-depth-layers.cjs [previewDir]
//
// The sky is found by flooding down from the top edge across smooth colour;
// everything below the resulting skyline is foreground. Only the band the
// clock can touch is kept, with soft outer edges, so the TV draws one small
// extra image. Keep CLOCK_HEIGHT, STRIP and the `bottom` values in step with
// lib/ronits/depth_clock.dart.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');

const W = 1920, H = 1080;
const CLOCK_HEIGHT = 0.37;                       // tallest digits the strip covers, fraction of screen height
const STRIP = { width: 0.60, above: 0.012, below: 0.026 };
// bottom: baseline of the digits, fraction of screen height. tolerance: how
// much neighbouring sky pixels may differ before they count as an edge.
const LAYERS = [
  { file: 'assets/wallpapers/aoraki-sunrise.jpg', x: 0.50, bottom: 0.630, height: 0.30 },
  { file: 'assets/wallpapers/dolomites.jpg', x: 0.30, bottom: 0.385, height: 0.24 },
  { file: 'assets/wallpapers/summit-glow.jpg', x: 0.61, bottom: 0.460, height: 0.26, tolerance: 4 },
  { file: 'assets/wallpapers/green-summit.jpg', x: 0.50, bottom: 0.453, height: 0.26 },
  { file: 'assets/wallpapers/rose-peak.jpg', x: 0.40, bottom: 0.449, height: 0.26 },
  { file: 'assets/wallpapers/blue-summit.jpg', x: 0.34, bottom: 0.442, height: 0.26 },
  { file: 'assets/wallpapers/misty-peak.jpg', x: 0.28, bottom: 0.444, height: 0.26 },
  { file: 'assets/wallpapers/volcano-view.jpg', x: 0.50, bottom: 0.565, height: 0.26 },
  { file: 'assets/wallpapers/steppe-range.jpg', x: 0.50, bottom: 0.474, height: 0.26 },
  { file: 'assets/wallpapers/golden-shore.jpg', x: 0.50, bottom: 0.640, height: 0.26 },
  { file: 'assets/wallpapers/star-dunes.jpg', x: 0.55, bottom: 0.593, height: 0.26, tolerance: 18 },
  { file: 'assets/wallpapers/twilight-lake.jpg', x: 0.30, bottom: 0.422, height: 0.24 },
  { file: 'assets/wallpapers/aurora-camp.jpg', x: 0.50, bottom: 0.600, height: 0.26, tolerance: 18 },
  { file: 'assets/wallpapers/lighthouse.jpg', x: 0.32, bottom: 0.450, height: 0.26 },
];

async function skyline(image, tolerance) {
  const data = await image.clone().blur(1.6).removeAlpha().raw().toBuffer();
  const sky = new Uint8Array(W * H), stack = [];
  for (let x = 0; x < W; x++) { sky[x] = 1; stack.push(x); }
  const limit = Math.round(H * 0.72);
  while (stack.length) {
    const p = stack.pop(), x = p % W, y = (p / W) | 0;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || nx >= W || ny < 0 || ny >= limit) continue;
      const q = ny * W + nx;
      if (sky[q]) continue;
      const a = p * 3, b = q * 3;
      const difference = Math.max(Math.abs(data[a] - data[b]), Math.abs(data[a + 1] - data[b + 1]), Math.abs(data[a + 2] - data[b + 2]));
      if (difference < tolerance) { sky[q] = 1; stack.push(q); }
    }
  }
  const line = new Float64Array(W);
  for (let x = 0; x < W; x++) { let y = 0; while (y < limit && sky[y * W + x]) y++; line[x] = y; }
  // A median over neighbouring columns removes one-pixel spikes.
  const smooth = new Float64Array(W);
  for (let x = 0; x < W; x++) {
    const window = [];
    for (let k = -12; k <= 12; k++) window.push(line[Math.min(W - 1, Math.max(0, x + k))]);
    smooth[x] = window.sort((a, b) => a - b)[12];
  }
  return smooth;
}

(async () => {
  const previewDir = process.argv[2];
  fs.mkdirSync('assets/wallpapers/depth', { recursive: true });
  for (const layer of LAYERS) {
    const name = path.basename(layer.file, '.jpg');
    const image = sharp(layer.file).resize(W, H, { fit: 'cover' });
    const line = await skyline(image, layer.tolerance ?? 7);
    const mask = Buffer.alloc(W * H);
    for (let x = 0; x < W; x++) for (let y = Math.floor(line[x]); y < H; y++) mask[y * W + x] = 255;
    const alpha = await sharp(mask, { raw: { width: W, height: H, channels: 1 } }).blur(1.1).extractChannel(0).raw().toBuffer();
    const rgb = await image.clone().removeAlpha().raw().toBuffer();

    // The strip is centred on the clock, kept on screen.
    const left = Math.round(W * Math.min(Math.max(layer.x - STRIP.width / 2, 0), 1 - STRIP.width));
    const width = Math.round(W * STRIP.width);
    // Never above the screen: on a high skyline the strip starts at the top.
    const top = Math.max(0, Math.round(H * (layer.bottom - CLOCK_HEIGHT - STRIP.above)));
    const height = Math.round(H * (CLOCK_HEIGHT + STRIP.above + STRIP.below));
    const strip = Buffer.alloc(width * height * 4);
    const fade = 24;
    for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
      const source = (top + y) * W + left + x, target = (y * width + x) * 4;
      const edge = Math.min(1, x / fade, (width - 1 - x) / fade, (height - 1 - y) / fade);
      strip[target] = rgb[source * 3]; strip[target + 1] = rgb[source * 3 + 1]; strip[target + 2] = rgb[source * 3 + 2];
      strip[target + 3] = Math.round(alpha[source] * Math.max(0, edge));
    }
    const png = await sharp(strip, { raw: { width, height, channels: 4 } }).png().toBuffer();
    await sharp(png).webp({ quality: 90, alphaQuality: 100 }).toFile(`assets/wallpapers/depth/${name}.webp`);
    console.log(name, 'bottom', layer.bottom, fs.statSync(`assets/wallpapers/depth/${name}.webp`).size, 'bytes');

    if (previewDir) {
      const digits = Math.round(H * layer.height / 0.84 / 1.22);
      const svg = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><text x="${Math.round(W * layer.x)}" y="${Math.round(H * layer.bottom)}" text-anchor="middle" font-family="Arial" font-weight="300" transform="translate(0 0)" font-size="${digits}" fill="white" fill-opacity="0.92">10:42</text></svg>`);
      const full = await image.clone().composite([{ input: svg }, { input: png, left, top }]).png().toBuffer();
      await sharp(full).resize(640).jpeg({ quality: 80 }).toFile(path.join(previewDir, name + '.jpg'));
    }
  }
})();
