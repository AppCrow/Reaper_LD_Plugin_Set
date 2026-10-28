#!/bin/bash
# Wofür: PreToolUse-Hook für alle Werkzeuge. Blockiert jeden Aufruf, dessen Eingabe einen Pfad im Benutzerordner außerhalb der erlaubten Ordner nennt (Positivliste TABU_ERLAUBT in konfig.sh) oder einen immer gesperrten Teilstring (TABU, ganze Eingabe). Geheimnis-Dateien (TABU_INHALT) sperrt er nur außerhalb der Textfelder: Pfad ja, Inhalt nie. Erkennt Punkt-Punkt-Ausbrüche, freistehende Tilde, $HOME und JSON-maskierte Anführungszeichen. Gilt auch für Sub-Agenten, weil der Hook an der Sitzung hängt: „Textregeln schlagen keine Rechte“, das hier ist das Recht.
# Anpassen: nichts hier, nur die Listen in konfig.sh. Kopie aus dem Projektstarter; neuer Stand per Vorlagen/nachziehen.sh (Projektstart.md).
HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HIER/konfig.sh" ] && . "$HIER/konfig.sh"
TABU_ERLAUBT_TXT="$(printf '%s\n' ${TABU_ERLAUBT[@]+"${TABU_ERLAUBT[@]}"})"
TABU_TXT="$(printf '%s\n' ${TABU[@]+"${TABU[@]}"})"
TABU_INHALT_TXT="$(printf '%s\n' ${TABU_INHALT[@]+"${TABU_INHALT[@]}"})"
export TABU_ERLAUBT_TXT TABU_TXT TABU_INHALT_TXT PROJEKTSTARTER
exec python3 -c '
import json, os, re, sys
HOME = os.path.expanduser("~").rstrip("/")
erlaubt = [os.path.expandvars(e) for e in os.environ.get("TABU_ERLAUBT_TXT", "").split("\n") if e.strip()]
ps = os.environ.get("PROJEKTSTARTER", "").rstrip("/")
if erlaubt and ps and os.path.isdir(ps):
    erlaubt.append(ps + "/")
tabu = [t for t in os.environ.get("TABU_TXT", "").split("\n") if t.strip()]
inhalt = [t for t in os.environ.get("TABU_INHALT_TXT", "").split("\n") if t.strip()]
# Textfelder: was in die Datei geschrieben wird; dort darf ein Geheimnis-Pfad stehen
TEXTFELDER = {"content", "old_string", "new_string", "new_source"}

def ohne_text(w):
    if isinstance(w, dict):
        return {k: ohne_text(v) for k, v in w.items() if k not in TEXTFELDER}
    if isinstance(w, list):
        return [ohne_text(v) for v in w]
    return w

def heim(s):
    # ~ und $HOME wie den ausgeschriebenen Benutzerordner behandeln
    s = re.sub(r"(?<![\w/.~])~(?=[/\s;&|)\x22\x27]|$)", HOME, s)
    return s.replace("${HOME}", HOME).replace("$HOME", HOME)

roh = sys.stdin.read()
try:
    eingabe = json.loads(roh).get("tool_input", {})
    text = json.dumps(eingabe, ensure_ascii=False)
    pfade = json.dumps(ohne_text(eingabe), ensure_ascii=False)
except Exception:
    text = pfade = roh
text, pfade = heim(text), heim(pfade)

def blockiert(grund, was="Nicht öffnen, nicht suchen, nicht nennen."):
    print(grund + " (CLAUDE.md, Abschnitt Tabu). " + was, file=sys.stderr)
    sys.exit(2)

for t in tabu:
    if t in text:
        blockiert(f"Blockiert: \"{t}\" ist tabu")
for t in inhalt:
    if re.search(re.escape(t) + r"(?!\.beispiel|\.example)", pfade):
        blockiert(f"Blockiert: \"{t}\" ist eine Geheimnis-Datei (Pfad ja, Inhalt nie)",
                  "Nicht öffnen, nicht durchsuchen, nicht in Befehle oder Agenten-Briefe; Skriptzeilen mit dem Pfad mit Write/Edit schreiben.")
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
