// QuietFeed for YouTube's TV interface (Fire TV only).
//
// YouTube and YouTube Music open in youtube.com/tv, the interface YouTube's own TV apps use, so
// they look and drive exactly like the app. Its page structure differs from the mobile site the
// shared rules describe, so Shorts are removed from YouTube's data instead, before the interface
// draws anything: every Short is marked by the same keys (reelWatchEndpoint and friends) on every
// YouTube client, so this doesn't depend on layout. FilterEngine.js strips ads from data read with
// JSON.parse and fetch; this also covers XHR responses read as JSON, which the TV interface can use.
//
// Configured by window.__qfYtTvOptions = { hideShorts: bool, stripAds: bool } before this runs.
(function () {
  if (window.__qfYtTv || window.top !== window) return;
  window.__qfYtTv = true;
  var options = window.__qfYtTvOptions || {};
  if (!options.hideShorts && !options.stripAds) return;

  var SHORTS = ['reelWatchEndpoint', 'reelShelfRenderer', 'reelItemRenderer',
                'shortsLockupViewModel', 'shortsLockupViewModelV2'];
  // The same keys FilterEngine.js strips.
  var ADS = ['adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams',
             'adBreakParams', 'adParams', 'adPlacementRenderer', 'linearAdSequenceRenderer'];
  var MAX_DEPTH = 80;
  var OK = 0, SHORT = 1, EMPTIED = 2;

  // A list entry is a one-key wrapper such as { tileRenderer: {...} } or { shelfRenderer: {...} }.
  function isEntry(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
    var keys = Object.keys(value);
    return keys.length === 1 || (keys.length === 2 && keys.indexOf('trackingParams') !== -1);
  }

  // Removes Short entries from lists. Returns SHORT if `value` itself is (or now only holds) Shorts,
  // EMPTIED if it's a list that held nothing but Shorts, OK otherwise.
  function clean(value, depth) {
    if (!value || typeof value !== 'object' || depth > MAX_DEPTH) return OK;
    if (Array.isArray(value)) {
      var before = value.length;
      for (var i = value.length - 1; i >= 0; i--) {
        if (clean(value[i], depth + 1) !== OK && isEntry(value[i])) value.splice(i, 1);
      }
      return before > 0 && value.length === 0 ? EMPTIED : OK;
    }
    var result = OK;
    if (options.stripAds) {
      for (var a = 0; a < ADS.length; a++) if (ADS[a] in value) { try { delete value[ADS[a]]; } catch (e) {} }
    }
    for (var key in value) {
      if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
      if (options.hideShorts && SHORTS.indexOf(key) !== -1) { result = SHORT; continue; }
      if (clean(value[key], depth + 1) !== OK) result = SHORT;
    }
    return result;
  }

  function sanitize(data) {
    if (data && typeof data === 'object' && !Array.isArray(data) && 'responseContext' in data) {
      try { clean(data, 0); } catch (e) { /* leave the response as it came */ }
    }
    return data;
  }

  var parse = JSON.parse;
  JSON.parse = function () { return sanitize(parse.apply(this, arguments)); };

  if (window.Response && Response.prototype.json) {
    var json = Response.prototype.json;
    Response.prototype.json = function () { return json.apply(this, arguments).then(sanitize); };
  }

  var descriptor = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, 'response');
  if (descriptor && descriptor.get) {
    Object.defineProperty(XMLHttpRequest.prototype, 'response', {
      configurable: true,
      get: function () {
        var value = descriptor.get.call(this);
        return this.responseType === 'json' ? sanitize(value) : value;
      }
    });
  }
})();
