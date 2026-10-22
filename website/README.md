# Website reaperldtools.appcrow.at

Produktseite von LD Tools (neutrale Fassung des REAPER LD Plugin Set),
statisch, ohne Cookies, fremde Schriften, Skripte oder Dienste. appcrow.at
(Studio, Impressum, Datenschutz) ist das Repo `AppCrow/appcrow` (lokal
`Code Factory/App Crow/`), Bauen, Prüfen und Hochladen macht das Repo
`AppCrow/appcrow_webtool` (lokal `Code Factory/appcrow_webtool/`). Welche
Werkzeug-Version, steht in `website.conf` in der Repo-Wurzel.

Die Seite baut der Website-Dirigent (Repo `AppCrow/appcrow`) nach den
AppCrow-Design-Vorgaben. Im Reaper-Repo gehören ihm nur `website/`,
`website.conf` und `scripts/website/` (Branch `website`).

| Pfad | Inhalt |
|---|---|
| `../website.conf` | Quelle, Dokumentstamm, Medien, Werkzeug-Version |
| `inhalt.js` | alle Texte der Seite (DE, EN); nur hier ändern |
| `seite/` | Deutsch `/`, Englisch `/en/`; `index.html` sind aus `inhalt.js` erzeugt |
| `angaben.conf` | leer: LD Tools ist kostenlos, es gibt keinen Kauflink |
| `ziel.conf` | SSH-Zugang, **nicht im Repo**; Vorlage `ziel.conf.beispiel` |
| `_bau/` | gebaute Seite, bei jedem Lauf neu erzeugt, nicht im Repo |

Nicht doppelt abgelegt: das Icon kommt beim Bauen aus
`design/material/AppIcon-1024.png`, die vier Bildschirmfotos aus
`design/material/ld-tools-neutral-en-*.png`, Stil und AppCrow-Symbol aus
`appcrow_webtool/gemeinsam/`. Der Download liegt nicht auf diesem Server:
die Knöpfe zeigen auf das neueste GitHub-Release.

## Texte ändern

Texte stehen nur in `inhalt.js`; Freigabe in `App Crow/Website/TEXTE.md`.
Funktionen erst aufnehmen, wenn sie im Release stecken. Die Vorlage für alle
AppCrow-Produktseiten liegt im Repo `AppCrow/appcrow`
(`Website/produkte/bauen.js`); nach jeder Änderung an `inhalt.js` die Seiten
neu erzeugen (aus der Wurzel dieses Worktrees):

```bash
node "../../../App Crow/Website/produkte/erzeugen.mjs" website/inhalt.js website/seite
```

## Veröffentlichen

```bash
./scripts/website/veroeffentlichen.sh
```

Ohne Argument nur Trockenlauf: baut nach `_bau/`, prüft und zeigt, welche
Dateien hochgingen. `--ausfuehren` lädt hoch, nur wenn die Prüfung nichts
findet und das Werkzeug auf der Version aus `website.conf` steht.
`--nur-bauen` erzeugt nur `_bau/` für die Vorschau:

```bash
cd website/_bau/reaperldtools.appcrow.at && python3 -m http.server 8020
```

Verweise auf appcrow.at (Impressum, Datenschutz) prüft das Werkzeug am
echten Server. Auf dem Server wird nichts gelöscht.

## Adressen

- LD Tools: `https://reaperldtools.appcrow.at/`
- Download macOS: `https://github.com/tobis-tales/Reaper_LD_Plugin_Set/releases/latest/download/LD-Tools-macOS.dmg`
- Download Windows: `https://github.com/tobis-tales/Reaper_LD_Plugin_Set/releases/latest/download/LD-Tools-Windows.zip`
- Impressum und Datenschutz: `https://appcrow.at/impressum/`,
  `/datenschutz/#ldtools`
