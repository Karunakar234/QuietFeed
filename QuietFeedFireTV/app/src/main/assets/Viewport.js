// QuietFeed page size (Fire TV only).
//
// Fire TV's web view reports half the screen's real width to pages (960 for a 1920 screen), so
// YouTube's TV interface, designed for 1920, draws everything at twice the size. This pins the
// page's layout width (window.__qfViewportWidth, set before this runs); the web view then fits
// that width to the screen. The menu's Size setting changes the width.
(function () {
  if (window.__qfViewport || window.top !== window) return;
  window.__qfViewport = true;
  var content = 'width=' + window.__qfViewportWidth + ', user-scalable=no';

  function ensure() {
    var head = document.head || document.documentElement;
    if (!head) return false;
    var metas = document.querySelectorAll('meta[name="viewport"]');
    if (!metas.length) {
      var meta = document.createElement('meta');
      meta.name = 'viewport';
      meta.setAttribute('content', content);
      head.appendChild(meta);
    } else {
      metas.forEach(function (m) { if (m.getAttribute('content') !== content) m.setAttribute('content', content); });
    }
    return true;
  }

  // The page may add or change its own viewport tag later; ours stays in charge.
  function touchesMeta(records) {
    for (var i = 0; i < records.length; i++) {
      var r = records[i];
      if (r.type === 'attributes' && r.target.nodeName === 'META') return true;
      for (var j = 0; j < r.addedNodes.length; j++) if (r.addedNodes[j].nodeName === 'META') return true;
    }
    return false;
  }
  function watch() {
    new MutationObserver(function (records) { if (touchesMeta(records)) ensure(); })
      .observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['content', 'name'] });
  }

  if (ensure()) { watch(); return; }
  new MutationObserver(function (_, observer) {
    if (!ensure()) return;
    observer.disconnect();
    watch();
  }).observe(document, { childList: true, subtree: true });
})();
