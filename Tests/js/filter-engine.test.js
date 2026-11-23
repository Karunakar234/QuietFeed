const test = require('node:test');
const assert = require('node:assert/strict');
const { load, defaultRules, tick } = require('./harness');

test('YouTube: a Shorts link becomes the normal watch page', () => {
  const page = load({ url: 'https://m.youtube.com/shorts/abc_123', rules: defaultRules('youtube') });
  assert.deepEqual(page.navigations, ['/watch?v=abc_123']);
  page.close();
});

test('YouTube: the Shorts feed itself goes home', () => {
  const page = load({ url: 'https://m.youtube.com/shorts', rules: defaultRules('youtube') });
  assert.deepEqual(page.navigations, ['/']);
  page.close();
});

test('YouTube: a normal watch page is left alone', () => {
  const page = load({ url: 'https://m.youtube.com/watch?v=xyz', rules: defaultRules('youtube') });
  assert.deepEqual(page.navigations, []);
  page.close();
});

test('Instagram: Explore redirects to search without looping', () => {
  const explore = load({ url: 'https://www.instagram.com/explore/', rules: defaultRules('instagram') });
  assert.deepEqual(explore.navigations, ['/explore/search/']);
  explore.close();
  const search = load({ url: 'https://www.instagram.com/explore/search/', rules: defaultRules('instagram') });
  assert.deepEqual(search.navigations, []);
  search.close();
});

test('Instagram: turning Hide Reels off lets /reels/ open', () => {
  const page = load({ url: 'https://www.instagram.com/reels/', rules: defaultRules('instagram', { hide_reels: false }) });
  assert.deepEqual(page.navigations, []);
  page.close();
});

test('Instagram: a Reels link is stopped before the site router sees it', () => {
  const page = load({
    url: 'https://www.instagram.com/',
    html: '<a id="reels" href="/reels/">Reels</a>',
    rules: defaultRules('instagram')
  });
  let siteSawClick = false;
  page.document.getElementById('reels').addEventListener('click', () => { siteSawClick = true; });
  const event = new page.window.MouseEvent('click', { bubbles: true, cancelable: true });
  page.document.getElementById('reels').dispatchEvent(event);
  assert.equal(event.defaultPrevented, true);
  assert.equal(siteSawClick, false);
  assert.deepEqual(page.navigations, ['/']);
  page.close();
});

test('Instagram: a single reel locks scrolling', () => {
  const page = load({ url: 'https://www.instagram.com/reel/AbC-12/', rules: defaultRules('instagram') });
  assert.ok(page.document.documentElement.classList.contains('stillfeed-single'));
  page.close();
});

test('Instagram: suggested posts are hidden and counted once', async () => {
  const page = load({
    url: 'https://www.instagram.com/',
    html: '<article id="suggested">Suggested for you</article><article id="friend">A friend posted</article>',
    rules: defaultRules('instagram')
  });
  await tick();
  assert.ok(page.document.getElementById('suggested').hasAttribute('data-stillfeed-hidden'));
  assert.ok(!page.document.getElementById('friend').hasAttribute('data-stillfeed-hidden'));
  const total = page.messages.filter(message => message.type === 'hidden').reduce((count, message) => count + message.count, 0);
  assert.equal(total, 1);
  page.close();
});

test('Updating rules does not recount an already-hidden post', async () => {
  const page = load({
    url: 'https://www.instagram.com/',
    html: '<article>Suggested for you</article>',
    rules: defaultRules('instagram')
  });
  await tick();
  page.window.__stillfeed.update(defaultRules('instagram'));
  await tick();
  const total = page.messages.filter(message => message.type === 'hidden').reduce((count, message) => count + message.count, 0);
  assert.equal(total, 1);
  page.close();
});

test('YouTube: ad skip advances and mutes playback when enabled', async () => {
  const page = load({
    url: 'https://m.youtube.com/watch?v=test',
    html: '<div id="movie_player" class="ad-showing"><video></video></div>',
    rules: defaultRules('youtube', { skip_ads: true })
  });
  const media = page.document.querySelector('video');
  Object.defineProperty(media, 'duration', { configurable: true, value: 30 });
  await tick(250);
  assert.ok(media.currentTime > 29, `currentTime should be advanced: ${media.currentTime}`);
  assert.equal(media.muted, true);
  assert.equal(media.playbackRate, 16);
  page.close();
});

test('YouTube: ad skip does not alter playback when disabled', async () => {
  const page = load({
    url: 'https://m.youtube.com/watch?v=test',
    html: '<div id="movie_player" class="ad-showing"><video></video></div>',
    rules: defaultRules('youtube', { skip_ads: false })
  });
  const media = page.document.querySelector('video');
  Object.defineProperty(media, 'duration', { configurable: true, value: 30 });
  await tick(250);
  assert.equal(media.currentTime, 0);
  assert.equal(media.muted, false);
  assert.equal(media.playbackRate, 1);
  page.close();
});

test('YouTube: disabling ad skip dynamically restores playback', async () => {
  const page = load({
    url: 'https://m.youtube.com/watch?v=test',
    html: '<div id="movie_player" class="ad-showing"><video></video></div>',
    rules: defaultRules('youtube', { skip_ads: true })
  });
  const media = page.document.querySelector('video');
  Object.defineProperty(media, 'duration', { configurable: true, value: 30 });
  await tick(250);
  assert.equal(media.muted, true);
  // User toggles skip_ads off in filter module
  page.window.__stillfeed.update(defaultRules('youtube', { skip_ads: false }));
  await tick(50);
  assert.equal(media.muted, false);
  assert.equal(media.playbackRate, 1);
  page.close();
});

test('YouTube Music: a promo pop-up is dismissed using its button', async () => {
  const page = load({
    url: 'https://music.youtube.com/',
    html: '<tp-yt-paper-dialog><ytmusic-mealbar-promo-renderer>Get the app<button id="no">No thanks</button></ytmusic-mealbar-promo-renderer></tp-yt-paper-dialog>',
    rules: defaultRules('youtube_music')
  });
  let pressed = 0;
  page.document.getElementById('no').addEventListener('click', () => { pressed++; });
  await tick();
  assert.equal(pressed, 1);
  assert.equal(page.document.querySelector('tp-yt-paper-dialog').hasAttribute('data-stillfeed-hidden'), false);
  page.close();
});

test('YouTube Music: a reused pop-up is dismissed again', async () => {
  const page = load({
    url: 'https://music.youtube.com/',
    html: '<tp-yt-paper-dialog><button id="no">Not now</button></tp-yt-paper-dialog>',
    rules: defaultRules('youtube_music')
  });
  let pressed = 0;
  page.document.getElementById('no').addEventListener('click', () => { pressed++; });
  await tick();
  assert.equal(pressed, 1);
  await tick(1050);
  page.document.body.appendChild(page.document.createElement('div'));
  await tick();
  assert.equal(pressed, 2);
  page.close();
});

test('YouTube Music: an invisible button is not pressed', async () => {
  const page = load({
    url: 'https://music.youtube.com/',
    html: '<button id="no">No thanks</button>',
    rules: defaultRules('youtube_music'),
    beforeBoot: window => {
      const real = window.Element.prototype.getClientRects;
      window.Element.prototype.getClientRects = function () {
        return this.id === 'no' ? [] : real.call(this);
      };
    }
  });
  let pressed = 0;
  page.document.getElementById('no').addEventListener('click', () => { pressed++; });
  await tick();
  assert.equal(pressed, 0);
  page.close();
});
