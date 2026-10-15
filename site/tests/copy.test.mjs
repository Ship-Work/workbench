import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Vercel builds from site/ alone and runs these tests first, so they read only pages inside site/.
const guide = await readFile(new URL('../guide/index.html', import.meta.url), 'utf8');

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
