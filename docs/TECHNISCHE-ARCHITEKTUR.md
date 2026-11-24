# WeFamily Adventsbingo – technische Architektur

## Ziel

Die bisherige statische GitHub-Pages-Anwendung wird zu einer gemeinsam genutzten Webanwendung mit Anmeldung und zentral gespeicherten Daten weiterentwickelt. GitHub Pages kann weiterhin die Oberfläche ausliefern; die gemeinsame Datenhaltung und Anmeldung laufen über einen separaten Backend-Dienst.

## Vorgeschlagener Backend-Baustein: Supabase

Supabase wird als Backend vorgeschlagen, weil es PostgreSQL, Benutzeranmeldung und serverseitige Zugriffskontrollen kombiniert.

Bausteine:
- Weboberfläche: responsives Frontend; zunächst weiterhin über GitHub Pages auslieferbar.
- Authentifizierung: Supabase Auth mit persönlichem Konto je Benutzer.
- Datenbank: PostgreSQL mit Tabellen für Benutzer, Events, Event-Mitgliedschaften, Teilnehmer, Runden, Bingo-Ergebnisse, Raumstatistiken und Audit-Protokoll.
- Zugriffsschutz: Row Level Security (RLS) auf allen Event-Daten. Der Browser darf nur Daten lesen oder ändern, für die das angemeldete Konto eine gültige Mitgliedschaft besitzt.
- Rollen: `owner` und `administrator`. Der Eigentümer ist dauerhaft geschützt; nur er darf Heidi ihre Administratorrechte entziehen oder wieder erteilen.
- Geheimnisse: Der öffentliche Browser-Schlüssel darf nur mit korrekt konfigurierten RLS-Regeln verwendet werden. Ein Service-Role-Schlüssel oder andere geheime Zugangsdaten gehören niemals in das Frontend oder GitHub-Repository.

## Sicherheitsregeln

1. Jede Event-Tabelle enthält eine nicht leere `event_id`.
2. Fremdschlüssel und zusammengesetzte Constraints verhindern Verknüpfungen zwischen Datensätzen unterschiedlicher Events.
3. RLS wird standardmäßig verweigernd konfiguriert.
4. Rollenänderungen werden serverseitig autorisiert und im Audit-Protokoll gespeichert.
5. Das Eigentümerkonto kann nicht über die normale Admin-Oberfläche entfernt oder herabgestuft werden.
6. Keine Zugangsdaten, privaten JSON-Exporte oder persönlichen Teilnehmerdaten werden in das öffentliche Repository eingecheckt.
7. Vor Produktivbetrieb werden Rechte, Event-Isolation, Import, Export und Wiederherstellung mit getrennten Testkonten geprüft.

## Bereitstellungs- und Migrationsplan

1. Supabase-Projekt im Eigentum des Nutzers anlegen.
2. Datenbankschema und RLS-Policies in einer Entwicklungsumgebung einrichten.
3. Authentifizierung und Eigentümerkonto konfigurieren.
4. Heidi als Administrator einladen und Rechteänderungen testen.
5. Neue Oberfläche mit Login, Event-Übersicht und Event-Verwaltung entwickeln.
6. JSON-Export in ein isoliertes Test-Event importieren.
7. Anzahl der Teilnehmer, Runden, Ergebnisdatensätze und Raumstatistik-Einträge mit dem Originalexport vergleichen.
8. Export/Import, Duplizieren, Archivieren, Wiederöffnen, Zurücksetzen und Löschen testen.
9. Erst nach Abnahme produktiv schalten. Die bestehende Version und der unveränderte JSON-Export bleiben Rückfalloptionen.

## Noch benötigt

Für die tatsächliche Einrichtung ist ein Supabase-Projekt erforderlich. Projekt-URL und öffentlicher Anon/Publishable Key können anschließend in die Frontend-Konfiguration eingetragen werden. Niemals den Service-Role-Key im Chat oder Frontend hinterlegen.