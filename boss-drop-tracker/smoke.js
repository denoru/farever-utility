const http = require('http');
const fs = require('fs');
const path = require('path');
const { JSDOM, VirtualConsole } = require('jsdom');

const ROOT = process.argv[2] ? require('path').resolve(process.argv[2]) : __dirname;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json' };

const server = http.createServer((req, res) => {
  const file = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
  fs.readFile(file, (err, buf) => {
    if (err) { res.writeHead(404); res.end('nope'); return; }
    res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream' });
    res.end(buf);
  });
});

const errors = [];
const vc = new VirtualConsole();
vc.on('jsdomError', (e) => errors.push('jsdomError: ' + e.message));
vc.on('error', (m) => errors.push('console.error: ' + m));

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  await new Promise((r) => server.listen(8931, '127.0.0.1', r));
  const dom = await JSDOM.fromURL('http://127.0.0.1:8931/index.html', {
    runScripts: 'dangerously',
    resources: 'usable',
    pretendToBeVisual: true,
    virtualConsole: vc,
  });
  const w = dom.window;
  await wait(700);
  const d = w.document;

  console.log('stats:', d.getElementById('stats').textContent.replace(/\s+/g, ' ').trim());
  console.log('subtitle:', d.getElementById('subtitle').textContent);
  console.log('default tab boss cards:', d.querySelectorAll('#view .boss-card').length);
  console.log('active tab:', d.querySelector('.tabs button.active').textContent);
  d.querySelector('.tabs button[data-tab="items"]').click();
  await wait(60);
  console.log('item cards:', d.querySelectorAll('#view .card').length);

  const first = d.querySelector('#view .own-btn');
  console.log('first button:', JSON.stringify(first.textContent.trim()));
  first.click();
  await wait(60);
  console.log('after click stats:', d.getElementById('stats').textContent.replace(/\s+/g, ' ').trim());
  console.log('localStorage:', w.localStorage.getItem('fareverBossTracker.v1'));
  console.log('card owned:', d.querySelector('#view .card').classList.contains('owned'));

  d.querySelector('.tabs button[data-tab="bosses"]').click();
  await wait(60);
  console.log('boss cards:', d.querySelectorAll('#view .boss-card').length);
  console.log('drop rows:', d.querySelectorAll('#view .drop-row').length);

  const tries = d.querySelector('.run-field input[data-field="tries"]');
  const rowCount = d.querySelector('.row-count');
  console.log('boss tries input:', !!tries, '| row count input:', !!rowCount, '| default rate:', d.querySelector('.run-rate').textContent);
  tries.value = '40';
  tries.dispatchEvent(new w.Event('input', { bubbles: true }));
  rowCount.value = '2';
  rowCount.dispatchEvent(new w.Event('input', { bubbles: true }));
  await wait(60);
  console.log('rate after input:', d.querySelector('.run-rate').textContent);
  console.log('runs store:', w.localStorage.getItem('fareverBossTracker.runs.v1'));
  console.log('item runs store:', w.localStorage.getItem('fareverBossTracker.itemruns.v1'));
  d.querySelector('.tabs button[data-tab="items"]').click();
  d.querySelector('.tabs button[data-tab="bosses"]').click();
  await wait(60);
  console.log('rate after re-render:', d.querySelector('.run-rate').textContent);
  console.log('row count preserved:', d.querySelector('.row-count').value);

  d.querySelector('.chip[data-cat="mount"]').click();
  await wait(60);
  console.log('mount rows:', d.querySelectorAll('#view .drop-row').length);

  const s = d.getElementById('search');
  s.value = 'ratsar';
  s.dispatchEvent(new w.Event('input'));
  await wait(60);
  console.log('search ratsar boss cards:', d.querySelectorAll('#view .boss-card').length);

  d.querySelector('.tabs button[data-tab="items"]').click();
  d.querySelector('.chip[data-cat="all"]').click();
  s.value = 'wingfish';
  s.dispatchEvent(new w.Event('input'));
  await wait(60);
  console.log('search wingfish items:', d.querySelectorAll('#view .card').length);

  const hide = d.getElementById('hideOwned');
  s.value = '';
  s.dispatchEvent(new w.Event('input'));
  hide.checked = true;
  hide.dispatchEvent(new w.Event('change'));
  await wait(60);
  console.log('hide owned -> cards:', d.querySelectorAll('#view .card').length);

  const wchip = d.querySelector('.chip[data-cat="weapon"]');
  console.log('weapon chip label:', wchip && wchip.textContent);
  wchip.click();
  await wait(60);
  const wcards = d.querySelectorAll('#view .card');
  console.log('weapon cards:', wcards.length);
  console.log('first weapon badges:', [...wcards[0].querySelectorAll('.badge')].map((b) => b.textContent).join(' | '));
  console.log('first weapon chance line:', wcards[0].querySelector('.chance').textContent);

  const iTr = wcards[0].querySelector('input[data-itemrun][data-field="tries"]');
  const iDr = wcards[0].querySelector('input[data-itemrun][data-field="drops"]');
  console.log('item inputs:', !!iTr, !!iDr, '| item rate:', wcards[0].querySelector('.run-rate').textContent);
  iTr.value = '100';
  iTr.dispatchEvent(new w.Event('input', { bubbles: true }));
  iDr.value = '1';
  iDr.dispatchEvent(new w.Event('input', { bubbles: true }));
  await wait(60);
  console.log('item rate after input:', d.querySelector('#view .run-rate').textContent);
  console.log('item runs store:', w.localStorage.getItem('fareverBossTracker.itemruns.v1'));

  console.log('errors:', errors.length ? errors : 'none');
  w.close();
  server.close();
})();
