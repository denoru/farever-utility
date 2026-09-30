/* Extracts CastleDB XML exports (per-language text tables) from Farever's res.pak.
 * Usage: node extract-cdb.js "<path\to\res.pak>" <outDir>
 * Output: <outDir>/cdb-<lang>-<n>.xml (multiple per language; scrape-items.js picks translations).
 */
const fs = require('fs');
const path = require('path');

const FILE = process.argv[2];
const OUT_DIR = process.argv[3];
if (!FILE || !OUT_DIR) {
  console.error('Usage: node extract-cdb.js "<path\\to\\res.pak>" <outDir>');
  process.exit(1);
}

const START_PAT = Buffer.from('<cdb project=', 'latin1');
const END_PAT = Buffer.from('</cdb>', 'latin1');
const CHUNK = 8 * 1024 * 1024;
const OVERLAP = 256;

fs.mkdirSync(OUT_DIR, { recursive: true });

const fd = fs.openSync(FILE, 'r');
const size = fs.fstatSync(fd).size;
const starts = [];
const ends = [];
let tail = Buffer.alloc(0);
let filePos = 0;
let lastReport = 0;

while (filePos < size) {
  const want = Math.min(CHUNK, size - filePos);
  const tmp = Buffer.alloc(want);
  const bytesRead = fs.readSync(fd, tmp, 0, want, filePos);
  if (bytesRead <= 0) break;
  const base = filePos - tail.length;
  const data = tail.length ? Buffer.concat([tail, tmp.slice(0, bytesRead)]) : tmp.slice(0, bytesRead);
  filePos += bytesRead;
  for (const [pat, arr] of [[START_PAT, starts], [END_PAT, ends]]) {
    let idx = 0;
    while (true) {
      const found = data.indexOf(pat, idx);
      if (found === -1) break;
      const abs = base + found;
      if (!arr.length || arr[arr.length - 1] !== abs) arr.push(abs);
      idx = found + 1;
    }
  }
  tail = data.slice(Math.max(0, data.length - OVERLAP));
  if (filePos - lastReport >= 1024 * 1024 * 1024) { lastReport = filePos; console.log('scanned', (filePos / 1e9).toFixed(2), 'GB'); }
}
fs.closeSync(fd);

const printable = (b) => b.toString('latin1').replace(/[^\x20-\x7e]/g, '.');
const fd2 = fs.openSync(FILE, 'r');
const blobs = [];
for (const s of starts) {
  const e = ends.find((x) => x > s + 100);
  if (!e) continue;
  const hdr = Buffer.alloc(200);
  fs.readSync(fd2, hdr, 0, 200, s + START_PAT.length);
  const h = printable(hdr);
  const lang = (h.match(/lang="([^"]*)"/) || [])[1] || '?';
  const rev = (h.match(/revision="([^"]*)"/) || [])[1] || '?';
  blobs.push({ s, e: e + 6, lang, rev });
}

for (const [i, b] of blobs.entries()) {
  const out = path.join(OUT_DIR, `cdb-${b.lang}-${i}.xml`);
  const w = fs.openSync(out, 'w');
  let pos = b.s;
  const buf = Buffer.alloc(1024 * 1024);
  while (pos < b.e) {
    const want = Math.min(buf.length, b.e - pos);
    const n = fs.readSync(fd2, buf, 0, want, pos);
    if (n <= 0) break;
    fs.writeSync(w, buf, 0, n);
    pos += n;
  }
  fs.closeSync(w);
  console.log('wrote', out, 'lang=' + b.lang, 'rev=' + b.rev, (b.e - b.s) + ' bytes');
}
fs.closeSync(fd2);
console.log('done:', blobs.length, 'cdb blobs');
