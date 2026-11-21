const test = require('node:test');
const assert = require('node:assert/strict');
const { RULESET } = require('./harness');

const ACTIONS = new Set(['hide', 'remove', 'redirect', 'block_navigation', 'disable_scroll', 'skip_ads', 'autohide_top', 'autohide_bottom', 'click']);

test('every rule belongs to a known platform and uses a known action', () => {
  const ids = new Set(RULESET.platforms.map(p => p.id));
  for (const r of RULESET.rules) {
    assert.ok(ids.has(r.platform_id), `${r.key}: unknown platform ${r.platform_id}`);
    assert.ok(ACTIONS.has(r.action), `${r.platform_id}/${r.key}: unknown action ${r.action}`);
  }
});

test('every pattern compiles', () => {
  for (const r of RULESET.rules) {
    for (const p of [...(r.url_patterns || []), ...(r.text_matches || [])]) {
      assert.doesNotThrow(() => new RegExp(p), `${r.key}: ${p}`);
    }
  }
});

test('rules that share a key agree on title, Pro and default (one switch per key)', () => {
  const byKey = new Map();
  for (const r of RULESET.rules) {
    const k = r.platform_id + '/' + r.key;
    const first = byKey.get(k);
    if (!first) { byKey.set(k, r); continue; }
    assert.equal(r.title, first.title, `${k} title`);
    assert.equal(r.is_pro, first.is_pro, `${k} is_pro`);
    assert.equal(r.default_on, first.default_on, `${k} default_on`);
  }
});

test('platforms are https and their base URL host is in allowed_hosts', () => {
  for (const p of RULESET.platforms) {
    const u = new URL(p.base_url);
    assert.equal(u.protocol, 'https:', p.id);
    assert.ok(p.allowed_hosts.some(h => u.hostname === h || u.hostname.endsWith('.' + h)), `${p.id} base host`);
    // NavigationGuard treats the FIRST allowed host as the platform's own site.
    const own = p.allowed_hosts[0];
    assert.ok(u.hostname === own || u.hostname.endsWith('.' + own), `${p.id}: first allowed host must be its own site`);
  }
});

test('redirect rules never redirect to a path they match again (no loops)', () => {
  for (const r of RULESET.rules.filter(r => r.action === 'redirect')) {
    for (const p of r.url_patterns) {
      const re = new RegExp(p);
      assert.ok(!re.test(r.redirect_to.replace(/\$\d/g, 'x')), `${r.key}: ${r.redirect_to}`);
    }
  }
});
