# WeFamily Adventsbingo 2026

Erste lokale Testversion des Organisations- und Auswertungsmanagers.

## Aktueller Stand

- `index.html` enthält einen mobilfreundlichen Prototyp.
- Teilnehmer mit Sonderzeichen können angelegt werden.
- 25 Runden sind vorbereitet; Rundenmodus und interne Notizen sind änderbar.
- Bingo-Ergebnisse können pro Teilnehmer, Runde und Spieltag manuell erfasst werden.
- Eine interne Tageswertung summiert Bingos; Gleichstände werden gemeinsam angezeigt.
- JSON-Export und -Import dienen der lokalen Datensicherung.

## Wichtige Einschränkungen von Version 0.1

- Daten liegen ausschließlich im Local Storage des jeweiligen Browsers/Geräts.
- Es gibt noch keine Anmeldung, Rollenprüfung, gemeinsame Datenbank oder Synchronisierung zwischen Pascal und Heidi.
- Der Bereich „Nur Moderation“ ist in dieser Version nur ausgeblendet und **nicht sicher geschützt**. Er darf nicht als vertraulicher Bereich auf einem Gerät verwendet werden, das Teilnehmer einsehen können.
- WePlay wird nicht automatisiert ausgelesen oder gesteuert. Ergebnisse werden manuell übertragen.

Vor produktivem Einsatz müssen echte Authentifizierung, serverseitige Rollen/Rechte, gemeinsame Speicherung und Zugriffsschutz ergänzt werden.
