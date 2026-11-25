# WeFamily Adventsbingo 2026

Entwicklungsstand des Organisations- und Auswertungsmanagers.

## Aktueller Entwicklungsstand

- Weboberfläche in `index.html`, mit Supabase-Authentifizierung.
- Rollen `owner` und `administrator`; neu registrierte Konten warten auf Freigabe.
- Teilnehmer, Runden, Bingo-Ergebnisse und Raumstatistiken werden in Supabase verwaltet.
- Der importierte Bestand kann in der Entwicklungsfassung als lokale Testkopie geladen und bearbeitet werden.
- Im lokalen Testmodus werden Änderungen nur im Browser gespeichert. Es werden keine Änderungen nach Supabase übertragen.
- JSON-Export und -Import dienen der lokalen Datensicherung; der Cloud-Import ist in der aktuellen Testfassung deaktiviert.

## Wichtige Dateien

- `supabase/schema-v1.sql`: Grundschema und RLS-Richtlinien für eine neue Datenbank.
- `supabase/registration-approval.sql`: Registrierung, Profilanlage und Freigabestatus.
- `supabase/apply-single-change.sql` und `supabase/apply-bingo-batch.sql`: versionsgesicherte Schreib-RPCs.
- `supabase/import-legacy-event.sql` und `supabase/sync-legacy-event.sql`: Import- und Sync-Funktionen.
- `supabase/security-hardening.sql`: zusätzliche Einschränkung von Funktionsrechten.
- `supabase/performance-indexes.sql`: additive Indizes für Fremdschlüssel.

## Sicherheits- und Testhinweise

- Änderungen an der Live-Datenbank werden nicht durch Commits im Repository ausgeführt. SQL-Dateien müssen separat geprüft und freigegeben angewendet werden.
- Die aktuelle Entwicklungsfassung hält Cloud-Schreibzugriffe und Cloud-Bearbeitung gesperrt.
- Vor Produktivbetrieb müssen Anmeldung, Registrierung, Freigabe, Rollen, RLS, Event-Isolation, Import/Export und Wiederherstellung mit getrennten Konten dynamisch getestet werden.
- Der öffentliche Supabase Publishable Key ist für den Browser vorgesehen. Ein Service-Role-Key oder andere Geheimnisse dürfen niemals im Frontend oder Repository liegen.
- Das Repository enthält historische Commits. Das Entfernen personenbezogener Daten aus der aktuellen Datei entfernt diese nicht rückwirkend aus der Git-Historie.
