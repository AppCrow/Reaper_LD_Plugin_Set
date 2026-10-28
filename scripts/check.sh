#!/bin/bash
# Wofür: Prüfkette. Erst die Budgets der geladenen Dateien (CLAUDE.md rot über 100 Zeilen, PLAN.md Warnung über 400), dann die Schritte aus scripts/pruefkette.txt über den gemeinsamen Läufer scripts/pruefkette.py: parallel, mit Zeitlimit je Schritt, Protokoll je Schritt unter .claude/pruefkette/, Baum-Hash des letzten grünen Laufs in .claude/pruefkette-stand (kein zweiter Lauf am unveränderten Stand), --schnell nur für berührte Dateien, rechnerweite Sperre für schwere Schritte, Zeiten in .claude/pruefkette-zeiten.log. Läuft per Hook vor jedem Push.
# Anpassen: nichts hier; die Schritte stehen in scripts/pruefkette.txt (TODO-Zeilen ersetzen). Aufruf: ./scripts/check.sh [--schnell] [--erzwingen] [--nur name,name]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PYTHONUNBUFFERED=1

fehler() { printf '\n\033[31mFEHLER: %s\033[0m\n' "$1" >&2; exit 1; }
ok()     { printf '   ok   %s\n' "$1"; }

# ---------------------------------------------------------------- 0. Geladener Kontext
BUDGET=100
ZEILEN=$(wc -l < CLAUDE.md | tr -d ' ')
[ "$ZEILEN" -le "$BUDGET" ] || fehler "CLAUDE.md hat $ZEILEN Zeilen, Budget $BUDGET. Erledigtes löschen, Chronik ins Archiv, Status in den Plan."
ok "CLAUDE.md: $ZEILEN/$BUDGET Zeilen"
if [ -f PLAN.md ]; then
  PZ=$(wc -l < PLAN.md | tr -d ' ')
  if [ "$PZ" -le 400 ]; then ok "PLAN.md: $PZ/400 Zeilen"; else printf '   \033[33mWARNUNG\033[0m PLAN.md hat %s Zeilen (Richtwert 400): erledigte Phasen und alte Entscheidungen nach archive/\n' "$PZ"; fi
fi

# ---------------------------------------------------------------- 1. bis 3. Schritte über den Läufer
[ -f scripts/pruefkette.py ] || fehler "scripts/pruefkette.py fehlt (Vorlage: Vorlagen/pruefkette.py des Projektstarters)"
[ -f scripts/pruefkette.txt ] || fehler "scripts/pruefkette.txt fehlt (Vorlage: Vorlagen/pruefkette.txt des Projektstarters)"
exec python3 scripts/pruefkette.py "$@"
