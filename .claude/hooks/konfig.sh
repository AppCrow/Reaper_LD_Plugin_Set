# Wofür: Einstellungen der zwei Hooks dieses Projekts (tabu.sh, vor-push.sh). Die Hook-Skripte daneben sind Kopien aus dem Projektstarter; ein neuer Stand kommt per Vorlagen/nachziehen.sh, das diese Datei nur einmal umstellt (TABU_INHALT einfügen) und sonst unangetastet lässt.
# Anpassen: alle Werte. Ordner mit Schrägstrich am Ende; TABU und TABU_INHALT als Pfadstücke, PROJEKTSTARTER und TABU_ERLAUBT mit $HOME statt ausgeschriebenem Benutzerordner (die Datei ist versioniert; bei öffentlichem Repo stünde sonst der Benutzername im Commit).

# Stammordner des Projektstarters (Bibliothek, Vorlagen); immer erlaubt.
PROJEKTSTARTER="$HOME/Desktop/Code Factory/Projektstarter"

# Prüfkette, die vor jedem git push laufen muss.
PRUEFKETTE="./scripts/check.sh"

# Tabu als Positivliste: Alles im Benutzerordner, das nicht unter einem dieser
# Präfixe liegt, ist gesperrt. Der Projektstarter selbst ist immer erlaubt.
# Leere Liste = keine Positivliste (dann gelten nur die Listen unten). Beispiel:
#   "$HOME/Desktop/Code Factory/"  "$HOME/.claude/"  "$HOME/Library/Developer/"
# (Xcode baut unter ~/Library/Developer; Dropbox-Tests brauchen ihren Ordner.)
TABU_ERLAUBT=(
)

# Immer gesperrt, auch innerhalb erlaubter Ordner (Teilstring eines Pfads,
# z. B. "/App Crow/Gewerbe"). Der bloße Name darf in Texten vorkommen,
# darum als Pfadstück mit Schrägstrich davor schreiben.
TABU=(
  "/TimecodeMate3/" "/grandMA3/Markers/" "/grandMA3/markers/" "/reaper-license"
)

# TABU_INHALT = Geheimnis-Dateien: Pfad ja, Inhalt nie. Geprüft ohne die Textfelder
# einer Änderung; Erklärung in der Vorlage konfig.sh des Projektstarters.
TABU_INHALT=(
  "/ziel.conf" "/config.php" "/zugang-" "/server/schluessel/" "/AuthKey_"
)
