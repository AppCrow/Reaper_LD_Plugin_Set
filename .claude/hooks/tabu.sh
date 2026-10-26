#!/bin/bash
# Wofür: PreToolUse-Hook für alle Werkzeuge. Blockiert jeden Aufruf, dessen Eingabe einen Pfad im Benutzerordner außerhalb der erlaubten Ordner nennt (Positivliste TABU_ERLAUBT in konfig.sh) oder einen immer gesperrten Teilstring (TABU). Erkennt Punkt-Punkt-Ausbrüche, freistehende Tilde, $HOME und JSON-maskierte Anführungszeichen. Gilt auch für Sub-Agenten, weil der Hook an der Sitzung hängt: „Textregeln schlagen keine Rechte“, das hier ist das Recht.
# Anpassen: nichts hier, nur die Listen in konfig.sh. Kopie aus dem Projektstarter; neuer Stand per Kopie (Projektstart.md).
HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HIER/konfig.sh" ] && . "$HIER/konfig.sh"
TABU_ERLAUBT_TXT="$(printf '%s\n' ${TABU_ERLAUBT[@]+"${TABU_ERLAUBT[@]}"})"
TABU_TXT="$(printf '%s\n' ${TABU[@]+"${TABU[@]}"})"
export TABU_ERLAUBT_TXT TABU_TXT PROJEKTSTARTER
exec python3 -c '
import json, os, re, sys
HOME = os.path.expanduser("~").rstrip("/")
erlaubt = [os.path.expandvars(e) for e in os.environ.get("TABU_ERLAUBT_TXT", "").split("\n") if e.strip()]
ps = os.environ.get("PROJEKTSTARTER", "").rstrip("/")
if erlaubt and ps and os.path.isdir(ps):
    erlaubt.append(ps + "/")
tabu = [t for t in os.environ.get("TABU_TXT", "").split("\n") if t.strip()]
roh = sys.stdin.read()
try:
    text = json.dumps(json.loads(roh).get("tool_input", {}), ensure_ascii=False)
except Exception:
    text = roh
# ~ und $HOME wie den ausgeschriebenen Benutzerordner behandeln
text = re.sub(r"(?<![\w/.~])~(?=[/\s;&|)\x22\x27]|$)", HOME, text)
text = text.replace("${HOME}", HOME).replace("$HOME", HOME)

def blockiert(grund):
    print(grund + " (CLAUDE.md, Abschnitt Tabu). Nicht öffnen, nicht suchen, nicht nennen.", file=sys.stderr)
    sys.exit(2)

for t in tabu:
    if t in text:
        blockiert(f"Blockiert: \"{t}\" ist tabu")
if erlaubt:
    for e in erlaubt:
        if e.rstrip("/") + "/.." in text:
            blockiert(f"Blockiert: Pfad klettert aus \"{e}\" heraus")
    # Erlaubt: Präfix mit Schrägstrich, oder der Ordner selbst, wenn der Pfad dort endet
    # (\x5c = Backslash: Anführungszeichen kommen JSON-maskiert als \")
    ende = r"(?=[\s\x22\x27\x5c;&|)]|$)"
    for m in re.finditer(re.escape(HOME), text):
        rest = text[m.start():]
        if not any(rest.startswith(e) or re.match(re.escape(e.rstrip("/")) + ende, rest) for e in erlaubt):
            pfad = re.split(r"[\x22\x27\n\x5c]", rest)[0][:80]
            blockiert(f"Blockiert: \"{pfad}\" liegt außerhalb der erlaubten Ordner und ist tabu")
sys.exit(0)
'
