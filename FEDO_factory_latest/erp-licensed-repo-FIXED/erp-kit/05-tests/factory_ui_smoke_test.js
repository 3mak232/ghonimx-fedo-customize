/* Local headless smoke test for the FEDO factory screen.
 * Renders app.js + factory-v5.js in jsdom against a stub Supabase client and
 * asserts each tab of the new "المصنع — الرولات" screen produces real markup.
 * No network, no real data: LOCAL / DISPOSABLE ONLY.
 *
 *   npm i jsdom && node factory_ui_smoke_test.js
 */
const fs = require('fs');
const path = require('path');
const { JSDOM, VirtualConsole } = require('jsdom');

const FRONTEND = path.resolve(__dirname, '../03-frontend');
const read = f => fs.readFileSync(path.join(FRONTEND, f), 'utf8');

// ---------------------------------------------------------------- fixtures
const UUID = {
  admin: 'd0000000-0000-4000-8000-000000000001',
  wh: 'd2000000-0000-4000-8000-000000000001',
  fabric: 'd3000000-0000-4000-8000-000000000001',
  garment: 'd4000000-0000-4000-8000-000000000001',
  rollA: 'd5000000-0000-4000-8000-000000000001',
  rollB: 'd5000000-0000-4000-8000-000000000002',
  wo: 'd6000000-0000-4000-8000-000000000001',
  sup: 'd7000000-0000-4000-8000-000000000001',
};

const rows = {
  products: [
    { id: UUID.fabric, name: 'قماش تجريبي', code: 'FAB', sale_price: 0, purchase_price: 10 },
    { id: UUID.garment, name: 'تيشيرت تجريبي', code: 'TSH', sale_price: 100, purchase_price: 0 },
  ],
  warehouses: [{ id: UUID.wh, name: 'المخزن الرئيسي' }],
  customers: [], suppliers: [{ id: UUID.sup, name: 'مورد تجريبي' }],
  stock_balances: [{ product_id: UUID.fabric, warehouse_id: UUID.wh, qty: 78 }],
  customer_balances: [], supplier_balances: [],
  factory_roll_balances: [
    { roll_id: UUID.rollA, roll_code: 'R-A', product_id: UUID.fabric, warehouse_id: UUID.wh, color: 'أبيض', width: 1.5, original_qty: 40, remaining_qty: 28, unit_cost: 10, value_remaining: 280, is_split_source: true },
    { roll_id: UUID.rollB, roll_code: 'R-B', product_id: UUID.fabric, warehouse_id: UUID.wh, color: 'أزرق', width: 1.5, original_qty: 60, remaining_qty: 50, unit_cost: 10, value_remaining: 500, is_split_source: false },
  ],
  factory_roll_moves: [
    { id: '1', roll_id: UUID.rollA, movement_type: 'receipt', quantity_delta: 40, unit_cost: 10, created_at: '2026-11-04T10:00:00Z' },
    { id: '2', roll_id: UUID.rollA, movement_type: 'consumption', quantity_delta: -12, consumed_qty: 10, waste_qty: 2, scrap_qty: 0, work_order_id: UUID.wo, created_at: '2026-11-04T11:00:00Z' },
  ],
  work_orders: [{ id: UUID.wo, number: 'WO-1001', status: 'Released', date: '2026-11-04', warehouse_id: UUID.wh, planned_qty: 10 }],
  factory_variants: [{ id: 'v1', parent_product_id: UUID.garment, variant_product_id: UUID.fabric, color: 'أبيض', size_label: 'L' }],
};

const calls = [];
function makeClient() {
  const builder = table => {
    const q = {
      select: () => q, order: () => q, eq: () => q, limit: () => q, gt: () => q,
      maybeSingle: () => Promise.resolve({ data: null, error: null }),
      single: () => Promise.resolve({ data: null, error: null }),
      insert: () => q, update: () => q, upsert: () => q, delete: () => q,
      then: (res, rej) => Promise.resolve({ data: rows[table] || [], error: null }).then(res, rej),
    };
    return q;
  };
  return {
    from: table => builder(table),
    rpc: (fn, args) => {
      calls.push([fn, args]);
      return Promise.resolve({ data: 'stub-id', error: null });
    },
    auth: {
      getSession: () => Promise.resolve({ data: { session: { user: { id: UUID.admin } } } }),
      getUser: () => Promise.resolve({ data: { user: { id: UUID.admin } } }),
      updateUser: () => Promise.resolve({ data: {}, error: null }),
      signInWithPassword: () => Promise.resolve({ data: {}, error: null }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
      setSession: () => Promise.resolve({ error: null }),
      signOut: () => Promise.resolve({}),
      mfa: { getAuthenticatorAssuranceLevel: () => Promise.resolve({ data: { currentLevel: 'aal2' } }) },
    },
    channel: () => ({ on: () => ({ subscribe: () => ({}) }), subscribe: () => ({}) }),
    removeChannel: () => {},
    functions: { invoke: () => Promise.resolve({ data: {}, error: null }) },
    storage: { from: () => ({ upload: () => Promise.resolve({}), getPublicUrl: () => ({ data: { publicUrl: '' } }) }) },
  };
}

const html = `<!DOCTYPE html><html lang="ar" dir="rtl"><body>
<div id="app"></div><div id="globalLoader"><b id="loaderTitle"></b><div id="loaderText"></div></div><div id="toast"></div>
</body></html>`;

const virtualConsole = new VirtualConsole();
const errors = [];
virtualConsole.on('jsdomError', e => errors.push(String(e && e.message || e)));
virtualConsole.on('error', e => errors.push(String(e)));

const dom = new JSDOM(html, { runScripts: 'outside-only', url: 'http://localhost/', virtualConsole, pretendToBeVisual: true });
const { window } = dom;
// install stubs before the app boots (module-level code talks to window.*)
Object.assign(window, {
  supabase: { createClient: () => makeClient() },
  fetch: () => Promise.resolve({ ok: true, json: () => Promise.resolve({}) }),
  matchMedia: window.matchMedia || (() => ({ matches: false, addListener() {}, removeListener() {} })),
  alert: m => calls.push(['alert', String(m)]),
  confirm: () => true,
});
if (!window.crypto) window.crypto = {};
if (!window.crypto.randomUUID) window.crypto.randomUUID = () => require('crypto').randomUUID();
window.crypto.getRandomValues = window.crypto.getRandomValues || (a => require('crypto').randomFillSync(a));
window.requestAnimationFrame = window.requestAnimationFrame || (cb => setTimeout(cb, 0));

const results = [];
function check(name, cond, detail) {
  results.push({ name, pass: !!cond, detail: detail || '' });
  console.log((cond ? 'PASS ' : 'FAIL ') + name + (cond ? '' : ' :: ' + (detail || '')));
}

function run(code, label) {
  try { dom.window.eval(code); } catch (e) { errors.push(label + ': ' + e.message); }
}

// A browser loads both files as classic scripts sharing one global lexical scope;
// eval code gets its own lexical scope, so concatenate to emulate the real page.
// order mirrors index.html: the theme helpers live in an inline <head> script
run("window.fedoThemeBtn = () => ''; window.fedoToggleTheme = () => {}; window.fedoCurrentTheme = () => 'light';", 'theme stub');
run(fs.readFileSync(path.join(FRONTEND, 'app.js'), 'utf8') + '\n;\n' + fs.readFileSync(path.join(FRONTEND, 'factory-v5.js'), 'utf8'), 'app.js + factory-v5.js');

check('app.js و factory-v5.js بلا أخطاء تحميل', errors.length === 0, errors.join(' | '));
check('شاشة المصنع مسجلة', typeof window.fmView === 'function');
check('مسارات المصنع مضافة للتنقل', /factory/.test(read('app.js')));

(async () => {
  // render every tab of the new screen
  const tabs = ['stock', 'issue', 'split', 'buy', 'setup', 'variants'];
  for (const t of tabs) {
    let out = '';
    try {
      window.FM.tab = t;
      out = await window.fmView();
    } catch (e) { out = 'ERROR: ' + e.message; }
    const ok = typeof out === 'string' && out.length > 200 && !/^ERROR/.test(out);
    check('تبويب ' + t + ' يُنتج واجهة', ok, out.slice(0, 160));
    if (!ok) continue;
    check('تبويب ' + t + ' بلا نص undefined', !/>undefined</.test(out), 'found undefined in markup');
    check('تبويب ' + t + ' يستخدم دوال التنسيق', !/\[object Object\]/.test(out));
    if (t === 'stock') check('تبويب stock يعرض الرولين', /R-A/.test(out) && /R-B/.test(out));
    if (t === 'issue') check('تبويب issue يعرض أمر تصنيع مفتوح', /WO-1001/.test(out));
    if (t === 'issue') check('تبويب issue يعرض حركة الهالك', /هالك/.test(out));
  }

  // real RPC contracts used by the screen (names + params)
  window.FM.forms.issue.req = null;
  window.document.body.insertAdjacentHTML('beforeend', `<div>
    <input id="fm_is_roll" value="${UUID.rollA}"><input id="fm_is_wo" value="${UUID.wo}">
    <input id="fm_is_qty" value="4"><input id="fm_is_waste" value="1"><input id="fm_is_scrap" value="0">
    <input id="fm_is_note" value="اختبار"></div>`);
  await window.FM.issue();
  await new Promise(r => setTimeout(r, 500));
  const issue = calls.filter(c => c[0] === 'factory_issue_roll').pop();
  check('FM.issue يستدعي factory_issue_roll', !!issue, JSON.stringify(calls.slice(-3)));
  check('FM.issue يمرر الصرف والهالك ضمن نفس الطلب',
    issue && issue[1].p_qty === 4 && issue[1].p_waste === 1 && issue[1].p_scrap === 0 &&
    /^[0-9a-f-]{36}$/.test(issue[1].p_request), JSON.stringify(issue && issue[1]));

  // request keys: reuse on retry, new key after success
  const before = window.FM.forms.issue.req;
  check('مفتاح الطلب ثابت أثناء الفشل/التكرار', before === window.FM.forms.issue.req);
  window.FM.resetReq('issue');
  check('مفتاح الطلب يتجدد بعد النجاح', window.FM.forms.issue.req === null);

  const failed = results.filter(r => !r.pass);
  console.log('\n' + (failed.length ? `FAILED ${failed.length}/${results.length}` : `ALL ${results.length} UI CHECKS PASSED`));
  process.exit(failed.length ? 1 : 0);
})();
