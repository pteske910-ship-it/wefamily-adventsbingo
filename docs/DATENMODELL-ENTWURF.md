# WeFamily Adventsbingo – Datenmodell für den Neuaufbau

Status: Entwurf auf dem isolierten Branch `redesign/bingo-safe-migration`  
Ausgangsbasis: bestehende Version 0.8 und der geprüfte JSON-Export.  
Wichtig: Dieses Dokument enthält keine privaten Teilnehmer- oder Ergebnisdaten.

## Grundprinzipien

1. Jedes Event ist ein eigenständiger Datensatz mit stabiler, unveränderlicher ID.
2. Teilnehmer, Runden, Wertungen, Raumstatistiken und Einstellungen gehören immer zu genau einem Event.
3. Ein Event darf nicht durch das Anlegen, Duplizieren, Archivieren oder Löschen eines anderen Events verändert werden.
4. Ein Duplikat erhält eine neue Event-ID und neue IDs für alle kopierten Unterdatensätze. Das Original bleibt unverändert.
5. Archivieren ist reversibel. Löschen und Zurücksetzen benötigen eine ausdrückliche Bestätigung.
6. Der Datenexport muss ein einzelnes Event oder alle Events vollständig sichern und wiederherstellen können.
7. Die alte Version bleibt online, bis Import, Abgleich und Tests erfolgreich abgeschlossen sind.

## Vorgeschlagene Struktur

```text
users
  userId
  displayName
  email / authentication-provider
  createdAt

eventMemberships
  eventId
  userId
  role                 # Rolle wird noch festgelegt

events
  eventId
  title
  eventType            # zunächst "advent-bingo"
  status               # draft | active | archived
  createdAt
  updatedAt
  createdBy
  settings
    sessionLabels      # z. B. 1.–4. Advent
    scoring
    roundDefaults

eventParticipants
  participantId
  eventId
  displayName
  family
  sourceParticipantId # optionaler Herkunftsverweis beim Kopieren

rounds
  roundId
  eventId
  number
  mode
  pointsPerBingo
  note

bingoResults
  resultId
  eventId
  roundId
  participantId
  sessionKey
  count
  bingoNo
  place
  points
  roomCount
  createdAt

roomStatistics
  roomStatId
  eventId
  sessionKey
  roundId
  start
  current
  peak
  low
  changes[]
```

## Integritätsregeln

- Jeder Datensatz unterhalb eines Events trägt eine `eventId`.
- Eine Wertung darf nur auf eine Runde und einen Teilnehmer desselben Events verweisen.
- IDs werden beim Duplizieren neu erzeugt; Namen und fachliche Einstellungen können übernommen werden.
- Archivierte Events bleiben lesbar und exportierbar. Änderungen sind standardmäßig gesperrt, bis das Event wieder geöffnet wird.
- Ein Event-Reset löscht nur dessen Wertungen und Raumstatistiken; Teilnehmer und Rundeneinstellungen bleiben nach einer gesonderten Auswahl erhalten.
- Das Löschen eines Events ist ein eigener, zweistufig bestätigter Vorgang.
- Teilnehmernamen sind nicht eindeutig. Gleiche Namen dürfen nicht automatisch zusammengeführt werden.

## Migration aus Version 0.8

Der bisherige Export enthält ein einzelnes Datenobjekt mit `players`, `rounds`, `results`, `presence`, `attendance`, `roomStats` und `scoring`.

Migrationszuordnung:
- `players` → `eventParticipants`
- `rounds` → `rounds`
- `results` → `bingoResults`
- `roomStats` → `roomStatistics`
- `scoring` → `events.settings.scoring`
- `presence` und `attendance` → als Legacy-Daten unverändert im Migrationsarchiv aufbewahren; nicht in die neue Bedienoberfläche übernehmen.

Der Export enthält aktuell nur den Spieltag „1. Advent“ mit Ergebnissen. Die vier Advent-Sonntage sind als Auswahlwerte in der alten Anwendung vorhanden; sie müssen nicht alle Ergebnisdatensätze besitzen.

## Sicherheits- und Migrationsablauf

1. JSON-Export unverändert archivieren.
2. Import in eine isolierte Testumgebung.
3. Datensatzanzahlen und Referenzen gegen den Export prüfen.
4. Duplikat-, Archivierungs-, Wiederöffnungs- und Löschtests durchführen.
5. Anmeldung und Berechtigungen mit mindestens zwei Konten testen.
6. Erst nach Freigabe den neuen Dienst produktiv schalten.
7. Alte Version und Originalexport als Rückfalloption behalten.

## Noch offene Produktentscheidung

Vor dem Einrichten der Konten muss geklärt werden, ob Heidi dieselben Verwaltungsrechte wie der Hauptadministrator erhalten soll oder ob es getrennte Rollen geben soll (z. B. Administrator und Spielleitung). Bis dahin wird keine Berechtigungsannahme fest eingebaut.
