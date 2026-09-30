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
  const foot = d.getElementById('footer');
  console.log('footer credits:', /Jardineiro/.test(foot.textContent),
    '| fareverdb link:', /fareverdb\.com/.test(foot.querySelector('a') ? foot.querySelector('a').href : ''),
    '| steam safety note:', /never sees or stores your Steam password/.test(foot.textContent),
    '| old notes gone:', !/rarityRules|no boss drops a Legendary/.test(foot.textContent));
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

  d.querySelector('.tabs button[data-tab="market"]').click();
  await wait(80);
  console.log('market toolbar mode:', d.querySelector('.toolbar').classList.contains('mkt'));
  const mktHero = d.querySelector('#view .mkt-hero');
  console.log('market hero:', mktHero ? mktHero.textContent.replace(/\s+/g, ' ').trim().slice(0, 90) : 'MISSING');
  console.log('market search placeholder:', d.getElementById('search').placeholder);

  w.localStorage.setItem('fareverMarket.session.v1', JSON.stringify({
    access_token: 'smoke-fake', refresh_token: 'smoke-fake',
    expires_at: Date.now() + 3600000,
    steam_id: '76561198000000000', display_name: 'SmokeTester', avatar: '',
  }));
  d.querySelector('.tabs button[data-tab="market"]').click();
  await wait(200);
  console.log('signed-in bar:', !!d.querySelector('#view .mkt-me'));
  console.log('region chips:', d.querySelectorAll('#view .mkt-region').length,
    '| label:', (d.querySelector('#view .mkt-region-label') || {}).textContent);
  const pickCat = d.getElementById('pick-cat');
  const catValues = pickCat ? [...pickCat.options].map((o) => o.value) : [];
  console.log('pick-cat cats:', catValues.join(','));
  console.log('has 4 cats:', ['weapon', 'equipment', 'mount', 'glider'].every((c) => catValues.includes(c)),
    '| no legacy cats:', !['legendary', 'other', 'custom'].some((c) => catValues.includes(c)));
  console.log('pick-item select:', !!d.getElementById('pick-item'),
    '| rarity options (all):', d.getElementById('pick-rarity').options.length);
  console.log('pool empty:', !!d.querySelector('#view .mkt-pool-empty'),
    '| add btn:', !!d.querySelector('[data-mkt="additem"]'),
    '| post btn:', !!d.querySelector('[data-mkt="post"]'));
  console.log('empty feed text:', (d.querySelector('#view .empty') || {}).textContent);

  d.querySelector('[data-mkt="additem"]').click();
  await wait(40);
  const errEl = d.querySelector('#view .mkt-error');
  console.log('add with empty pool error:', errEl ? errEl.textContent.trim() : 'NO ERROR BOX',
    '| jsdom errors:', errors);

  const pickItem = d.getElementById('pick-item');
  pickItem.value = pickItem.options[1].value;
  pickItem.dispatchEvent(new w.Event('input', { bubbles: true }));
  const rarAuto = d.getElementById('pick-rarity').value;
  d.querySelector('[data-mkt="additem"]').click();
  await wait(40);
  const trow = d.querySelector('#view .mkt-pool-row');
  console.log('tracker pool row:', trow && trow.querySelector('.mkt-pool-name').textContent,
    '| thumb:', !!(trow && trow.querySelector('.dthumb img')),
    '| kind:', trow && trow.querySelector('.badge').textContent,
    '| rarity auto-filled:', rarAuto);
  d.querySelector('#view .mkt-pool-x').click();
  await wait(40);
  console.log('pool empty after tracker remove:', !!d.querySelector('#view .mkt-pool-empty'));

  let pc = d.getElementById('pick-cat');
  pc.value = 'mount';
  pc.dispatchEvent(new w.Event('input', { bubbles: true }));
  await wait(40);
  let rr = d.getElementById('pick-rarity');
  console.log('mount rarity locked:', rr.options.length === 1 && rr.value === 'Epic',
    '| opts:', [...rr.options].map((o) => o.value).join(','));
  pc = d.getElementById('pick-cat');
  pc.value = 'weapon';
  pc.dispatchEvent(new w.Event('input', { bubbles: true }));
  await wait(40);
  rr = d.getElementById('pick-rarity');
  console.log('weapon rarity full ladder:', rr.options.length === 6 && rr.value === 'auto',
    '| last:', rr.options[rr.options.length - 1].value);

  pc = d.getElementById('pick-cat');
  pc.value = 'equipment';
  pc.dispatchEvent(new w.Event('input', { bubbles: true }));
  await wait(40);
  rr = d.getElementById('pick-rarity');
  console.log('equipment rarity capped:', [...rr.options].map((o) => o.value).join(',') === ',Common,Uncommon,Rare',
    '| text input shown:', !!d.getElementById('pick-custom'));
  const custom = d.getElementById('pick-custom');
  custom.value = 'Test Sword of Smoke';
  custom.dispatchEvent(new w.Event('input', { bubbles: true }));
  d.querySelector('[data-mkt="additem"]').click();
  await wait(40);
  const poolRow = d.querySelector('#view .mkt-pool-row');
  console.log('pool rows:', d.querySelectorAll('#view .mkt-pool-row').length,
    '| name:', poolRow && poolRow.querySelector('.mkt-pool-name').textContent);
  d.querySelector('#view .mkt-pool-x').click();
  await wait(40);
  console.log('after remove, empty again:', !!d.querySelector('#view .mkt-pool-empty'));

  d.querySelector('[data-mkt="pickkind"][data-val="want"]').click();
  await wait(40);
  console.log('want chip active:',
    d.querySelector('[data-mkt="pickkind"][data-val="want"]').classList.contains('active'));

  w.__fareverMarket.announcements = [
    { id: 'a1', steam_id: '76561198000000000', note: 'fast deal', status: 'active',
      items: [{ kind: 'have', item_id: 'Mount_Aries_05', item_name: 'Aegis', rarity: null },
              { kind: 'want', item_id: null, item_name: 'Wanted Custom Blade', rarity: 'Epic' }],
      created_at: '2026-09-29T00:00:00Z' },
    { id: 'a2', steam_id: '76561198000000001', note: '', status: 'active',
      items: [{ kind: 'have', item_id: null, item_name: 'Other Guys Sword', rarity: null }],
      created_at: '2026-09-28T00:00:00Z' },
    { id: 'a3', steam_id: '76561198000000001', note: '', status: 'closed',
      items: [{ kind: 'want', item_id: null, item_name: 'Closed Want Item', rarity: null }],
      created_at: '2026-09-27T00:00:00Z' },
  ];
  w.__fareverMarket.profiles = [
    { steam_id: '76561198000000000', display_name: 'SmokeTester', avatar: '', region: 'EU' },
    { steam_id: '76561198000000001', display_name: 'OtherGuy', avatar: '', region: 'NA' },
  ];
  d.querySelector('.tabs button[data-tab="bosses"]').click();
  d.querySelector('.tabs button[data-tab="market"]').click();
  await wait(120);
  console.log('feed cards:', d.querySelectorAll('#view .mkt-listing').length,
    '| closed hidden:', !/Closed Want Item/.test(d.getElementById('view').textContent));
  const card = d.querySelector('#view .mkt-listing');
  console.log('card head:', card.querySelector('.name').textContent,
    '| region:', card.querySelector('.mkt-region-badge').getAttribute('data-r'),
    '| item rows:', card.querySelectorAll('.mkt-item-row').length,
    '| own actions:', card.querySelector('[data-mkt="done"]') ? 'Mark done' : 'MISSING');
  console.log('region chip now:',
    (d.querySelector('.mkt-region.active') || {}).getAttribute &&
    d.querySelector('.mkt-region.active').getAttribute('data-val'),
    '| label:', d.querySelector('#view .mkt-region-label').textContent);
  d.querySelector('[data-mkt="closedtoggle"]').click();
  await wait(40);
  console.log('after show closed:', d.querySelectorAll('#view .mkt-listing').length);
  d.querySelector('[data-mkt="closedtoggle"]').click();
  d.querySelector('[data-mkt="mfilter"][data-val="want"]').click();
  await wait(40);
  console.log('want filter cards:', d.querySelectorAll('#view .mkt-listing').length);
  d.querySelector('[data-mkt="mfilter"][data-val="all"]').click();
  await wait(40);
  const s2 = d.getElementById('search');
  s2.value = 'wanted custom';
  s2.dispatchEvent(new w.Event('input'));
  await wait(40);
  console.log('search "wanted custom" cards:', d.querySelectorAll('#view .mkt-listing').length);
  s2.value = '';
  s2.dispatchEvent(new w.Event('input'));
  await wait(40);

  d.querySelector('[data-mkt="signout"]').click();
  await wait(40);
  console.log('after signout hero:', !!d.querySelector('#view .mkt-hero'),
    '| session cleared:', w.localStorage.getItem('fareverMarket.session.v1') === null);

  d.querySelector('.tabs button[data-tab="bosses"]').click();
  await wait(60);
  console.log('toolbar restored:', !d.querySelector('.toolbar').classList.contains('mkt'),
    '| boss cards back:', d.querySelectorAll('#view .boss-card').length);

  console.log('errors:', errors.length ? errors : 'none');
  w.close();
  server.close();
})();
