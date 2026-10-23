import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const root = path.dirname(new URL(import.meta.url).pathname);
try {
  for (const l of fs.readFileSync(path.join(root, '.env'), 'utf8').split('\n')) {
    const m = l.match(/^([A-Z_]+)=(.*)$/);
    if (m) process.env[m[1]] ??= m[2].trim();
  }
} catch (e) { if (e.code !== 'ENOENT') throw e; }
const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.json': 'application/json' };
http.createServer((req, res) => {
  const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  if (pathname === '/api/config') return require('./api/config.js')(req, res);
  if (pathname.split('/').some((p) => p.startsWith('.')) || pathname.startsWith('/docs/') || pathname.startsWith('/tests/') || pathname.startsWith('/api/')) {
    res.writeHead(404); return res.end('No encontrado');
  }
  const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
  if (!file.startsWith(root + '/') || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    res.writeHead(404); return res.end('No encontrado');
  }
  res.setHeader('Content-Type', (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8');
  fs.createReadStream(file).pipe(res);
}).listen(Number(process.env.PORT || 4173), '0.0.0.0', () => console.log('BUSRAX listo en puerto ' + (process.env.PORT || 4173)));
