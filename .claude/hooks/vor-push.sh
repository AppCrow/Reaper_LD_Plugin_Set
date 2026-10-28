#!/bin/bash
# Wofür: PreToolUse-Hook für Bash. Blockiert `git push`, solange die Prüfkette nicht grün ist (die Regel „vor dem Push die Prüfkette“ als Mechanismus statt als Text), und verlangt den Push als eigenen Befehl, weil ein Rot sonst den ganzen Aufruf verwirft, auch Commits und Änderungen davor. Heredoc-Texte zählen nicht, aber nur ein echter Heredoc mit Endzeile; „<<“ in Strings, Kommentaren oder Here-Strings und ein Heredoc ohne Endzeile verwerfen keine Zeilen (ein Push dahinter wird erkannt). Solange die Prüfkette noch Vorlage ist (Projektstart: check.sh enthält „# TODO“, oder check.sh nutzt den Läufer pruefkette.py und scripts/pruefkette.txt enthält „# TODO“), geht der Push mit Warnung durch. PUSH_OHNE_PRUEFKETTE öffnet nichts mehr, weder exportiert noch vor dem Befehl (Showtracker TT-72): der Versuch wird nach .claude/push-ohne-pruefkette.log geschrieben, dann entscheidet die Prüfkette wie ohne die Variable. Eine TODO-pruefkette.txt neben einer alten check.sh ohne Läufer (die legt nachziehen.sh an) zählt nicht: dann läuft die alte Kette. Läuft im Projektordner ($CLAUDE_PROJECT_DIR), nicht im Ordner der Shell. Nutzt check.sh den Läufer pruefkette.py, startet der Hook die Kette nicht selbst, sondern fragt mit --gruen nach, ob genau dieser Inhalt (Baum-Hash, auch nach einem Commit) in den letzten sechs Stunden voll grün war; sonst blockiert er mit dem Rat, check.sh im Hintergrund laufen zu lassen (ein Hook hält den Chat an, bis er fertig ist: Aura 2026-10-17 fror zweimal beim Push ein). Bei einer alten check.sh ohne Läufer schreibt der Hook Commit und Zeit nach .claude/pruefkette-stand und lässt die Kette aus, solange HEAD gleich und nichts geändert ist. In settings.json braucht dieser Hook "timeout": 1800 (für die alte check.sh ohne Läufer, die noch im Hook läuft), sonst bricht Claude Code ihn nach 600 s ab und der Push läuft ungeprüft weiter.
# Anpassen: nichts hier; PRUEFKETTE in konfig.sh. Kopie aus dem Projektstarter; neuer Stand per Kopie (Projektstart.md).
HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HIER/konfig.sh" ] && . "$HIER/konfig.sh"
cd "${CLAUDE_PROJECT_DIR:-$HIER/../..}" 2>/dev/null || true
PRUEFKETTE="${PRUEFKETTE:-./scripts/check.sh}"
LOG=".claude/push-ohne-pruefkette.log"

EINGABE="$(cat)"
# 0 = kein Push; 1 = Push als einziger Befehl; 2 = Push zusammen mit anderen Befehlen.
# Heredoc-Texte, grep-Muster und Commit-Nachrichten zählen nicht; `git -C <ordner> push` zählt.
# Ein Heredoc verwirft die Folgezeilen nur, wenn „<<WORT“ als Umleitung steht (nicht in einem Zeilen-String, Kommentar oder als „<<<“) und die Endzeile „WORT“ folgt; fehlt sie, bleibt der Beginn wirkungslos und die Zeilen werden trotzdem geprüft (lieber ein Push zu viel blockiert als einer durchgelassen).
ERGEBNIS=$(printf '%s' "$EINGABE" | python3 -c '
import json, re, sys
try:
    befehl = json.load(sys.stdin).get("tool_input", {}).get("command", "")
except Exception:
    befehl = ""
# Heredoc-Beginn = "<<WORT" als Umleitung. Vorher verbraucht und damit nicht gewertet: Backslash-Paare, vollständige Strings derselben Zeile, Here-String "<<<", Kommentar ab "#". Körper und Endzeile (Zeile = WORT) fallen nur weg, wenn die Endzeile folgt; sonst ist der Beginn wirkungslos (kein Textblock, "<<" in Rechnungen oder Code auch nicht) und die Zeilen werden geprüft. Mehrzeilige Strings werden zeilenweise gelesen.
kopf = re.compile(r"\\.|\x27[^\x27]*\x27|\x22(?:\\.|[^\x22\\])*\x22|<<<|(?:^|(?<=\s))#.*|<<-?\s*[\x27\x22]?(\w+)[\x27\x22]?")
roh = befehl.split("\n")
zeilen, i = [], 0
while i < len(roh):
    z = roh[i]
    zeilen.append(z)
    i += 1
    for m in kopf.finditer(z):
        if m.group(1):
            for j in range(i, len(roh)):
                if roh[j].strip() == m.group(1):
                    i = j + 1
                    break
text = "\n".join(zeilen)
teile = [t.strip() for t in re.split(r"&&|\|\||;|\||\n", text) if t.strip()]
push = re.compile(r"^git(\s+-C\s+(\x22[^\x22]*\x22|\x27[^\x27]*\x27|\S+))?(\s+--?[\w-]+)*\s+push(\s|$)")
# Vorangestellte Zuweisungen und env zählen nicht ("X=1 git push" ist ein Push); PUSH_OHNE_PRUEFKETTE im Befehl ist der Notausgang (FlicFlacShowtracker 2026-10-14: ging ungeprüft und ohne Protokoll durch).
vorsatz = re.compile(r"^(?:env\s+|(\w+)=(\x22[^\x22]*\x22|\x27[^\x27]*\x27|\S*)\s+)")
grund = ""
treffer = []
for t in teile:
    werte = {}
    while (m := vorsatz.match(t)):
        if m.group(1): werte[m.group(1)] = m.group(2).strip("\x22\x27")
        t = t[m.end():]
    if push.match(t):
        treffer.append(t); grund = grund or werte.get("PUSH_OHNE_PRUEFKETTE", "")
if not treffer:
    print(0)
elif len(teile) == 1:
    print(1)
else:
    print(2)
print(grund.replace("\n", " "))
')
GRUND_IM_BEFEHL="$(printf '%s\n' "$ERGEBNIS" | sed -n 2p)"
ERGEBNIS="$(printf '%s\n' "$ERGEBNIS" | head -1)"
[ -n "$GRUND_IM_BEFEHL" ] && PUSH_OHNE_PRUEFKETTE="$GRUND_IM_BEFEHL"
[ "$ERGEBNIS" = "0" ] && exit 0

if [ "$ERGEBNIS" = "2" ]; then
  echo "Push blockiert: \`git push\` als eigenen Befehl absetzen, nicht hinter anderen Befehlen im selben Aufruf. Bei roter Prüfkette verwirft der Wächter sonst den ganzen Aufruf, auch Commits und Änderungen davor (Kernzeile Push)." >&2
  exit 2
fi

if [ ! -x "$PRUEFKETTE" ]; then
  echo "Push blockiert: Prüfkette $PRUEFKETTE fehlt oder ist nicht ausführbar (Projektordner: $(pwd))." >&2
  exit 2
fi

# Kein Notausgang mehr: die Variable wird protokolliert und sonst ignoriert, die Prüfkette unten entscheidet.
if [ -n "${PUSH_OHNE_PRUEFKETTE:-}" ]; then
  mkdir -p "$(dirname "$LOG")"
  echo "$(date '+%Y-%m-%d %H:%M') Push ohne Prüfkette versucht: $PUSH_OHNE_PRUEFKETTE" >> "$LOG"
  echo "HINWEIS: PUSH_OHNE_PRUEFKETTE öffnet nichts mehr (Kernzeile Push); der Versuch steht in $LOG. Es zählt allein die Prüfkette." >&2
fi

# Nutzt check.sh den Läufer (pruefkette.py in einer Zeile, die kein Kommentar ist), entscheidet der über den Inhalt: Er vergleicht den Baum mit dem
# Merker des letzten grünen Laufs, meldet „kein zweiter Lauf“ und schreibt den Merker selbst, mit Baum. Ein Commit nach dem grünen Lauf ändert
# den Baum nicht (Aura 2026-10-17: Commit-Vergleich hier und Merker ohne Baum hießen zweiter Lauf am gleichen Inhalt, 594 s).
LAEUFER=0
grep -v '^[[:space:]]*#' "$PRUEFKETTE" 2>/dev/null | grep -q 'pruefkette\.py' && LAEUFER=1

# Alte check.sh ohne Läufer: schon grün für genau diesen Commit (voller Lauf, höchstens sechs Stunden alt, keine geänderten Dateien)? Dann nicht erneut.
if [ "$LAEUFER" = 0 ] && [ -f .claude/pruefkette-stand ]; then
  read -r SH SD ST SM REST < .claude/pruefkette-stand
  if [ "${SM:-}" = "voll" ] && [ "$SH" = "$(git rev-parse --short HEAD 2>/dev/null)" ] && [ -z "$(git status --porcelain 2>/dev/null | grep -v '^??')" ]; then
    ALTER=$(python3 -c 'import datetime,sys
try:
    d=datetime.datetime.strptime(sys.argv[1]+" "+sys.argv[2], "%Y-%m-%d %H:%M"); print(int((datetime.datetime.now()-d).total_seconds()))
except Exception: print(-1)' "$SD" "$ST")
    if [ "$ALTER" -ge 0 ] && [ "$ALTER" -le 21600 ]; then
      echo "Prüfkette für $SH schon grün ($SD $ST, voll), läuft nicht erneut." >&2
      exit 0
    fi
  fi
fi

# Noch Vorlage (Projektstart)? Dann geht der Push mit Warnung durch. Vorlage heißt: check.sh selbst enthält „# TODO“, oder check.sh nutzt den Läufer (pruefkette.py in einer Zeile, die kein Kommentar ist) UND pruefkette.txt enthält „# TODO“. Eine TODO-pruefkette.txt neben einer alten check.sh ohne Läufer (die legt nachziehen.sh an) ist kein Grund, die Kette zu überspringen.
VORLAGE=0
grep -q '^# TODO' "$PRUEFKETTE" 2>/dev/null && VORLAGE=1
if [ "$LAEUFER" = 1 ] && grep -q '^# TODO' "$(dirname "$PRUEFKETTE")/pruefkette.txt" 2>/dev/null; then VORLAGE=1; fi
if [ "$VORLAGE" = 1 ]; then
  echo "WARNUNG: Prüfkette enthält noch TODO-Schritte der Vorlage (check.sh oder pruefkette.txt); Push geht durch. Prüfkette in Phase 1 ausfüllen." >&2
  exit 0
fi

# Mit Läufer läuft die Kette nie im Hook, er sieht nur nach (--gruen). Der Hook hält den Chat an, bis er fertig ist, und reißt nach 1800 s ab
# (Aura 2026-10-17: zweimal „Chat reagiert nicht mehr“ beim Push, die volle Kette brauchte 2264 s). Also erst die Kette im Hintergrund, dann der Push.
if [ "$LAEUFER" = 1 ]; then
  if AUSGABE="$("$PRUEFKETTE" --gruen 2>&1)"; then
    printf '%s\n' "$AUSGABE" | grep -v '^[[:space:]]*$' | tail -1 >&2
    exit 0
  fi
  printf '%s\n' "$AUSGABE" | grep -v '^[[:space:]]*$' | tail -3 >&2
  echo "Push blockiert, die Kette läuft nicht im Hook (der hält den Chat an, bis sie fertig ist). Erst \`$PRUEFKETTE > .claude/pruefkette-lauf.txt 2>&1\` mit run_in_background starten, auf die Meldung warten, bei Grün \`git push\` allein absetzen. Am gleichen Inhalt läuft dabei nichts doppelt." >&2
  exit 2
fi
if ! AUSGABE="$("$PRUEFKETTE" 2>&1)"; then
  echo "Push blockiert: Prüfkette rot. Letzte Zeilen:" >&2
  printf '%s\n' "$AUSGABE" | tail -15 >&2
  exit 2
fi
mkdir -p .claude
printf '%s %s voll\n' "$(git rev-parse --short HEAD 2>/dev/null || echo '?')" "$(date '+%Y-%m-%d %H:%M')" > .claude/pruefkette-stand
exit 0
