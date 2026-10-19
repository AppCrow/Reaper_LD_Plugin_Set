# Material für die Produktseite — steelblue LD Tools

Erstellt 2026-10-19 vom Dirigenten, aus Repo-Commit `e0a9f22` (main). Alles hier
ist **vorläufig**, bis Tobi es freigibt. Der Ordner `design/` wird von
`build-package.sh` nicht ins Paket kopiert.

## Dateien

| Datei | Was man sieht | Stand |
| --- | --- | --- |
| `AppIcon-1024.png` | Das steelblue-Bildzeichen (grauer Block, weiße Linse, blaue Pupille) auf dem Fensterhintergrund der Plugins `#232326`, 1024×1024, kein Alpha | vorläufig — Kandidat, aus `Tutorials/mark.svg` mit Chrome headless gerendert; Freigabe Tobi fehlt |
| `ld-plugin-set-en-1-rename.png` | Fenster „Rename selected markers“, 4 Marker gewählt, Vorschau `Pre Chorus 1(1)[Top]^Pre Chorus 1^` | vorläufig |
| `ld-plugin-set-en-2-midi.png` | Fenster „MIDI notes to project markers“ | vorläufig |
| `ld-plugin-set-en-3-copy.png` | Fenster „Copy Markers“ mit Zielfeldern | vorläufig |
| `ld-plugin-set-en-4-bpm.png` | Fenster „Live BPM Analyzer“ mit Messwert | vorläufig |
| `ld-plugin-set-en-5-workspace.png` | Workspace: Tabs und BPM-Block im Kopf | vorläufig |
| `FUNKTIONSLISTE.md` | Funktionen mit Datei/Funktion-Beleg und exakten UI-Wörtern | fertig für v2.0.0 |

## Wie die Bilder entstanden sind

- Quelle: `Tutorials/img/rename-03-window.png`, `midi-03-window.png`,
  `copy-03-window.png`, `bpm-03-window.png`, `workspace-03-bpm.png` — Tobis
  Aufnahmen vom 2.0-Stand (Retina, mit Alpha, verschiedene Größen).
- Umbau mit ffmpeg: längste Seite auf 1180 px, zentriert auf 1280×1280 mit
  `#232326`, Alpha entfernt. Kein Nachschärfen, kein Text.
- Die Oberfläche ist nur Englisch. Darum gibt es nur `-en-` Bilder; nach
  `docs/anforderungen-neue-app-website.md` gelten sie für beide Sprachen.
- Die Bilder zeigen das **steelblue**-Branding. Falls die Seite die neutrale
  „LD Tools“-Variante zeigen soll, müssen alle fünf neu aufgenommen werden
  (TT 138 offen).
- Der Dateiname-Slug `ld-plugin-set` ist ein Platzhalter, bis Tobi die
  Subdomain festlegt. Umbenennen ist dann ein `mv`.

## Was fehlt

- Video 1080×1080 (vorhanden ist nur `Tutorials/video/copy-markers-tutorial.mp4`,
  1080×1920 hochkant, zeigt v1.0). Offen.
- Finale Screenshots nach Tobis Freigabe von Branding und Beispieldaten.
- Keine Aufnahmeskripte → keine `AUFNAHMELISTE.md`.
