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

test('Spielmanager zeigt zuerst die zentrale Startseite; Adventsbingo-Intro ist eventgebunden', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  assert.match(html, /id="managerHome"/, 'Zentrale Startseite muss vorhanden sein');
  assert.match(html, /function openBingoEvent\(\)[\s\S]*?runBingoIntro\(\);/, 'Das Intro wird beim Öffnen des Events gestartet');
  assert.match(html, /function returnToManagerHome\(\)/, 'Rücknavigation zur Startseite muss vorhanden sein');
  assert.match(html, /id="introSplash"[^>]*hidden/, 'Das Intro muss beim Seitenstart verborgen sein');
  assert.match(html, /data-src="wefamily-sleigh\.webp"/, 'Das Schlittenbild darf nicht direkt beim Seitenstart geladen werden');
  assert.doesNotMatch(html, /\(function runIntro\(\)/, 'Ein automatischer Intro-Aufruf beim Seitenstart darf nicht existieren');
});
