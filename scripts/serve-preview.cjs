const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '../build/web');
const port = Number(process.env.LUMA_PREVIEW_PORT || 4174);
let fingerprint;
let revision;
const types = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.otf': 'font/otf'};

http.createServer((request, response) => {
  response.setHeader('Cache-Control', 'no-store, max-age=0');
  response.setHeader('Pragma', 'no-cache');
  response.setHeader('Expires', '0');
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
    if (pathname === '/__luma_preview_revision') {
      const main = path.join(root, 'main.dart.js');
      const stat = fs.statSync(main);
      const next = `${stat.mtimeMs}:${stat.size}`;
      if (fingerprint !== next) {
        revision = crypto.createHash('sha256').update(fs.readFileSync(main)).digest('hex');
        fingerprint = next;
      }
      response.writeHead(200, {'Content-Type': 'application/json'});
      response.end(JSON.stringify({revision, design: 'restored-glass-home-20261019'}));
      return;
    }
    const file = path.resolve(root, `.${pathname === '/' ? '/index.html' : pathname}`);
    if (!file.startsWith(root + path.sep)) {
      response.writeHead(403).end('Forbidden');
      return;
    }
    fs.readFile(file, (error, data) => {
      if (error) { response.writeHead(404).end('Not found'); return; }
      response.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Content-Length': data.length});
      response.end(request.method === 'HEAD' ? undefined : data);
    });
  } catch (_) {
    response.writeHead(503).end('Preview rebuild in progress');
  }
}).listen(port, '127.0.0.1', () => console.log(`Luma preview: http://127.0.0.1:${port}/`));
