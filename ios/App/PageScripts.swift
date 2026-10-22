import Foundation

enum PageScripts {
    /// Runs on Claude's page around the app. When asked, it lays the app's frame over the whole screen and hides
    /// the rest of Claude's page; asked again, it puts everything back. Returns whether it found the frame.
    static let focus = #"""
    (function () {
      if (window.__gymFocus) return;
      var on = false, frame = null, observer = null, raf = 0, viewportOld = null;
      var CSS = [
        'html[data-gym-on], html[data-gym-on] body { overflow: hidden !important; overscroll-behavior: none !important; background: var(--gym-bg, #000) !important; }',
        'html[data-gym-on] [data-gym-anc] { transform: none !important; filter: none !important; perspective: none !important; contain: none !important; container-type: normal !important; will-change: auto !important; clip-path: none !important; -webkit-mask: none !important; mask: none !important; z-index: auto !important; opacity: 1 !important; isolation: auto !important; mix-blend-mode: normal !important; -webkit-backdrop-filter: none !important; backdrop-filter: none !important; content-visibility: visible !important; visibility: visible !important; }',
        'html[data-gym-on] iframe[data-gym-focus] { position: fixed !important; top: 0 !important; left: 0 !important; right: auto !important; bottom: auto !important; width: 100% !important; height: 100% !important; min-width: 0 !important; min-height: 0 !important; max-width: none !important; max-height: none !important; margin: 0 !important; padding: 0 !important; border: 0 !important; border-radius: 0 !important; box-shadow: none !important; transform: none !important; opacity: 1 !important; visibility: visible !important; z-index: 2147483647 !important; background: var(--gym-bg, #000) !important; }',
        'html[data-gym-on] body > *:not([data-gym-anc]):not([data-gym-focus]) { visibility: hidden !important; }'
      ].join(' ');

      function pick() {
        var best = null, area = 0, list = document.getElementsByTagName('iframe');
        for (var i = 0; i < list.length; i++) {
          var r = list[i].getBoundingClientRect(), a = r.width * r.height;
          if (a > area) { area = a; best = list[i]; }
        }
        return best;
      }
      function unmark() {
        var marked = document.querySelectorAll('[data-gym-anc],[data-gym-focus]');
        for (var i = 0; i < marked.length; i++) {
          marked[i].removeAttribute('data-gym-anc');
          marked[i].removeAttribute('data-gym-focus');
        }
        frame = null;
      }
      function mark() {
        var f = (frame && frame.isConnected) ? frame : pick();
        if (!f) return false;
        if (frame && frame !== f) unmark();
        frame = f;
        if (!f.hasAttribute('data-gym-focus')) f.setAttribute('data-gym-focus', '');
        for (var p = f.parentElement; p && p !== document.documentElement; p = p.parentElement) {
          if (!p.hasAttribute('data-gym-anc')) p.setAttribute('data-gym-anc', '');
        }
        return true;
      }
      function ensureStyle() {
        if (document.getElementById('gym-focus-style')) return;
        var s = document.createElement('style');
        s.id = 'gym-focus-style';
        s.textContent = CSS;
        (document.head || document.documentElement).appendChild(s);
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
          m.setAttribute('content', 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover');
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
          ensureStyle();
          if (!document.documentElement.hasAttribute('data-gym-on')) document.documentElement.setAttribute('data-gym-on', '');
          mark();
        });
      }
      window.__gymFocusBg = function (color) {
        if (color) document.documentElement.style.setProperty('--gym-bg', color);
        return true;
      };
      window.__gymFocus = function (want, color) {
        window.__gymFocusBg(color);
        if (want) {
          ensureStyle();
          if (!mark()) return false;
          on = true;
          document.documentElement.setAttribute('data-gym-on', '');
          setViewport(true);
          if (!observer) {
            observer = new MutationObserver(keep);
            observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-gym-on'] });
          }
          return true;
        }
        on = false;
        if (observer) { observer.disconnect(); observer = null; }
        document.documentElement.removeAttribute('data-gym-on');
        setViewport(false);
        unmark();
        return false;
      };
    })();
    """#
}
