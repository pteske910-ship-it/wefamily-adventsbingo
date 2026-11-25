# WeFamily Spielmanager – Integrationsfahrplan

## Ziel
Die bestehende Adventsbingo-Webapp wird schrittweise zu einer gemeinsam genutzten Webapp mit Supabase-Anmeldung und zentraler Datenhaltung weiterentwickelt. Die bisherige GitHub-Pages-Version bleibt bis zur erfolgreichen Abnahme unverändert.

## Sicherheitsregeln
- Niemals direkt auf `main` entwickeln oder ungeprüfte Änderungen veröffentlichen.
- Vor jeder Datenmigration einen JSON-Export sichern.
- Keine Service-Role-Keys oder anderen Geheimnisse im Browser oder Repository ablegen.
- Cloud-Schreibzugriff bleibt gesperrt, bis Lesen, Datenvergleich, Schreibtest und Wiederherstellung erfolgreich geprüft wurden.
- Vorhandene Supabase-Benutzer, Rollen und Spieldaten nicht löschen oder zurücksetzen.
- Bestehende lokale Daten müssen bei Login, Reload und fehlgeschlagenen Cloud-Aufrufen erhalten bleiben.

## Phasen und Abnahmekriterien

### 1. Sichere Integrationsbasis
- [x] Neuen Branch `integration/webapp-supabase` aus dem offiziellen `main` angelegt.
- [x] Bestand von `main` und `redesign/bingo-safe-migration` dateiweise verglichen; der Redesign-Branch wird nicht pauschal übernommen.
- [ ] Nur benötigte Änderungen gezielt übernehmen; keine divergierenden Branches pauschal mergen.
- Abnahme: Hauptbranch und veröffentlichte Seite bleiben unverändert.

### 2. Authentifizierung und Rollen
- [x] Supabase-Login und Logout in die main-basierte Oberfläche integriert.
- [x] Registrierung per E-Mail und Passwort integriert (Mindestlänge 8 Zeichen).
- [x] Neue Konten starten laut bestehendem Auth-Trigger als `pending`; Freigabeoberfläche nur für Owner ergänzt.
- [x] Aktiven Status und Rolle `owner`/`administrator` beim App-Einstieg prüfen.
- [ ] Mit zwei getrennten Konten und abgelehnten Registrierungen im Browser testen.
- Abnahme: Nicht freigegebene Konten erhalten keinen Zugriff auf Spieldaten.

### 3. Cloud-Lesen und Datenabgleich
- [ ] Event, Teilnehmer, Runden, Ergebnisse und Raumstatistiken laden.
- [ ] JSON-Export gegen Cloud-Bestand vergleichen.
- [ ] IDs und Verknüpfungen erhalten; keine stillen Duplikate.
- [ ] Lokale Kopie bei Reload erhalten.
- Abnahme: Alle Datensatzanzahlen und fachlichen Inhalte stimmen überein.

### 4. Sicheres Cloud-Schreiben
- [ ] Atomare Mehrfachänderungen und Versionsprüfung integrieren.
- [ ] Temporäre Testdaten anlegen und wieder entfernen.
- [ ] Ergebnis löschen und identisch wiederherstellen.
- [ ] Veraltete Version muss mit Konflikt abgewiesen werden.
- [ ] Fehlerfall darf keinen halben Schreibvorgang hinterlassen.
- Abnahme: Tests bestanden, Datenvergleich danach weiterhin identisch. Erst dann Schreibzugriff freigeben.

### 5. Spiellogik und Auswertungen
- [ ] Regeln für Runde 1 ohne Vergleichsstand erhalten.
- [ ] Ab Runde 2 Rangbewegung und Kennzeichnung „Neu dabei“ korrekt berechnen.
- [ ] Punktelogik, Bingo-Zählung, Tages- und Gesamtranglisten vergleichen.
- [ ] Import/Export und Wiederherstellung testen.
- Abnahme: Referenzfälle aus dem bisherigen Spiel ergeben dieselben korrekten Werte.

### 6. Bedienung und Geräte
- [ ] Mobile Tabellen und Eingabeformulare prüfen.
- [ ] Navigation, Admin-Ansichten und Statusmeldungen testen.
- [ ] Reload, Offline-/Fehlerfälle und erneute Anmeldung testen.
- Abnahme: Kernabläufe auf Smartphone und Desktop ohne Datenverlust bedienbar.

### 7. Veröffentlichung
- [ ] Browser- und Zufallssimulation bestehen lassen.
- [ ] Mindestens einen vollständigen Zwei-Konten-Test durchführen.
- [ ] Export der produktiven Daten erstellen und Wiederherstellung verifizieren.
- [ ] Separaten Release-PR erstellen.
- Abnahme: Veröffentlichung erst nach ausdrücklicher Freigabe; alte Version bleibt Rückfalloption.

## Aktueller Bestand (25.11.2026)
- Supabase enthält 2 Auth-Benutzer und 2 aktive Profile (Owner und Administrator).
- 1 Veranstaltung, 47 Teilnehmer, 25 Runden, 22 Bingo-Ergebnisse und 4 Raumstatistiken.
- Es gibt bereits SQL-Funktionen für Import, Einzeländerungen, Batch-Änderungen und Snapshot-Synchronisierung.
- Der Supabase-Redesign-Branch hat Login/Registrierung und einen Cloud-Lese-/Vergleichspfad. Cloud-Import und Cloud-Schreibtest sind in der untersuchten Fassung ausdrücklich deaktiviert.
- Die offizielle `main`-Anwendung ist weiterhin lokal-/localStorage-basiert.

## Arbeitsstatus (25.11.2026)
- Phase 1: Integrationsbranch basiert direkt auf `main`; keine pauschale Übernahme des stark abweichenden Redesign-Branches.
- Phase 2: Login, Logout, Registrierung und Owner-Freigabeoberfläche sind auf dem Integrationsbranch eingebaut.
- Die Spieloberfläche bleibt ausdrücklich lokal: Diese Änderung synchronisiert noch keine Teilnehmer oder Ergebnisse mit Supabase.
- Die Anmeldung verwendet das vorhandene Supabase-Projekt und die bereits vorhandenen `app_users`-Profile/Rollen. Der aktive Status wird vor Freigabe der Oberfläche geprüft.
- Noch nicht erledigt: Browser-Test mit Owner- und Administrator-Konto, Registrierung/Freigabe mit einem frischen Testkonto, anschließend Cloud-Lesen und Datenvergleich.
- Keine produktiven Tabellen oder Datensätze wurden durch diese Integration verändert.
