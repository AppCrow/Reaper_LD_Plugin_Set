# Wofür: Einstellungen der zwei Hooks dieses Projekts (tabu.sh, vor-push.sh). Die Hook-Skripte daneben sind Kopien aus dem Projektstarter; ein neuer Stand wird per Kopie übernommen (Projektstart.md), diese Datei bleibt dabei unangetastet.
# Anpassen: alle Werte. Pfade absolut, Ordner mit Schrägstrich am Ende.

# Stammordner des Projektstarters (Bibliothek, Vorlagen); immer erlaubt.
PROJEKTSTARTER="$HOME/Desktop/Code Factory/Projektstarter"

# Prüfkette, die vor jedem git push laufen muss.
PRUEFKETTE="./scripts/check.sh"

# Tabu als Positivliste: Alles im Benutzerordner, das nicht unter einem dieser
# Präfixe liegt, ist gesperrt. Der Projektstarter selbst ist immer erlaubt.
# Leere Liste = keine Positivliste (dann gilt nur TABU unten). Beispiel:
#   "$HOME/Desktop/Code Factory/"  "$HOME/.claude/"  "$HOME/Library/Developer/"
# (Xcode baut unter ~/Library/Developer; Dropbox-Tests brauchen ihren Ordner.)
TABU_ERLAUBT=(
)

# Immer gesperrt, auch innerhalb erlaubter Ordner (Teilstring eines Pfads,
# z. B. "/App Crow/Gewerbe"). Der bloße Name darf in Texten vorkommen,
# darum als Pfadstück mit Schrägstrich davor schreiben.
# Steckplatz Geheimnis-Dateien: die Grundbesetzung bleibt in jedem Projekt
# stehen, dieselben Namen stehen unter „Niemals“ in CLAUDE.md; eigene Stücke
# dahinter anhängen.
TABU=(
  "/ziel.conf" "/config.php" "/zugang-" "/server/schluessel/"
  "/TimecodeMate3/" "/grandMA3/Markers/" "/grandMA3/markers/" "/reaper-license"
)
