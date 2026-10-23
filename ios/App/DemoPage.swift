import Foundation

/// A small test page for the UI checks in CI (launch argument -GymDemo): it talks to the app exactly like Gym Tracker
/// does — the wheels for weight and reps, the wheels for time, a button with a press-and-hold menu — so the checks
/// can open them in the simulator and take pictures. Nobody sees it in normal use.
enum DemoPage {
    static let html = #"""
    <!doctype html>
    <html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
    <style>
    :root{color-scheme:dark}
    body{margin:0;background:#1E1E1E;color:#DADADA;font:17px -apple-system,system-ui;padding:calc(env(safe-area-inset-top) + 16px) 16px 420px;-webkit-user-select:none;-webkit-touch-callout:none}
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
    </style></head>
    <body>
    <h1>Проверка</h1>
    <div class="card">
      <div class="row"><span class="n">1</span><button class="chip" id="w" aria-label="Вес">30 кг</button><span>×</span><button class="chip r" id="r" aria-label="Повторы">8 раз</button></div>
      <div class="row"><span class="n">2</span><button class="chip" id="t" aria-label="Время">27 мин 30 с</button></div>
    </div>
    <div class="btns"><button class="btn main" id="go">Начать</button><button class="btn gray" id="hold" aria-label="Запланировать">Запланировать</button></div>
    <div id="log">—</div>
    <script>
    const N = window.webkit.messageHandlers.gymNative;
    const log = document.getElementById('log');
    window.__gymNative = d => { log.textContent = JSON.stringify(d); return true; };
    N.postMessage({ type: 'hello', v: 'demo' });
    N.postMessage({ type: 'look', bg: '#1E1E1E', accent: '#8B6CEF', dark: true, sheet: '#262626', label: '#DADADA', label2: '#A3A3A3', tint: '#A88BFA' });
    const range = (a, b, s) => { const r = []; for (let v = a; v <= b + 1e-9; v += s || 1) r.push(+v.toFixed(2)); return r; };
    const kg = range(0, 150, 2.5), reps = range(0, 30);
    const pl = n => (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) ? 'раза' : 'раз';
    const weights = id => N.postMessage({ type: 'picker', id: id, title: 'Жим штанги лёжа', sub: 'Подход 1', done: 'Готово',
      cols: [{ rows: kg.map(v => String(v).replace('.', ',')), sel: kg.indexOf(30), units: ['кг'], label: 'Вес, кг' },
             { rows: reps.map(String), sel: 8, units: reps.map(pl), label: 'Повторы' }] });
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
    const zones = () => { const r = hold.getBoundingClientRect(); N.postMessage({ type: 'holdZones', zones: { hero: { x: r.left, y: r.top, w: r.width, h: r.height, r: 25 } } }); };
    addEventListener('scroll', () => requestAnimationFrame(zones), { passive: true });
    addEventListener('resize', zones);
    setTimeout(zones, 300); setTimeout(zones, 1500);
    </script>
    </body></html>
    """#
}
