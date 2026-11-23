// Loads FilterEngine.js into a jsdom page the way WKWebView does: at document start,
// then boot(rules) with the rules the app would enable for that platform.
const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

const ROOT = path.join(__dirname, '..', '..', 'QuietFeed', 'Filtering');
const ENGINE = fs.readFileSync(path.join(ROOT, 'FilterEngine.js'), 'utf8');
const RULESET = JSON.parse(fs.readFileSync(path.join(ROOT, 'rules.json'), 'utf8'));

/** The rules RuleStore.enabledRules returns with every switch left at its default. */
function defaultRules(platformId, overrides = {}) {
  return RULESET.rules.filter(r => r.platform_id === platformId && (overrides[r.key] ?? r.default_on));
}

/**
 * Boots the engine on `url` with `html` as the body. Layout doesn't exist in jsdom, so
 * every element counts as visible; media play() resolves instead of throwing.
 */
function load({ url, html = '', rules, beforeBoot }) {
  const dom = new JSDOM(`<!doctype html><html><head></head><body>${html}</body></html>`, {
    url, runScripts: 'outside-only', pretendToBeVisual: true
  });
  const w = dom.window;
  const messages = [];
  const navigations = [];
  w.webkit = { messageHandlers: { stillfeed: { postMessage: m => messages.push(m) } } };
  w.__stillfeedNavigate = u => navigations.push(u);
  w.Element.prototype.getClientRects = function () { return [{ width: 1, height: 1 }]; };
  w.HTMLMediaElement.prototype.play = function () { return Promise.resolve(); };
  w.HTMLMediaElement.prototype.pause = function () {};
  if (beforeBoot) beforeBoot(w);
  w.eval(ENGINE);
  w.__stillfeed.boot(rules);
  const close = () => w.close();
  return { dom, window: w, document: w.document, messages, navigations, close };
}

const tick = (ms = 60) => new Promise(r => setTimeout(r, ms));

module.exports = { load, defaultRules, tick, RULESET };
