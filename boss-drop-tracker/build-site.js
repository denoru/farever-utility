/* Builds a deploy-ready static site into ./site (index.html + data only). */
const fs = require('fs');
const path = require('path');

const root = __dirname;
const out = path.join(root, 'site');

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(path.join(out, 'data'), { recursive: true });

fs.copyFileSync(path.join(root, 'index.html'), path.join(out, 'index.html'));
for (const f of ['bosses.js', 'bosses.json']) {
  const src = path.join(root, 'data', f);
  if (fs.existsSync(src)) fs.copyFileSync(src, path.join(out, 'data', f));
}

fs.writeFileSync(path.join(out, '.nojekyll'), '');

const kb = (p) => Math.round(fs.statSync(p).size / 102.4) / 10;
console.log('Wrote ' + out);
console.log('  index.html      ' + kb(path.join(out, 'index.html')) + ' KB');
console.log('  data/bosses.js  ' + kb(path.join(out, 'data', 'bosses.js')) + ' KB');
console.log('Upload this folder (or push it) to your host.');
