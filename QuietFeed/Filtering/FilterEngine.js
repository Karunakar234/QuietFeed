// Stillfeed filter engine. Bundled with the app and reviewed with each release.
// It takes rules as DATA (selectors, URL patterns, text patterns, one action from a
// fixed set) and never evaluates code that arrives from the server.
// Actions: hide | remove | redirect | block_navigation | disable_scroll | skip_ads
//          | autohide_top | autohide_bottom | click
(function () {
  'use strict';
  if (window.__stillfeed) return;

  var STYLE_ID = 'stillfeed-style';
  var HIDDEN = 'data-stillfeed-hidden';
  // Marks elements a plain CSS rule hides once they've been counted for weekly insights.
  var COUNTED = 'data-stillfeed-counted';
  // Marks buttons a `click` rule has already pressed, so each is pressed once.
  var CLICKED = 'data-stillfeed-clicked';
  var SINGLE = 'stillfeed-single';
  var state = { rules: [], locked: false, lastPath: null, timer: null, observer: null, adTimer: null, adSanitizerInstalled: false };

  // Remove ad scheduling data before YouTube's player consumes its JSON response.
  // The visual/player-state skipper below remains as a fallback when the response shape changes.
  // Ad fields sit near the top of YouTube's player data (at most a couple of levels down, e.g.
  // inside a page's playerResponse), so the walk stops after a few levels. Walking every object
  // in every large response made each JSON.parse several times slower and the page stutter.
  var AD_SEARCH_DEPTH = 5;

  function stripPlayerAds(value, seen, depth) {
    if (!value || typeof value !== 'object') return value;
    depth = depth || 0;
    if (depth > AD_SEARCH_DEPTH) return value;
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
      for (var j = 0; j < value.length; j++) stripPlayerAds(value[j], seen, depth + 1);
    } else {
      Object.keys(value).forEach(function (key) {
        stripPlayerAds(value[key], seen, depth + 1);
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
      if (!r.selectors.length) return;
      if (r.action === 'click') {
        // Presses a button whose own label matches, e.g. "Not now" on an "open the app" pop-up.
        var buttons = document.querySelectorAll(r.selectors.join(','));
        for (var b = 0; b < buttons.length; b++) {
          var button = buttons[b];
          if (button.hasAttribute(CLICKED)) continue;
          if (!firstMatch(r.text, (button.textContent || '').trim())) continue;
          button.setAttribute(CLICKED, '');
          button.click();
        }
        return;
      }
      if (r.action !== 'hide' && r.action !== 'remove') return;
      var nodes = document.querySelectorAll(r.selectors.join(','));
      if (!r.text.length) {
        // Plain CSS already hides these (writeStyle); count each one once for weekly insights.
        // Results come in document order, so an outer match is marked before anything inside it,
        // and an ad slot inside its already-counted feed item isn't counted twice.
        for (var j = 0; j < nodes.length; j++) {
          var node = nodes[j];
          if (node.hasAttribute(COUNTED)) continue;
          var insideCounted = node.parentElement && node.parentElement.closest('[' + COUNTED + ']');
          node.setAttribute(COUNTED, '');
          if (!insideCounted) hidden++;
        }
        return;
      }
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

  // MARK: autohide_top / autohide_bottom
  // While the person scrolls down, slide the site's own top and/or bottom bar out of view so
  // the page fills the screen; scrolling up, reaching the top, or a new page brings them back.
  // The bars are found by what's pinned to the screen edge rather than by site-specific
  // selectors, so it works on any platform. Anything taller than a fifth of the screen is left
  // alone (YouTube's pinned video player, dialogs). Moving them with `translate` doesn't change
  // the page's layout, so hiding can't shift the scroll position.
  var chrome = { hidden: false, lastY: 0, run: 0, bars: [] };

  function chromeEdges() {
    var edges = { top: false, bottom: false };
    state.rules.forEach(function (r) {
      if (r.action === 'autohide_top') edges.top = true;
      if (r.action === 'autohide_bottom') edges.bottom = true;
    });
    return edges;
  }
  function pinnedBarsAt(y) {
    var found = [];
    var nearTop = y < window.innerHeight / 2;
    function add(el) {
      if (!el || found.indexOf(el) !== -1) return;
      var box = el.getBoundingClientRect();
      var touchesEdge = nearTop ? box.top <= 8 : box.bottom >= window.innerHeight - 8;
      if (box.height > 0 && box.height < window.innerHeight * 0.2 && touchesEdge) found.push(el);
    }
    [0.15, 0.5, 0.85].forEach(function (fx) {
      var el = document.elementFromPoint(window.innerWidth * fx, y);
      while (el && el !== document.body && el !== document.documentElement) {
        var position = window.getComputedStyle(el).position;
        if (position === 'fixed' || position === 'sticky') { add(el); break; }
        el = el.parentElement;
      }
    });
    var selectors = nearTop
      ? 'header,[role="banner"],ytm-mobile-topbar-renderer,ytmusic-nav-bar'
      : 'footer,nav,[role="navigation"],ytm-pivot-bar-renderer,ytmusic-player-bar';
    document.querySelectorAll(selectors).forEach(add);
    return found;
  }
  function hideChrome() {
    var edges = chromeEdges();
    chrome.bars = [];
    if (edges.top) pinnedBarsAt(2).forEach(function (el) { chrome.bars.push({ el: el, offset: '0 -110%' }); });
    if (edges.bottom) pinnedBarsAt(window.innerHeight - 2).forEach(function (el) { chrome.bars.push({ el: el, offset: '0 110%' }); });
    chrome.bars.forEach(function (bar) {
      bar.el.style.setProperty('transition', 'translate 0.25s ease', 'important');
      bar.el.style.setProperty('translate', bar.offset, 'important');
    });
    // Pages often create their navigation after the script boots. Keep retrying until
    // at least one matching bar exists instead of recording a false hidden state.
    chrome.hidden = chrome.bars.length > 0;
  }
  function showChrome() {
    chrome.bars.forEach(function (bar) { bar.el.style.removeProperty('translate'); });
    chrome.bars = [];
    chrome.hidden = false;
  }
  function chromeScrolled(event) {
    var target = event && event.target;
    var isDocumentScroll = !target || target === document || target === document.documentElement || target === document.body;
    var y = isDocumentScroll ? window.scrollY : (target.scrollTop || 0);
    var delta = y - chrome.lastY;
    chrome.lastY = y;
    var edges = chromeEdges();
    if (!edges.top && !edges.bottom) { if (chrome.hidden) showChrome(); return; }
    // Same feel as QuietFeed's own bar: ~30pt down hides, ~40pt up or near the top shows.
    chrome.run = (delta >= 0) === (chrome.run >= 0) ? chrome.run + delta : delta;
    if (y < 40 || chrome.run < -40) {
      if (chrome.hidden) showChrome();
    } else if (chrome.run > 30) {
      if (!chrome.hidden) hideChrome();
    }
  }

  function checkLocation() {
    var path = currentPath();
    state.lastPath = path;
    if (chrome.hidden) showChrome();
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
    // Separate header/footer scrolling modes start visible and react to the next scroll.
    if (chrome.hidden) showChrome();
  }

  window.__stillfeed = {
    boot: function (raw) {
      apply(raw);
      hookHistory();
      window.addEventListener('wheel', blockScroll, { capture: true, passive: false });
      window.addEventListener('touchmove', blockScroll, { capture: true, passive: false });
      window.addEventListener('keydown', blockKeys, true);
      document.addEventListener('click', interceptClick, true);
      // Scroll does not bubble, so capture on document to see the nested scrollers used by
      // YouTube, YouTube Music, Instagram, and Prime Video.
      document.addEventListener('scroll', chromeScrolled, { capture: true, passive: true });
      state.observer = new MutationObserver(scheduleScan);
      state.observer.observe(document.documentElement, { childList: true, subtree: true });
      document.addEventListener('DOMContentLoaded', function () { writeStyle(); scheduleScan(); });
    },
    update: function (raw) { unhideAll(); apply(raw); }
  };
})();
