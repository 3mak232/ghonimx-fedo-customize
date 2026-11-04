/* ============================================================================
 * factory-v5.js — واجهة المصنع (المرحلة 1: دفتر الرولات)
 * يُحمَّل بعد app.js. لا يلمس أي دالة FEDO قائمة، ويستخدم فقط:
 *   - القراءة من factory_roll_balances / factory_rolls / factory_roll_moves
 *   - استدعاء RPC الآمنة: factory_enable_roll_tracking / factory_normalize_roll_costs /
 *     factory_activate_roll_control / factory_buy_rolls / factory_issue_roll /
 *     factory_split_roll_remainder
 * كل عملية كتابة تتطلب مفتاح request (idempotency key) يُولَّد في المتصفح.
 * ==========================================================================*/
(function () {
  'use strict';
  if (typeof window === 'undefined' || typeof rpc !== 'function') return;

  var FM_MOVE = {
    receipt: 'استلام', consumption: 'صرف إنتاج', waste: 'هالك', scrap: 'بواقي',
    remainder: 'بقية/تقسيم', return: 'مرتجع مورد', adjustment: 'تسوية'
  };
  var FM_ACTIONS = ['enable', 'issue', 'split', 'purchase', 'activate', 'normalize'];

  function fmUuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = new Uint8Array(16);
    (window.crypto || {}).getRandomValues ? crypto.getRandomValues(b) : b.forEach(function (_, i) { b[i] = Math.floor(Math.random() * 256); });
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    var h = [].map.call(b, function (x) { return x.toString(16).padStart(2, '0'); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }
  function fmNum(x, d) { var v = parseFloat(String(x).replace(/[^\d.\-]/g, '')); return isFinite(v) ? v : (d === undefined ? 0 : d); }
  function fmInt(x) { return Math.round(fmNum(x)); }
  function fmMoney(x) { return (isFinite(+x) ? +x : 0).toLocaleString(locOf(), { maximumFractionDigits: 2 }); }
  function fmQty(x) { return (isFinite(+x) ? +x : 0).toLocaleString(locOf(), { maximumFractionDigits: 3 }); }
  function fmSafe(fn) { try { return fn(); } catch (e) { return null; } }

  // ------------------------------------------------------------------ state
  var FM = window.FM = {
    tab: localStorage.getItem('fedo_fm_tab') || 'stock',
    rolls: [], moves: [], products: [], warehouses: [], orders: [], variants: [],
    error: '',
    forms: { issue: {}, split: {}, buy: {} },
    busy: false
  };

  FM.req = function (kind) {
    var f = FM.forms[kind];
    if (!f.req) f.req = fmUuid();
    return f.req;
  };
  FM.resetReq = function (kind) {
    FM.forms[kind].req = null;
  };

  FM.setTab = function (t) {
    FM.tab = t;
    try { localStorage.setItem('fedo_fm_tab', t); } catch (e) {}
    return R('soft');
  };

  // ---------------------------------------------------------------- loading
  FM.load = async function () {
    FM.error = '';
    var q;
    FM.products = (C && C.products) || [];
    FM.warehouses = (C && C.warehouses) || [];
    q = await fmSafeAsync(function () { return g('factory_roll_balances', 'roll_code'); });
    if (q === null) {
      FM.error = 'جداول المصنع غير مثبتة على هذه القاعدة. نفّذ ERP_FACTORY_CUSTOMIZE_v1.sql ثم ERP_FACTORY_ROLL_LEDGER_v4.sql و v5.';
      FM.rolls = [];
    } else { FM.rolls = q; }
    FM.moves = (await fmSafeAsync(function () { return g('factory_roll_moves', 'created_at'); })) || [];
    FM.orders = (await fmSafeAsync(function () { return g('work_orders', 'date'); })) || [];
    FM.variants = (await fmSafeAsync(function () { return g('factory_variants'); })) || [];
    return FM;
  };
  async function fmSafeAsync(fn) { try { return await fn(); } catch (e) { return null; } }

  // ------------------------------------------------------------- selectors
  FM.pname = function (id) { var p = (FM.products || []).find(function (x) { return x.id === id; }); return p ? p.name : '—'; };
  FM.wname = function (id) { var w = (FM.warehouses || []).find(function (x) { return x.id === id; }); return w ? w.name : '—'; };
  FM.oname = function (id) { var o = (FM.orders || []).find(function (x) { return x.id === id; }); return o ? o.number : '—'; };
  FM.roll = function (id) { return (FM.rolls || []).find(function (x) { return x.roll_id === id; }); };
  FM.byProduct = function (pid, wid) {
    return (FM.rolls || []).filter(function (r) {
      return r.product_id === pid && (!wid || r.warehouse_id === wid) && +r.remaining_qty > 0;
    });
  };
  // أصناف متتبعة فعلية (لها رولات مسجلة)
  FM.trackedProducts = function () {
    var seen = {}, out = [];
    (FM.rolls || []).forEach(function (r) { if (!seen[r.product_id]) { seen[r.product_id] = 1; out.push(r.product_id); } });
    return out;
  };

  // ------------------------------------------------------------- actions
  FM.run = async function (label, fn, kind) {
    if (FM.busy) return;
    FM.busy = true;
    try {
      await act(fn, function () { if (kind) FM.resetReq(kind); return label || 'تمت العملية'; });
    } catch (e) {
      // act already alerts; keep request key so a retry is idempotent
    } finally {
      FM.busy = false;
    }
  };

  FM.enableTracking = function () {
    var pid = v('fm_en_p'), wid = v('fm_en_w');
    if (!pid || !wid) return alert('اختر الصنف والمخزن');
    if (!confirm('بدء تتبع الرولات يعني أن كل حركة مخزون لهذا الصنف في هذا المخزن يجب أن تمر عبر دفتر الرولات. لا يمكن التراجع. متابعة؟')) return;
    return FM.run('تم تفعيل تتبع الرولات', function () {
      return rpc('factory_enable_roll_tracking', { p_product: pid, p_warehouse: wid });
    });
  };

  FM.normalizeCosts = function (pid, wid) {
    return FM.run('تمت معايرة تكلفة الرولات مع متوسط تكلفة الصنف', function () {
      return rpc('factory_normalize_roll_costs', { p_product: pid, p_warehouse: wid });
    });
  };

  FM.activate = function (pid, wid) {
    if (!confirm('تفعيل التتبع لصنف له رصيد قائم يتطلب أن يساوي مجموع كميات الرولات رصيد المخزون بالضبط. متابعة؟')) return;
    return FM.run('تم تفعيل تتبع الرولات', function () {
      return rpc('factory_activate_roll_control', { p_product: pid, p_warehouse: wid });
    });
  };

  FM.issue = async function () {
    var rollId = v('fm_is_roll'), wo = v('fm_is_wo');
    var qty = fmNum(v('fm_is_qty')), waste = fmNum(v('fm_is_waste')), scrap = fmNum(v('fm_is_scrap'));
    var r = FM.roll(rollId);
    if (!r) return alert('اختر الرول');
    if (!wo) return alert('اختر أمر التصنيع');
    if (qty + waste + scrap <= 0) return alert('أدخل كمية صرف أو هالك أو بواقي أكبر من صفر');
    if (qty + waste + scrap > (+r.remaining_qty) + 1e-9) {
      return alert('الكمية المطلوبة أكبر من المتبقي في الرول (' + fmQty(r.remaining_qty) + ')');
    }
    var payload = {
      p_request: FM.req('issue'), p_roll: rollId, p_order: wo,
      p_qty: qty, p_kind: 'consumption', p_note: v('fm_is_note') || null,
      p_waste: waste, p_scrap: scrap
    };
    return FM.run('تم صرف الكمية من الرول', function () {
      return rpc('factory_issue_roll', payload);
    }, 'issue');
  };

  FM.split = function () {
    var rollId = v('fm_sp_roll'), keep = fmNum(v('fm_sp_qty')), code = (v('fm_sp_code') || '').trim();
    var r = FM.roll(rollId);
    if (!r) return alert('اختر الرول');
    if (!code) return alert('أدخل كودًا للرول الجديد');
    if (keep <= 0) return alert('أدخل الكمية المتبقية المراد نقلها');
    if (keep >= +r.remaining_qty) return alert('البقية يجب أن تكون أقل من المتبقي الحالي (' + fmQty(r.remaining_qty) + ')');
    return FM.run('تم تقسيم البقية إلى رول مستقل', function () {
      return rpc('factory_split_roll_remainder', { p_request: FM.req('split'), p_roll: rollId, p_keep: keep, p_new_code: code });
    }, 'split');
  };

  // شراء رولات: صفوف ديناميكية في الجدول
  FM.buyLines = [{ code: '', color: '', width: '', qty: '' }];
  FM.addBuyLine = function () { FM.buyLines.push({ code: '', color: '', width: '', qty: '' }); return R('soft'); };
  FM.delBuyLine = function (i) { FM.buyLines.splice(i, 1); if (!FM.buyLines.length) FM.addBuyLineRaw(); return R('soft'); };
  FM.addBuyLineRaw = function () { FM.buyLines = [{ code: '', color: '', width: '', qty: '' }]; };
  FM.readBuyLines = function () {
    FM.buyLines.forEach(function (l, i) {
      l.code = v('fm_bc' + i) || ''; l.color = v('fm_bcol' + i) || '';
      l.width = v('fm_bw' + i) || ''; l.qty = v('fm_bq' + i) || '';
    });
  };
  FM.buy = function () {
    FM.readBuyLines();
    var pid = v('fm_b_p'), wid = v('fm_b_w'), sup = v('fm_b_sup'), price = fmNum(v('fm_b_price'));
    if (!pid || !wid || !sup) return alert('اختر الصنف والمخزن والمورد');
    var rolls = [], total = 0;
    for (var i = 0; i < FM.buyLines.length; i++) {
      var l = FM.buyLines[i];
      if (!l.code && !l.qty) continue;
      if (!l.code.trim() || !l.color.trim() || fmNum(l.width) <= 0 || fmNum(l.qty) <= 0) return alert('كل رول يحتاج كودًا ولونًا وعرضًا وكمية أكبر من صفر');
      rolls.push({ code: l.code.trim(), color: l.color.trim(), width: fmNum(l.width), qty: fmNum(l.qty) });
      total += fmNum(l.qty);
    }
    if (!rolls.length) return alert('أضف رولًا واحدًا على الأقل');
    if (!confirm('سيتم إنشاء فاتورة شراء آجلة بقيمة ' + fmMoney(total * price) + ' و' + rolls.length + ' رول. متابعة؟')) return;
    return FM.run('تم شراء الرولات وإنشاء فاتورة الشراء', function () {
      return rpc('factory_buy_rolls', { p_request: FM.req('buy'), p_supplier: sup, p_warehouse: wid, p_product: pid, p_price: price, p_rolls: rolls });
    }, 'buy');
  };

  // ------------------------------------------------------------------ view
  function fmTabBtn(id, label, icon) {
    return '<button class="btn ' + (FM.tab === id ? '' : 'soft') + '" onclick="FM.setTab(\'' + id + '\')">' + (icon ? ico(icon) + ' ' : '') + label + '</button>';
  }

  function fmBanner() {
    return '<div class="card" role="alert" style="border-inline-start:4px solid #b45309">' +
      '<b>دفتر الرولات — المرحلة 1 (محلي/تجريبي)</b>' +
      '<p class="muted" style="margin:6px 0 0">الرولات صارت أرصدة حقيقية تُصرف مع حركة مخزون FEDO في نفس المعاملة. ' +
      'إكمال التصنيع ما زال يستخدم الوظيفة القديمة ولن يعتمد على دفتر الرولات قبل المرحلة 2.</p></div>' +
      (FM.error ? '<div class="card error-card"><b>تنبيه</b><p>' + e(FM.error) + '</p></div>' : '');
  }

  function fmSummary() {
    var tracked = FM.trackedProducts();
    var remaining = (FM.rolls || []).reduce(function (a, r) { return a + (+r.remaining_qty || 0); }, 0);
    var value = (FM.rolls || []).reduce(function (a, r) { return a + (+r.value_remaining || 0); }, 0);
    var waste = (FM.moves || []).filter(function (m) { return m.movement_type === 'waste'; })
      .reduce(function (a, m) { return a + Math.abs(+m.quantity_delta || 0); }, 0);
    var cards = [
      ['الرولات المسجلة', fmt((FM.rolls || []).length)],
      ['أصناف متتبعة', fmt(tracked.length)],
      ['إجمالي المتبقي', fmQty(remaining)],
      ['قيمة المتبقي (بالتكلفة)', fmMoney(value)],
      ['الهالك المسجل', fmQty(waste)]
    ];
    return '<div class="report-cards">' + cards.map(function (c) {
      return '<div class="card"><small class="muted">' + c[0] + '</small><div style="font-size:22px;font-weight:700">' + c[1] + '</div></div>';
    }).join('') + '</div>';
  }

  // tab 1 — the roll stock table
  function fmStockTab() {
    var rows = (FM.rolls || []).map(function (r) {
      return [e(r.roll_code), e(FM.pname(r.product_id)), e(FM.wname(r.warehouse_id)), e(r.color || '—'),
        fmt(r.width), fmQty(r.original_qty), '<b>' + fmQty(r.remaining_qty) + '</b>',
        fmMoney(r.unit_cost), fmMoney(r.value_remaining),
        r.is_split_source ? chip('مقسّم', 'warning') : chip(r.remaining_qty > 0 ? 'متاح' : 'مستهلك', r.remaining_qty > 0 ? 'success' : 'info')];
    });
    var body = rows.length ? T(['الرول', 'الخامة', 'المخزن', 'اللون', 'العرض', 'الأصلية', 'المتبقي', 'تكلفة', 'القيمة', 'الحالة'], rows)
      : '<div class="card muted">لا توجد رولات مسجلة. ابدأ بتفعيل التتبع لصنف جديد ثم اشترِ رولات من تبويب «شراء رولات».</div>';
    return '<div class="card"><div class="card-title"><b>أرصدة الرولات</b><span class="muted">الرصيد محسوب من دفتر الحركات ولا يُعدَّل يدويًا.</span></div>' + body + '</div>';
  }

  // tab 2 — issue from a roll (requires a work order)
  function fmIssueTab() {
    var tracked = FM.trackedProducts();
    var rolls = (FM.rolls || []).filter(function (r) { return +r.remaining_qty > 0; });
    var openOrders = (FM.orders || []).filter(function (o) { return o.status !== 'Completed' && o.status !== 'Cancelled'; });
    if (!rolls.length) return '<div class="card muted">لا توجد رولات متاحة للصرف.</div>';
    if (!openOrders.length) return '<div class="card muted">لا يوجد أمر تصنيع مفتوح. أنشئ أمر تصنيع من شاشة التصنيع أولًا.</div>';
    return '<div class="card form-card"><div class="card-title"><b>صرف من رول</b><span class="muted">كل صرف يُسجَّل في دفتر الرولات وحركة مخزون FEDO في نفس المعاملة.</span></div>' +
      '<div class="row"><select id="fm_is_roll">' + rolls.map(function (r) {
        return '<option value="' + r.roll_id + '">' + e(r.roll_code) + ' — ' + e(FM.pname(r.product_id)) + ' — متبقي ' + fmQty(r.remaining_qty) + '</option>';
      }).join('') + '</select>' +
      '<select id="fm_is_wo">' + openOrders.map(function (o) {
        return '<option value="' + o.id + '">' + e(o.number) + ' — ' + e(FM.wname(o.warehouse_id)) + '</option>';
      }).join('') + '</select></div>' +
      '<div class="row"><input id="fm_is_qty" type="number" step="0.001" placeholder="الكمية المصروفة للإنتاج">' +
      '<input id="fm_is_waste" type="number" step="0.001" placeholder="هالك (اختياري)">' +
      '<input id="fm_is_scrap" type="number" step="0.001" placeholder="بواقي (اختياري)">' +
      '<input id="fm_is_note" placeholder="ملاحظة"></div>' +
      '<div class="row"><button class="btn" onclick="FM.issue()">صرف</button>' +
      '<span class="muted">الهالك والبواقي تُخصم من نفس الرول وتُسجَّل تفصيلًا على الحركة.</span></div></div>' +
      '<div class="card"><b>حركات الرولات (آخر 50)</b>' + fmMovesTable(50) + '</div>';
  }

  function fmMovesTable(limit) {
    var rows = (FM.moves || []).slice().sort(function (a, b) { return String(b.created_at).localeCompare(String(a.created_at)); })
      .slice(0, limit || 200).map(function (m) {
        var r = FM.roll(m.roll_id);
        return [new Date(m.created_at).toLocaleString(locOf()), r ? e(r.roll_code) : '—',
          chip(FM_MOVE[m.movement_type] || m.movement_type, m.movement_type === 'waste' ? 'danger' : m.movement_type === 'receipt' ? 'success' : 'info'),
          fmQty(m.quantity_delta), m.consumed_qty != null ? fmQty(m.consumed_qty) : '—',
          m.waste_qty != null ? fmQty(m.waste_qty) : '—', m.scrap_qty != null ? fmQty(m.scrap_qty) : '—',
          e(FM.oname(m.work_order_id)), e(m.ref_doc || '—')];
      });
    return rows.length ? T(['الوقت', 'الرول', 'النوع', 'الكمية', 'للتشغيل', 'هالك', 'بواقي', 'الأمر', 'ملاحظة'], rows)
      : '<p class="muted">لا توجد حركات بعد.</p>';
  }

  // tab 3 — split remainder
  function fmSplitTab() {
    var rolls = (FM.rolls || []).filter(function (r) { return +r.remaining_qty > 0 && !r.is_split_source; });
    if (!rolls.length) return '<div class="card muted">لا يوجد رول متاح للتقسيم.</div>';
    return '<div class="card form-card"><div class="card-title"><b>تقسيم بقية</b><span class="muted">ينقل الكمية المحددة إلى رول جديد مستقل؛ الأصل يبقى بالأثر الكامل.</span></div>' +
      '<div class="row"><select id="fm_sp_roll">' + rolls.map(function (r) {
        return '<option value="' + r.roll_id + '">' + e(r.roll_code) + ' — متبقي ' + fmQty(r.remaining_qty) + '</option>';
      }).join('') + '</select>' +
      '<input id="fm_sp_qty" type="number" step="0.001" placeholder="الكمية المنقولة للرول الجديد">' +
      '<input id="fm_sp_code" placeholder="كود الرول الجديد">' +
      '<button class="btn" onclick="FM.split()">تقسيم</button></div></div>';
  }

  // tab 4 — purchase rolls for a tracked product
  function fmBuyTab() {
    var tracked = FM.trackedProducts();
    if (!tracked.length) {
      return '<div class="card muted">لا يوجد صنف متتبع بعد. فعّل التتبع من تبويب «تفعيل التتبع» ثم عد إلى هنا.</div>';
    }
    var lines = FM.buyLines.map(function (l, i) {
      return '<div class="row"><input id="fm_bc' + i + '" placeholder="كود الرول" value="' + e(l.code) + '">' +
        '<input id="fm_bcol' + i + '" placeholder="اللون" value="' + e(l.color) + '">' +
        '<input id="fm_bw' + i + '" type="number" step="0.001" placeholder="العرض" value="' + e(l.width) + '">' +
        '<input id="fm_bq' + i + '" type="number" step="0.001" placeholder="الطول/الكمية" value="' + e(l.qty) + '">' +
        (FM.buyLines.length > 1 ? '<button class="btn s" onclick="FM.delBuyLine(' + i + ')">حذف</button>' : '') + '</div>';
    }).join('');
    return '<div class="card form-card"><div class="card-title"><b>شراء رولات</b><span class="muted">ينشئ فاتورة شراء آجلة وقيودها ودفتر استلام الرولات معًا.</span></div>' +
      '<div class="row"><select id="fm_b_p">' + tracked.map(function (pid) { return '<option value="' + pid + '">' + e(FM.pname(pid)) + '</option>'; }).join('') + '</select>' +
      '<select id="fm_b_w">' + (C.warehouses || []).map(function (w) { return '<option value="' + w.id + '">' + e(w.name) + '</option>'; }).join('') + '</select>' +
      '<select id="fm_b_sup">' + (C.suppliers || []).map(function (s) { return '<option value="' + s.id + '">' + e(s.name) + '</option>'; }).join('') + '</select>' +
      '<input id="fm_b_price" type="number" step="0.01" placeholder="سعر الوحدة"></div>' +
      lines + '<div class="row"><button class="btn soft" onclick="FM.addBuyLine()">+ رول</button>' +
      '<button class="btn" onclick="FM.buy()">شراء الرولات</button></div></div>';
  }

  // tab 5 — tracking setup (zero start / activation of existing stock)
  function fmSetupTab() {
    var trackedRows = (FM.rolls || []).reduce(function (acc, r) {
      var k = r.product_id + '|' + r.warehouse_id;
      if (!acc[k]) acc[k] = { pid: r.product_id, wid: r.warehouse_id, rolls: 0, qty: 0 };
      acc[k].rolls++; acc[k].qty += +r.remaining_qty || 0; return acc;
    }, {});
    var trows = Object.keys(trackedRows).map(function (k) {
      var x = trackedRows[k];
      return [e(FM.pname(x.pid)), e(FM.wname(x.wid)), fmt(x.rolls), fmQty(x.qty),
        '<button class="btn s" onclick="FM.normalizeCosts(\'' + x.pid + '\',\'' + x.wid + '\')">معايرة التكلفة</button>'];
    });
    return '<div class="card form-card"><div class="card-title"><b>بدء تتبع صنف جديد</b><span class="muted">لصنف رصيده صفر. يمنع النظام البدء إذا كان للصنف رصيد غير مطابق.</span></div>' +
      '<div class="row"><select id="fm_en_p">' + (C.products || []).map(function (p) { return '<option value="' + p.id + '">' + e(p.name) + '</option>'; }).join('') + '</select>' +
      '<select id="fm_en_w">' + (C.warehouses || []).map(function (w) { return '<option value="' + w.id + '">' + e(w.name) + '</option>'; }).join('') + '</select>' +
      '<button class="btn" onclick="FM.enableTracking()">بدء التتبع</button></div></div>' +
      '<div class="card"><div class="card-title"><b>الأصناف المتتبعة</b><span class="muted">معايرة التكلفة متاحة فقط قبل التفعيل.</span></div>' +
      (trows.length ? T(['الصنف', 'المخزن', 'الرولات', 'المتبقي', ''], trows) : '<p class="muted">لا توجد أصناف متتبعة.</p>') + '</div>' +
      '<div class="card"><div class="card-title"><b>تفعيل صنف له رصيد قائم</b><span class="muted">يتطلب تسجيل رولات تساوي رصيد FEDO بالضبط؛ استخدمه فقط بعد إدخال الرولات.</span></div>' +
      '<p class="muted">تُدار هذه الحالة عبر <code>factory_activate_roll_control</code> من الأدوات الإدارية بعد تسجيل الرولات ومعايرة التكلفة.</p></div>';
  }

  // tab 6 — variants (read-only in phase 1)
  function fmVariantsTab() {
    var rows = (FM.variants || []).map(function (vr) {
      return [e(FM.pname(vr.parent_product_id)), e(FM.pname(vr.variant_product_id)), e(vr.color), e(vr.size_label)];
    });
    return '<div class="card"><div class="card-title"><b>التركيبات المرتبطة</b><span class="muted">ربط التركيبات يُدار من شاشة التصنيع؛ هنا عرض فقط.</span></div>' +
      (rows.length ? T(['المنتج الأساسي', 'التركيبة', 'اللون', 'المقاس'], rows) : '<p class="muted">لا توجد تركيبات مرتبطة.</p>') + '</div>';
  }

  window.fmView = async function () {
    await FM.load();
    var head = sectionHead('المصنع — دفتر الرولات', 'رولات حقيقية بأرصدة وحركات، مربوطة بمخزون FEDO ومحاسبة الشراء.') +
      fmBanner() + fmSummary() +
      '<div class="card"><div class="row">' +
      fmTabBtn('stock', 'أرصدة الرولات', 'box') + fmTabBtn('issue', 'صرف واستخدام', 'box2') +
      fmTabBtn('split', 'تقسيم بقية', 'swaplr') + fmTabBtn('buy', 'شراء رولات', 'down') +
      fmTabBtn('setup', 'تفعيل التتبع', 'gear') + fmTabBtn('variants', 'التركيبات', 'grid') +
      '</div></div>';
    var body =
      FM.tab === 'issue' ? fmIssueTab() :
      FM.tab === 'split' ? fmSplitTab() :
      FM.tab === 'buy' ? fmBuyTab() :
      FM.tab === 'setup' ? fmSetupTab() :
      FM.tab === 'variants' ? fmVariantsTab() : fmStockTab();
    return head + body;
  };
})();
