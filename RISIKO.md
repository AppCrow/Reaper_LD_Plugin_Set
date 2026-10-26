<!-- Wofür: die schweren Regeln für riskante Aufgaben (CLAUDE.md, Klasse „riskant“). Wird nicht in jede Sitzung geladen, nur gelesen, wenn eine Aufgabe riskant ist. Jede Regel stammt aus einem echten Schaden in einem früheren Projekt. -->
<!-- Anpassen: die zwei Steckplätze „Ausliefern“ (Skript, Vorbedingungen, Nachweis) und „Geräte und Umgebung“ ausfüllen; was im Projekt nie vorkommt, darf raus. -->
# Riskante Aufgaben

Riskant ist, was „Das darf niemals kaputtgehen“ berührt, Daten löscht oder
umzieht, ausliefert, Geld bewegt, signiert oder an fremde Server sendet. Hier
lohnt der Aufwand, weil ein Fehler Tage oder Daten kostet. Nur die Abschnitte
anwenden, die die Aufgabe betrifft.

## Vorher
- **Plan in drei Zeilen**: was sich ändert, was schiefgehen kann, woran man
  es merkt. Bei Unklarheit fragen, bevor gebaut wird.
- **Fremdes System: erst die Mini-Sonde.** Zehn Zeilen, die nur klären, wie
  man liest und schreibt; dann bauen. Was ein Programm kann, steht im
  Programm oder in der Herstellerdoku, nicht im Blog.
- **Commit vor dem Eingriff**, damit es einen Weg zurück gibt.

## Daten
- **Vor Löschen, Überschreiben, Umziehen**: `git log`/`git status` auf den
  Pfad, zeigen, was passieren würde, auch wenn der Ordner kaputt aussieht.
  Die alte Stelle erst löschen, wenn am Ziel alles nachgewiesen ist, auch was
  nicht in Git liegt.
- **Massenumschreiber** (Formatierer, Skripte über viele Dateien) zuerst an
  einer Kopie; danach Zeilenzahl und `git diff --stat` vergleichen.
- **Destruktives tut ohne Argumente nichts**; stille Werkzeuge bekommen eine
  Kontrolle danach (Größe, Anzahl, Diff).
- **Was von außen kommt**, wird beim Lesen begrenzt und vor dem Speichern
  auf Plausibilität geprüft.
- **Keine echten Empfänger*innen, Endpunkte oder Produktivdaten beim Testen.**
  Geteilte Umgebungen nur mit eigenen Prüfkonten.

## Prüfen
- **Am Produkt, nicht an der Quelle**: gebaute Datei, echte Seite, echtes
  Gerät, live mit derselben Anfrage wie der Besucher. Ein 200 ist kein
  Nachweis; die Zahl am Ziel ist einer.
- **Test mit Gegenprobe**: Fix zurücknehmen, der Test muss rot werden. Einmal.
- **Zweiter Blick nur hier**: Ein Prüf-Agent liest den Diff (nicht den
  Bericht) und sucht Fehler, statt zu bestätigen. Für Fachtext, der
  veröffentlicht wird: gegen die Primärquelle.
- **Ein mit `|| true` oder `2>/dev/null` abgefangener Fehler ist kein „ok“**:
  Ergebnis unabhängig prüfen.

## Ausliefern
- Signatur, Auslieferungs- oder Löschskripte, Sync-Datenmodell: einmal über
  den echten Verteilweg oder am echten Server prüfen, bevor es Nutzer*innen
  erreicht.
- Was ein sichtbarer Text zusagt (Datenschutz, „keine Zählung“), stimmt mit
  Code und Server überein.
- **Skript und Trockenlauf**: kein Auslieferskript, kein `--ausfuehren`. Der Assistent baut
  (`./build-package.sh all` und `./build-package.sh all --neutral`, jeder Lauf löscht nur
  seine eigenen Produkte) und schreibt `dist/RELEASE-NOTES-<ver>.md` (englisch, mit dem
  Satz, dass LD Tools dieselben Werkzeuge ohne steelblue-Marke sind). Push, `git tag -a`
  und `gh release create … --latest` macht Tobi selbst, als TT mit fertigen Befehlen.
- **Vorbedingungen**: alle `tests/*_test.lua` grün; Repo auf `main`, `git status` sauber;
  die vier Pakete am Commit gebaut, auf den der Tag kommt (sonst steht es in den Notes);
  neutrale Pakete ohne „steelblue“ in Dateinamen und Textdateien, jedes `<img src>` der
  Guides vorhanden; die Lua-Dateien im Marken-Paket byteidentisch zu `main` (`cmp`).
  Jedes Release trägt `LD-Tools-macOS.dmg` und `LD-Tools-Windows.zip` unter genau
  diesen Namen und ist Latest; sonst ist der Download-Knopf der Website kaputt.
- **Nachweis am Ziel**: die Release-Seite zeigt den Tag auf dem Commit der Pakete, vier
  Assets, Latest. Ohne Anmeldung: `curl -sL -r 0-0 -o /dev/null -w '%{http_code}'
  https://github.com/AppCrow/Reaper_LD_Plugin_Set/releases/latest/download/<Datei>`
  → 206 für beide LD-Tools-Dateien (ein 404 heißt: Repo privat oder Datei fehlt). Tobi
  hat den Installer aus dem Paket auf einem frischen REAPER laufen lassen (macOS, Windows
  je Release). Dann Rückmeldung an den Website-Dirigenten in dessen Übergabe-Datei.

## Danach
- Bericht: was hätte passieren können, was nachgewiesen ist, was ungeprüft
  bleibt. Offene Risiken als TT oder im Plan, nicht durch Schweigen.

## Geräte und Umgebung
- REAPER 7.7x auf Tobis Mac (arm64); Windows x64 prüft Tobi je Release auf einem
  frischen REAPER. Win32 (`reaper_imgui-x86.dll`) ist nur vom Harness geprüft, nie echt.
- REAPER führt die installierte Kopie aus (`Scripts/steelblue/`, neutral `Scripts/ld-tools/`),
  nicht das Repo. Was wirklich läuft, steht in `reaper-kb.ini` (`SCR`-Zeilen); die Datei ist
  CRLF, REAPER schreibt sie beim Beenden neu, sie wird nur bei geschlossenem REAPER und mit
  Sicherung angefasst. Eine `SCR`-Zeile neu anlegen vergibt eine neue ID und verliert den
  Shortcut; den Pfad in der Zeile ändern erhält ihn.
- Blanker REAPER: `~/Library/Application Support/REAPER` plus `~/Library/Preferences/
  com.cockos.reaper.plist` bei geschlossenem REAPER beiseite benennen. Tobis echte
  Einrichtung liegt als `REAPER-backup-20260715-174011`; sie wird nie gelöscht.
- TimecodeMate3 (fremde Erweiterung) schreibt in jedes Projekt, das es anfasst, einen eigenen
  Block: `tests/fixtures/*.RPP` nie aus REAPER speichern (beim Schließen „No“).
- Ein gemountetes Disk-Image folgt der Datei darunter nicht: vor jedem neuen Paket-Test
  `hdiutil detach`, sonst lädt REAPER den alten Installer.
- Die gebündelten macOS-Erweiterungen sind arm64; Downloads aus dem Browser tragen das
  Quarantäne-Attribut, der Installer entfernt es; Erweiterungen laden erst nach Neustart.
- Computer-use erreicht keine ReaImGui-Knöpfe: Screenshots und native REAPER-Fenster ja,
  Plugin-Knöpfe nein. Die Prüfung am Produkt macht Tobi, der Assistent die Harnesse.
