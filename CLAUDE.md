<!-- Wofür: die Datei, die in jede Sitzung geladen wird; Budget 100 Zeilen, check.sh prüft es. Anpassen: nur eckige Klammern und die Steckplätze (Berechtigungen, Tabu, RISIKO.md „Ausliefern“ und „Geräte und Umgebung“, hooks/konfig.sh). Kernzeilen und Grundsätze sind in jedem Projekt wortgleich; wer eine ändert, ändert die Vorlage und rollt sie aus. -->
# Projekt: Reaper LD Plugin Set (steelblue / LD Tools)

## Was das ist
Vier REAPER-Lua-Plugins für Lichtdesign (MA-Tools-Marker-Syntax, Live-BPM, Marker kopieren und
umbenennen, MIDI → Marker-Lanes) plus ein Installer, der in REAPER läuft. Eine Quelle, zwei Produkte:
steelblue-Marke und neutrales „LD Tools“ (`build-package.sh --neutral`). Öffentlich auf GitHub, MIT.
Architektur, API-Fakten und Geschichte: `AGENTS.md`; Dirigenten-Übergabe: `UEBERGABE.md` (beide lokal).

## Wer ich bin
Ich bin Tobi, kein Programmierer, Lichtdesigner mit REAPER und grandMA3. Komplexes in
Alltagssprache mit einem Bild, die Fachbegriffe daneben. Chat deutsch, Plugin-Oberfläche englisch.

## Fertig heißt
Suiten grün, Tobi hat es in REAPER an der installierten Kopie ausprobiert, sein „check“ reicht.

## Umgebungen und Geräte
- Entwicklung: `for t in tests/*_test.lua; do lua "$t"; done` (offline gegen ein Fake-REAPER); echt nur in REAPER auf Tobis Mac, Windows je Release. Live: GitHub Releases, verlinkt von reaperldtools.appcrow.at — Lichtdesigner*innen laden es dort.
- Zielgeräte: REAPER 7.7x auf macOS (arm64) und Windows x64; Besonderheiten in `RISIKO.md` unter „Geräte und Umgebung“.

## Berechtigungen
- Ohne Rückfrage: Code ändern, Suiten laufen lassen, Pakete nach `dist/` bauen, lokal committen.
- Nur auf ausdrückliche Ansage: Push, Tag, Release, Remote oder Sichtbarkeit ändern; Installer in REAPER starten; unter `~/Library/Application Support/REAPER` schreiben.
- Niemals: `reaper-kb.ini` bei laufendem REAPER anfassen; `tests/fixtures/*.RPP` aus REAPER neu speichern; Kundenmaterial ins Repo; `AGENTS.md`, `UEBERGABE.md`, `TT-LISTE.md`, `PROMPT-*`, `REPORT-*`, `archive/`, `Input/`, `dist/` versionieren. Geheimnis-Dateien: `reaper-license.rk`, Lizenz- und Key-Dateien von ReaPack-Repos und MATools (dieselben in `konfig.sh` unter `TABU`).
- Ausnahmen von den Kernzeilen: Push und Release nur auf Tobis Wort (CP/PD sind dieses Wort, Release macht Tobi selbst); Bildschirmfotos aus REAPER macht Tobi (ReaImGui nimmt keine Werkzeug-Klicks an); sichtbare Texte sind englisch, Tobi sieht sie in REAPER.
- Entschieden: 2026-10-20 das Set bleibt frei und MIT, keine Lizenzprüfung. 2026-10-23 jedes Release trägt `LD-Tools-macOS.dmg` und `LD-Tools-Windows.zip` als Latest. 2026-10-24 die neutralen Guides zeigen nur das gedockte Band.

## Tabu
`~/Downloads/TimecodeMate3/` und `grandMA3/Markers/` im Repo-Ordner: kommerzielle Produkte, Ideen lernen, nie Code lesen, Schlüssel nie öffnen; Unter-Agenten bekommen das wortgleich. Dieselben in `.claude/hooks/konfig.sh`.

## Das darf niemals kaputtgehen
- Items bei „Set project tempo“ (Positionen, Längen, Offsets bleiben, wie sie sind).
- Shortcuts und Command-IDs beim Neu-Installieren über eine bestehende Installation.
- Die zwei Release-Dateinamen (der Download-Knopf der Website zeigt fest darauf).
- Die installierte Kopie darf nie still veralten.

## Fallen
- REAPER läuft die installierte Kopie unter `Scripts/steelblue/`, nicht das Repo: vor jeder Prüfung erst den Installer laufen lassen; `reaper-kb.ini` sagt, was wirklich läuft, und wird beim Beenden überschrieben.
- Jedes neue Modul in `MODULES` des Installers eintragen, sonst löscht der nächste Lauf es.
- `SB.BRAND` bleibt eine Zeile; jeder neue Markentext muss in der `MAP` von `build-package.sh` stehen, sonst bricht der neutrale Build ab.
- Computer-use klickt keine ReaImGui-Knöpfe: Harness und Tobis Klick entscheiden, nie der Werkzeug-Klick.
- `SB.end_window` in jedem Frame; nichts rechtsbündig in Auto-Resize-Fenstern.

## Compact instructions
Behalten: Aufgabe, Entscheidungen, Commit-Hashes, offene TT. Verwerfen: Ausgaben, Diffs.

---
# Arbeitsregeln
## Kernzeilen
- **Push:** Commit und Push sind frei, sobald die Prüfkette grün ist; der Hook erzwingt das, fragt nur den grünen Stand ab und startet keine Kette. Nach Änderungen `./scripts/check.sh --schnell`, vor dem Push einmal `./scripts/check.sh` mit `run_in_background`, dann `git push` allein; direkt vor dem Push kein weiterer Lauf.
- **Kürzel:** CP = committen und pushen. PD = pushen und ausliefern. CPD = beides. TT-n = Antwort auf TT n. Backup Pi = Projekt auf den Pi sichern (Bibliothek `projekt-auf-den-pi-sichern`). Die Ansage ist die Freigabe.
- **Ausliefern:** nur auf PD/CPD. Erst Trockenlauf; zeigt er mehr als erwartet, anhalten und fragen. `--ausfuehren` steht in `settings.json` auf `ask`. Vorbedingungen je Projekt in `RISIKO.md` unter „Ausliefern“.
- **Geheimnisse:** liest, zeigt, kopiert oder tippt der Assistent nie, auch nicht auf Ansage. Skripte dürfen einen Schlüssel per Pfad nutzen. Tobi gibt Geheimnisse selbst ein oder legt die Datei außerhalb des Repos ab. Dateinamen je Projekt unter „Niemals“ und im Hook-Tabu.
- **Löschen:** im Repo frei bei sauberem `git status` und wörtlichem absolutem Pfad. Außerhalb des Repos oder am Server nur auf Ansage. Mehr als eine Handvoll Dateien: Skript mit Trockenlauf, Tobi führt aus.
- **Sichtbare Texte:** prüft ein zweiter Agent (anderes Modell) gegen `TEXTE.md`; fehlt sie, gilt „Wer ich bin“. Tobi sieht sie im Produkt, nicht als TT. Projekt-Ausnahmen (Store-Texte) im Berechtigungs-Block.
- **Bildschirmfotos und TT:** Bildschirmfotos macht der Assistent selbst (Browser, Simulator, Emulation), von Tobi keine verlangen; Tobis „check“ ist der Nachweis. TT-Antworten: eine Zeile je TT, Bestätigung mit einem Wort.
- **Eingänge:** Was Tobi von außen liefert, liegt in `input/` (`/input/` steht in `.gitignore`; fehlt der Ordner, anlegen): einsortieren, erst danach aus `input/` löschen, auch viele Dateien ohne Rückfrage; der Ordner bleibt. Wohin unklar: liegen lassen und fragen. Fremde Projekte nie selbst ändern; Befund als Übergabe-Datei nach `uebergaben/` im Zielprojekt.
- **Arbeitskopien:** `.worktrees/phase-N` im Projektordner (`git worktree add .worktrees/phase-3 -b phase-3`), `.worktrees/` steht in `.gitignore`; nie daneben in `Code Factory/`. Nach Merge und Push Tag `archiv/<branch>` statt Branch behalten.
- **Kosten:** ein Chat je Aufgabe, danach `/clear`. Sonnet als Standard, Haiku für Mechanisches, Opus nur bei riskant. Unter-Agenten nur für breite Suche, echte Parallelarbeit und sichtbare Texte. `--schnell` für Zwischenläufe; lange Läufe mit `run_in_background`, kein `sleep`.
- **Rechnerweit:** Browser-Schritte in `pruefkette.txt` mit `schwer=browser:2`, der Läufer teilt die Plätze rechnerweit; eigene Simulatoren nach dem Lauf herunterfahren.
- **Budget:** CLAUDE.md höchstens 100 Zeilen (`check.sh` prüft es). Architektur, Invarianten und Glossar in eigene Dateien, die CLAUDE.md zeigt nur darauf.

## Aufwand passt zum Risiko
Vor jeder Aufgabe die Klasse in einem Wort nennen und danach handeln. Im
Zweifel die kleinere; wird es unterwegs heikel, hochstufen und es sagen.
- **klein** (Text, Farbe, Abstand, Umbenennen, Einzeiler, Doku): ändern,
  ansehen, `./scripts/check.sh --schnell`, committen. Kein neuer Test, kein
  zweiter Agent, keine Gegenprobe.
- **normal** (Feature, Fehlerbehebung, Umbau): dazu ein Test für das Neue;
  bei einem Fehler ein Test, der ohne den Fix rot ist (einmal zeigen genügt).
- **riskant** (berührt „Das darf niemals kaputtgehen“, Löschen, Migration,
  Release, Zahlungen, Signatur, fremde Server): zuerst `RISIKO.md` lesen.

## Grundsätze
1. **Denken statt abhaken.** Kostet eine Prüfung mehr als der Fehler, den sie
   fangen kann, fällt sie weg; ein Satz Begründung genügt.
2. **Diagnose mit Beweis**: Zahl, Log oder Bild. Sonst heißt es Vermutung.
3. **Erst suchen, dann bauen**: Gibt es das schon, gibt es den Weg mehrfach?
   Klingt ein Problem bekannt: `grep -il '<wort>' ../Projektstarter/Bibliothek/*.md`.
4. **Ein Nachweis genügt.** Ungeprüftes heißt ungeprüft; ein grüner Lauf
   wird nicht wiederholt, um sicherer zu sein. Sichtbares: ein Bild.
5. **Sicherheitsschalter bleiben an** (Sandbox, Hooks, Rechte). Vor dem
   Überschreiben `git status` auf den Pfad und zeigen, was passiert.
6. **Committen**: Zwischenstände und vor jedem Experiment; `git add <datei>`.
7. **Unklar mit Folgen: fragen.** Ohne Folgen: entscheiden, Annahme nennen.
8. **Ehrlich und kurz berichten**: erst was schiefging, dann der Rest. Im
   Chat Ergebnis und rote Zeilen, keine langen Ausgaben.
9. **Was ich tun muss, ist ein TT** in `TT.md`, nummeriert, eigenständig.
10. **Neue Falle unter „Fallen“** nur, wenn sie wieder passieren kann und
    der Code sie nicht schon sagt. Eine neue Regel nur gegen eine alte.
