const fontkit = require('fontkit'), fs = require('fs'), sharp = require('sharp');
const F = 'D:/Luma/LUMA/assets/fonts/';
// [file, weight, tracking(em), label]
const candidates = [
  ['Outfit-Variable.ttf', 500, .16, 'Outfit 500'],
  ['Outfit-Variable.ttf', 300, .22, 'Outfit 300'],
  ['PlusJakartaSans-Variable.ttf', 600, .14, 'Jakarta 600'],
  ['Manrope-Variable.ttf', 600, .16, 'Manrope 600'],
  ['Figtree-Variable.ttf', 500, .18, 'Figtree 500'],
  ['DMSans-Variable.ttf', 500, .16, 'DM Sans 500'],
];
function wordPath(file, weight, tracking, text, size) {
  let font = fontkit.openSync(F + file);
  if (font.variationAxes && font.variationAxes.wght) font = font.getVariation({ wght: weight });
  const scale = size / font.unitsPerEm;
  const run = font.layout(text);
  let x = 0, d = '', minY = 1e9, maxY = -1e9;
  run.glyphs.forEach((g, i) => {
    const p = g.path.scale(scale, -scale).translate(x, 0);
    d += p.toSVG();
    const bb = p.bbox; minY = Math.min(minY, bb.minY); maxY = Math.max(maxY, bb.maxY);
    x += run.positions[i].xAdvance * scale + (i < run.glyphs.length - 1 ? tracking * size : 0);
  });
  return { d, width: x, minY, maxY };
}
module.exports = { wordPath };
if (require.main === module) (async () => {
  const rows = candidates.map(([f, w, t, label], i) => {
    const wp = wordPath(f, w, t, 'LUMA', 60);
    const y = 30 + i * 100 + 70;
    const x = (800 - wp.width) / 2;
    return `<g transform="translate(${x},${y})"><path fill="#fff" d="${wp.d}"/></g><text x="20" y="${y - 50}" fill="#777" font-size="14" font-family="sans-serif">${label}</text>`;
  }).join('');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="640"><rect width="800" height="640" fill="#050506"/>${rows}</svg>`;
  await sharp(Buffer.from(svg)).png().toFile('word-candidates.png');
  console.log('ok');
})();
