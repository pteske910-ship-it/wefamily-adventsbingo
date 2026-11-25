const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('Inline-JavaScript der Webapp ist syntaktisch gültig', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)]
    .map(match => match[1])
    .filter(source => source.trim());
  assert.equal(scripts.length, 1, 'Es wird genau ein Inline-App-Script erwartet');
  assert.doesNotThrow(() => new vm.Script(scripts[0]), 'Inline-App-Script muss parsebar sein');
});
