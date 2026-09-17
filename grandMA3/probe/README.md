# steelblue Probe 1b für grandMA3

Ein kleines Test-Plugin für die MA3. Es baut noch nichts ein — es schaut nur
nach, wie die MA3 innen aufgebaut ist, und schreibt alles in eine Textdatei.
Die Datei schickst du zurück. Danach wird der eigentliche Importer gebaut.

**Dauer:** etwa 10 Minuten.
**Wichtig:** Nimm die **Wegwerf-Show**. Das Plugin legt Cues an und löscht sie
am Ende wieder — aber eine echte Show ist dafür trotzdem der falsche Ort.

---

## Was beim letzten Lauf schief ging (und jetzt anders ist)

Beim letzten Mal hat die Probe im **falschen Datenpool** nachgesehen. Deine Show
arbeitet in **DataPool 2**, die Probe hat aber immer in DataPool 1 geschaut —
und der ist leer. Deshalb hat sie den Timecode nicht gefunden, zwei Kapitel sind
ausgefallen, und in der Cue-Liste stand nichts.

Diese Version nimmt **immer den Pool, in dem du gerade arbeitest**. Sonst ändert
sich für dich nichts — außer: die **zweite Box** mit den Auswahlfeldern und
Häkchen ist weg. Die Frage ist beantwortet, du musst nur noch einmal **OK**
tippen.

---

## Was das Plugin anfasst

- **Timecode 1** und **Sequence 1** — im Datenpool, in dem du gerade arbeitest.
  Gibt es dort keinen Timecode 1, nimmt die Probe den ersten, den es gibt, und
  schreibt in den Bericht, welchen.
- **Cues 990, 991, 992** dieser Sequence.
- Es legt eine Track-Gruppe an und **löscht am Ende alles wieder**.
- Was schon in der Show ist, wird nur **angeschaut**, nie verändert.

Wenn deine Wegwerf-Show andere Nummern hat: siehe unten, „Andere Nummern".

---

## Schritt 1 — Ordner anlegen und Dateien kopieren

Die MA3 hat auf der Platte einen Ordner für Plugins:

- **macOS:** `~/MALightingTechnology/gma3_library/datapools/plugins`
- **Windows:** `C:\ProgramData\MALightingTechnology\gma3_library\datapools\plugins`

1. Diesen Ordner im Finder (bzw. Explorer) öffnen.
2. Darin einen **neuen Ordner** anlegen. Er muss exakt so heißen:
   `steelblue_probe`
3. Diese zwei Dateien hineinkopieren:
   - `steelblue_ma3_probe.xml`
   - `steelblue_ma3_probe.lua`

Es muss danach so aussehen:

```
.../gma3_library/datapools/plugins/steelblue_probe/steelblue_ma3_probe.xml
.../gma3_library/datapools/plugins/steelblue_probe/steelblue_ma3_probe.lua
```

---

## Schritt 2 — Plugin in die MA3 importieren

1. In der MA3 einen **Plugin Pool** öffnen (falls keiner da ist: leeres Fenster,
   dann „Plugins" wählen).
2. Auf ein **leeres Feld** im Plugin Pool tippen. Es öffnet sich ein Fenster.
3. Dort **Import** wählen.
4. Das Laufwerk wählen, dann den Ordner `steelblue_probe`, dann die Datei
   `steelblue_ma3_probe.xml`.
5. **Import** bestätigen.

Im Pool steht jetzt ein Plugin namens **steelblue_probe**.

---

## Schritt 3 — Probe laufen lassen

1. Die **Wegwerf-Show** öffnen (falls noch nicht offen).
2. Im Plugin Pool auf **steelblue_probe** tippen.
3. Es kommt **eine** Box: *„The probe runs in timecode 1 and sequence 1 of the
   CURRENT data pool…"* — mit **OK** bestätigen.
   (Mit **Cancel** passiert gar nichts, falls du die falsche Show offen hast.)
4. Warten, bis nichts mehr passiert (ein paar Sekunden). Eine zweite Box kommt
   diesmal nicht.

---

## Schritt 4 — Ergebnisdatei holen und schicken

Die Probe schreibt die Datei **`steelblue_probe.txt`** in den Library-Ordner:

- **macOS:** `~/MALightingTechnology/gma3_library/steelblue_probe.txt`
- **Windows:** `C:\ProgramData\MALightingTechnology\gma3_library\steelblue_probe.txt`

Den genauen Pfad sagt die Probe außerdem im **System Monitor** (die
Meldungszeile der MA3): dort steht `steelblue probe: report goes to …`.

Diese Datei schicken. Das ist alles, was wir brauchen.

Falls die Datei nicht da ist: einen Screenshot vom System Monitor schicken.

---

## Wenn etwas nicht klappt

**Der Import meckert.**
Die Datei `steelblue_ma3_probe.xml` in einem Texteditor öffnen. In Zeile

```
<GMA3 DataVersion="2.0.2.0">
```

die Nummer auf deine MA3-Version ändern:

```
<GMA3 DataVersion="2.3.2.0">
```

(2.3.2.0 ist die Version, die deine MA3 beim letzten Lauf gemeldet hat.)

Speichern, in der MA3 noch einmal importieren.

**Das Plugin startet, aber es kommt keine Box.**
Dann findet die MA3 die `.lua` nicht. Prüfen, ob beide Dateien wirklich im
Ordner `steelblue_probe` liegen und ob der Ordner genau so heißt.

**Es kommt eine Fehlermeldung im System Monitor.**
Screenshot davon schicken — das ist auch ein Ergebnis.

---

## Andere Nummern

Du musst hier nichts tun: Gibt es keinen Timecode 1 oder keine Sequence 1,
nimmt die Probe von selbst die erste, die es gibt, und schreibt in den Bericht,
welche das war.

Wenn du trotzdem bestimmte Nummern willst: `steelblue_ma3_probe.lua` in einem
Texteditor öffnen. Ganz oben stehen vier Zeilen:

```lua
local TIMECODE_NO = 1   -- the EXISTING timecode the probe writes into
local SEQUENCE_NO = 1   -- the EXISTING sequence the probe points a track at
local CUE_FIRST   = 990 -- first scratch cue number (990, 991, 992 are used)
local CUE_COUNT   = 3
```

Die Zahlen hinter `TIMECODE_NO` und `SEQUENCE_NO` ändern, speichern, das Plugin
in der MA3 neu importieren (oder im Plugin Pool „Reload" wählen, falls es das
gibt).

Darunter steht noch eine Zeile:

```lua
local EXTERNAL_FILE = ""
```

Wenn du magst: dort den vollen Pfad zu irgendeiner kleinen Textdatei auf dem
Schreibtisch eintragen, zum Beispiel

```lua
local EXTERNAL_FILE = "/Users/tobiaspehla/Desktop/test.txt"
```

Dann prüft die Probe zusätzlich, ob die MA3 Dateien von außerhalb ihrer eigenen
Ordner lesen darf. Das ist für den späteren Importer interessant, aber nicht
nötig — leer lassen ist auch in Ordnung.

---

## Wenn du zwei Minuten übrig hast

Am wertvollsten wäre **ein Event, das du selbst von Hand** in Timecode 1
angelegt hast — irgendeins, das auf einen Cue zeigt. Die Probe schreibt dann in
den Bericht, wie die MA3 dieses Event intern speichert, und daran sieht man, wie
der Importer seine Events schreiben muss. Wenn schon eins drin ist: einfach
drin lassen. Die Probe fasst es nicht an.

---

## Was danach passiert

Aus der Textdatei geht hervor, wie der Importer gebaut werden muss: ob er
Tracks und Events direkt setzen kann oder über die Kommandozeile gehen muss, in
welcher Einheit die Zeiten stehen, und wie Cues angelegt und benannt werden.
Erst danach entsteht das richtige Plugin.
