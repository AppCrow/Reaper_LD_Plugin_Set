# Funktionsliste mit Beleg — steelblue LD Tools (REAPER LD Plugin Set)

Stand: v2.1.0 (Repo-Commit `c7441c7`, main, 2026-10-23; Funktionen unverändert gegenüber v2.0.0, GitHub Release 2026-09-16). Die Seite zeigt die neutrale Fassung „LD Tools“; die UI-Wörter unten sind identisch, nur der Fenstertitel heißt „LD Tools“ statt „steelblue LD Tools“.
Pfade sind relativ zum Repo. Die Benutzeroberfläche ist nur Englisch; es gibt keine
deutschen UI-Wörter. Die exakten UI-Wörter stehen in Anführungszeichen.

Legende Spalte „Steht so drin“: ja = im Code vorhanden und durch Offline-Suite
abgedeckt · teilweise = vorhanden, mit genannter Einschränkung · nein = nicht gebaut.

## A. Workspace „steelblue LD Tools“ (ein Fenster, drei Tabs, BPM im Kopf)

| Funktion | Was es tut | Beleg (Datei / Funktion) | Steht so drin | UI-Wörter (EN) |
| --- | --- | --- | --- | --- |
| Ein Fenster für alle Werkzeuge | Drei Tabs, dockbar, merkt sich Tab und Dock-Zustand | `steelblue_workspace.lua` → `run_gui`, `ext_get`/`ext_set`, `dock_decision`, `enable_docking` | ja | Tabs „Rename selected markers“ · „MIDI notes to markers“ · „Copy Markers“ |
| BPM-Anzeige im Kopfbereich | Kompakter Live-BPM-Block, läuft bei jedem Tab weiter | `steelblue_workspace.lua` (Header-Band), `steelblue_bpm.lua` → `frame(ctx, SB, {layout="compact"})`, `tick()` | ja | „›››“ (öffnet das Mehr-Popup) |
| Autostart | Der Installer trägt den Workspace in `Scripts/__startup.eel` ein, er öffnet mit REAPER | `steelblue_install.lua` → `write_autostart` | ja | — |

## B. Live BPM Analyzer

| Funktion | Was es tut | Beleg | Steht so drin | UI-Wörter (EN) |
| --- | --- | --- | --- | --- |
| Tempo aus einem Audio-Item messen | Onset-Hüllkurve, Multi-Harmonik-Comb, Langlag-Verfeinerung; 2 Nachkommastellen | `steelblue_bpm.lua` → `estimate_bpm`, `refine_period`, `comb_score` (Exports über `BPM_ANALYZER_TEST`) | ja | „Analyze now“ |
| Genauigkeit | Synthetische Tests: max. Fehler 0,004 BPM; echter Song 0,017 BPM gegen gemessene Ground Truth | `tests/bpm_accuracy_test.lua`, `tests/bpm_busy_test.lua` | ja | — |
| Live-Modus | Alle 0,75 s neu messen, ohne den Abspielcursor zu bremsen (inkrementell, 4 ms pro Frame) | `steelblue_bpm.lua` → `tick()`; `tests/bpm_incremental_test.lua` | ja | „Live update“ |
| Präzisionsmessung | Bis 120 s aus der Mitte des Items, Intro/Outro ausgelassen | `steelblue_bpm.lua` (precision pass) | ja | „Precision analyze“ |
| Oktave korrigieren | Halbes / doppeltes Tempo per Klick; Hinweis, wenn eine Oktave ähnlich gut passt | `steelblue_bpm.lua` → `pick_rival`, Oktav-Hinweis | ja | „Half“ · „Double“ · „Octave: … also fits“ |
| Konfidenz | 0.5 Dominanz + 0.25 Absolut + 0.25 Verfeinerung; gegen Rauschen/Rubato validiert | `tests/bpm_confidence_validate.lua` | ja | „Confidence“ |
| Projekttempo setzen, ohne Items zu verschieben | Positionen, Längen, Take-Offsets, Playrate gesichert, Timebase kurz auf Zeit, danach zurück | `steelblue_bpm.lua` → Set-project-tempo-Pfad | ja | „Set project tempo“ · „Clear“ |
| Quelle wählen | Ausgewähltes Item > Item unter Cursor auf gewählter Spur > unter Cursor > einziges Audio-Item; Timecode-Spuren (LTC/SMPTE/MTC) verlieren immer | `steelblue_bpm.lua` → `pick_audio_item`; `tests/bpm_item_pick_test.lua` | ja | „Source  Track 2 "Song" · song.wav“ |

## C. MIDI notes to project markers

| Funktion | Was es tut | Beleg | Steht so drin | UI-Wörter (EN) |
| --- | --- | --- | --- | --- |
| Marker aus MIDI-Noten | Je Notenstart ein Projektmarker; Loop-Items über die sichtbare Länge | `steelblue_midi.lua` → `add_markers_for_note`, `place_marker`, `get_source_length_ppq` | ja | „All MIDI items in the project“ · „Only selected MIDI items“ |
| Eine Ruler-Lane pro Spur | Spuren mit gleichem Basisnamen („Kick (12)“ → „Kick“) teilen eine Lane; Lane wird angelegt | `steelblue_midi.lua` → `track_name`; `steelblue_markers.lua` → `ensure_lane`; `steelblue_matools.lua` → `track_basename` | teilweise — braucht REAPER 7.72+; darunter landen die Marker in der Standard-Lane | — |
| MA-Tools-Syntax | Name `Note(Rang)[Command]^Basisname^`; Rang = wievielte Note dieser Tonhöhe in der Gruppe | `steelblue_matools.lua` → `format`; `tests/midi_lanes_test.lua` | ja | „MA-Tools syntax“ · „Command“ |
| Farben | Spurfarbe, sonst feste 12er-Palette nach Spurindex | `steelblue_midi.lua` → `palette_colour`, `group_colour` | ja | — |
| Lane leeren vor dem Schreiben | Vorhandene Marker der Gruppe werden ersetzt (Standard an) | `steelblue_midi.lua`, `steelblue_markers.lua` → `markers_in_lane`, `delete_marker` | ja | „Replace existing markers in these lanes“ |
| Kollisionswarnung | Zwei Spuren mit gleichem Basisnamen → Ja/Nein-Abfrage vor dem Schreiben | `steelblue_midi.lua` → `collision_text` | ja | — |

## D. Rename selected markers

| Funktion | Was es tut | Beleg | Steht so drin | UI-Wörter (EN) |
| --- | --- | --- | --- | --- |
| Auswahl aus dem Region/Marker Manager | Liest die Manager-Auswahl live (150 ms), Regionen werden ignoriert | `steelblue_markers.lua` → `selected`; `tests/markers_test.lua` | ja | „4 markers selected (manager)“ |
| MA-Tools-Syntax zusammenbauen | Cue name / Command / Sequence name, leeres Feld lässt das Element weg; Vorschau | `steelblue_rename.lua` → `command_choices`, `resolve_marker_name_placeholder`; `steelblue_matools.lua` → `format`/`parse` | ja | „Cue name“ · „Command“ · „Sequence name“ · „MarkerName“ · „Legend“ |
| Platzhalter MarkerName | Nimmt den vorhandenen Namen; bei bereits vorhandener Syntax den geparsten Cue-Namen (zweimal ausführen schachtelt nichts) | `steelblue_matools.lua` → `parse`; `tests/rename_test.lua` | ja | „MarkerName = the name of the first selected marker.“ |
| Cue-Nummern in Reihenfolge | Nummeriert in Klick-Reihenfolge; „How many cues“ wickelt um (6 Marker, 3 Cues → 1 2 3 1 2 3) | `steelblue_rename.lua` → `format_cue_number`, `step_cue_number` | teilweise — Klick-Reihenfolge nur mit js_ReaScriptAPI; ohne: Zeitachsen-Reihenfolge | „Cue number“ · „Create multiple cues in timeline order“ · „How many cues“ |
| Farbe setzen | Zufällig pro Lauf oder zuletzt benutzt (gemerkt in ExtState) | `steelblue_rename.lua` → `random_marker_colour`; `steelblue_markers.lua` → `set_color` | ja | „Also set colour“ · „Random“ · „Last used“ |
| Lane bleibt erhalten | Umbenennen über `P_NAME`, Marker wandert nicht aus seiner Lane | `steelblue_markers.lua` → `rename` | teilweise — 7.72+; darunter klassischer Pfad | „Rename selected markers“ · „Reset to defaults“ |

## E. Copy Markers

| Funktion | Was es tut | Beleg | Steht so drin | UI-Wörter (EN) |
| --- | --- | --- | --- | --- |
| Markergruppe kopieren | Name, Farbe und Abstände bleiben; sortiert nach Position, nicht nach Klick | `steelblue_copy.lua`; `steelblue_markers.lua` → `sorted_by_position`, `add_marker` | ja | „Use selection“ · „Clear selection“ |
| Zielposition | Takt.Schlag, Timecode oder Cursor; Fenster darf offen bleiben, Cursor darf bewegt werden | `steelblue_copy.lua` → `parse_target_position` | ja | „measure.beats“ · „hh:mm:ss:ff“ · „Copy to measure.beats“ · „Copy to hh:mm:ss:ff“ · „Copy to cursor“ |
| Läuft ohne js_ReaScriptAPI | Auswahl über `B_UISEL` ab REAPER 7.62 | `steelblue_markers.lua` → `selected` (Quelle „arrange“) | ja | „(arrange view)“ |

## F. Installer

| Funktion | Was es tut | Beleg | Steht so drin | UI-Wörter |
| --- | --- | --- | --- | --- |
| Installation aus REAPER heraus | Kopiert nach `Scripts/steelblue/`, registriert fünf Actions, bietet Shortcuts über REAPERs eigenen Dialog an, trägt Autostart ein | `steelblue_install.lua` → `copy_into_reaper`, `register_plugins`, `assign_shortcuts`, `write_autostart`; `tests/installer_test.lua` | ja | Plain-Dialoge von REAPER (ShowMessageBox) |
| Erweiterungen legen | ReaImGui und js_ReaScriptAPI aus dem Paket nach `UserPlugins/`, Quarantäne entfernt, Architektur geprüft | `steelblue_install.lua` → `ensure_extension`; `pe_arch`, `lipo -archs` | ja | „restart REAPER“ |
| Alte Dateien räumen | Entfernt im eigenen Ordner, was nicht mehr zum Set gehört | `steelblue_install.lua` → `remove_stale_files` | ja | „Removed (no longer part of the set):“ |
| Windows | Gleicher Ablauf, DLLs x64 + x86 im Paket; x86 nur per Suite geprüft | `steelblue_install.lua` → `is_windows`, `PLATFORMS` | teilweise — 32-bit nie in echt getestet | — |
| Neutrale Variante „LD Tools“ | Gleiche Quelle, ohne steelblue-Marke, installiert nach `Scripts/ld-tools/` | `build-package.sh --neutral`, `debrand`; `tests/neutral_build_test.lua` | teilweise — noch nicht in REAPER geprüft (TT 136–138) | „LD Tools“ |

## Gebaut, aber nicht auf die Seite

- Autostart-Fallback: die vier Einzel-Plugins bleiben eigene Actions (Doppel-Einträge, wenn beide Varianten installiert sind). Technikdetail.
- Demo-Projekt `Demo Project/steelblue_demo.RPP` mit synthetischem 128-BPM-Beat (liest 128.00 BPM bei 95 %). Für die Anleitung, nicht als Verkaufsargument.
- `tests/probe_lanes.lua` und die Offline-Suiten. Entwicklerwerkzeug.
- Startprüfung der Abhängigkeiten: jedes Plugin meldet beim Start einmal, was fehlt und was das kostet (`steelblue_boot.lua` → `check_dependencies`, in allen fünf Hosts verdrahtet). Technikdetail, taugt aber als FAQ-Fakt.

## Was fehlt, wenn etwas fehlt

| Fehlt | Folge |
| --- | --- |
| ReaImGui | BPM Analyzer startet nicht; Rename, MIDI, Copy fallen auf einfache REAPER-Dialoge zurück |
| js_ReaScriptAPI | Rename nummeriert in Zeitachsen- statt Klick-Reihenfolge; Copy läuft ab 7.62 ohne |
| REAPER < 7.72 | Keine Ruler-Lanes; Marker landen in der Standard-Lane |
| SWS | Wird nicht benutzt. Nicht in die Installationshinweise |
