const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { chromium } = require('playwright');

const DURATION_MS = Number(process.env.SOAK_DURATION_MS || 60 * 60 * 1000);
const ROOT = path.resolve(__dirname, '..');

function makeSeed() {
  let state = 0x60FA11;
  const random = () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 0x100000000;
  };
  const int = (min, max) => min + Math.floor(random() * (max - min + 1));
  const initialNames = ["Nami","🔥Viktor","itslaylla👻","MoMo¹⁶¹","Mommy","CHARLY ✨🥖","PASCAL","Hubii","King","David","Christoph","Jenny","ARRO-FISCHER","ELFI_ÖMMEL","QUEEN♡p","FABIⓎ","Tanja","Ⓨ Dark","Santa Clause","Petra","Santas Wife","Rene","JONNY💀","Rover","Klein Marie","Daniel","Ⓨ Fanni","LovelyWoman","GARY","Carsten","Gus","Eis. de","JOSI","NICII ☀️","Shadow ☯","Soulgard","Unknown","Itacki"];
  const players = Array.from({ length: 70 }, (_, i) => ({
    id: 'soak-player-' + String(i + 1).padStart(2, '0'),
    name: initialNames[i] || 'Dauerlast Teilnehmer ' + String(i + 1).padStart(2, '0'),
    family: ''
  }));
  const modes = ['Normal', 'Power-up', 'Blackout'];
  const rounds = Array.from({ length: 50 }, (_, i) => ({
    n: i + 1, mode: modes[int(0, modes.length - 1)], note: ''
  }));
  const roomStats = {};
  const sessions = Array.from({ length: 100 }, (_, i) =>
    'Belastungstag ' + String(i + 1).padStart(3, '0'));
  for (const session of sessions) {
    roomStats[session + '|1'] = {
      round: 1, start: int(25, 70), current: int(25, 70),
      peak: 70, low: 25, changes: []
    };
  }
  return {
    random, int, players, rounds, sessions,
    db: {
      players, rounds, results: [], presence: {}, attendance: {},
      roomStats,
      scoring: { mode: 'mode', normal: 2, power: 4, blackout: 7,
        placements: [10, 8, 7, 6, 5] }
    }
  };
}

function startServer() {
  const mime = {
    '.html': 'text/html; charset=utf-8', '.png': 'image/png',
    '.webp': 'image/webp', '.css': 'text/css', '.js': 'text/javascript'
  };
  const server = http.createServer((req, res) => {
    const pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
    const relative = pathname === '/' ? 'index.html' : pathname.slice(1);
    const file = path.resolve(ROOT, relative);
    if (!file.startsWith(ROOT + path.sep) && file !== path.join(ROOT, 'index.html')) {
      res.writeHead(403).end('Forbidden'); return;
    }
    fs.readFile(file, (error, data) => {
      if (error) { res.writeHead(404).end('Not found'); return; }
      res.writeHead(200, { 'content-type': mime[path.extname(file)] || 'application/octet-stream' });
      res.end(data);
    });
  });
  return new Promise(resolve => server.listen(0, '127.0.0.1', () =>
    resolve({ server, url: 'http://127.0.0.1:' + server.address().port })));
}

test('60 Minuten Browser-Dauerlast: echte UI, Dateneingabe, Tageswechsel und Ranglisten', {
  timeout: 66 * 60 * 1000
}, async () => {
  const { random, int, players, rounds, sessions, db } = makeSeed();
  const { server, url } = await startServer();
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage']
  });
  const page = await browser.newPage({ viewport: { width: 1365, height: 900 } });
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error') pageErrors.push('console: ' + message.text());
  });

  const startedAt = new Date();
  const started = Date.now();
  const deadline = started + DURATION_MS;
  const report = {
    startedAt: startedAt.toISOString(),
    requestedDurationMs: DURATION_MS,
    sessions: sessions.length,
    participants: players.length,
    availableRounds: rounds.length,
    rounds: rounds.map(r => ({ round: r.n, mode: r.mode })),
    actions: 0,
    completedDays: 0,
    rankingChecks: 0,
    reloads: 0,
    samples: [],
    simulatedDurationCount: 0,
    simulatedDurationTotalSeconds: 0,
    simulatedDurationMinSeconds: 240,
    simulatedDurationMaxSeconds: 30,
    errors: pageErrors
  };

  try {
    await page.addInitScript(seed => {
      if (!localStorage.getItem('wf-adventbingo-v01')) {
        localStorage.setItem('wf-adventbingo-v01', JSON.stringify(seed));
      }
    }, db);
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.locator('#sessionName').waitFor({ state: 'attached', timeout: 5000 });
    await page.waitForTimeout(2000);
    // Die Intro-Animation darf den Test nicht blockieren; Fehler vor dem Entfernen erfassen.
    await page.evaluate(() => document.getElementById('introSplash')?.remove());
    assert.deepEqual(pageErrors, [], 'Keine JavaScript-Fehler beim initialen Rendern: ' + pageErrors.join(' | '));
    assert.equal(await page.title(), 'WeFamily Adventsbingo');

    const tab = name => page.locator('button.tab[data-tab="' + name + '"]');
    await tab('results').click();
    await page.locator('#results').waitFor({ state: 'visible', timeout: 5000 });
    assert.equal(await tab('results').getAttribute('class').then(v => v.includes('active')), true,
      'Ergebnis-Tab wird durch echten Klick aktiviert');
    const saveSelector = '#results button[onclick="saveResult()"]';
    assert.equal(await page.locator(saveSelector).count(), 1, 'Speichern-Schaltfläche ist sichtbar');

    let dayIndex = 0;
    let roundIndex = 0;
    let lastSample = started;
    while (Date.now() < deadline) {
      const session = sessions[dayIndex % sessions.length];
      const roundsToday = int(12, 50);
      const selectedRounds = Array.from({ length: roundsToday }, (_, i) => i + 1);

      for (const roundNo of selectedRounds) {
        if (Date.now() >= deadline) break;
        const player = players[int(0, players.length - 1)];
        const simulatedDurationSeconds = int(30, 240);

        // Bedienung ausschließlich über sichtbare Controls – wie ein Mensch mit Maus/Tastatur.
        await page.locator('#sessionName').selectOption(session);
        await page.locator('#resultRound').selectOption(String(roundNo));
        await page.locator('#playerSearch').fill(player.name);
        const suggestion = page.locator('#playerSuggestions button').filter({ hasText: player.name }).first();
        await suggestion.waitFor({ state: 'visible', timeout: 5000 });
        await suggestion.click();
        await page.locator(saveSelector).click();

        report.actions++;
        roundIndex++;
        report.simulatedDurationCount++;
        report.simulatedDurationTotalSeconds += simulatedDurationSeconds;
        report.simulatedDurationMinSeconds = Math.min(report.simulatedDurationMinSeconds, simulatedDurationSeconds);
        report.simulatedDurationMaxSeconds = Math.max(report.simulatedDurationMaxSeconds, simulatedDurationSeconds);

        if (roundIndex % 25 === 0) {
          const snapshot = await page.evaluate(() => {
            const stored = JSON.parse(localStorage.getItem('wf-adventbingo-v01') || '{}');
            const resultCount = Array.isArray(stored.results) ? stored.results.length : 0;
            const bytes = new Blob([JSON.stringify(stored)]).size;
            const memory = performance.memory ? performance.memory.usedJSHeapSize : null;
            return { resultCount, storageBytes: bytes, heapBytes: memory };
          });
          assert.ok(snapshot.resultCount >= report.actions,
            'Local Storage enthält alle über die Oberfläche gespeicherten Ergebnisse');
          report.lastSnapshot = snapshot;
        }
      }

      report.completedDays++;
      dayIndex++;

      // Tatsächliche Navigation durch die Bereiche und Neuberechnung der Tages- und Gesamtwertung.
      await tab('internal').click();
      await page.locator('#internalSession').fill(session);
      await page.locator('#adminRoomView button[onclick="renderInternal()"]').click();
      await page.locator('button[data-adminview="stats"]').click();
      const statsSelection = dayIndex % 10 === 0 ? '__all' : session;
      await page.locator('#statsSession').selectOption(statsSelection);
      const statsText = await page.locator('#statsReport').innerText();
      assert.match(statsText, /Bingos gesamt/i, 'Gesamtstatistik wird im Browser gerendert');
      report.rankingChecks++;

      if (dayIndex % 4 === 0) {
        await tab('players').click();
        assert.equal(await page.locator('#playerList').count(), 1);
        await tab('results').click();
      } else {
        await tab('results').click();
      }

      const now = Date.now();
      if (now - lastSample >= 60_000) {
        const snapshot = await page.evaluate(() => ({
          resultCount: JSON.parse(localStorage.getItem('wf-adventbingo-v01') || '{}').results?.length || 0,
          heapBytes: performance.memory ? performance.memory.usedJSHeapSize : null,
          renderedResultRows: document.querySelectorAll('#resultList .item').length
        }));
        report.samples.push({ elapsedMs: now - started, ...snapshot });
        lastSample = now;
      }

      // Nach jeweils 20 vollständigen Tagen wird ein echter Browser-Reload ausgeführt.
      if (dayIndex % 20 === 0 && Date.now() < deadline) {
        await page.reload({ waitUntil: 'domcontentloaded' });
        await page.locator('#sessionName').waitFor({ state: 'attached', timeout: 5000 });
        await page.evaluate(() => document.getElementById('introSplash')?.remove());
        await tab('results').click();
        await page.locator('#results').waitFor({ state: 'visible', timeout: 5000 });
        report.reloads++;
        const persistedCount = await page.evaluate(() =>
          JSON.parse(localStorage.getItem('wf-adventbingo-v01') || '{}').results?.length || 0);
        assert.ok(persistedCount >= report.actions, 'Ergebnisse bleiben nach Browser-Reload erhalten');
      }
    }

    report.elapsedMs = Date.now() - started;
    report.finishedAt = new Date().toISOString();
    report.simulatedDurationAverageSeconds = report.simulatedDurationCount
      ? report.simulatedDurationTotalSeconds / report.simulatedDurationCount : 0;
    report.finalResultCount = await page.evaluate(() =>
      JSON.parse(localStorage.getItem('wf-adventbingo-v01') || '{}').results?.length || 0);
    report.errors = pageErrors.slice();
    assert.ok(report.elapsedMs >= DURATION_MS, 'Der Browser-Test lief mindestens 60 Minuten');
    assert.ok(report.actions > 0, 'Es wurden Bingo-Ergebnisse über die echte UI gespeichert');
    assert.ok(report.completedDays > 0, 'Es wurden Spieltage durchlaufen');
    assert.ok(report.rankingChecks > 0, 'Tages- und Gesamtwertungen wurden wiederholt gerendert');
    assert.ok(report.simulatedDurationMinSeconds >= 30 && report.simulatedDurationMaxSeconds <= 240,
      'Simulierte Rundendauern liegen zwischen 30 und 240 Sekunden');
    assert.equal(report.finalResultCount, report.actions, 'Alle Aktionen liegen dauerhaft im Browser-Speicher');
    assert.deepEqual(pageErrors, [], 'Keine Browser-JavaScript- oder Konsolenfehler');

    fs.mkdirSync(path.join(ROOT, 'artifacts'), { recursive: true });
    fs.writeFileSync(path.join(ROOT, 'artifacts', 'browser-soak-report.json'),
      JSON.stringify(report, null, 2));
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
});
