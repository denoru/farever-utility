/* Builds a deploy-ready static site into ./site (index.html + data only). */
const fs = require('fs');
const path = require('path');

const root = __dirname;
const out = path.join(root, 'site');

if (fs.existsSync(out)) {
  for (const e of fs.readdirSync(out)) fs.rmSync(path.join(out, e), { recursive: true, force: true });
}
fs.mkdirSync(path.join(out, 'data'), { recursive: true });

fs.copyFileSync(path.join(root, 'index.html'), path.join(out, 'index.html'));
fs.copyFileSync(path.join(root, 'MiniBanner.svg'), path.join(out, 'MiniBanner.svg'));
for (const f of ['bosses.js', 'bosses.json', 'items.js', 'items.json', 'i18n.js', 'i18n.json', 'market-config.js']) {
  const src = path.join(root, 'data', f);
  if (fs.existsSync(src)) fs.copyFileSync(src, path.join(out, 'data', f));
}

fs.writeFileSync(path.join(out, '.nojekyll'), '');

const kb = (p) => Math.round(fs.statSync(p).size / 102.4) / 10;
console.log('Wrote ' + out);
console.log('  index.html           ' + kb(path.join(out, 'index.html')) + ' KB');
console.log('  MiniBanner.svg       ' + kb(path.join(out, 'MiniBanner.svg')) + ' KB');
console.log('  data/bosses.js       ' + kb(path.join(out, 'data', 'bosses.js')) + ' KB');
console.log('  data/items.js        ' + kb(path.join(out, 'data', 'items.js')) + ' KB');
console.log('  data/i18n.js         ' + kb(path.join(out, 'data', 'i18n.js')) + ' KB');
console.log('  data/market-config.js ' + kb(path.join(out, 'data', 'market-config.js')) + ' KB');
console.log('Upload this folder (or push it) to your host.');
