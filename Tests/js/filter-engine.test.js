const test = require('node:test');
const assert = require('node:assert/strict');
const { load, defaultRules, tick } = require('./harness');

// ---------- Navigation rules (mirrors NavigationGuard.swift) ----------

test('YouTube: a Shorts link becomes the normal watch page', () => {
  const p = load({ url: 'https://m.youtube.com/shorts/abc_123', rules: defaultRules('youtube') });
  assert.deepEqual(p.navigations, ['/watch?v=abc_123']);
  p.close();
});

test('YouTube: the Shorts feed itself goes home', () => {
  const p = load({ url: 'https://m.youtube.com/shorts', rules: defaultRules('youtube') });
  assert.deepEqual(p.navigations, ['/']);
  p.close();
});

test('YouTube: a normal watch page is left alone', () => {
  const p = load({ url: 'https://m.youtube.com/watch?v=xyz', rules: defaultRules('youtube') });
  assert.deepEqual(p.navigations, []);
  p.close();
});

test('Instagram: Explore grid redirects to search, search itself does not loop', () => {
  const a = load({ url: 'https://www.instagram.com/explore/', rules: defaultRules('instagram') });
  assert.deepEqual(a.navigations, ['/explore/search/']);
  a.close();
  const b = load({ url: 'https://www.instagram.com/explore/search/', rules: defaultRules('instagram') });
  assert.deepEqual(b.navigations, []);
  b.close();
});

test('Instagram: turning Hide Reels off lets /reels/ open', () => {
  const p = load({ url: 'https://www.instagram.com/reels/', rules: defaultRules('instagram', { hide_reels: false }) });
  assert.deepEqual(p.navigations, []);
  p.close();
});

test('Instagram: tapping a Reels link is stopped before the site router sees it', () => {
  const p = load({
    url: 'https://www.instagram.com/',
    html: '<a id="r" href="/reels/">Reels</a>',
    rules: defaultRules('instagram')
  });
  let siteSawClick = false;
  p.document.getElementById('r').addEventListener('click', () => { siteSawClick = true; });
  const ev = new p.window.MouseEvent('click', { bubbles: true, cancelable: true });
  p.document.getElementById('r').dispatchEvent(ev);
  assert.equal(ev.defaultPrevented, true);
  assert.equal(siteSawClick, false);
  assert.deepEqual(p.navigations, ['/']);
  p.close();
});

test('Instagram: a single reel from a friend locks scrolling', () => {
  const p = load({ url: 'https://www.instagram.com/reel/AbC-12/', rules: defaultRules('instagram') });
  assert.ok(p.document.documentElement.classList.contains('stillfeed-single'));
  p.close();
});

// ---------- Hiding and weekly counts ----------

test('Instagram: suggested posts are hidden by their label and counted once', async () => {
  const p = load({
    url: 'https://www.instagram.com/',
    html: '<article id="s">Suggested for you · someone</article><article id="f">A friend posted</article>',
    rules: defaultRules('instagram')
  });
  await tick();
  assert.ok(p.document.getElementById('s').hasAttribute('data-stillfeed-hidden'));
  assert.ok(!p.document.getElementById('f').hasAttribute('data-stillfeed-hidden'));
  const total = p.messages.filter(m => m.type === 'hidden').reduce((n, m) => n + m.count, 0);
  assert.equal(total, 1);
  p.close();
});

test('Instagram: sponsored posts stay visible unless that switch is on', async () => {
  const html = '<article id="ad">Sponsored · brand</article>';
  const off = load({ url: 'https://www.instagram.com/', html, rules: defaultRules('instagram') });
  await tick();
  assert.ok(!off.document.getElementById('ad').hasAttribute('data-stillfeed-hidden'));
  off.close();
  const on = load({ url: 'https://www.instagram.com/', html, rules: defaultRules('instagram', { hide_sponsored: true }) });
  await tick();
  assert.ok(on.document.getElementById('ad').hasAttribute('data-stillfeed-hidden'));
  on.close();
});

test('YouTube: an ad slot inside an already-counted feed item is not counted twice', async () => {
  const p = load({
    url: 'https://m.youtube.com/',
    html: '<ytm-rich-item-renderer><ad-slot-renderer><ytm-promoted-video-renderer></ytm-promoted-video-renderer></ad-slot-renderer></ytm-rich-item-renderer>',
    rules: defaultRules('youtube')
  });
  await tick();
  const total = p.messages.filter(m => m.type === 'hidden').reduce((n, m) => n + m.count, 0);
  assert.equal(total, 1);
  p.close();
});

test('Changing switches does not count already-hidden posts again', async () => {
  const p = load({
    url: 'https://www.instagram.com/',
    html: '<article>Suggested for you</article>',
    rules: defaultRules('instagram')
  });
  await tick();
  p.window.__stillfeed.update(defaultRules('instagram', { hide_sponsored: true }));
  await tick();
  const total = p.messages.filter(m => m.type === 'hidden').reduce((n, m) => n + m.count, 0);
  assert.equal(total, 1);
  p.close();
});

// ---------- Ad skipping ----------

function spotifyNowPlaying(title) {
  return `<div data-testid="now-playing-widget"><a data-testid="context-item-info-title">${title}</a></div><audio></audio>`;
}

test('Spotify: a real ad in the player is detected and muted', () => {
  const p = load({ url: 'https://open.spotify.com/', html: spotifyNowPlaying('Advertisement'), rules: defaultRules('spotify') });
  assert.equal(p.document.querySelector('audio').muted, true);
  p.close();
});

test('Spotify: a song whose title starts with "Ad" is not treated as an ad', () => {
  for (const title of ['Ad Astra', 'Ad-Lib', 'Sponsored Content (Live)', 'Ad']) {
    const p = load({ url: 'https://open.spotify.com/', html: spotifyNowPlaying(title), rules: defaultRules('spotify') });
    const expectAd = title === 'Ad';
    assert.equal(p.document.querySelector('audio').muted, expectAd, `title "${title}"`);
    p.close();
  }
});

test('YouTube: a showing ad is muted and the player is restored when it ends', () => {
  const p = load({
    url: 'https://m.youtube.com/watch?v=x',
    html: '<div id="movie_player" class="html5-video-player ad-showing"><video></video></div>',
    rules: defaultRules('youtube')
  });
  const video = p.document.querySelector('video');
  assert.equal(video.muted, true);
  p.document.getElementById('movie_player').classList.remove('ad-showing');
  // The 200ms skipper tick notices the ad is over.
  return new Promise(r => setTimeout(r, 260)).then(() => {
    assert.equal(video.muted, false);
    p.close();
  });
});

test('YouTube: no ad, no change to playback', () => {
  const p = load({
    url: 'https://m.youtube.com/watch?v=x',
    html: '<div id="movie_player" class="html5-video-player"><video></video></div>',
    rules: defaultRules('youtube')
  });
  assert.equal(p.document.querySelector('video').muted, false);
  p.close();
});

test('YouTube: player JSON has its ad schedule removed', () => {
  const p = load({ url: 'https://m.youtube.com/watch?v=x', rules: defaultRules('youtube') });
  const parsed = p.window.JSON.parse('{"playerResponse":{"adPlacements":[1],"videoDetails":{"videoId":"x"}}}');
  assert.equal(parsed.playerResponse.adPlacements, undefined);
  assert.equal(parsed.playerResponse.videoDetails.videoId, 'x');
  p.close();
});

// ---------- Cost of the 200ms ad check ----------

test('Ad check on YouTube does not walk the whole page every tick when no ad is showing', () => {
  const p = load({
    url: 'https://m.youtube.com/watch?v=x',
    html: '<div id="movie_player" class="html5-video-player"><video></video></div>' + '<p>row</p><span>x</span>'.repeat(500),
    rules: defaultRules('youtube'),
  });
  let fullWalks = 0;
  const wrap = proto => {
    const orig = proto.querySelectorAll;
    proto.querySelectorAll = function (sel) { if (sel === '*' || /\bspan\b.*\bp\b/.test(sel)) fullWalks++; return orig.call(this, sel); };
  };
  wrap(p.window.Document.prototype); wrap(p.window.Element.prototype); wrap(p.window.DocumentFragment.prototype);
  return new Promise(r => setTimeout(r, 450)).then(() => {
    // Two ticks elapse in 450ms. Searching shadow roots / Prime's text labels is only needed on Prime Video.
    assert.equal(fullWalks, 0, `whole-page walks during 2 ticks: ${fullWalks}`);
    p.close();
  });
});

test('Prime Video: an ad label and Skip button inside a shadow root are still found', () => {
  let skipped = 0;
  const p = load({
    url: 'https://www.primevideo.com/detail/x',
    html: '<div id="dv-web-player"><div id="host"></div><video></video></div>',
    rules: defaultRules('amazon_prime'),
    beforeBoot: w => {
      const root = w.document.getElementById('host').attachShadow({ mode: 'open' });
      root.innerHTML = '<span>Ad 1 of 2 0:15</span><button aria-label="Skip">Skip</button>';
      root.querySelector('button').addEventListener('click', () => { skipped++; });
    }
  });
  assert.equal(skipped, 1);
  // Prime owns its ad handoff: the video itself is never muted or sped up.
  assert.equal(p.document.querySelector('video').muted, false);
  p.close();
});

test('Prime Video: no ad, no button pressed', () => {
  let pressed = 0;
  const p = load({
    url: 'https://www.primevideo.com/detail/x',
    html: '<div id="dv-web-player"><button aria-label="Skip">Skip Intro</button><video></video></div>',
    rules: defaultRules('amazon_prime'),
    beforeBoot: w => w.document.querySelector('button').addEventListener('click', () => { pressed++; })
  });
  assert.equal(pressed, 0);
  p.close();
});
