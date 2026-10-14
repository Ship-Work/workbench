import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { renderPublishedRelease, selectPublicRelease, validateRelease } from '../release.mjs';

// Synthetic records exercise selection only; they are never staged for publication.
const preview = {
  channel: 'preview', version: '2.1.0', tag: 'v2.1.0-preview.9', build: '9', source: 'a'.repeat(40), sha256: 'b'.repeat(64),
  download_url: 'https://github.com/Ship-Work/workbench/releases/download/v2.1.0-preview.9/Workbench.Preview.zip'
};
const production = {
  ...preview, channel: 'production', tag: 'v2.1.0',
  download_url: 'https://github.com/Ship-Work/workbench/releases/download/v2.1.0/Workbench.zip',
  feed_url: 'https://workbench-mac.vercel.app/updates/production.xml', feed_sha256: 'c'.repeat(64)
};

test('production takes precedence and an incomplete production record never falls back', () => {
  assert.equal(selectPublicRelease({ preview }).tag, preview.tag);
  assert.equal(selectPublicRelease({ preview, production }).tag, production.tag);
  assert.throws(() => selectPublicRelease({ preview }, { requireProduction: true }), /Production promotion requires/);
  for (const value of [null, {}, preview, { ...production, feed_url: undefined }]) {
    assert.throws(() => selectPublicRelease({ preview, production: value }), /Invalid published release/);
  }
});

test('release identity, digest and immutable links must agree', () => {
  for (const change of [
    { version: '2.0.0' }, { channel: 'preview' }, { channel: undefined }, { build: 'local' },
    { source: 'HEAD' }, { sha256: '' }, { feed_sha256: undefined },
    { download_url: preview.download_url }, { download_url: 'https://other.example/update.zip' },
    { feed_url: 'https://workbench-mac.vercel.app/updates/preview.xml' }
  ]) assert.throws(() => validateRelease({ ...production, ...change }), /Invalid published release/);
});

test('repository transfer accepts exact historical URLs without rewriting receipts', () => {
  for (const record of [preview, production]) {
    const legacy = { ...record, download_url: record.download_url.replace('Ship-Work/workbench', 'EthDawg/workbench') };
    assert.deepEqual(validateRelease(legacy), legacy);
    assert.equal(renderPublishedRelease('{{DOWNLOAD_URL}}', legacy), legacy.download_url);
    assert.match(renderPublishedRelease('{{RELEASE_URL}} {{CHECKSUM_URL}}', legacy), /github\.com\/Ship-Work\/workbench\//);
    for (const url of [
      legacy.download_url.replace('EthDawg/workbench', 'EthDawg/another-repo'),
      legacy.download_url.replace('github.com/', 'github.com.evil.example/'),
      legacy.download_url + '?download=other',
      record.download_url.replace('/download/', '/download/../')
    ]) assert.throws(() => validateRelease({ ...record, download_url: url }), /Invalid published release/);
  }
});

test('production rebuild tag must identify the exact build and keeps immutable links together', () => {
  const tag = 'v2.1.0+9';
  const value = { ...production, tag,
    download_url: `https://github.com/Ship-Work/workbench/releases/download/${tag}/Workbench.zip` };
  assert.equal(validateRelease(value, 'production').tag, tag);
  assert.equal(renderPublishedRelease('{{RELEASE_TAG}} {{RELEASE_VERSION}} {{DOWNLOAD_URL}}', value),
    `${tag} 2.1.0 ${value.download_url}`);
  for (const invalid of ['v2.1.0+8', 'v2.2.0+9', 'v2.1.0-preview.1+9',
    'v2.1.0+local', 'v2.1.0+', 'v2.1.0+9/other']) {
    assert.throws(() => validateRelease({ ...value, tag: invalid,
      download_url: `https://github.com/Ship-Work/workbench/releases/download/${invalid}/Workbench.zip` }),
    /Invalid published release/);
  }
  assert.throws(() => validateRelease({ ...value, channel: 'preview' }), /Invalid published release/);
});

test('one receipt changes every current download and notes link together', async () => {
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  const value = { ...preview, feed_url: 'https://workbench-mac.vercel.app/updates/preview.xml', feed_sha256: 'c'.repeat(64) };
  const result = renderPublishedRelease(html, value);
  assert.ok(result.includes(value.download_url));
  assert.ok(result.includes('/v2.1.0-preview.9/SHA256SUMS.txt'));
  assert.ok(result.includes('/tag/v2.1.0-preview.9'));
  assert.ok(result.includes('2.1.0 Preview 9'));
  assert.ok(result.includes('one-time manual installation'));
  assert.ok(result.includes('Automatic checks and background downloads are on by default'));
  assert.ok(result.includes('both can be changed in Settings, and existing choices are retained'));
  assert.ok(result.includes('normal Quit or when you explicitly restart an idle app'));
  assert.ok(result.includes('Active work defers an update-triggered restart'));
  assert.ok(result.includes('Versions without the updater need one manual replacement first'));
  assert.ok(!result.includes('no automatic updater'));
  const older = renderPublishedRelease(html, preview);
  assert.ok(older.includes('no automatic updater'));
  assert.ok(!older.includes('background downloads are on by default'));
  assert.ok(!older.includes('explicitly restart an idle app'));
  assert.ok(result.includes('same Applications folder'));
  assert.ok(!result.includes('{{'));
  assert.ok(!result.includes('value="2.0.0-preview.4"'));
});

test('production copy names Workbench and makes the Mac focus and separate data explicit', async () => {
  const html = renderPublishedRelease(await readFile(new URL('../index.html', import.meta.url), 'utf8'), production);
  assert.ok(html.includes(production.download_url));
  assert.ok(html.includes(`<span>Workbench ${production.version}</span>`));
  assert.ok(html.includes('<strong>Workbench.app</strong>'));
  assert.ok(!html.includes('Workbench.Preview.zip'));
  assert.ok(!html.includes('Get Workbench Preview'));
  assert.ok(!html.includes('class="beta"'));
  assert.ok(!html.includes('href="/mobile/"'));
  assert.ok(!html.includes('EthDawg/StageMark/issues'));
  assert.ok(html.includes('Work on iPhone, iPad and the Chrome extension is paused'));
  assert.ok(html.includes('does not copy Preview data automatically'));
  assert.ok(html.includes('~/Library/Application Support/Workbench</code>'));
  assert.ok(!html.includes('{{'));
  assert.equal(renderPublishedRelease('{{PREVIEW_TAG}} {{PREVIEW_VERSION}}', production), 'v2.1.0 2.1.0');
  assert.throws(() => renderPublishedRelease('{{UNKNOWN_RELEASE}}', production), /Unknown release placeholder/);
});

test('install and update copy matches what the app does, on the home page and in the guide', async () => {
  const pages = {
    index: await readFile(new URL('../index.html', import.meta.url), 'utf8'),
    guide: await readFile(new URL('../guide/index.html', import.meta.url), 'utf8')
  };
  const feedPreview = { ...preview, feed_url: 'https://workbench-mac.vercel.app/updates/preview.xml', feed_sha256: 'c'.repeat(64) };
  const forbidden = ['Signed by Apple', 'about a minute', 'minute away', 'in a minute', 'compact links',
    'when you open a session', 'In Preview:', 'Everything else works without it', '{{'];
  const required = {
    // Snap & Talk narration is transcribed by the same speech model as Dictate and Meetings.
    index: ['Update to', 'General › Updates', 'Go › Home', 'same Applications folder', 'Request capture access',
      'Snap &amp; Talk narration turn speech into text'],
    guide: ['Update to', 'General › Updates', 'Go › Home', 'same Applications folder']
  };
  for (const record of [production, feedPreview]) {
    for (const [name, html] of Object.entries(pages)) {
      const result = renderPublishedRelease(html, record);
      for (const phrase of forbidden) assert.ok(!result.includes(phrase), `${name} (${record.tag}) still says ${phrase}`);
      for (const phrase of required[name]) assert.ok(result.includes(phrase), `${name} (${record.tag}) lacks ${phrase}`);
      // 2.3.0 through 2.4.1 have the old heading (2.4.0 and 2.4.1 are on the production feed),
      // so the only mention is the one that names every version before 2.5.0.
      const old = [...result.matchAll(/Workbench updates/g)].map(match => result.slice(match.index, match.index + 32));
      assert.ok(old.every(text => text.includes('before 2.5.0')), `${name} (${record.tag}) names the old heading without its versions`);
    }
  }
  assert.ok(renderPublishedRelease(pages.index, preview).includes('no automatic updater'));
});

test('feedback never substitutes website version for the installed build', async () => {
  const js = await readFile(new URL('../app.mjs', import.meta.url), 'utf8');
  assert.ok(!js.includes("getElementById('version').value = apps"));
});
