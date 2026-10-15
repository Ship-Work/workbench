import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Vercel builds from site/ alone and runs these tests first, so they read only pages inside site/.
const guide = await readFile(new URL('../guide/index.html', import.meta.url), 'utf8');
const handbook = await readFile(new URL('../handbook/index.html', import.meta.url), 'utf8');

function element(html, id) {
  const start = html.indexOf(`id="${id}"`);
  assert.ok(start >= 0, `no element with id ${id}`);
  const tag = html.lastIndexOf('<', start), name = html.slice(tag + 1).match(/^[a-z]+/)[0];
  return html.slice(tag, html.indexOf(`</${name}>`, start));
}

test('the phone-share help says what a window share leaves out, as Present\'s footer does', () => {
  // Can't see your phone?'s Help online opens this section.
  assert.ok(element(guide, 'phone-share').includes(
    'To include Draw, the Timer or a floating persona, share your entire display instead.'));
});

test('the guide says the complete words are copied when live insertion stops', () => {
  // LiveDictationDelivery.finish copies the words whatever Restore clipboard says once its writer has stopped.
  assert.ok(element(guide, 'dictate').includes(
    'Moving or editing the field stops live insertion, and the complete words are copied, ready to paste.'));
});

test('the handbook names no retired tool as an entry point', () => {
  // Read text-to-speech is retired; its drafts stay in Library.
  const craft = element(handbook, 'craft');
  assert.ok(craft.includes('Dictate, Draw and Present remain direct entry points.'));
  assert.ok(!craft.includes('Read,'));
});
