// QuietFeed TV navigation (Fire TV only).
//
// Makes a website behave like a TV app: the remote's arrows move a highlight between the things
// you can select (videos, buttons, tabs, fields), the page scrolls to keep it in view, and OK
// selects it. Selecting is done natively, as a real tap at the point activate() returns, so the
// site sees a genuine user gesture (needed for playback and full screen).
//
// Native calls: move(dir), activate(), media(cmd), configure(options), clear().
(function () {
  if (window.__qfTv || window.top !== window) return;

  var SELECTABLE = [
    'a[href]', 'button', 'input:not([type="hidden"])', 'textarea', 'select', 'summary',
    '[role="button"]', '[role="link"]', '[role="tab"]', '[role="menuitem"]', '[role="option"]',
    '[role="checkbox"]', '[role="switch"]', '[role="radio"]', '[role="slider"]',
    '[tabindex]:not([tabindex="-1"])', '[contenteditable="true"]'
  ].join(',');
  var FILTERED = '[data-stillfeed-hidden]';
  var RING_ID = 'qf-tv-ring';
  var options = { autoFullscreen: false };
  var state = { el: null, last: null, ring: null, frame: 0, tappedAt: 0 };

  // MARK: Finding what can be selected

  function rectOf(el) {
    var r = el.getBoundingClientRect();
    return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height,
             cx: r.left + r.width / 2, cy: r.top + r.height / 2 };
  }

  function isUsable(el) {
    if (!el || !el.isConnected) return false;
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') return false;
    if (el.closest(FILTERED) || el.closest('[aria-hidden="true"]') || el.closest('[inert]')) return false;
    var r = el.getBoundingClientRect();
    if (r.width < 6 || r.height < 6) return false;
    var s = getComputedStyle(el);
    if (s.visibility === 'hidden' || s.pointerEvents === 'none' || Number(s.opacity) < 0.05) return false;
    return true;
  }

  function similar(a, b) {
    return Math.abs(a.left - b.left) < 6 && Math.abs(a.top - b.top) < 6 &&
           Math.abs(a.width - b.width) < 12 && Math.abs(a.height - b.height) < 12;
  }

  // A thumbnail link often wraps a button of the same size: keep only the outermost of such stacks.
  function candidates() {
    var all = Array.prototype.slice.call(document.querySelectorAll(SELECTABLE), 0, 4000).filter(isUsable);
    var set = new Set(all);
    return all.filter(function (el) {
      var r = el.getBoundingClientRect();
      for (var p = el.parentElement, depth = 0; p && depth < 6; p = p.parentElement, depth++) {
        if (set.has(p) && similar(r, p.getBoundingClientRect())) return false;
      }
      return true;
    });
  }

  // MARK: Moving

  function scoreFor(dir, from, to) {
    var vertical = dir === 'up' || dir === 'down';
    var gap, ahead, overlap, offset;
    if (dir === 'down') { ahead = to.cy > from.cy + 2 && to.top > from.top + 2; gap = to.top - from.bottom; }
    if (dir === 'up') { ahead = to.cy < from.cy - 2 && to.bottom < from.bottom - 2; gap = from.top - to.bottom; }
    if (dir === 'right') { ahead = to.cx > from.cx + 2 && to.left > from.left + 2; gap = to.left - from.right; }
    if (dir === 'left') { ahead = to.cx < from.cx - 2 && to.right < from.right - 2; gap = from.left - to.right; }
    if (!ahead) return Infinity;
    gap = Math.max(0, gap);
    if (vertical) {
      overlap = Math.max(0, Math.max(from.left - to.right, to.left - from.right));
      offset = Math.abs(to.cx - from.cx);
    } else {
      overlap = Math.max(0, Math.max(from.top - to.bottom, to.top - from.bottom));
      offset = Math.abs(to.cy - from.cy);
    }
    // Sideways means the same row, roughly; up and down may shift across columns a little more.
    if (overlap > (vertical ? innerWidth * 0.6 : innerHeight * 0.3)) return Infinity;
    // Stay in the same row or column when there is one; distance decides the rest.
    return gap + overlap * 4 + offset * 0.35;
  }

  function nearestTo(point, list) {
    var best = null, bestD = Infinity;
    list.forEach(function (el) {
      var r = rectOf(el);
      if (r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth) return;
      var d = Math.hypot(r.cx - point.x, r.cy - point.y);
      if (d < bestD) { bestD = d; best = el; }
    });
    return best;
  }

  function move(dir) {
    var list = candidates();
    var current = isUsable(state.el) ? state.el : null;
    if (!current) {
      var start = state.last ? { x: state.last.cx, y: Math.min(Math.max(state.last.cy, 0), innerHeight) }
                             : { x: innerWidth * 0.25, y: innerHeight * 0.2 };
      var first = nearestTo(start, list);
      if (first) { focus(first, dir); return true; }
      scrollPage(dir);
      return false;
    }
    var from = rectOf(current), best = null, bestScore = Infinity;
    var reach = Math.max(innerHeight, innerWidth) * 2.5;
    list.forEach(function (el) {
      if (el === current || el.contains(current) || current.contains(el)) return;
      var score = scoreFor(dir, from, rectOf(el));
      if (score < bestScore && score < reach) { bestScore = score; best = el; }
    });
    if (best) { focus(best, dir); return true; }
    // Nothing further that way on screen: scroll, and pick up what appears.
    scrollPage(dir);
    setTimeout(function () {
      var again = candidates(), pick = null, s = Infinity;
      again.forEach(function (el) {
        if (el === current || el.contains(current) || current.contains(el)) return;
        var sc = scoreFor(dir, rectOf(current), rectOf(el));
        if (sc < s) { s = sc; pick = el; }
      });
      if (pick) focus(pick, dir);
    }, 380);
    return false;
  }

  function focus(el, dir) {
    state.el = el;
    var r = rectOf(el);
    var vertical = dir === 'up' || dir === 'down';
    // Keep the highlight comfortably on screen, centring rows as a TV app does.
    var offscreen = r.top < innerHeight * 0.12 || r.bottom > innerHeight * 0.88 || r.left < 0 || r.right > innerWidth;
    if (offscreen) {
      try {
        el.scrollIntoView({ block: vertical || r.top < 0 || r.bottom > innerHeight ? 'center' : 'nearest',
                            inline: 'nearest', behavior: 'smooth' });
      } catch (e) { el.scrollIntoView(false); }
    }
    state.last = rectOf(el);
    ensureRing();
    track();
  }

  function scrollPage(dir) {
    var dx = dir === 'left' ? -0.6 * innerWidth : dir === 'right' ? 0.6 * innerWidth : 0;
    var dy = dir === 'up' ? -0.6 * innerHeight : dir === 'down' ? 0.6 * innerHeight : 0;
    var base = state.el && state.el.isConnected ? state.el : document.elementFromPoint(innerWidth / 2, innerHeight / 2);
    for (var el = base; el && el !== document.body && el !== document.documentElement; el = el.parentElement) {
      var s = getComputedStyle(el);
      var canY = dy && /(auto|scroll)/.test(s.overflowY) && el.scrollHeight > el.clientHeight + 4;
      var canX = dx && /(auto|scroll)/.test(s.overflowX) && el.scrollWidth > el.clientWidth + 4;
      if (canY || canX) { el.scrollBy({ left: dx, top: dy, behavior: 'smooth' }); return; }
    }
    window.scrollBy({ left: dx, top: dy, behavior: 'smooth' });
  }

  // MARK: The highlight

  function ensureRing() {
    var ring = document.getElementById(RING_ID);
    if (!ring) {
      ring = document.createElement('div');
      ring.id = RING_ID;
      ring.setAttribute('aria-hidden', 'true');
      ring.style.cssText = [
        'position:fixed', 'z-index:2147483647', 'pointer-events:none', 'box-sizing:border-box',
        'border:4px solid #5CC6C4', 'border-radius:14px',
        'box-shadow:0 0 0 6px rgba(92,198,196,.28),0 10px 34px rgba(0,0,0,.55)',
        'transition:left .12s ease-out,top .12s ease-out,width .12s ease-out,height .12s ease-out,opacity .2s',
        'left:0', 'top:0', 'width:0', 'height:0', 'opacity:0'
      ].join(';');
      (document.body || document.documentElement).appendChild(ring);
    }
    state.ring = ring;
  }

  // Follows the selected element while the page scrolls or animates.
  function track() {
    if (state.frame) return;
    var step = function () {
      state.frame = 0;
      var ring = state.ring;
      if (!ring) return;
      if (!isUsable(state.el) || document.fullscreenElement) { ring.style.opacity = '0'; return; }
      var r = rectOf(state.el);
      state.last = r;
      ring.style.left = (r.left - 6) + 'px';
      ring.style.top = (r.top - 6) + 'px';
      ring.style.width = (r.width + 12) + 'px';
      ring.style.height = (r.height + 12) + 'px';
      ring.style.opacity = '1';
      state.frame = requestAnimationFrame(step);
    };
    state.frame = requestAnimationFrame(step);
  }

  // MARK: Selecting

  // The point to tap: the middle of the element's visible part, nudged to a spot that is
  // really the element and not something drawn over it.
  function activate() {
    var el = isUsable(state.el) ? state.el : null;
    if (!el) return null;
    var r = rectOf(el);
    var left = Math.max(r.left, 0), right = Math.min(r.right, innerWidth);
    var top = Math.max(r.top, 0), bottom = Math.min(r.bottom, innerHeight);
    if (right <= left || bottom <= top) return null;
    var points = [[0.5, 0.5], [0.3, 0.3], [0.7, 0.3], [0.3, 0.7], [0.7, 0.7], [0.5, 0.2], [0.5, 0.8]];
    var x = (left + right) / 2, y = (top + bottom) / 2;
    for (var i = 0; i < points.length; i++) {
      var px = left + (right - left) * points[i][0], py = top + (bottom - top) * points[i][1];
      var hit = document.elementFromPoint(px, py);
      if (hit && (hit === el || el.contains(hit) || hit.contains(el))) { x = px; y = py; break; }
    }
    state.tappedAt = Date.now();
    return JSON.stringify({ x: x, y: y, typing: /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) || el.isContentEditable });
  }

  // MARK: Video

  function mainVideo() {
    var fs = document.fullscreenElement || document.webkitFullscreenElement;
    if (fs) return fs.tagName === 'VIDEO' ? fs : fs.querySelector('video');
    var best = null, area = 0;
    document.querySelectorAll('video').forEach(function (v) {
      var r = v.getBoundingClientRect(), a = r.width * r.height;
      if (a > area || (!v.paused && best && best.paused)) { area = a; best = v; }
    });
    return best;
  }

  function media(cmd) {
    var v = mainVideo();
    if (!v) return null;
    if (cmd === 'toggle') { if (v.paused) v.play().catch(function () {}); else v.pause(); }
    else if (cmd.indexOf('seek:') === 0 && isFinite(v.duration)) {
      v.currentTime = Math.min(v.duration, Math.max(0, v.currentTime + Number(cmd.slice(5))));
    }
    return JSON.stringify({ t: v.currentTime || 0, d: isFinite(v.duration) ? v.duration : 0, paused: v.paused,
                            title: document.title.replace(/\s*-\s*YouTube\s*$/, '') });
  }

  // Choosing a video opens it full screen, as in a TV app. Browsers only allow that shortly after
  // a real tap, which is why it's tied to the tap activate() just prepared.
  document.addEventListener('play', function (e) {
    var v = e.target;
    if (!options.autoFullscreen || !(v instanceof HTMLVideoElement)) return;
    if (document.fullscreenElement || Date.now() - state.tappedAt > 8000) return;
    if (v.getBoundingClientRect().width < innerWidth * 0.3) return;
    var request = v.requestFullscreen || v.webkitRequestFullscreen;
    if (!request) return;
    try {
      var result = request.call(v);
      if (result && result.catch) result.catch(function () {});
    } catch (err) {}
  }, true);

  window.__qfTv = {
    move: move,
    activate: activate,
    media: media,
    configure: function (o) { for (var k in o) options[k] = o[k]; },
    clear: function () { state.el = null; if (state.ring) state.ring.style.opacity = '0'; },
    exitFullscreen: function () {
      var exit = document.exitFullscreen || document.webkitExitFullscreen;
      if ((document.fullscreenElement || document.webkitFullscreenElement) && exit) exit.call(document);
    }
  };
})();
