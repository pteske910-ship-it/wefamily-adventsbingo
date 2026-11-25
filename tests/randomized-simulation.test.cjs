const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

function extractFunction(name) {
  const start = html.indexOf('function ' + name + '(');
  assert.notEqual(start, -1, 'Produktionsfunktion fehlt: ' + name);
  const brace = html.indexOf('{', start);
  let depth = 0, quote = null, escaped = false;
  for (let i = brace; i < html.length; i++) {
    const c = html[i], n = html[i + 1];
    if (quote) {
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '\`') { quote = c; continue; }
    if (c === '/' && n === '/') { while (i < html.length && html[i] !== '\n') i++; continue; }
    if (c === '/' && n === '*') { i += 2; while (i < html.length && !(html[i] === '*' && html[i+1] === '/')) i++; i++; continue; }
    if (c === '{') depth++;
    if (c === '}' && --depth === 0) return html.slice(start, i + 1);
  }
  throw new Error('Funktion nicht vollständig: ' + name);
}

const functions = ['statSessions', 'tally', 'statData', 'compareDays', 'resolveBingoPoints', 'pointsForResult'].map(extractFunction);
const sandbox = { db: null, Object, Number, String, Math, Set };
vm.createContext(sandbox);
vm.runInContext(functions.join('\n') + '\nthis.api={statSessions,tally,statData,compareDays,resolveBingoPoints,pointsForResult};', sandbox);
const { statSessions, tally, statData, compareDays, resolveBingoPoints, pointsForResult } = sandbox.api;

function rng(seed) {
  let x = seed >>> 0;
  return () => {
    x = (x * 1664525 + 1013904223) >>> 0;
    return x / 4294967296;
  };
}
function integer(random, min, max) { return min + Math.floor(random() * (max - min + 1)); }

test('100 zufällige vollständige Spielverläufe: Bingo-, Punkte- und Tagesvergleiche', () => {
  for (let run = 1; run <= 100; run++) {
    const random = rng(0xA11CE + run * 7919);
    const playerCount = integer(random, 4, 45);
    const roundCount = integer(random, 3, 25);
    const sessions = ['1. Advent', '2. Advent', '3. Advent', '4. Advent'];
    const players = Array.from({ length: playerCount }, (_, i) => ({
      id: 'p' + i, name: 'Spieler ' + String(i).padStart(2, '0'), family: ''
    }));
    const rounds = Array.from({ length: roundCount }, (_, i) => ({ n: i + 1, mode: ['Normal', 'Power-up', 'Blackout'][integer(random, 0, 2)] }));
    const results = [];
    for (const session of sessions) {
      const activeCount = integer(random, 1, playerCount);
      const active = new Set();
      while (active.size < activeCount) active.add(integer(random, 0, playerCount - 1));
      for (let round = 1; round <= roundCount; round++) {
        for (const playerIndex of active) {
          if (random() < 0.48) {
            const count = integer(random, 1, 4);
            results.push({
              id: 'r' + results.length, session, round,
              playerId: 'p' + playerIndex, count,
              points: integer(random, 0, 15) * count,
              bingoNo: count === 1 ? integer(random, 1, 100) : null
            });
          }
        }
      }
    }
    if (random() < 0.5) results.push({
      id: 'orphan-' + run, session: sessions[integer(random, 0, 3)],
      round: integer(random, 1, roundCount), playerId: 'deleted-player',
      count: integer(random, 1, 3), points: integer(random, 1, 20)
    });
    sandbox.db = { players, rounds, results, roomStats: {}, scoring: { mode: 'mode', normal: 2, power: 3, blackout: 9 } };
    const scenario = 'Durchlauf ' + run + ' (Spieler=' + playerCount + ', Runden=' + roundCount + ')';
    assert.deepEqual([...statSessions()], sessions, scenario + ': Spieltage');
    for (const session of sessions) {
      for (const round of [null, ...Array.from({length: roundCount}, (_, i) => i + 1)]) {
        const actual = tally(session, round);
        const expected = new Map(players.map(p => [p.id, { total: 0, points: 0 }]));
        results.filter(r => r.session === session && (round === null || r.round === round))
          .forEach(r => {
            const item = expected.get(r.playerId);
            if (item) { item.total += Math.max(0, Number(r.count) || 0); item.points += pointsForResult(r); }
          });
        for (const row of actual) {
          const e = expected.get(row.id);
          assert.equal(row.total, e.total, scenario + ': Bingos ' + session + ' Runde ' + round + ' Spieler ' + row.id);
          assert.equal(row.points, e.points, scenario + ': Punkte ' + session + ' Runde ' + round + ' Spieler ' + row.id);
        }
        assert.equal(actual.length, playerCount, scenario + ': Teilnehmerzahl in Rangliste');
      }
    }
    const all = statData('__all');
    assert.equal(all.total, results.reduce((sum, r) => sum + (Number(r.count) || 0), 0), scenario + ': Gesamtzahl Bingos');
    assert.equal(all.daily.length, 4, scenario + ': Anzahl Spieltage');
    for (const day of all.daily) {
      const expected = results.filter(r => r.session === day.session);
      assert.equal(day.total, expected.reduce((sum, r) => sum + (Number(r.count) || 0), 0), scenario + ': Tages-Bingos ' + day.session);
      assert.equal(day.participants, new Set(expected.filter(r => (Number(r.count) || 0) > 0).map(r => r.playerId)).size, scenario + ': aktive Spieler ' + day.session);
    }
    const compared = compareDays(all.daily);
    assert.equal(compared[0].returning, null, scenario + ': erster Spieltag darf keinen Vergleich haben');
    assert.equal(compared[0].newcomers, null, scenario + ': erster Spieltag darf niemanden als neu markieren');
    for (let i = 1; i < compared.length; i++) {
      const previous = all.daily[i - 1].bingoPlayers;
      const current = all.daily[i].bingoPlayers;
      assert.equal(compared[i].returning, [...current].filter(id => previous.has(id)).length, scenario + ': Wiederkehrer ' + compared[i].session);
      assert.equal(compared[i].newcomers, [...current].filter(id => !previous.has(id)).length, scenario + ': Neu dabei ' + compared[i].session);
    }
  }
});


test('Wertung ist turnierweit global: Spielmodus oder Platzierung', () => {
  const scoring = { mode: 'mode', normal: 2, power: 1, blackout: 3 };
  assert.equal(resolveBingoPoints({ n: 1, mode: 'Normal', pointsPerBingo: 99 }, 1, scoring), 2,
    'Ein alter Runden-Sonderwert wird ignoriert; Normal nutzt den globalen Wert');
  assert.equal(resolveBingoPoints({ n: 2, mode: 'Power-up' }, 1, scoring), 1,
    'Alle Power-up-Runden nutzen denselben globalen Wert');
  assert.equal(resolveBingoPoints({ n: 3, mode: 'Blackout' }, 1, scoring), 3,
    'Alle Blackout-Runden nutzen denselben globalen Wert');

  const placements = [8, 7, 5, 3];
  const placementScoring = { mode: 'place', placements };
  assert.equal(resolveBingoPoints({ n: 1, mode: 'Normal' }, 1, placementScoring), 8,
    'Bingo Nr. 1 erhält den Wert für Platz 1');
  assert.equal(resolveBingoPoints({ n: 1, mode: 'Blackout' }, 2, placementScoring), 7,
    'Die Platzierungstabelle gilt unabhängig vom Spielmodus');
  assert.equal(resolveBingoPoints({ n: 1, mode: 'Power-up' }, 3, placementScoring), 5,
    'Die Punktwerte können frei gestaffelt werden');
  assert.equal(resolveBingoPoints({ n: 1, mode: 'Normal' }, 5, placementScoring), 0,
    'Nicht konfigurierte Platzierungen erhalten 0 Punkte');

  sandbox.db = {
    rounds: [{ n: 1, mode: 'Blackout' }],
    scoring: { mode: 'mode', normal: 2, power: 1, blackout: 3 }
  };
  assert.equal(pointsForResult({ round: 1, bingoNo: 1, points: 99 }), 3,
    'Gespeicherte alte Punkte werden anhand der aktuellen globalen Turnierwertung neu berechnet');
  sandbox.db.scoring = { mode: 'place', placements: [10, 8, 7] };
  assert.equal(pointsForResult({ round: 1, bingoNo: 2, points: 99 }), 8,
    'Auch historische Ergebnisse folgen der zentralen Platzierungstabelle');
  assert.equal(pointsForResult({ round: 1, count: 2, points: 12 }), 12,
    'Ältere zusammengefasste Datensätze ohne Bingo-Nummer behalten ihren gespeicherten Punktewert');

  sandbox.db = {
    players: [{ id: 'p1', name: 'Spieler 1' }, { id: 'p2', name: 'Spieler 2' }],
    rounds: [{ n: 1, mode: 'Normal' }],
    scoring: { mode: 'place', placements: [10, 8, 7] },
    results: [
      { session: 'Tag 1', round: 1, playerId: 'p1', count: 1, bingoNo: 2, points: 8 },
      { session: 'Tag 1', round: 1, playerId: 'p2', count: 1, bingoNo: 1, points: 10 }
    ],
    roomStats: {}
  };
  assert.deepEqual(tally('Tag 1').map(x => x.id), ['p2', 'p1'],
    'Die Tagesrangliste sortiert nach erreichten Punkten, nicht nach bloßer Bingo-Anzahl');
});


test('100 Spieltage mit 25–70 Spielern, 12–50 Runden und 30–240 Sekunden je Runde', () => {
  const random = rng(0xB1A60 + 20261125);
  const modes = ['Normal', 'Power-up', 'Blackout'];
  const players = Array.from({ length: 70 }, (_, i) => ({
    id: 'load-p' + i, name: 'Teilnehmer ' + String(i + 1).padStart(2, '0'), family: ''
  }));
  const rounds = Array.from({ length: 50 }, (_, i) => ({
    n: i + 1,
    mode: modes[integer(random, 0, modes.length - 1)]
  }));
  const sessions = [];
  const results = [];
  const durations = [];
  const dayExpected = new Map();
  let bingoId = 0;

  for (let day = 1; day <= 100; day++) {
    const session = day <= 4
      ? day + '. Advent'
      : 'Spieltag ' + String(day).padStart(3, '0');
    const playerCount = integer(random, 25, 70);
    const roundCount = integer(random, 12, 50);
    sessions.push(session);
    const activePlayers = players.slice(0, playerCount);
    const expected = new Map(activePlayers.map(p => [p.id, { total: 0, points: 0 }]));
    const durationRows = [];

    for (let roundNo = 1; roundNo <= roundCount; roundNo++) {
      const durationSeconds = integer(random, 30, 240);
      durationRows.push({ round: roundNo, seconds: durationSeconds });
      assert.ok(durationSeconds >= 30 && durationSeconds <= 240,
        session + ' Runde ' + roundNo + ': Rundendauer außerhalb 30–240 Sekunden');

      const winners = new Set();
      const winnerCount = integer(random, 1, Math.min(15, playerCount));
      while (winners.size < winnerCount) winners.add(integer(random, 0, playerCount - 1));
      let bingoNo = 0;

      for (const playerIndex of winners) {
        const player = activePlayers[playerIndex];
        bingoNo++;
        const round = rounds[roundNo - 1];
        const points = resolveBingoPoints(round, bingoNo, {
          mode: 'mode', normal: 2, power: 4, blackout: 7
        });
        results.push({
          id: 'load-r' + (++bingoId), session, round: roundNo,
          playerId: player.id, count: 1, bingoNo, points
        });
        const row = expected.get(player.id);
        row.total++;
        row.points += points;
      }
    }

    durations.push({ session, playerCount, roundCount, rounds: durationRows,
      totalSeconds: durationRows.reduce((sum, r) => sum + r.seconds, 0) });
    dayExpected.set(session, expected);
  }

  sandbox.db = {
    players,
    rounds,
    results,
    roomStats: {},
    scoring: { mode: 'mode', normal: 2, power: 4, blackout: 7 }
  };

  assert.deepEqual([...statSessions()], sessions, 'Alle 100 Spieltage werden in richtiger Reihenfolge erkannt');
  assert.equal(durations.length, 100, 'Es wurden exakt 100 Spieltage simuliert');
  assert.ok(durations.every(d => d.playerCount >= 25 && d.playerCount <= 70),
    'Jeder Spieltag hat 25–70 Spieler');
  assert.ok(durations.every(d => d.roundCount >= 12 && d.roundCount <= 50),
    'Jeder Spieltag hat 12–50 Runden');
  assert.ok(durations.every(d => d.rounds.length === d.roundCount),
    'Jede Runde besitzt eine eigene simulierte Dauer');
  assert.ok(durations.every(d => d.totalSeconds >= d.roundCount * 30 && d.totalSeconds <= d.roundCount * 240),
    'Die aufsummierte Spieldauer liegt innerhalb der Rundengrenzen');

  for (const day of durations) {
    const actual = tally(day.session);
    const expected = dayExpected.get(day.session);
    assert.equal(actual.length, 70, day.session + ': globale Teilnehmerliste bleibt vollständig');
    for (const row of actual) {
      const e = expected.get(row.id) || { total: 0, points: 0 };
      assert.equal(row.total, e.total, day.session + ': Bingo-Gesamtzahl ' + row.id);
      assert.equal(row.points, e.points, day.session + ': Punktegesamtzahl ' + row.id);
    }
    const dayResults = results.filter(r => r.session === day.session);
    assert.equal(dayResults.length, dayResults.reduce((sum, r) => sum + r.count, 0),
      day.session + ': jedes gespeicherte Ergebnis entspricht genau einem Bingo');
    for (let roundNo = 1; roundNo <= day.roundCount; roundNo++) {
      const roundResults = dayResults.filter(r => r.round === roundNo);
      assert.ok(roundResults.length >= 1 && roundResults.length <= 15,
        day.session + ' Runde ' + roundNo + ': simulierte Bingo-Anzahl');
      assert.deepEqual(roundResults.map(r => r.bingoNo),
        roundResults.map((r, i) => i + 1),
        day.session + ' Runde ' + roundNo + ': Bingo-Nummern laufen lückenlos');
      const roundTally = tally(day.session, roundNo);
      assert.equal(roundTally.reduce((sum, r) => sum + r.total, 0), roundResults.length,
        day.session + ' Runde ' + roundNo + ': Rundensumme stimmt');
    }
  }

  const all = statData('__all');
  assert.equal(all.daily.length, 100, 'Statistik enthält genau 100 Spieltage');
  assert.equal(all.total, results.length, 'Gesamtstatistik zählt alle simulierten Bingos');
  for (const day of all.daily) {
    const expected = dayExpected.get(day.session);
    assert.equal(day.total, [...expected.values()].reduce((sum, x) => sum + x.total, 0),
      day.session + ': Tagesstatistik stimmt');
    assert.equal(day.participants, [...expected.values()].filter(x => x.total > 0).length,
      day.session + ': Teilnehmerzahl mit Bingo stimmt');
  }

  const compared = compareDays(all.daily);
  assert.equal(compared.length, 100, 'Vergleich enthält 100 Tage');
  assert.equal(compared[0].returning, null, 'Tag 1 ist die Grundtabelle ohne Vergleich');
  assert.equal(compared[0].newcomers, null, 'Tag 1 markiert niemanden als neu dabei');
  for (let i = 1; i < compared.length; i++) {
    const prior = all.daily[i - 1].bingoPlayers;
    const current = all.daily[i].bingoPlayers;
    assert.equal(compared[i].returning, [...current].filter(id => prior.has(id)).length,
      compared[i].session + ': Wiederkehrer korrekt');
    assert.equal(compared[i].newcomers, [...current].filter(id => !prior.has(id)).length,
      compared[i].session + ': Neu-dabei-Zahl korrekt');
  }
});
