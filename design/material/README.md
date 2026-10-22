# Material für die Produktseite — steelblue LD Tools

Erstellt 2026-10-19 vom Dirigenten, aus Repo-Commit `e0a9f22` (main). Alles hier
ist **vorläufig**, bis Tobi es freigibt. Der Ordner `design/` wird von
`build-package.sh` nicht ins Paket kopiert.

## Dateien

| Datei | Was man sieht | Stand |
| --- | --- | --- |
| `AppIcon-1024.png` | Tobis Icon (2026-10-22): drei gestaffelte Ruler-Lanes mit je einem Marker-Pin in Steelblue, abgerundetes Quadrat auf dem Fenstergrau der Plugins `#232326`; 1024×1024, kein Alpha | **freigegeben von Tobi (Entwurf E, 22.10.2026)** — aus `AppIcon-source-1254.png` umgefärbt, siehe unten |
| `AppIcon-source-1254.png` | Dasselbe Icon in Tobis Original (violett), 1254×1254 | Quelle, unverändert |
| `ld-plugin-set-en-1-rename.png` | Fenster „Rename selected markers“, 4 Marker gewählt, Vorschau `Pre Chorus 1(1)[Top]^Pre Chorus 1^` | vorläufig |
| `ld-plugin-set-en-2-midi.png` | Fenster „MIDI notes to project markers“ | vorläufig |
| `ld-plugin-set-en-3-copy.png` | Fenster „Copy Markers“ mit Zielfeldern | vorläufig |
| `ld-plugin-set-en-4-bpm.png` | Fenster „Live BPM Analyzer“ mit Messwert | vorläufig |
| `ld-plugin-set-en-5-workspace.png` | Workspace: Tabs und BPM-Block im Kopf | vorläufig |
| `ld-tools-neutral-en-1-rename.png` | **Neutral** (LD Tools, gedockt im REAPER-Fenster): Tab „Rename selected markers“, 4 Marker, Vorschau `Kick(1)[Top]^Kick^` | Tobis Aufnahme 22.10.2026, umgebaut |
| `ld-tools-neutral-en-2-rename-result.png` | Neutral: dasselbe nach dem Umbenennen, Marker 1–4 heißen `Kick(1)[Top]^Kick^` | dito |
| `ld-tools-neutral-en-3-copy.png` | Neutral: Tab „Copy Markers“ nach dem Kopieren, Cursor bei 225.1.00, Liste mit 5 Markern, 4 gewählt | dito |
| `ld-tools-neutral-en-4-midi.png` | Neutral: Tab „MIDI notes to markers“ mit Meldung „47 markers created in 1 lanes“, Lane „Kick“ im Lineal. Macke: während der Meldung steht „OFFLINE“ über dem Audio-Item | dito, bleibt so (Tobi, 22.10.2026) |
| `src-neutral/ld-tools-{1-rename,2-rename-result,3-copy,4-midi}.png` | Die vier Originale, 3024 px breit, mit Alpha | Quelle |
| `FUNKTIONSLISTE.md` | Funktionen mit Datei/Funktion-Beleg und exakten UI-Wörtern | fertig für v2.0.0 |

## Wie das Icon entstanden ist

Tobis violettes Original, mit ffmpeg auf die Set-Farben gebracht: Farbton um
−90° gedreht (Magenta → Steelblue), Sättigung ×0,82, dann alle Töne unter
Luma 35 auf neutrales Grau gezogen (Hintergrund und Rahmen landen bei `#232326`,
Luma 35–80 blendet weich über), zuletzt lanczos auf 1024. Lane-Pixel messen
`103,132,169`, das Ziel `#4682B4` ist `70,130,180`. Reproduzierbar mit:

```
L='(0.299*r(X,Y)+0.587*g(X,Y)+0.114*b(X,Y))'; K="clip(($L-35)/45,0,1)"; G="clip($L+13,0,255)"
ffmpeg -i AppIcon-source-1254.png -vf "hue=h=-90:s=0.82,format=rgb24,geq=r='r(X,Y)*$K+$G*(1-$K)':g='g(X,Y)*$K+$G*(1-$K)':b='b(X,Y)*$K+$G*(1-$K)',scale=1024:1024:flags=lanczos" AppIcon-1024.png
```

Tobi hat aus fünf Entwürfen (A–E) E gewählt; die anderen sind verworfen.

## Wie die Bilder entstanden sind

- Quelle: `Tutorials/img/rename-03-window.png`, `midi-03-window.png`,
  `copy-03-window.png`, `bpm-03-window.png`, `workspace-03-bpm.png` — Tobis
  Aufnahmen vom 2.0-Stand (Retina, mit Alpha, verschiedene Größen).
- Umbau mit ffmpeg: längste Seite auf 1180 px, zentriert auf 1280×1280 mit
  `#232326`, Alpha entfernt. Kein Nachschärfen, kein Text.
- Die Oberfläche ist nur Englisch. Darum gibt es nur `-en-` Bilder; nach
  `docs/anforderungen-neue-app-website.md` gelten sie für beide Sprachen.
- Die `ld-plugin-set-*`-Bilder zeigen das **steelblue**-Branding, die
  `ld-tools-neutral-*`-Bilder die neutrale Fassung „LD Tools“ (Tobis Aufnahmen
  vom 22.10.2026 in `src-neutral/`, Workspace unten im REAPER-Fenster gedockt,
  derselbe ffmpeg-Umbau). Neutral gibt es kein reines BPM-Motiv (der BPM-Block
  sitzt in jedem Kopf, 113.77 BPM), und das MIDI-Bild zeigt die Meldungsbox und
  „OFFLINE“; beides bleibt so (Tobi, 22.10.2026). Auf die Seite kommt die neutrale Reihe (Website-TT-63).
- Entschieden (Website-TT-63, 2026-10-22): die Seite ist
  `reaperldtools.appcrow.at` und zeigt die neutrale Fassung „LD Tools“; ihr
  Download-Knopf lädt `LD-Tools-macOS.dmg` / `LD-Tools-Windows.zip` über
  `releases/latest/download/…` (ab v2.1.0). Der Dateiname-Slug
  `ld-plugin-set` der Bilder bleibt; die Website benennt beim Übernehmen um.

## Was fehlt

- Video 1080×1080 (vorhanden ist nur `Tutorials/video/copy-markers-tutorial.mp4`,
  1080×1920 hochkant, zeigt v1.0). Offen.
- Finale Screenshots nach Tobis Freigabe von Branding und Beispieldaten.
- Keine Aufnahmeskripte → keine `AUFNAHMELISTE.md`.
