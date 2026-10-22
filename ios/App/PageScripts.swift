import Foundation

enum PageScripts {
    /// Runs on Claude's page around the app. When asked, it lays the app's frame over the whole screen and hides
    /// the rest of Claude's page; asked again, it puts everything back as it was. Returns whether it found the frame.
    /// Styles go in through the element's own style object, which a page's Content-Security-Policy doesn't block.
    static let focus = #"""
    (function () {
      if (window.__gymFocus) return;
      var on = false, frame = null, observer = null, raf = 0, viewportOld = null, bg = '#000000';
      var saved = new Map();
      var FRAME = { position: 'fixed', top: '0px', left: '0px', right: 'auto', bottom: 'auto', width: '100%', height: '100%',
        'min-width': '0px', 'min-height': '0px', 'max-width': 'none', 'max-height': 'none', margin: '0px', padding: '0px',
        border: '0px', 'border-radius': '0px', 'box-shadow': 'none', transform: 'none', opacity: '1', visibility: 'visible',
        'z-index': '2147483647' };
      var ANCESTOR = { transform: 'none', filter: 'none', perspective: 'none', contain: 'none', 'container-type': 'normal',
        'will-change': 'auto', 'clip-path': 'none', '-webkit-mask': 'none', mask: 'none', 'z-index': 'auto', opacity: '1',
        isolation: 'auto', 'mix-blend-mode': 'normal', '-webkit-backdrop-filter': 'none', 'backdrop-filter': 'none',
        'content-visibility': 'visible', visibility: 'visible' };
      var ROOT = { overflow: 'hidden', 'overscroll-behavior': 'none' };

      function put(el, props) {
        if (!saved.has(el)) saved.set(el, el.style.cssText);
        for (var k in props) {
          var v = props[k];
          if (el.style.getPropertyValue(k) !== v || el.style.getPropertyPriority(k) !== 'important') el.style.setProperty(k, v, 'important');
        }
      }
      function restoreAll() {
        saved.forEach(function (css, el) { el.style.cssText = css; });
        saved.clear();
      }
      function pick() {
        var best = null, area = 0, list = document.getElementsByTagName('iframe');
        for (var i = 0; i < list.length; i++) {
          var r = list[i].getBoundingClientRect(), a = r.width * r.height;
          if (a > area) { area = a; best = list[i]; }
        }
        return best;
      }
      function apply() {
        var f = (frame && frame.isConnected) ? frame : pick();
        if (!f) return false;
        if (frame && frame !== f) restoreAll();
        frame = f;
        var own = {}; for (var k in FRAME) own[k] = FRAME[k]; own.background = bg;
        put(f, own);
        var chain = [];
        for (var p = f.parentElement; p; p = p.parentElement) chain.push(p);
        for (var i = 0; i < chain.length; i++) {
          var el = chain[i], props = {};
          for (var a in ANCESTOR) props[a] = ANCESTOR[a];
          if (el === document.documentElement || el === document.body) { for (var r in ROOT) props[r] = ROOT[r]; props.background = bg; }
          put(el, props);
        }
        var kids = document.body ? document.body.children : [];
        for (var j = 0; j < kids.length; j++) {
          if (kids[j] !== f && chain.indexOf(kids[j]) < 0) put(kids[j], { visibility: 'hidden' });
        }
        return true;
      }
      function setViewport(want) {
        var m = document.querySelector('meta[name="viewport"]');
        if (want) {
          if (!m) {
            m = document.createElement('meta');
            m.setAttribute('name', 'viewport');
            (document.head || document.documentElement).appendChild(m);
            viewportOld = '';
          } else if (viewportOld === null) {
            viewportOld = m.getAttribute('content') || '';
          }
          var v = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
          if (m.getAttribute('content') !== v) m.setAttribute('content', v);
        } else if (m && viewportOld !== null) {
          m.setAttribute('content', viewportOld);
          viewportOld = null;
        }
      }
      function keep() {
        if (raf) return;
        raf = requestAnimationFrame(function () {
          raf = 0;
          if (!on) return;
          apply();
          setViewport(true);
        });
      }
      window.__gymFocusBg = function (color) {
        if (color) bg = color;
        if (on) apply();
        return true;
      };
      window.__gymFocus = function (want, color) {
        if (color) bg = color;
        if (want) {
          if (!apply()) return false;
          on = true;
          setViewport(true);
          if (!observer) {
            observer = new MutationObserver(keep);
            observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'content'] });
          }
          return true;
        }
        on = false;
        if (observer) { observer.disconnect(); observer = null; }
        if (raf) { cancelAnimationFrame(raf); raf = 0; }
        restoreAll();
        setViewport(false);
        frame = null;
        return false;
      };
    })();
    """#
}
