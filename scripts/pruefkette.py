#!/usr/bin/env python3
# Wofür: gemeinsamer Läufer der Prüfkette. Liest scripts/pruefkette.txt (Name | Befehl | berührt | Optionen), lässt die Schritte parallel mit Zeitlimit laufen (Ausgabe je Schritt in .claude/pruefkette/<name>.log, im Chat eine Zeile je Schritt und bei Rot die letzten Zeilen), merkt sich den Baum-Hash des Inhalts beim letzten grünen vollen Lauf (gemeinsam für alle Worktrees eines Repos im Git-Ordner unter pruefkette/staende, dazu je Ordner .claude/pruefkette-stand für Anzeige und Bezugspunkt; auch ein --schnell, der alle Schritte lief, zählt als voll; Rot am selben Inhalt löscht das Grün) und läuft am selben Inhalt nicht erneut, auch nicht nach einem Commit und nicht in einem anderen Worktree mit demselben Inhalt (Dateien, die ein Schritt laut schreibt= selbst schreibt, zählen nicht zum Inhalt), überspringt auch im vollen Lauf jeden Schritt, dessen Eingaben (Dateien seiner Globs plus Befehl) seit seinem letzten grünen Lauf gleich sind (Schritt-Cache gemeinsam für alle Worktrees im Git-Ordner unter pruefkette/gruen, je Schritt und Eingaben-Hash, 6 Stunden; nicht für „immer“-Schritte, nicht mit --erzwingen oder --nur, nicht ohne grünen Bezugspunkt oder bei einer geänderten Datei ohne zuständigen Schritt), kennt !glob (die Datei liest der Schritt nicht; schließt ein Schritt sie aus, läuft für sie nur, wer sie liest, auch über *, und eine Datei, die keiner liest, startet nichts), kennt --schnell (nur Schritte, deren Globs eine geänderte Datei treffen; nur-voll-Schritte nie, die laufen erst im vollen Lauf; unbekannte Datei = alles; ohne Git-Repo, etwa in der Kopie von mutation.sh, gibt es weder Merker noch geänderte Dateien: dort läuft immer alles; ebenso solange kein voller Lauf grün war oder dessen Commit fehlt: ohne grünen Stand ist „geändert“ nicht zu bestimmen), nimmt je schwerem Schritt eine rechnerweite Sperre (Normalfall schwer=<ressource> für eine eigene Sperre je Browser, Simulator, Build: leichte Schritte und andere Ressourcen laufen weiter, auch in anderen Projekten; schwer=<ressource>:<n> gibt der Ressource n Plätze, dann laufen bis zu n solche Schritte gleichzeitig, auch projektübergreifend; schwer ohne Ressource ist die Ausnahme und sperrt alle schweren Schritte aller Projekte), setzt einen Schritt, dessen Sperre nach SPERRE_WARTEN (Standard 600 s, je Sperre und Lauf) nicht frei ist, nicht rot, sondern lässt ihn mit gelber Warnung trotzdem laufen (die Sperre schützt Laufzeit, nicht Richtigkeit; ein Rot ohne Fehler im Projekt wäre eine falsche Auskunft) und vermerkt das im Zeitprotokoll (Feld ohne-sperre=) und in der Schlusszeile, meldet beim Warten alle SPERRE_MELDEN Sekunden Halter und Wartedauer, übernimmt die Sperre eines toten Prozesses sofort, protokolliert jede Laufzeit nach .claude/pruefkette-zeiten.log und warnt, wenn die Kette über den Richtwert wächst. Warum 600 statt 1800 s: eine alte check.sh ohne Läufer läuft noch im Hook-Timeout des Push-Wächters von 1800 s (claude-settings.json); 30 Minuten Warten plus eine Kette von 15 Minuten reißen ihn, und ein Lauf unter Fremdlast ist das kleinere Übel. Mit dem Läufer startet der Push-Wächter die Kette nicht selbst, er fragt nur --gruen (Exit 0: genau dieser Inhalt war in den letzten sechs Stunden voll grün; Exit 3: nicht, mit Grund), denn ein Hook hält den Chat an, bis er fertig ist (Aura 2026-10-17: zweimal eingefroren beim Push). Drei Projekte hatten sich Teile davon einzeln gebaut (paralleler Läufer, Gegenproben nach Prüfsumme, Merker für den grünen Stand).
# Anpassen: nichts hier; die Schritte stehen in scripts/pruefkette.txt. Aufruf über scripts/check.sh oder direkt: python3 scripts/pruefkette.py [--schnell] [--erzwingen] [--nur name,name] [--liste datei] [--gruen: nur nachsehen, nichts laufen lassen]. Umgebung: PRUEFKETTE_PARALLEL (Standard 3), PRUEFKETTE_MAX_MINUTEN (5), PRUEFKETTE_STRENG=1 (über dem Richtwert rot), SPERRE_GEMEINSAM=0 (keine Sperre), SPERRE_ORDNER, SPERRE_WARTEN (Sekunden, nach denen ein gesperrter Schritt mit Warnung trotzdem läuft, Standard 600; 0 = nie warten), SPERRE_MELDEN (Sekunden zwischen zwei Wartemeldungen, Standard 180).
import datetime
import fcntl
import fnmatch
import hashlib
import os
import re
import shutil
import signal
import subprocess
import sys
import time

GIT_TOP = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
# Ohne Git (etwa die Kopie von scripts/mutation.sh) liefern die git-Befehle nichts: der Baum-Hash wäre konstant
# (ein Eingriff träfe den Merker des Basislaufs) und keine Datei gälte als geändert. Dann kein Merker und --schnell läuft alles.
OHNE_GIT = not GIT_TOP
ROOT = GIT_TOP or os.getcwd()
os.chdir(ROOT)
ARGS = sys.argv[1:]
SCHNELL = "--schnell" in ARGS
ERZWINGEN = "--erzwingen" in ARGS
NUR = set()
LISTE = os.path.join("scripts", "pruefkette.txt")
for i, a in enumerate(ARGS):
    if a == "--nur" and i + 1 < len(ARGS):
        NUR = set(ARGS[i + 1].split(","))
    if a == "--liste" and i + 1 < len(ARGS):
        LISTE = ARGS[i + 1]
PARALLEL = max(1, int(os.environ.get("PRUEFKETTE_PARALLEL", "3")))
MAX_MIN = float(os.environ.get("PRUEFKETTE_MAX_MINUTEN", "5"))
STRENG = os.environ.get("PRUEFKETTE_STRENG", "0") == "1"
LOGDIR = os.path.join(".claude", "pruefkette")
STAND = os.path.join(".claude", "pruefkette-stand")
ZEITEN = os.path.join(".claude", "pruefkette-zeiten.log")
os.makedirs(LOGDIR, exist_ok=True)
os.environ.setdefault("PYTHONUNBUFFERED", "1")

ROT = "\033[31m"; GRUEN = "\033[32m"; GELB = "\033[33m"; FETT = "\033[1m"; AUS = "\033[0m"

def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True).stdout

# ---------------------------------------------------------------- Schritte lesen
def schritte_lesen(pfad):
    schritte = []
    if not os.path.exists(pfad):
        sys.exit(f"{ROT}FEHLER: {pfad} fehlt. Vorlage: Vorlagen/pruefkette.txt des Projektstarters.{AUS}")
    for nr, zeile in enumerate(open(pfad, encoding="utf-8"), 1):
        z = zeile.strip()
        if not z or z.startswith("#"):
            continue
        teile = [t.strip() for t in z.split("|")]
        if len(teile) < 2:
            sys.exit(f"{ROT}FEHLER: {pfad} Zeile {nr}: Form ist 'name | befehl | globs | optionen'{AUS}")
        name, befehl = teile[0], teile[1]
        globs = teile[2].split() if len(teile) > 2 and teile[2] else ["*"]
        ohne = [g[1:] for g in globs if g.startswith("!")]   # !glob = liest der Schritt nicht, z. B. „* !uebergaben/**“
        globs = [g for g in globs if not g.startswith("!")] or ["*"]
        opt = teile[3].split() if len(teile) > 3 else []
        # schwer=<ressource> (browser, simulator, build …) = eigene Sperre je Ressource, der Normalfall; schwer ohne Ressource = die eine Sperre „pruefkette“ für alle schweren Schritte aller Projekte auf dem Rechner, nur für Ausnahmen
        # schwer=<ressource>:<n> = n Plätze: bis zu n Schritte dieser Ressource gleichzeitig auf dem Rechner (ohne Zahl 1, wie bisher)
        sperrname, plaetze = None, 1
        for o in opt:
            if o == "schwer":
                sperrname = "pruefkette"
            elif o.startswith("schwer="):
                res, _, zahl = o[7:].partition(":")
                if not res or (zahl and not (zahl.isdigit() and int(zahl) >= 1)):
                    sys.exit(f"{ROT}FEHLER: {pfad} Zeile {nr}: Form ist 'schwer=<ressource>' oder 'schwer=<ressource>:<plätze ab 1>', war '{o}'{AUS}")
                sperrname, plaetze = "pruefkette-" + res, int(zahl or 1)
        s = {"name": name, "befehl": befehl, "globs": globs, "ohne": ohne, "schwer": sperrname, "plaetze": plaetze, "immer": "immer" in opt,
             "nur_voll": "nur-voll" in opt, "zeit": 600, "nach": [], "mindestens": None}
        for o in opt:
            if o.startswith("schreibt="): AUSGABEN.update(o[9:].split(","))
            if o.startswith("zeit="): s["zeit"] = int(o[5:])
            if o.startswith("nach="): s["nach"] = o[5:].split(",")
            if o.startswith("mindestens="): s["mindestens"] = int(o[11:])
        schritte.append(s)
    namen = {s["name"] for s in schritte}
    for s in schritte:
        for d in s["nach"]:
            if d not in namen:
                sys.exit(f"{ROT}FEHLER: Schritt {s['name']} wartet auf unbekannten Schritt {d}{AUS}")
    return schritte

# ---------------------------------------------------------------- Baum-Hash und geänderte Dateien
# Dateien, die ein Schritt selbst schreibt (Option schreibt=<pfad|glob>,…), etwa ein versionierter Gegenproben-Stand: Sie sind
# Ausgabe, keine Eingabe, zählen weder zum Baum noch zu den geänderten Dateien noch zu den Eingaben des Schritt-Caches. Sonst
# verdirbt jeder Lauf seinen eigenen Merker (Aura 2026-10-17: tests lief am gleichen Code noch einmal 465 s).
AUSGABEN = set()

def ausgabe(pfad):
    return any(passt(g, pfad) for g in AUSGABEN)

def baum_hash():
    """Hash des Inhalts: Pfad, Inhaltskennung und Ausführbarkeit jeder versionierten und jeder neuen Datei. Vorgemerkt oder nicht,
    vor oder nach dem Commit ist er gleich (Aura 2026-10-17: grüner Lauf, Commit, Push = zweiter Lauf am gleichen Inhalt)."""
    h = hashlib.sha256()
    for p, k in sorted(datei_hashes().items()):
        h.update(f"{p} {k} {int(os.access(p, os.X_OK))}\n".encode())
    return h.hexdigest()[:16]

def letzter_stand():
    try:
        teile = open(STAND, encoding="utf-8").read().split()
    except FileNotFoundError:
        return None
    if len(teile) < 4:
        return None
    return {"commit": teile[0], "zeit": " ".join(teile[1:3]), "modus": teile[3], "baum": teile[4] if len(teile) > 4 else None}

def gemeinsamer_stand(baum):
    """Letztes Ergebnis (voll oder rot) für genau diesen Inhalt aus irgendeinem Worktree, in der Form von letzter_stand()."""
    for z in merker_lesen(STAENDE):
        if len(z) >= 4 and z[0] == baum:
            return {"commit": z[1], "modus": z[2], "zeit": z[3], "baum": baum}
    return None

def stand_merken(baum, modus):
    """Ergebnis für genau diesen Inhalt merken: gemeinsam (gilt in jedem Worktree) und hier (Anzeige der Hooks, Bezugspunkt von
    --schnell). Rot ersetzt ein Grün desselben Baums; den Merker hier ändert Rot nur, wenn er denselben Baum trägt."""
    commit = git("rev-parse", "--short", "HEAD").strip() or "?"
    jetzt = f"{datetime.datetime.now():%Y-%m-%d %H:%M}"
    merker_aendern(STAENDE, lambda zeilen: [z for z in zeilen if z[0] != baum] + [[baum, commit, modus, jetzt]])
    hier = letzter_stand()
    if modus == "voll" or (hier and hier.get("baum") == baum):
        os.makedirs(".claude", exist_ok=True)
        open(STAND, "w", encoding="utf-8").write(f"{commit} {jetzt} {modus} {baum}\n")

def bezugspunkt_da(stand):
    """Gibt es einen grünen Stand, dessen Commit noch da ist? Nur dann sagt „keine geänderten Dateien“ etwas. Sonst (nie voll grün gelaufen,
    Merker ohne Commit, Commit nach Rebase oder in einem anderen Klon weg) fehlt der Vergleichspunkt, der Diff liefe leer und --schnell wäre grün ohne Lauf."""
    if not (stand and stand.get("commit")) or stand.get("modus") != "voll":
        return False
    return subprocess.run(["git", "rev-parse", "--verify", "--quiet", stand["commit"] + "^{commit}"], capture_output=True).returncode == 0

def geaenderte_dateien(stand):
    dateien = set()
    if stand and stand.get("commit"):
        dateien |= set(git("diff", "--name-only", stand["commit"]).split("\n"))
    dateien |= set(git("diff", "--name-only", "--", ".", ":!.claude").split("\n"))
    dateien |= set(git("diff", "--name-only", "--cached", "--", ".", ":!.claude").split("\n"))
    dateien |= set(git("ls-files", "--others", "--exclude-standard").split("\n"))
    return {d for d in dateien if d and not d.startswith(".claude/") and not ausgabe(d)}

def liest(s, pfad):
    """Trifft ein Glob des Schritts die Datei und kein !-Glob?"""
    return any(passt(g, pfad) for g in s["globs"]) and not any(passt(g, pfad) for g in s["ohne"])

def zustaendige(schritte, pfad):
    """Schritte, die eine geänderte Datei neu prüfen muss; None = niemand ist ausdrücklich zuständig, darum alles.
    Ausdrücklich zuständig ist ein Schritt mit eigenem Glob (nicht *). Schließt ein !-Glob die Datei irgendwo aus,
    hat jemand über sie entschieden: dann prüfen genau die Schritte, die sie lesen, auch über *; liest sie keiner
    (Bericht, Plan, Übergabe), läuft für sie nichts (Aura 2026-10-17: 101 von 247 Commits nur Text, jeder startete
    Tests und Gegenproben neu, rund 40 Minuten)."""
    eigen = [s for s in schritte if liest(s, pfad) and any(g != "*" and passt(g, pfad) for g in s["globs"])]
    if eigen:
        return eigen
    if any(passt(g, pfad) for s in schritte for g in s["ohne"]):
        return [s for s in schritte if liest(s, pfad)]
    return None

def passt(glob, pfad):
    if glob == "*":
        return True
    if glob.endswith("/**"):
        return pfad.startswith(glob[:-3] + "/") or pfad == glob[:-3]
    if glob.startswith("**/"):
        return fnmatch.fnmatch(pfad, glob) or fnmatch.fnmatch(os.path.basename(pfad), glob[3:])
    return fnmatch.fnmatch(pfad, glob)

# ---------------------------------------------------------------- Eingaben je Schritt (Schritt-Cache)
# Ein Schritt, dessen Eingaben (alle Dateien, die seine Globs treffen, plus sein Befehl) seit seinem letzten grünen Lauf
# gleich sind, läuft nicht noch einmal, auch im vollen Lauf: gemessen (PickFlow, 2026-10-13) liefen 470 volle Ketten und 10
# schnelle, fünf davon binnen 20 Minuten am fast gleichen Stand, weil der Produktschritt mit seinen Globs jede Änderung traf.
# Der Merker gilt für alle Worktrees (gemeinsamer Git-Ordner, pruefkette/gruen: Name|Hash|Zeit, je Name mehrere Hashes); Rot
# löscht den Eintrag für genau diese Eingaben, --erzwingen lässt alles laufen, „immer“-Schritte laufen immer. Gleiche Sicherung wie --schnell: eine geänderte Datei ohne zuständigen Schritt
# oder kein grüner Bezugspunkt, dann wird nichts übersprungen. Ignorierte Dateien (Konfig, dist/) zählen nicht zu den Eingaben.
CACHE_STUNDEN = 6

# ---------------------------------------------------------------- Gemeinsame Merker aller Worktrees
# Grüner Stand und Schritt-Cache liegen im gemeinsamen Git-Ordner (git rev-parse --git-common-dir; in einem Worktree der .git des
# Hauptordners) unter pruefkette/: Ein Ergebnis für Baum X gilt in jedem Worktree mit Baum X (Aura 2026-10-19: Phase 1.5 im
# Worktree um 15:25 grün, nach dem Merge trug main denselben Baum, der Push-Wächter verlangte trotzdem 30 bis 45 Minuten Kette).
# Geschrieben wird unter flock: neu lesen, einen Eintrag ändern, Abgelaufenes streichen, über eine Zwischendatei mit os.replace
# ersetzen. Zwei Worktrees zugleich verlieren so keinen Eintrag, und wer liest, sieht nie eine halbe Datei.
GEMEINSAM = "" if OHNE_GIT else os.path.join(os.path.abspath(git("rev-parse", "--git-common-dir").strip() or ".git"), "pruefkette")
STAENDE = os.path.join(GEMEINSAM, "staende")       # Baum|Commit|voll oder rot|Zeit: das letzte Ergebnis je Inhalt
GRUEN_DATEI = os.path.join(GEMEINSAM, "gruen")     # Name|Eingaben-Hash|Zeit; nicht GRUEN: das ist die Farbe

def merker_lesen(pfad):
    try:
        with open(pfad, encoding="utf-8") as f:
            return [z.rstrip("\n").split("|") for z in f if z.strip()]
    except OSError:
        return []

def merker_aendern(pfad, aendern):
    """Unter Sperre neu lesen, aendern(zeilen) liefert die neuen Zeilen, Einträge über CACHE_STUNDEN fallen heraus, dann atomar ersetzen."""
    try:
        os.makedirs(GEMEINSAM, exist_ok=True)
        with open(os.path.join(GEMEINSAM, "sperre"), "a") as sperre:
            fcntl.flock(sperre, fcntl.LOCK_EX)   # endet mit dem Schließen, auch wenn der Prozess stirbt
            zeilen = [z for z in aendern(merker_lesen(pfad)) if len(z) >= 3 and cache_frisch(z[-1])]
            zwischen = f"{pfad}.{os.getpid()}.neu"
            with open(zwischen, "w", encoding="utf-8") as f:
                f.writelines("|".join(z) + "\n" for z in sorted(zeilen))
            os.replace(zwischen, pfad)
    except OSError as e:
        print(f"{GELB}Merker {pfad} nicht geschrieben ({e}); der nächste Lauf prüft dann mehr, nie weniger.{AUS}", flush=True)

def datei_hashes():
    """Pfad -> Kennung des Inhalts: für unveränderte versionierte Dateien der Blob-Hash aus dem Index, sonst ein Hash des Inhalts."""
    m = {}
    for z in git("ls-files", "-s").split("\n"):
        if "\t" in z:
            meta, pfad = z.split("\t", 1)
            m[pfad] = meta.split()[1]
    anders = set()
    for args in (("diff", "--name-only"), ("diff", "--name-only", "--cached"), ("ls-files", "--others", "--exclude-standard")):
        anders |= set(git(*args).split("\n"))
    # Geänderte Dateien mit derselben Kennung wie im Index (git hash-object), sonst liefe nach dem Commit jeder berührte
    # Schritt erneut, obwohl der Inhalt gleich ist (FlicFlacShowtracker 2026-10-15: abbau-skript 491 s am selben Inhalt).
    dateien = sorted(f for f in anders if f and os.path.isfile(f))
    for f in anders:
        if f and not os.path.isfile(f):
            m.pop(f, None)
    if dateien:
        r = subprocess.run(["git", "hash-object", "--stdin-paths"], input="\n".join(dateien) + "\n", capture_output=True, text=True)
        kennungen = r.stdout.split()
        if r.returncode == 0 and len(kennungen) == len(dateien):
            m.update(zip(dateien, kennungen))
        else:   # Notweg: eigener Hash; höchstens ein Cache-Fehlschlag, nie ein falsches Grün
            for f in dateien:
                with open(f, "rb") as fh:
                    m[f] = "sha256:" + hashlib.sha256(fh.read()).hexdigest()[:16]
    return {p: h for p, h in m.items() if not p.startswith(".claude/") and not ausgabe(p)}

def schritt_hash(s, hashes):
    h = hashlib.sha256(s["befehl"].encode())
    for p in sorted(hashes):
        if liest(s, p):
            h.update(f"{p} {hashes[p]}\n".encode())
    return h.hexdigest()[:16]

def gruen_lesen():
    """(Name, Eingaben-Hash) -> Zeit des letzten grünen Laufs, aus irgendeinem Worktree."""
    return {(z[0], z[1]): z[2] for z in merker_lesen(GRUEN_DATEI) if len(z) >= 3}

def cache_frisch(zeit):
    try:
        return (datetime.datetime.now() - datetime.datetime.strptime(zeit, "%Y-%m-%d %H:%M")).total_seconds() <= CACHE_STUNDEN * 3600
    except ValueError:
        return False

# ---------------------------------------------------------------- Sperre
# Je schwerem Schritt, nicht je Lauf: leichte Schritte laufen weiter, während ein schwerer auf die Sperre wartet,
# und Projekte blockieren sich nur bei derselben Ressource (eine 15-Minuten-Kette hielt sonst die Sperre für alles).
# Wer länger als SPERRE_WARTEN wartet, läuft trotzdem (lauf_innen): die Sperre schützt Laufzeit, nicht Richtigkeit.
# Plätze (schwer=browser:2): Platz 1 ist der Ordner <name> wie bisher, Platz i der Ordner <name>.<i>. Ein Läufer ohne Plätze
# kennt nur Platz 1 und wartet, solange der belegt ist; gemischt laufen also höchstens so viele, wie der größte Platzwert erlaubt.
def sperre_versuchen(name, schritt, plaetze=1):
    """Nicht blockierend. Liefert (True, ordner) für den ersten freien Platz oder (False, [ordner der Halter]); Sperren toter Prozesse werden übernommen."""
    if os.environ.get("SPERRE_GEMEINSAM", "1") == "0":
        return True, None
    ordner = os.environ.get("SPERRE_ORDNER", "/tmp/code-factory-sperren")
    os.makedirs(ordner, exist_ok=True)
    belegt = []
    for i in range(1, plaetze + 1):
        d = os.path.join(ordner, name if i == 1 else f"{name}.{i}")
        while True:
            try:
                os.mkdir(d)
                open(os.path.join(d, "pid"), "w").write(str(os.getpid()))
                open(os.path.join(d, "wer"), "w").write(f"{os.path.basename(ROOT)} ({schritt}) seit {datetime.datetime.now():%H:%M}")
                return True, d
            except FileExistsError:
                try:
                    pid = int(open(os.path.join(d, "pid")).read().strip())
                    os.kill(pid, 0)
                except (ValueError, FileNotFoundError, ProcessLookupError):
                    shutil.rmtree(d, ignore_errors=True); continue
                except PermissionError:
                    pass
                belegt.append(d); break
    return False, belegt

def sperre_wer(ds):
    def wer(d):
        try:
            return open(os.path.join(d, "wer")).read().strip()
        except Exception:
            return "?"
    return "; ".join(wer(d) for d in ds)

# ---------------------------------------------------------------- Lauf
def schon_gruen(stand, baum):
    """Leer, wenn der letzte grüne volle Lauf genau diesen Inhalt hatte und höchstens sechs Stunden alt ist; sonst der Grund."""
    if not stand:
        return "noch kein grüner voller Lauf vermerkt"
    if stand.get("modus") == "rot" and stand.get("baum") == baum:
        return f"der letzte Lauf an genau diesem Inhalt ({stand.get('zeit', '?')}) war rot"
    if stand.get("modus") != "voll":
        return "der letzte vermerkte Lauf war kein voller"
    if stand.get("baum") != baum:
        return f"seit dem letzten grünen Lauf ({stand.get('zeit', '?')}) hat sich der Inhalt geändert"
    try:
        alter = (datetime.datetime.now() - datetime.datetime.strptime(stand["zeit"], "%Y-%m-%d %H:%M")).total_seconds()
    except (KeyError, ValueError):
        alter = 10 ** 9
    return "" if alter <= 6 * 3600 else f"der letzte grüne Lauf ({stand.get('zeit', '?')}) ist älter als sechs Stunden"

def main():
    if "--baum" in ARGS:   # nur den Baum-Hash drucken, wie ihn der Merker des grünen Stands trägt
        if os.path.exists(LISTE):
            schritte_lesen(LISTE)   # für schreibt=
        print("" if OHNE_GIT else baum_hash()); return 0
    start = time.time()
    modus = "schnell" if SCHNELL else "voll"
    schritte = schritte_lesen(LISTE)
    stand_hier = None if OHNE_GIT else letzter_stand()
    baum = baum_hash()
    # Gilt das neueste Ergebnis für genau diesen Inhalt, aus diesem oder einem anderen Worktree (bei gleicher Minute gewinnt Rot);
    # sonst der letzte grüne Stand hier, als Bezugspunkt für --schnell und als Grund, warum nicht grün
    gleich = [s for s in (None if OHNE_GIT else gemeinsamer_stand(baum), stand_hier) if s and s.get("baum") == baum]
    stand = max(gleich, key=lambda s: (s["zeit"], s["modus"] == "rot")) if gleich else stand_hier
    bezug = stand if stand and stand.get("modus") == "voll" else stand_hier   # Rot an diesem Inhalt: Bezugspunkt bleibt das Grün hier

    warum_nicht = schon_gruen(stand, baum)
    if "--gruen" in ARGS:   # nur nachsehen, nichts laufen lassen (Push-Wächter: der Hook hält den Chat an, bis er fertig ist)
        if warum_nicht:
            print(f"Für genau diesen Stand (Baum {baum}) gibt es keinen grünen Lauf: {warum_nicht}.")
            return 3
        print(f"{GRUEN}Prüfkette grün für genau diesen Stand ({stand['zeit']}, Baum {baum}).{AUS}")
        return 0
    if modus == "voll" and not NUR and not ERZWINGEN and not warum_nicht:
        if stand is not stand_hier:   # grün aus einem anderen Worktree: hier übernehmen, für Anzeige und Bezugspunkt
            open(STAND, "w", encoding="utf-8").write(f"{stand['commit']} {stand['zeit']} voll {baum}\n")
        print(f"{GRUEN}Prüfkette grün für genau diesen Stand ({stand['zeit']}, Baum {baum}); nichts geändert, kein zweiter Lauf. Erzwingen: --erzwingen{AUS}")
        return 0

    auswahl = list(schritte)
    schnell_alle = [s for s in schritte if not s["nur_voll"]]   # --schnell lässt nur-voll-Schritte immer aus, auch wenn „alles“ läuft
    nur_voll_hinweis = f"; {len(schritte) - len(schnell_alle)} nur-voll-Schritt(e) erst im vollen Lauf" if len(schnell_alle) < len(schritte) else ""
    grund = ""
    # Schritt-Cache: nur, wenn der Bezugspunkt da ist und jede geänderte Datei einen Schritt hat (dieselbe Sicherung wie --schnell)
    cache = not (NUR or ERZWINGEN or OHNE_GIT) and bezugspunkt_da(bezug)
    if cache:
        for d in geaenderte_dateien(bezug):
            if zustaendige(schritte, d) is None:
                cache = False; break
    if NUR:
        auswahl = [s for s in schritte if s["name"] in NUR]
        unbekannt = NUR - {s["name"] for s in schritte}
        if unbekannt:
            sys.exit(f"{ROT}FEHLER: unbekannte Schritte: {', '.join(sorted(unbekannt))}{AUS}")
        grund = "nur " + ", ".join(s["name"] for s in auswahl)
    elif SCHNELL and OHNE_GIT:
        auswahl = schnell_alle
        grund = "kein Git-Repo, geänderte Dateien unbekannt, darum alles" + nur_voll_hinweis
    elif SCHNELL and not bezugspunkt_da(bezug):
        auswahl = schnell_alle
        grund = ("kein grüner Stand bekannt" if not bezug else f"Commit des grünen Stands ({bezug['commit']}) nicht auffindbar") + ", darum alles" + nur_voll_hinweis
    elif SCHNELL:
        dateien = geaenderte_dateien(bezug)
        if not dateien:
            print(f"{GRUEN}Schnelltest: keine geänderten Dateien seit dem letzten grünen Stand.{AUS}")
            return 0
        ohne_zuordnung, betroffen = set(), set()
        for d in dateien:
            z = zustaendige(schritte, d)
            if z is None:
                ohne_zuordnung.add(d)
            else:
                betroffen |= {s["name"] for s in z}   # auch ein nur-voll-Schritt ist zuständig; er läuft nur erst im vollen Lauf
        auswahl = [s for s in schritte if (s["name"] in betroffen or s["immer"]) and not s["nur_voll"]]
        if ohne_zuordnung:
            auswahl = schnell_alle
            grund = f"geänderte Datei ohne zuständigen Schritt ({sorted(ohne_zuordnung)[0]}), darum alles" + nur_voll_hinweis
        else:
            grund = f"{len(dateien)} geänderte Datei(en), {len(auswahl)} von {len(schritte)} Schritten" + nur_voll_hinweis
        # Abhängigkeiten mitnehmen
        namen = {s["name"] for s in auswahl}
        geaendert = True
        while geaendert:
            geaendert = False
            for s in schritte:
                if s["name"] in namen:
                    for d in s["nach"]:
                        if d not in namen:
                            namen.add(d); geaendert = True
        auswahl = [s for s in schritte if s["name"] in namen]
    if not auswahl:
        print(f"{GRUEN}Nichts zu prüfen.{AUS}")
        return 0

    print(f"{FETT}Prüfkette ({modus}{', ' + grund if grund else ''}), {len(auswahl)} Schritt(e), bis zu {PARALLEL} parallel, Protokolle unter {LOGDIR}/{AUS}", flush=True)
    # Lief --schnell alle Schritte (Datei ohne Zuständigen, keine nur-voll-Schritte), ist das ein voller Lauf: Merker schreiben (Aura 2026-10-17)
    voll = not NUR and {s["name"] for s in auswahl} == {s["name"] for s in schritte}
    return lauf(auswahl, modus, baum, start, cache, voll)

def lauf(auswahl, modus, baum, start, cache, voll):
    gehalten = {}     # Sperrname -> Liste der Platz-Ordner, die dieser Lauf hält (None ohne Sperre, SPERRE_GEMEINSAM=0)
    try:
        return lauf_innen(auswahl, modus, baum, start, gehalten, cache, voll)
    finally:
        for ds in gehalten.values():
            for d in ds:
                if d:
                    shutil.rmtree(d, ignore_errors=True)

def lauf_innen(auswahl, modus, baum, start, gehalten, cache, voll):
    offen = {s["name"]: s for s in auswahl}
    fertig = {}       # name -> (ok, sekunden, grund)
    laufend = {}      # name -> (Popen, t0, schritt, logdatei, sperrordner)
    rot_gesamt = False
    # Schritt-Cache: Hash der Eingaben je Schritt, einmal zu Beginn; grüne Schritte landen im Merker, rote fliegen heraus
    gruen = {} if OHNE_GIT else gruen_lesen()
    hashes = datei_hashes() if not OHNE_GIT else {}
    eingaben = {s["name"]: schritt_hash(s, hashes) for s in auswahl} if not OHNE_GIT else {}
    uebersprungen = []
    if cache:
        for name in list(offen):
            s = offen[name]
            alt = gruen.get((name, eingaben[name]))
            if not s["immer"] and alt and cache_frisch(alt):
                fertig[name] = (True, 0.0, f"übersprungen, Eingaben unverändert seit grün um {alt[11:]}")
                uebersprungen.append(name); del offen[name]
                print(f"   {GRUEN}ok{AUS}      {name}: übersprungen, Eingaben unverändert seit grün um {alt[11:]}", flush=True)
    def merken(name, ok):
        if OHNE_GIT:
            return
        h, jetzt = eingaben[name], f"{datetime.datetime.now():%Y-%m-%d %H:%M}"
        # Grün ersetzt den Eintrag dieser Eingaben; Rot löscht alle Einträge des Schritts, auch für andere Eingaben (wie vorher:
        # nach Rot läuft der Schritt wieder, selbst wenn die alten, grünen Eingaben zurück sind).
        merker_aendern(GRUEN_DATEI, lambda zeilen: [z for z in zeilen if z[:2] != [name, h]] + [[name, h, jetzt]] if ok
                       else [z for z in zeilen if z[0] != name])
    wartet_seit = {}; gemeldet = {}   # Sperrname -> Beginn des Wartens bzw. Zeit der letzten Wartemeldung
    durchgelassen = {}; ohne_sperre = {}   # Sperrname -> Liste der Schritte, die trotz fremder Sperre laufen; Schritt -> (Sperrname, gewartete Sekunden)
    WARTEN = int(os.environ.get("SPERRE_WARTEN", "600"))
    MELDEN = max(1, int(os.environ.get("SPERRE_MELDEN", "180")))
    def freigeben(name):
        s, d = laufend[name][2], laufend[name][4]
        sp = s["schwer"]
        if not sp:
            return
        if d:
            shutil.rmtree(d, ignore_errors=True)   # nur der eigene Platz; eine durchgelassene hat keinen Ordner von uns
        # auch ohne Ordner (SPERRE_GEMEINSAM=0) austragen, sonst hielte der Lauf den Platz ewig und der nächste schwere Schritt desselben Namens hinge
        if name in durchgelassen.get(sp, []):
            durchgelassen[sp].remove(name)
            if not durchgelassen[sp]:
                del durchgelassen[sp]
        elif d in gehalten.get(sp, []):
            gehalten[sp].remove(d)
            if not gehalten[sp]:
                del gehalten[sp]
    while offen or laufend:
        # starten, was bereit ist
        for name in list(offen):
            if len(laufend) >= PARALLEL:
                break
            s = offen[name]
            if any(d in offen or d in laufend for d in s["nach"]):
                continue
            if any(not fertig.get(d, (True,))[0] for d in s["nach"] if d in fertig):
                fertig[name] = (False, 0.0, "übersprungen, Abhängigkeit rot")
                # das Protokoll des vorigen Laufs ersetzen: sonst stünde unter „Letzte Zeilen der roten Schritte“ dessen „grün“ (Aura 2026-10-16)
                with open(os.path.join(LOGDIR, f"{name}.log"), "w", encoding="utf-8") as log:
                    log.write(f"{name} ist nicht gelaufen: Abhängigkeit rot ({', '.join(d for d in s['nach'] if not fertig.get(d, (True,))[0])}).\n")
                del offen[name]; rot_gesamt = True
                print(f"   {ROT}rot{AUS}     {name}: übersprungen, Abhängigkeit rot", flush=True)
                continue
            sperrordner = None
            if s["schwer"]:
                sp, k = s["schwer"], s["plaetze"]
                if len(gehalten.get(sp, [])) + len(durchgelassen.get(sp, [])) >= k:
                    continue  # eigene schwere Schritte derselben Ressource belegen schon alle Plätze
                frei, d = sperre_versuchen(sp, name, k)
                if frei:
                    gehalten.setdefault(sp, []).append(d); wartet_seit.pop(sp, None); sperrordner = d
                else:
                    jetzt = time.time()
                    erstes = sp not in wartet_seit
                    gewartet = jetzt - wartet_seit.setdefault(sp, jetzt)
                    if gewartet < WARTEN:
                        if erstes or jetzt - gemeldet.get(sp, 0) >= MELDEN:   # gleich beim ersten Mal, danach alle MELDEN Sekunden
                            if not erstes:
                                print(f"{GELB}warte weiter auf Sperre '{sp}' für {name} seit {gewartet:.0f}s (hält: {sperre_wer(d)}); noch {WARTEN - gewartet:.0f}s, dann läuft der Schritt trotzdem.{AUS}", flush=True)
                            else:
                                tipp = " Tipp: „schwer“ ohne Ressource sperrt alle Projekte; schwer=build, schwer=browser oder schwer=simulator trennt." if sp == "pruefkette" else ""
                                wie = "nacheinander" if k == 1 else f"zu höchstens {k} gleichzeitig"
                                print(f"{GELB}warte auf Sperre '{sp}' für {name} (hält: {sperre_wer(d)}); schwere Schritte derselben Ressource laufen auf diesem Rechner {wie}, leichte laufen weiter; nach {WARTEN}s läuft der Schritt trotzdem.{tipp}{AUS}", flush=True)
                            gemeldet[sp] = jetzt
                        continue
                    # Wartezeit um: trotzdem laufen, ohne die fremde Sperre zu halten oder am Ende zu löschen; eigene Schritte derselben Sperre zählen gegen die Plätze
                    durchgelassen.setdefault(sp, []).append(name); ohne_sperre[name] = (sp, gewartet)
                    print(f"{GELB}{name}: Sperre '{sp}' nach {gewartet:.0f}s nicht frei (hält: {sperre_wer(d)}), laufe trotzdem; die Sperre schützt Laufzeit, nicht Richtigkeit.{AUS}", flush=True)
            log = open(os.path.join(LOGDIR, f"{name}.log"), "w", encoding="utf-8")
            p = subprocess.Popen(["bash", "-c", s["befehl"]], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            laufend[name] = (p, time.time(), s, log, sperrordner)
            del offen[name]
        # prüfen, was fertig ist; wartet nur noch Gesperrtes, langsamer takten
        time.sleep(0.2 if laufend else float(os.environ.get("SPERRE_TAKT", "5")))
        for name in list(laufend):
            p, t0, s, log, _ = laufend[name]
            rc = p.poll()
            dauer = time.time() - t0
            if rc is None and dauer > s["zeit"]:
                for sig in (signal.SIGTERM, signal.SIGKILL):
                    try:
                        os.killpg(p.pid, sig)
                    except (ProcessLookupError, PermissionError):
                        pass
                    time.sleep(0.5)
                try:
                    p.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    pass
                log.close(); freigeben(name); merken(name, False)
                fertig[name] = (False, dauer, f"Zeitlimit {s['zeit']}s überschritten, beendet"); rot_gesamt = True
                print(f"   {ROT}rot{AUS}     {name}: Zeitlimit {s['zeit']}s überschritten ({dauer:.0f}s)", flush=True)
                del laufend[name]
            elif rc is not None:
                log.close(); freigeben(name)
                ok = rc == 0
                grund = f"Exit {rc}" if not ok else ""
                if ok and s["mindestens"] is not None:
                    text = open(os.path.join(LOGDIR, f"{name}.log"), encoding="utf-8", errors="replace").read()
                    zahlen = [int(m) for m in re.findall(r"(\d+)\s*(?:tests?|Tests?|passed|bestanden|Fälle|cases|Proben)", text)]
                    if not zahlen or max(zahlen) < s["mindestens"]:
                        ok = False; grund = f"weniger als {s['mindestens']} ausgeführte Tests gezählt (Regel: null Tests sind ein Fehler)"
                fertig[name] = (ok, dauer, grund); merken(name, ok)
                if not ok:
                    rot_gesamt = True
                print(f"   {GRUEN+'ok'+AUS if ok else ROT+'rot'+AUS}{'  ' if ok else ' '}    {name}: {dauer:.0f}s{(' ' + grund) if grund else ''}", flush=True)
                del laufend[name]
    gesamt = time.time() - start
    # Protokoll der Zeiten; ein sechstes Feld nennt Schritte, die ohne die Sperre liefen (Schritt:Sperre:gewartete Sekunden), nur wenn es welche gab; übersprungene Schritte stehen als name=0~
    sperrfeld = ("|ohne-sperre=" + ",".join(f"{n}:{sp}:{w:.0f}s" for n, (sp, w) in ohne_sperre.items())) if ohne_sperre else ""
    sperrhinweis = f" {GELB}Ohne Sperre gelaufen (Fremdlast möglich): {', '.join(ohne_sperre)}.{AUS}" if ohne_sperre else ""
    cachehinweis = f" {len(uebersprungen)} Schritt(e) übersprungen, Eingaben unverändert (alles: --erzwingen)." if uebersprungen else ""
    with open(ZEITEN, "a", encoding="utf-8") as z:
        z.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M}|{modus}|{gesamt:.0f}|{'rot' if rot_gesamt else 'gruen'}|" +
                ",".join(f"{n}={f[1]:.0f}{'~' if n in uebersprungen else '' if f[0] else '!'}" for n, f in fertig.items()) + sperrfeld + "\n")
    if rot_gesamt:
        if not OHNE_GIT:
            stand_merken(baum, "rot")   # ein früheres Grün genau dieses Inhalts gilt nicht mehr, in keinem Worktree
        print(f"\n{ROT}Prüfkette rot ({modus}, {gesamt:.0f}s).{AUS}{sperrhinweis} Letzte Zeilen der roten Schritte:")
        for n, (ok, dauer, grund) in fertig.items():
            if ok:
                continue
            print(f"{FETT}--- {n}: {grund}{AUS}")
            try:
                zeilen = open(os.path.join(LOGDIR, f"{n}.log"), encoding="utf-8", errors="replace").read().rstrip("\n").split("\n")
                print("\n".join(zeilen[-15:]))
            except FileNotFoundError:
                pass
        return 1
    if voll and not OHNE_GIT:
        stand_merken(baum, "voll")
    hinweis = ""
    if gesamt > MAX_MIN * 60:
        hinweis = f" {GELB}Über dem Richtwert von {MAX_MIN:.0f} Minuten: Schritte teilen, parallelisieren oder in --schnell nur nach berührter Datei laufen lassen (Zeiten: {ZEITEN}).{AUS}"
        if STRENG:
            print(f"{ROT}Prüfkette rot: {gesamt:.0f}s über dem Richtwert von {MAX_MIN:.0f} Minuten (PRUEFKETTE_STRENG=1).{AUS}")
            return 1
    print(f"\n{GRUEN}Prüfkette grün ({modus}, {gesamt:.0f}s).{AUS}{cachehinweis}{sperrhinweis}{hinweis}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
