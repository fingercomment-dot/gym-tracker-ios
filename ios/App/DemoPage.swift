import Foundation

/// A small test page for the UI checks in CI (launch argument -GymDemo): it talks to the app exactly like Gym Tracker
/// does — the tab bar, Today and Settings drawn by the app from what the web app sends (DemoScreens), a workout list
/// the app draws itself (with a sheet of the page over it), the player bar of a minimised workout, the wheels' panel,
/// a button with a press-and-hold menu — so the checks can use them in the simulator and take pictures. Nobody sees
/// it in normal use.
enum DemoPage {
    static let html = #"""
    <!doctype html>
    <html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
    <style>
    :root{color-scheme:dark}
    html,body{background:#1E1E1E}
    body{margin:0;color:#DADADA;font:17px -apple-system,system-ui;padding:calc(env(safe-area-inset-top) + 16px) 16px 420px;-webkit-user-select:none;-webkit-touch-callout:none}
    html.nunder,html.nunder body{background:transparent!important}
    html.nunder #page{visibility:hidden}
    h1{font-size:30px;margin:0 0 16px}
    .card{background:#2A2A2A;border-radius:14px;padding:6px 12px;margin-bottom:14px}
    .row{display:flex;align-items:center;gap:8px;min-height:48px}
    .n{color:#666;width:20px}
    .chip{border:0;border-radius:9px;padding:6px 10px;background:rgba(116,116,128,.18);color:#A88BFA;font:600 17px -apple-system}
    .chip.r{color:#DADADA}
    .btns{display:flex;gap:10px;margin:18px 0}
    .btn{flex:1;display:inline-flex;align-items:center;justify-content:center;min-height:50px;padding:0 16px;border-radius:25px;border:0;font:600 17px -apple-system}
    .btn.main{background:#7C5CEF;color:#fff}
    .btn.gray{background:rgba(118,118,128,.24);color:#DADADA}
    #log{font:13px ui-monospace,Menlo,monospace;color:#A3A3A3;white-space:pre-wrap;margin-top:8px}
    #back{position:fixed;inset:0;background:rgba(0,0,0,.4);display:none}
    #sheet{position:fixed;left:0;right:0;bottom:0;height:55%;background:#262626;border-radius:12px 12px 0 0;display:none;padding:16px;box-sizing:border-box}
    #sheet h2{margin:8px 0 12px;font-size:20px}
    </style></head>
    <body>
    <div id="page">
    <h1 id="tabtitle">Сегодня</h1>
    <div class="card">
      <div class="row"><span class="n">1</span><button class="chip" id="w" aria-label="Вес">30 кг</button><span>×</span><button class="chip r" id="r" aria-label="Повторы">8 раз</button></div>
      <div class="row"><span class="n">2</span><button class="chip" id="t" aria-label="Время">27 мин 30 с</button></div>
    </div>
    <div class="btns"><button class="btn main" id="go" aria-label="Тренировка">Тренировка</button><button class="btn gray" id="hold" aria-label="Запланировать">Запланировать</button></div>
    <div id="log">—</div>
    </div>
    <div id="back"></div>
    <div id="sheet"><h2>Как выполнять</h2><p>Окно страницы поверх списка приложения.</p><button class="btn gray" id="close" aria-label="Закрыть окно">Закрыть</button></div>
    <script>
    const N = window.webkit.messageHandlers.gymNative;
    const log = document.getElementById('log');
    const TABS = [['today', 'Сегодня', 'dumbbell.fill'], ['calendar', 'Календарь', 'calendar'], ['progress', 'Прогресс', 'chart.bar.fill'], ['more', 'Настройки', 'gearshape.fill']];
    let tab = 'calendar';
    const tabs = show => N.postMessage({ type: 'tabs', show: show, tab: tab, items: TABS.map(t => ({ id: t[0], title: t[1], sf: t[2] })) });

    /* a workout like the real one: pull-ups, bench, a superset */
    const plural = n => (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) ? 'раза' : 'раз';
    const kgVals = []; for (let v = 0; v <= 150 + 1e-9; v += 2.5) kgVals.push(+v.toFixed(2));
    const W = { on: false, warm: false, rest: null, startedAt: Date.now() - 4000, blocks: [
      { title: 'Подтягивания прямым хватом', sub: 'лесенка 4 · 3 · 3 · 3', info: true, open: true, items: [{ name: 'Подтягивания прямым хватом', bw: true, sets: [[0, 4], [0, 3], [0, 3], [0, 3]], done: 0 }] },
      { title: 'Жим штанги лёжа', sub: '3 × 6–10 · отдых 3:00 · 30 кг', info: true, open: false, items: [{ name: 'Жим штанги лёжа', sets: [[30, 8], [30, 8], [30, 8]], done: 0 }] },
      { title: 'Бицепс + Трицепс', sub: 'суперсет · 3 круга · отдых 2:45', info: false, open: false, ss: true, items: [
        { name: 'Бицепс со штангой', sets: [[22.5, 10], [22.5, 10], [22.5, 10]], done: 0 }, { name: 'Трицепс вниз', sets: [[10, 12], [10, 12], [10, 12]], done: 0 }] }] };
    const fmt = v => String(v).replace('.', ',');
    function state() {
      const units = []; for (let v = 0; v <= 30; v++) units.push(plural(v));
      return { sid: 'demo', title: 'Верх A', startedAt: W.startedAt,
        today: [{ kind: 'ready', score: 61, t: 'Готовность', v: 'Держим веса', tone: 'warn' }, { kind: 'info', t: 'Восстановление среднее: веса не повышаем, отдых +30 секунд.' }],
        warm: { t: '5 минут кардио', s: 'велосипед или эллипс', on: W.warm },
        done: W.blocks.filter(b => b.items.every(it => it.done >= it.sets.length)).length, total: W.blocks.length, rest: W.rest,
        blocks: W.blocks.map((b, bi) => ({ b: bi, key: 'b' + bi, title: b.title, sub: b.sub, done: b.items.every(it => it.done >= it.sets.length), quick: false,
          open: b.open, info: b.info, ss: !!b.ss, canEnd: b.items.some(it => it.done > 0),
          items: b.items.map((it, ii) => ({ i: ii, name: it.name,
            w: it.bw ? null : { vals: kgVals, rows: kgVals.map(fmt), unit: 'кг', label: 'Вес' },
            r: { max: 30, units: units, label: 'Повторы' },
            sets: it.sets.map((s, k) => ({ k: k, w: s[0], r: s[1], done: k < it.done, last: k === it.done - 1, next: k === it.done,
              text: (it.bw ? '+' + fmt(s[0]) + ' кг × ' : fmt(s[0]) + ' кг × ') + s[1] + ' ' + plural(s[1]) })) })) })),
        finish: { t: 'Завершить досрочно', primary: false, ask: { kind: 'finish', title: 'Завершить тренировку?', text: 'Не закончено: 3 упражнения. Сохраню всё, что успел сделать.', ok: 'Завершить', cancel: 'Продолжить', danger: false } },
        labels: { minimize: 'Свернуть', today: 'Сегодня', warm: 'Разминка', exercises: 'Упражнения', of: ' из ', set: 'Подход', round: 'Круг', addSet: 'Добавить подход', addRound: 'Добавить круг',
          more: 'Ещё', endBlock: 'Закончить упражнение', old: 'Разминка, замена, заметки', info: 'Как выполнять', rest: 'Отдых', noRest: 'Без отдыха', quick: 'Отметить по плану', unquick: 'Снять отметку' } };
    }
    /* a step of the workout, the summary: the app draws what the web app sends for them (captured) */
    const STEP_NEXT = { intro: 'set', set: 'rest', rest: 'trans', trans: 'set' };
    /* the captured rest timer and the workout's clock start now, as they would in a real workout */
    const fresh = sc => { if (!sc) return null; const c = JSON.parse(JSON.stringify(sc)); const now = Date.now();
      (c.right || []).forEach(i => { if (i.k === 'clock') i.since = W.startedAt; });
      (c.secs || []).forEach(sec => sec.rows.forEach(r => { if (r.k === 'ring') r.start = now - 25000; if (r.k === 'timer') r.since = now - 8000; }));
      return c; };
    const sendStage = () => N.postMessage({ type: 'nv', tab: 'stage', screen: W.stage ? fresh(NVS.stage[W.stage].screen) : null, mode: W.stage ? NVS.stage[W.stage].mode : null });
    const sendWorkout = () => {
      if (W.on) W.started = true;
      sendStage();
      N.postMessage({ type: 'workout', show: W.on, state: W.on ? state() : null });
      tabs(!W.on && !W.stage);
      N.postMessage(W.started && !W.on ? { type: 'mini', show: true, t: 'Верх A', letter: 'A', c: '#0A84FF', on: '#FFFFFF', startedAt: W.startedAt,
        rest: W.rest ? { start: W.rest.start, end: W.rest.end } : null, label: 'Идёт тренировка · 0 из 3', restT: 'Отдых', overT: 'Отдых закончился', open: 'Открыть тренировку' } : { type: 'mini', show: false });
      nvSend();
    };

    /* Today and Settings, drawn by the app from what the web app sends (captured on test data) */
    \#(DemoScreens.js)
    let moreSub = null;
    /* Calendar stays the page's own (the wheels and the menu checks use it) until Today has been opened */
    let calNative = false;
    const nativeTab = () => !W.on && (tab === 'today' || tab === 'more' || tab === 'progress' || (tab === 'calendar' && calNative));
    function nvSend() {
      document.documentElement.classList.toggle('nunder', W.on || nativeTab());
      if (tab === 'today') N.postMessage({ type: 'nv', tab: 'today', screen: NVS.today, root: null });
      if (tab === 'more') N.postMessage({ type: 'nv', tab: 'more', screen: moreSub ? NVS[moreSub] : NVS.more, root: moreSub ? NVS.more : null });
      if (tab === 'progress') N.postMessage({ type: 'nv', tab: 'progress', screen: NVS.progress, root: null });
      if (tab === 'calendar') N.postMessage({ type: 'nv', tab: 'calendar', screen: calNative ? NVS.calendar : null, root: null });
    }
    /* the sheets the app draws: the web app's own sheets, captured */
    let SH = [];
    const nvsSend = () => N.postMessage({ type: 'nvs', sheets: SH });
    const openNv = list => { SH = SH.concat(list.map(x => JSON.parse(JSON.stringify(x)))); nvsSend(); };
    function sheetAct(f, d) {
      const i = SH.findIndex(sh => findFn(sh, f, null));
      if (i < 0) return false;
      const sh = SH[i];
      /* the exercise card: its tabs are the captured tabs of the same sheet */
      if (sh._excard) {
        const seg = findFn(sh, f, null);
        if (seg && seg.node.k === 'seg' && NVS.excard[d.v]) { const c = JSON.parse(JSON.stringify(NVS.excard[d.v])); c.id = sh.id; c._excard = true; SH[i] = c; nvsSend(); return true; }
      }
      const closeHere = () => { SH = SH.slice(0, i); nvsSend(); };
      if (sh.kind === 'actions') { closeHere(); return true; }
      if (f === sh.close || (sh.left && f === sh.left.fn) || (sh.right && f === sh.right.fn)) { closeHere(); return true; }
      if ((sh.foot || []).some(b => b.fn === f)) {
        closeHere();
        if (/Начать/.test(sh.foot[0].t || '')) { W.on = true; sendWorkout(); }
        return true;
      }
      const hit = findFn(sh, f, null); const n = hit.node;
      if (n.k === 'row' && n.tt === 'bad' && NVS.sheets.session[1]) { openNv([NVS.sheets.session[1]]); return true; }
      if (n.k === 'toggle') n.on = !!d.v;
      else if (n.k === 'seg') n.sel = String(d.v);
      else if (n.k === 'wheels' && Array.isArray(d.v)) n.cols.forEach((c, k) => { c.sel = d.v[k]; });
      nvsSend();
      return true;
    }
    /* the thing whose function the app sent back, and what holds it */
    function findFn(node, fn, parent) {
      if (!node || typeof node !== 'object') return null;
      if (Array.isArray(node)) { for (const x of node) { const r = findFn(x, fn, parent); if (r) return r; } return null; }
      for (const k in node) {
        if (node[k] === fn) return { node: node, key: k, parent: parent };
        if (node[k] && typeof node[k] === 'object') { const r = findFn(node[k], fn, Array.isArray(node[k]) ? node : node[k]); if (r) return r; }
      }
      return null;
    }
    function nvAct(d) {
      const f = String(d.fn || '');
      log.textContent = 'nva ' + f + (d.v !== undefined ? ' = ' + JSON.stringify(d.v) : '');
      if (d.tab === 'sheets' || SH.length) { if (sheetAct(f, d)) return; }
      if (d.tab === 'stage') {
        const sc = W.stage && NVS.stage[W.stage].screen; if (!sc) return;
        if (f === sc.back) { W.stage = null; sendStage(); return; }
        if ((sc.foot || []).some(b => b.fn === f)) { W.stage = STEP_NEXT[W.stage] || null; sendStage(); return; }
        if ((sc.right || []).some(r => r.fn === f)) { W.stage = null; tab = 'today'; sendWorkout(); return; }
        /* «Отправить Claude» on the summary: the page copies the report and says so */
        const hit = findFn(sc, f, null);
        if (hit && /Отправить/.test(hit.node.t || '')) N.postMessage({ type: 'toast', t: 'Отчёт скопирован — вставь его в чат с Claude', sf: 'doc.on.doc' });
        return;
      }
      if (f.indexOf('s:plan/ex:') >= 0) { const c = JSON.parse(JSON.stringify(NVS.excard.tech)); c._excard = true; SH = SH.concat([c]); nvsSend(); return; }
      if (f.indexOf('q-weight') >= 0) { openNv(NVS.sheets.weight); return; }
      if (f.indexOf('q-sleep') >= 0) { openNv(NVS.sheets.sleep); return; }
      if (f.indexOf('q-cardio') >= 0) { openNv(NVS.sheets.cardio); return; }
      if (f.indexOf('Начать тренировку') >= 0) { openNv(NVS.sheets.start); return; }
      if (f.indexOf('Последняя тренировка') >= 0) { openNv([NVS.sheets.session[0]]); return; }
      if (d.tab === 'calendar') {
        if (f.indexOf(':mfn') >= 0) return;
        if (f.indexOf('month') >= 0) { openNv(NVS.sheets.day); return; }
        if (f.indexOf('Спланировать') >= 0) { openNv(NVS.sheets.planweek); return; }
      }
      if (f.indexOf('/Оформление:fn') >= 0) { moreSub = 'look'; nvSend(); return; }
      if (f.indexOf('/Программа:fn') >= 0) { moreSub = 'program'; nvSend(); return; }
      if (/:back$/.test(f)) { moreSub = null; nvSend(); return; }
      const scr = tab === 'today' ? NVS.today : moreSub ? NVS[moreSub] : NVS.more;
      const hit = findFn(scr, f, null); if (!hit) return;
      const n = hit.node;
      if (hit.key === 'move') {
        const keyed = n.rows.filter(r => r.key), rest = n.rows.filter(r => !r.key);
        n.rows = rest.concat(d.v.map(k => keyed.find(r => r.key === k)).filter(Boolean));
      } else if (hit.key === 'fn' && !n.k && 'open' in n) n.open = !!d.v;
      else if (hit.key === 'fn' && n.k === 'toggle') n.on = !!d.v;
      else if (hit.key === 'fn' && (n.k === 'swatches' || n.k === 'seg')) n.sel = String(d.v);
      else if (hit.key === 'fn' && n.k === 'weeks') n.page = +d.v;
      else if (hit.key === 'fn' && !n.k && n.t !== undefined) {
        /* a pick in a button's menu: it becomes what the button does */
        const btn = findFn(scr, n.fn.replace(/:menu:items\.\d+:fn$/, ':fn'), null);
        const items = (btn && btn.node.menu && btn.node.menu.items) || [];
        items.forEach(it => { it.on = it === n; });
        if (btn) { btn.node.t = n.t; btn.node.sf = n.sf; }
      } else return;
      nvSend();
    }
    function act(d) {
      const b = W.blocks[d.b], it = b && b.items[d.i];
      if (d.a === 'log' && it) { it.done = Math.max(it.done, d.k + 1); W.rest = { kind: 'rest', start: Date.now(), end: Date.now() + 120000 }; N.postMessage({ type: 'haptic', style: 'medium' }); }
      if (d.a === 'unlog' && it && it.done > 0) it.done--;
      if (d.a === 'val' && it) { const s = it.sets[d.k]; if (typeof d.w === 'number') s[0] = d.w; if (typeof d.r === 'number') s[1] = d.r; }
      if (d.a === 'open' && b) b.open = !!d.open;
      if (d.a === 'add' && b) b.items.forEach(x => x.sets.push(x.sets[x.sets.length - 1].slice()));
      if (d.a === 'warm') W.warm = !!d.on;
      if (d.a === 'quick' && b) b.items.forEach(x => { x.done = x.sets.length; });
      if (d.a === 'info') openSheet();
      if (d.a === 'old') W.stage = 'intro';
      if (d.a === 'min' || d.a === 'finish') { W.on = false; W.stage = null; }
      if (d.a === 'finish') { W.started = false; W.stage = 'sum'; }
      sendWorkout();
    }
    function openSheet() { document.getElementById('back').style.display = 'block'; document.getElementById('sheet').style.display = 'block'; N.postMessage({ type: 'overlay', on: true }); }
    function closeSheet() { document.getElementById('back').style.display = 'none'; document.getElementById('sheet').style.display = 'none'; N.postMessage({ type: 'overlay', on: false }); }
    document.getElementById('close').onclick = closeSheet;
    document.getElementById('back').onclick = closeSheet;
    document.getElementById('go').onclick = () => { W.on = true; sendWorkout(); };

    window.__gymNative = d => {
      if (d.type === 'tab') { tab = d.tab; if (tab === 'today') calNative = true; document.getElementById('tabtitle').textContent = TABS.find(t => t[0] === tab)[1]; tabs(true); nvSend(); }
      if (d.type === 'wact') act(d);
      if (d.type === 'nva') { nvAct(d); return true; }
      if (d.type === 'mini' && d.a === 'open') { W.on = true; sendWorkout(); }
      log.textContent = JSON.stringify(d);
      return true;
    };
    N.postMessage({ type: 'hello', v: 'demo' });
    N.postMessage({ type: 'look', bg: '#1E1E1E', accent: '#8B6CEF', dark: true, sheet: '#262626', label: '#DADADA', label2: '#A3A3A3', tint: '#A88BFA' });
    tabs(true);
    document.getElementById('tabtitle').textContent = 'Календарь';
    const range = (a, b, s) => { const r = []; for (let v = a; v <= b + 1e-9; v += s || 1) r.push(+v.toFixed(2)); return r; };
    const reps = range(0, 30);
    const weights = id => N.postMessage({ type: 'picker', id: id, title: 'Жим штанги лёжа', sub: 'Подход 1', done: 'Готово',
      cols: [{ rows: kgVals.map(fmt), sel: kgVals.indexOf(30), units: ['кг'], label: 'Вес, кг' },
             { rows: reps.map(String), sel: 8, units: reps.map(plural), label: 'Повторы' }] });
    document.getElementById('w').onclick = () => weights('p1');
    document.getElementById('r').onclick = () => weights('p2');
    document.getElementById('t').onclick = () => N.postMessage({ type: 'picker', id: 'p3', title: 'Время', sub: '', done: 'Готово',
      cols: [{ rows: range(0, 9).map(String), sel: 0, units: ['ч'], label: 'Часы' },
             { rows: range(0, 59).map(String), sel: 27, units: ['мин'], label: 'Минуты' },
             { rows: range(0, 59).map(v => String(v).padStart(2, '0')), sel: 30, units: ['с'], label: 'Секунды' }] });
    const hold = document.getElementById('hold');
    hold.onclick = () => { log.textContent = 'tap'; };
    N.postMessage({ type: 'holdMenu', id: 'hero', title: 'Что делает кнопка', items: [
      { id: '0', title: 'Запланировать', sub: 'поставить тренировку на сегодня в календарь', sf: 'calendar', on: true },
      { id: '1', title: 'Отправить Claude', sub: 'копирует отчёт о последней тренировке для чата', sf: 'doc.on.doc', on: false },
      { id: '2', title: 'Как прошло?', sub: 'заметка к последней тренировке', sf: 'square.and.pencil', on: false },
      { id: '3', title: 'Восстановление', sub: 'какие мышцы работали и когда их снова грузить', sf: 'battery.75percent', on: false }] });
    const zones = () => { const r = hold.getBoundingClientRect(); N.postMessage({ type: 'holdZones', zones: { hero: W.on || nativeTab() ? null : { x: r.left, y: r.top, w: r.width, h: r.height, r: 25 } } }); };
    addEventListener('scroll', () => requestAnimationFrame(zones), { passive: true });
    addEventListener('resize', zones);
    setTimeout(zones, 300); setTimeout(zones, 1500); setInterval(zones, 1000);
    </script>
    </body></html>
    """#
}
