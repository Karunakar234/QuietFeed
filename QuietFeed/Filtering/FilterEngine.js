// Stillfeed filter engine. Bundled with the app and reviewed with each release.
// It takes rules as DATA (selectors, URL patterns, text patterns, one action from a
// fixed set) and never evaluates code that arrives from the server.
// Actions: hide | remove | redirect | block_navigation | disable_scroll | skip_ads
(function () {
  'use strict';
  if (window.__stillfeed) return;

  var STYLE_ID = 'stillfeed-style';
  var HIDDEN = 'data-stillfeed-hidden';
  var SINGLE = 'stillfeed-single';
  var state = { rules: [], locked: false, lastPath: null, timer: null, observer: null, adTimer: null, adSanitizerInstalled: false };

  // Remove ad scheduling data before YouTube's player consumes its JSON response.
  // The visual/player-state skipper below remains as a fallback when the response shape changes.
  function stripPlayerAds(value, seen) {
    if (!value || typeof value !== 'object') return value;
    seen = seen || new WeakSet();
    if (seen.has(value)) return value;
    seen.add(value);

    var adKeys = [
      'adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams',
      'adBreakParams', 'adParams', 'adPlacementRenderer', 'linearAdSequenceRenderer'
    ];
    for (var i = 0; i < adKeys.length; i++) {
      try { delete value[adKeys[i]]; } catch (e) {}
    }

    if (Array.isArray(value)) {
      for (var j = 0; j < value.length; j++) stripPlayerAds(value[j], seen);
    } else {
      Object.keys(value).forEach(function (key) {
        stripPlayerAds(value[key], seen);
      });
    }
    return value;
  }

  function installPlayerResponseSanitizer() {
    if (state.adSanitizerInstalled || !/(^|\.)youtube\.com$/.test(location.hostname)) return;
    state.adSanitizerInstalled = true;

    var originalParse = JSON.parse;
    JSON.parse = function () {
      return stripPlayerAds(originalParse.apply(this, arguments));
    };

    if (window.Response && Response.prototype && Response.prototype.json) {
      var originalResponseJSON = Response.prototype.json;
      Response.prototype.json = function () {
        return originalResponseJSON.apply(this, arguments).then(function (value) {
          return stripPlayerAds(value);
        });
      };
    }

    try {
      var initialPlayerResponse;
      Object.defineProperty(window, 'ytInitialPlayerResponse', {
        configurable: true,
        enumerable: true,
        get: function () { return initialPlayerResponse; },
        set: function (value) { initialPlayerResponse = stripPlayerAds(value); }
      });
    } catch (e) {}
  }

  function post(msg) {
    try { window.webkit.messageHandlers.stillfeed.postMessage(msg); } catch (e) { /* not in the app */ }
  }
  function navigate(url) {
    if (typeof window.__stillfeedNavigate === 'function') return window.__stillfeedNavigate(url);
    window.location.replace(url);
  }
  function compile(list, flags) {
    return (list || []).map(function (p) {
      try { return new RegExp(p, flags || ''); } catch (e) { return null; }
    }).filter(Boolean);
  }
  function normalise(raw) {
    return (raw || []).map(function (r) {
      return {
        key: r.key, action: r.action,
        selectors: (r.selectors || []).filter(validSelector),
        url: compile(r.url_patterns),
        text: compile(r.text_matches, 'i'),
        redirectTo: r.redirect_to || '/'
      };
    });
  }
  function validSelector(s) {
    try { document.createDocumentFragment().querySelector(s); return true; } catch (e) { return false; }
  }
  function currentPath() { return window.location.pathname + window.location.search; }
  function firstMatch(list, path) {
    for (var i = 0; i < list.length; i++) if (list[i].test(path)) return list[i];
    return null;
  }

  // Where a path should go instead: a URL string, or null to leave it alone.
  function destinationFor(path) {
    for (var i = 0; i < state.rules.length; i++) {
      var r = state.rules[i];
      if (r.action !== 'redirect' && r.action !== 'block_navigation') continue;
      var re = firstMatch(r.url, path);
      if (!re) continue;
      var target = r.action === 'redirect' ? path.replace(re, r.redirectTo) : '/';
      if (target !== path) return target;
    }
    return null;
  }

  // CSS for plain hide rules. Injected first so nothing flashes on screen.
  function writeStyle() {
    var css = '[' + HIDDEN + ']{display:none!important}' +
      'html.' + SINGLE + ',html.' + SINGLE + ' body{overscroll-behavior:none!important}';
    state.rules.forEach(function (r) {
      if ((r.action === 'hide' || r.action === 'remove') && r.selectors.length && !r.text.length) {
        css += r.selectors.join(',') + '{display:none!important}';
      }
    });
    var el = document.getElementById(STYLE_ID);
    if (!el) {
      el = document.createElement('style');
      el.id = STYLE_ID;
      (document.head || document.documentElement).appendChild(el);
    }
    el.textContent = css;
  }

  // Rules that hide a container only when its text matches (e.g. a "suggested" label).
  function scan() {
    state.timer = null;
    var hidden = 0;
    state.rules.forEach(function (r) {
      if (!r.text.length || !r.selectors.length) return;
      if (r.action !== 'hide' && r.action !== 'remove') return;
      var nodes = document.querySelectorAll(r.selectors.join(','));
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        if (n.hasAttribute(HIDDEN)) continue;
        var text = (n.textContent || '').slice(0, 400);
        if (!firstMatch(r.text, text)) continue;
        if (r.action === 'remove') n.remove(); else n.setAttribute(HIDDEN, r.key);
        hidden++;
      }
    });
    if (hidden) post({ type: 'hidden', count: hidden });
  }
  function scheduleScan() {
    if (state.timer === null) state.timer = setTimeout(scan, 30);
  }
  function unhideAll() {
    var nodes = document.querySelectorAll('[' + HIDDEN + ']');
    for (var i = 0; i < nodes.length; i++) nodes[i].removeAttribute(HIDDEN);
  }

  // YouTube Music serves playback ads from the same media hosts as songs, so request
  // blocking alone cannot distinguish them. Detect the player state and current ad controls.
  function isVisible(node) {
    return !!(node && node.getClientRects().length && getComputedStyle(node).visibility !== 'hidden');
  }
  function restoreMedia() {
    if (!state.adMedia) return;
    var saved = state.adMedia;
    if (saved.media) {
      saved.media.playbackRate = saved.rate;
      saved.media.muted = saved.muted;
    }
    state.adMedia = null;
  }
  function skipPlaybackAd() {
    var player = document.querySelector(
      '#movie_player, .html5-video-player, [class~="ad-showing"], [class~="ad-interrupting"]'
    );
    var scope = player || document;
    var adControl = scope.querySelector(
      '.ytp-ad-player-overlay, .ytp-ad-text, .ytp-ad-preview-text, ' +
      '.ytp-ad-simple-ad-badge, .ytp-ad-skip-button-container, ' +
      '[class*="ad-showing"], [class*="ad-interrupting"]'
    );
    var classes = player && player.classList;
    var isAd = !!(classes && (classes.contains('ad-showing') ||
      classes.contains('ad-interrupting'))) || isVisible(adControl);
    if (!isAd) { restoreMedia(); return; }
    if (!isAd) { restoreMedia(); return; }

    var skip = scope.querySelector(
      '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, ' +
      '.ytp-ad-skip-button-slot button, button[class*="skip"]'
    );
    if (isVisible(skip)) skip.click();

    var media = scope.querySelector('video, audio') || document.querySelector('video, audio');
    if (!media) return;
    if (!state.adMedia || state.adMedia.media !== media) {
      restoreMedia();
      state.adMedia = { media: media, rate: media.playbackRate, muted: media.muted };
    }
    // Seeking removes most ads immediately. Fast, silent playback is the fallback for
    // streams that reject seeking until their skip threshold has elapsed.
    if (isFinite(media.duration) && media.duration > 0) {
      try { media.currentTime = Math.max(0, media.duration - 0.05); } catch (e) {}
    }
    media.muted = true;
    try { media.playbackRate = 16; } catch (e) { media.playbackRate = 2; }
    if (media.paused) media.play().catch(function () {});
  }
  function updateAdSkipping() {
    var enabled = state.rules.some(function (r) { return r.action === 'skip_ads'; });
    if (enabled && state.adTimer === null) {
      installPlayerResponseSanitizer();
      skipPlaybackAd();
      state.adTimer = setInterval(skipPlaybackAd, 250);
    } else if (!enabled && state.adTimer !== null) {
      clearInterval(state.adTimer);
      state.adTimer = null;
      restoreMedia();
    }
  }

  function checkLocation() {
    var path = currentPath();
    state.lastPath = path;
    var dest = destinationFor(path);
    if (dest) {
      post({ type: 'blocked', path: window.location.pathname });
      navigate(dest);
      return;
    }
    var lock = false;
    state.rules.forEach(function (r) {
      if (r.action === 'disable_scroll' && firstMatch(r.url, path)) lock = true;
    });
    state.locked = lock;
    document.documentElement.classList.toggle(SINGLE, lock);
  }

  function isTyping(t) {
    return t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName || ''));
  }
  function blockScroll(e) { if (state.locked && e.cancelable) e.preventDefault(); }
  function blockKeys(e) {
    if (!state.locked || isTyping(e.target)) return;
    if (['ArrowDown', 'ArrowUp', 'PageDown', 'PageUp', ' '].indexOf(e.key) !== -1) e.preventDefault();
  }
  // Stop taps on links to blocked places before the site's router sees them.
  function interceptClick(e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var url;
    try { url = new URL(a.getAttribute('href'), window.location.href); } catch (err) { return; }
    if (url.origin !== window.location.origin) return;
    var dest = destinationFor(url.pathname + url.search);
    if (!dest) return;
    e.preventDefault();
    e.stopPropagation();
    post({ type: 'blocked', path: url.pathname });
    navigate(dest);
  }

  function hookHistory() {
    ['pushState', 'replaceState'].forEach(function (name) {
      var original = window.history[name];
      window.history[name] = function () {
        var out = original.apply(this, arguments);
        checkLocation();
        return out;
      };
    });
    window.addEventListener('popstate', checkLocation);
    setInterval(function () { if (currentPath() !== state.lastPath) checkLocation(); }, 500);
  }

  function apply(raw) {
    state.rules = normalise(raw);
    writeStyle();
    checkLocation();
    updateAdSkipping();
    scheduleScan();
  }

  window.__stillfeed = {
    boot: function (raw) {
      apply(raw);
      hookHistory();
      window.addEventListener('wheel', blockScroll, { capture: true, passive: false });
      window.addEventListener('touchmove', blockScroll, { capture: true, passive: false });
      window.addEventListener('keydown', blockKeys, true);
      document.addEventListener('click', interceptClick, true);
      state.observer = new MutationObserver(scheduleScan);
      state.observer.observe(document.documentElement, { childList: true, subtree: true });
      document.addEventListener('DOMContentLoaded', function () { writeStyle(); scheduleScan(); });
    },
    update: function (raw) { unhideAll(); apply(raw); }
  };
})();
