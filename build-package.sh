#!/bin/bash
# Build the shippable packages: a .dmg for macOS, a .zip for Windows.
#
# Both wrap the SAME thing — steelblue_install.lua, which runs inside REAPER.
# The wrapper is only a delivery format. An external installer (a .exe, a .pkg)
# cannot do the actual job: REAPER's AddRemoveReaScript only exists in-process,
# so nothing outside REAPER can register the actions or open the shortcut
# dialog. Tobi's own 2025 Windows installer proves the point — it bundled
# ReaPack, SWS and js_ReaScriptAPI, and its readme still had to end with "now
# open the Action List and Load ReaScript by hand". That step is exactly what
# the Lua installer removes, so wrapping it in an .exe would only add an
# unsigned-binary warning and take nothing away.
#
# Usage:
#   ./build-package.sh [mac|win|all]              branded (default: all)
#   ./build-package.sh [mac|win|all] --neutral    the neutral "LD Tools" build
#       Every release MUST ship LD-Tools-macOS.dmg and LD-Tools-Windows.zip
#       under exactly these names: reaperldtools.appcrow.at links to
#       releases/latest/download/<name> (since v2.1.0, 2026-10-23).
#   ./build-package.sh stage-neutral <dir> [macOS|Windows]
#                                                 neutral payload into <dir>,
#                                                 no dmg/zip, no PDFs (tests)
#   ./build-package.sh debrand <dir>              debrand a tree in place, then
#                                                 run the gate (tests)
#
# Branded:  dist/steelblue-LD-Plugin-Set-macOS.dmg, -Windows.zip
# Neutral:  dist/LD-Tools-macOS.dmg (volume "LD Tools"), dist/LD-Tools-Windows.zip
#
# The neutral build is ONE source, two products: there is no second copy of
# any script in the repo. It stages the branded payload exactly as below and
# then runs debrand() over the staged copy — renames files, rewrites the one
# SB.BRAND line in the theme, replaces the brand words in every text file —
# and a gate that fails the build if "steelblue" survives anywhere or a .lua
# no longer compiles. What the neutral build leaves out, and why:
#   Tutorials/mark.svg   the logo itself
#   Tutorials/video/     the tutorial video shows the branded windows
#   Guides (PDF)/        the branded PDFs; re-rendered from the debranded HTML
#                        when Google Chrome is installed, omitted otherwise
# The screenshots in Tutorials/img/ are pixels, so debrand() swaps them
# instead of translating them: the seven that show the branded header are
# removed, five figures are re-pointed at the neutral docked shots Tobi took
# (ld-*.png — they live in the repo next to the branded ones and ship in both
# builds), and the three figures showing a large view (the numbering wrap, the
# BPM window, the ">>>" popup) are cut out of the guides: the neutral guides
# show only the docked band (Tobi, 2026-10-24). See IMG_* in debrand().
#
# Both products can be installed side by side: the neutral installer uses
# Scripts/ld-tools/, the action "LD Tools" and ld_* ExtState sections.
#
# What deliberately does NOT ship: tests/, AGENTS.md, .git, build scripts,
# Tutorials/video/work/. Those are how the package is made, not what it is.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Branded product
NAME="steelblue LD Plugin Set"                      # root folder, volume name
INNER="steelblue Plugin Set"                        # payload folder inside it
INSTALLER="steelblue_install.lua"
TITLE="steelblue studios — REAPER LD Plugin Set"

# Neutral product: what debrand() turns the names above into
NEUTRAL_NAME="LD Tools"
NEUTRAL_INNER="LD Tools"
NEUTRAL_INSTALLER="ld_install.lua"
NEUTRAL_TITLE="LD Tools — REAPER LD Plugin Set"
NEUTRAL_BRAND='SB.BRAND = { word = "LD Tools", sub = "", sub_bar = "", mark = false }'

CHROME="${BUILD_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"   # BUILD_CHROME: tests/pdf_render_test.lua

die() { echo "build-package.sh: $*" >&2; exit 1; }

usage() {
  echo "usage: $0 [mac|win|all] [--neutral]" >&2
  echo "       $0 stage-neutral <dir> [macOS|Windows]" >&2
  echo "       $0 debrand <dir>" >&2
  echo "       $0 render-pdfs <dir>   (<dir>/Tutorials/*.html -> <dir>/Guides (PDF)/)" >&2
  exit 2
}

# --- staging, shared by both platforms ---------------------------------------
# $1 = root dir to fill, $2 = "macOS" | "Windows" (which extensions/ to include)

stage_payload() {
  local root="$1" platform="$2"
  local inner="$root/$INNER"
  mkdir -p "$inner"

  cp "$REPO/steelblue_install.lua"              "$inner/"
  cp "$REPO/steelblue_ui.lua"                   "$inner/"
  cp "$REPO/steelblue_markers.lua"              "$inner/"
  cp "$REPO/steelblue_boot.lua"                 "$inner/"
  cp "$REPO/steelblue_matools.lua"              "$inner/"
  cp "$REPO/steelblue_rename.lua"               "$inner/"
  cp "$REPO/steelblue_midi.lua"                 "$inner/"
  cp "$REPO/steelblue_copy.lua"                 "$inner/"
  cp "$REPO/steelblue_bpm.lua"                  "$inner/"
  cp "$REPO/Live BPM Analyzer.lua"              "$inner/"
  cp "$REPO/MIDI notes to project markers.lua"  "$inner/"
  cp "$REPO/Rename selected markers.lua"        "$inner/"
  cp "$REPO/CopyMarkers.lua"                    "$inner/"
  cp "$REPO/steelblue_workspace.lua"            "$inner/"

  cp -R "$REPO/Tutorials" "$inner/Tutorials"
  rm -rf "$inner/Tutorials/pdf"            # the HTML guides are the on-screen ones
  rm -rf "$inner/Tutorials/video/work"     # slide/clip intermediates, rebuildable
  cp -R "$REPO/Demo Project" "$inner/Demo Project"
  rm -rf "$inner/Demo Project/peaks"

  mkdir -p "$inner/Guides (PDF)"
  cp "$REPO/Tutorials/pdf/"*.pdf "$inner/Guides (PDF)/"

  # Only this platform's binaries: shipping the other one's would double the
  # download for something the installer would never look at.
  mkdir -p "$inner/extensions/$platform"
  cp "$REPO/extensions/$platform/"* "$inner/extensions/$platform/"
  cp "$REPO/extensions/NOTICE.txt" "$REPO/extensions/LICENSE-"*.txt "$inner/extensions/"

  # The installer also sits at the top, next to the note: it is the one thing
  # people need to find. It resolves the payload one folder down by itself.
  cp "$REPO/steelblue_install.lua" "$root/"
}

# --- the note people actually read -------------------------------------------
# $1 = root dir, $2 = "mac" | "win", $3 = title, $4 = installer file name,
# $5 = payload folder name. The "Guides (PDF)/" line only appears when that
# folder was staged (a neutral build without Chrome has none).

write_readme() {
  local root="$1" flavour="$2" title="$3" installer="$4" inner="$5"
  local wrapper builds discard underline guides=""

  if [ "$flavour" = mac ]; then
    wrapper="disk image"
    builds="macOS (Apple Silicon and Intel)"
    discard="eject and delete this disk image"
  else
    wrapper="folder"
    builds="Windows (64-bit and 32-bit)"
    discard="delete this folder"
  fi

  # as many "=" as the title has characters (not bytes: the dash is UTF-8)
  underline="$(printf '%s' "$title" | perl -CS -ne 'print "=" x length')"
  if [ -d "$root/$inner/Guides (PDF)" ]; then
    guides="   Guides (PDF)/           the same guides for printing or mailing
"
  fi

  cat > "$root/READ ME FIRST.txt" <<TXT
$title
$underline

Four tools for cue programming in REAPER:

   Live BPM Analyzer                reads the real tempo out of the audio
   MIDI notes to project markers    turns MIDI notes into markers
   Rename selected markers          builds MA-Tools cue names in bulk
   Copy Markers                     copies a block of markers elsewhere


HOW TO INSTALL — one step
-------------------------

In REAPER:

   Actions  >  Show Action List  >  New action...  >  Load ReaScript...

Pick  $installer  — it is right here next to this note.

That is it. The installer copies the plugins into REAPER's own Scripts
folder, registers all four as actions, and lets you assign a keyboard
shortcut to each. Afterwards you can $discard —
REAPER will not need it again.


TWO EXTENSIONS ARE NEEDED — AND THEY ARE INCLUDED
-------------------------------------------------

   ReaImGui          needed by all four plugins.
   js_ReaScriptAPI   needed by "Rename selected markers" to read the order
                     of your selection. Without it the cue numbering
                     silently follows plain timeline order instead.

Neither ships with REAPER, so both are bundled here for $builds.
The installer picks the right build for your machine and offers to
install it — nothing is downloaded.

If you already have one of them, the installer leaves it strictly alone.
It never overwrites or downgrades what you have; if you manage extensions
through ReaPack, ReaPack stays in charge.

They are the authors' own unmodified builds, shipped under their own
licences. See  $inner/extensions/NOTICE.txt  for versions,
licences and where the source lives.

REAPER loads extensions only when it starts. If the installer places one,
it will offer to quit REAPER for you — open it again and everything is
there.


THE ONE THING EVERYBODY TRIPS OVER
----------------------------------

Before starting a marker plugin from a shortcut, click once into the
arrange view. While the Region/Marker Manager has keyboard focus it
swallows the shortcut: the window never appears, and your marker
selection gets cleared as well.


WHAT IS IN THE $(echo "$wrapper" | tr '[:lower:]' '[:upper:]')
---------------$(echo "$wrapper" | sed 's/./-/g')

   $(printf '%-24s' "$installer")the installer — start here
   Tutorials/              one guide per plugin, open index.html
${guides}   Demo Project/           a small REAPER project to practise on:
                           a beat at exactly 128 BPM, a MIDI item,
                           and named markers
TXT
}

# --- the neutral build: debrand a staged tree ---------------------------------
# Works on any tree, and running it twice changes nothing the second time.
# tests/neutral_build_test.lua relies on both: it debrands a staged payload
# with a copy of tests/ inside it, and runs those suites there.

debrand() {
  local dir="$1"
  [ -d "$dir" ] || die "debrand: no such directory: $dir"

  # Text substitutions, applied in this order to every line, most specific
  # first: once "steelblue_" or the bare word has been replaced, the longer
  # phrases could no longer be found.
  local -a MAP=(
    "steelblue LD Tools — steelblue studios" "LD Tools"
    "steelblue studios — steelblue LD Tools" "LD Tools"
    "the steelblue LD Plugin Set"            "LD Tools"
    "steelblue LD Tools"                     "LD Tools"
    "steelblue LD Plugin Set"                "LD Tools"
    "steelblue Plugin Set"                   "LD Tools"
    "steelblue studios"                      "LD Tools"
    "steelblue package"                      "LD Tools package"
    'INSTALL_SUBFOLDER = "steelblue"'        'INSTALL_SUBFOLDER = "ld-tools"'
    "steelblue.css"                          "ld.css"
    "steelblue-ld-tools.html"                "ld-tools.html"
    "<b>steelblue</b><span>STUDIOS</span>"   "<b>LD Tools</b>"
    "steelblue_"                             "ld_"
    "Steelblue"                              "LD Tools"
    "steelblue"                              "LD Tools"
  )
  # Plus: every line mentioning mark.svg is dropped (the <img> of the logo).

  # 1. file and folder names, deepest first so a parent's rename never
  #    invalidates a path still in the list
  local path base new
  while IFS= read -r -d '' path; do
    base="$(basename "$path")"
    new="${base//steelblue Plugin Set/LD Tools}"
    new="${new//steelblue-ld-tools.html/ld-tools.html}"
    new="${new//steelblue.css/ld.css}"
    new="${new//steelblue_/ld_}"
    [ "$new" = "$base" ] && continue
    [ -e "$(dirname "$path")/$new" ] && die "debrand: $new already exists next to $path"
    mv "$path" "$(dirname "$path")/$new"
  done < <(find "$dir" -depth -name '*steelblue*' -print0)

  # removals: the logo, the branded video, the branded PDFs
  find "$dir" -type f -path '*/Tutorials/mark.svg' -exec rm -f {} +
  find "$dir" -type d -path '*/Tutorials/video' -prune -exec rm -rf {} +
  find "$dir" -type d -name 'Guides (PDF)' -prune -exec rm -rf {} +

  # 1b. the screenshots. Seven PNGs show the branded header band. Where a
  #     neutral twin exists (Tobi's docked "LD Tools" shots, 2026-10-22) the
  #     figure points at that; the stand-alone windows and the ">>>" popup are
  #     cut out of the guides (Tobi's decision, 2026-10-24: the neutral guides
  #     show only the docked band); the eight files are removed so nothing can
  #     show them. Three
  #     captions described the stand-alone window and no longer fit the
  #     docked shot, so they are reworded. Runs clean a second time: nothing
  #     is left to match.
  local -a IMG_MAP=(
    "img/workspace-01-rename.png"  "img/ld-workspace-01-rename.png"
    "img/workspace-02-copy.png"    "img/ld-workspace-02-copy.png"
    "img/rename-03-window.png"     "img/ld-workspace-01-rename.png"
    "img/copy-03-window.png"       "img/ld-workspace-02-copy.png"
    "img/midi-03-window.png"       "img/ld-midi-03-window.png"
  )
  local -a IMG_DROP=("img/rename-04-numbering.png" "img/bpm-03-window.png" "img/workspace-03-bpm.png")
  local -a CAPTION_MAP=(
    "Preview at the top, <strong>Legend</strong> beside it, then the fields."
    "The fields first, then the preview with <strong>Legend</strong> beside it."
    "The list is the selection. The count under it says how many are ticked."
    "The list is the selection. Under it sit <strong>Use selection</strong>, <strong>Clear selection</strong> and the count of ticked markers — cut off here by the docker's tab bar."
    "The example line under the switch previews the naming, and the count at the bottom tells you what you are about to convert."
    "The example beside the switch previews the naming, and the count beside the buttons tells you what you are about to convert."
  )
  local img_text="" drop_text=""
  for ((i = 0; i < ${#IMG_MAP[@]}; i += 2)); do
    img_text+="${IMG_MAP[i]}"$'\t'"${IMG_MAP[i + 1]}"$'\n'
  done
  for ((i = 0; i < ${#CAPTION_MAP[@]}; i += 2)); do
    img_text+="${CAPTION_MAP[i]}"$'\t'"${CAPTION_MAP[i + 1]}"$'\n'
  done
  for path in "${IMG_DROP[@]}"; do drop_text+="$path"$'\n'; done
  local -a guides=()
  while IFS= read -r -d '' path; do guides+=("$path"); done < <(
    find "$dir" -type f -path '*/Tutorials/*.html' -print0)
  if [ ${#guides[@]} -gt 0 ]; then
    DEBRAND_IMG="$img_text" DEBRAND_DROP="$drop_text" perl -0777 -i -pe '
      BEGIN {
        @map  = map { [ split /\t/, $_, 2 ] } split /\n/, $ENV{DEBRAND_IMG};
        @drop = grep { length } split /\n/, $ENV{DEBRAND_DROP};
      }
      for my $d (@drop) { s{<figure>\s*<img src="\Q$d\E"[^>]*>.*?</figure>\s*\n}{}gs }
      for my $m (@map) { s/\Q$m->[0]\E/$m->[1]/g }
    ' "${guides[@]}"
  fi
  local -a branded_png=()
  for ((i = 0; i < ${#IMG_MAP[@]}; i += 2)); do branded_png+=("${IMG_MAP[i]#img/}"); done
  for path in "${IMG_DROP[@]}"; do branded_png+=("${path#img/}"); done
  for base in "${branded_png[@]}"; do
    find "$dir" -type f -path "*/Tutorials/img/$base" -exec rm -f {} +
  done

  # 2. the brand table in the theme: anchored, and exactly once per file —
  #    a reformatted or duplicated line must fail here, not ship half-branded
  local ui count found=0
  while IFS= read -r -d '' ui; do
    count="$(grep -c '^SB\.BRAND = ' "$ui" || true)"
    [ "$count" = 1 ] || die "debrand: expected exactly one line starting 'SB.BRAND = ' in $ui, found $count"
    NEUTRAL_BRAND="$NEUTRAL_BRAND" perl -pi -e 's/^SB\.BRAND = .*$/$ENV{NEUTRAL_BRAND}/' "$ui"
    found=$((found + 1))
  done < <(find "$dir" -type f -name 'ld_ui.lua' -print0)
  [ "$found" -ge 1 ] || die "debrand: no ld_ui.lua under $dir"

  # 3. the substitutions. One perl pass over all files; it also re-fits a
  #    text underline (==== / ----) whose heading changed length, but only
  #    one that matched its heading before.
  local map_text="" i
  for ((i = 0; i < ${#MAP[@]}; i += 2)); do
    map_text+="${MAP[i]}"$'\t'"${MAP[i + 1]}"$'\n'
  done
  local -a files=()
  while IFS= read -r -d '' path; do files+=("$path"); done < <(
    find "$dir" -type f \( -name '*.lua' -o -name '*.html' -o -name '*.css' \
      -o -name '*.txt' -o -name '*.md' -o -iname '*.rpp' -o -iname '*.rpp-bak' \
      -o -name '*.sh' \) -print0)
  if [ ${#files[@]} -gt 0 ]; then
    DEBRAND_MAP="$map_text" perl -n -i -e '
      BEGIN { @map = map { [ split /\t/, $_, 2 ] } split /\n/, $ENV{DEBRAND_MAP} }
      sub clen { my $s = shift; utf8::decode($s); length $s }
      if (!defined $file || $file ne $ARGV) { $file = $ARGV; undef $po; undef $pn }
      next if /mark\.svg/;
      my $orig = $_;
      for my $m (@map) { s/\Q$m->[0]\E/$m->[1]/g }   # not "for @map": that aliases $_
      if (defined $po && /^(([=-])\2{2,})(\r?\n?)\z/) {
        my ($ul, $c, $eol) = ($1, $2, $3);
        $_ = ($c x clen($pn)) . $eol
          if clen($po) == length($ul) && clen($pn) != length($ul) && $pn =~ /\S/;
      }
      print;
      ($po = $orig) =~ s/\r?\n?\z//;
      ($pn = $_) =~ s/\r?\n?\z//;
    ' "${files[@]}"
  fi

  gate "$dir"
}

# The gate: run after every debrand, not behind a flag. Fails the build with
# the offending paths if "steelblue" survives in any file's content or name,
# or if a .lua no longer compiles. Only binaries and media are exempt (a .png
# cannot be grepped for meaning; the extension binaries are not ours). The
# extensions' NOTICE.txt IS ours and is checked.

gate() {
  local dir="$1" hits names path bad=0
  hits="$(grep -ril --exclude='*.png' --exclude='*.wav' --exclude='*.mp4' \
    --exclude='*.pdf' --exclude='*.dylib' --exclude='*.dll' steelblue "$dir" || true)"
  names="$(find "$dir" -iname '*steelblue*' || true)"
  if [ -n "$hits" ]; then
    echo "gate: these files still say steelblue:" >&2
    echo "$hits" | sed 's/^/   /' >&2
    bad=1
  fi
  if [ -n "$names" ]; then
    echo "gate: these names still say steelblue:" >&2
    echo "$names" | sed 's/^/   /' >&2
    bad=1
  fi
  while IFS= read -r -d '' path; do
    if ! luac -p "$path" >&2; then
      echo "gate: does not compile: $path" >&2
      bad=1
    fi
  done < <(find "$dir" -type f -name '*.lua' -print0)
  # every picture a guide shows must be in the package (the screenshot swap
  # in debrand() is the one place that can break this)
  local guide src
  while IFS= read -r -d '' guide; do
    while IFS= read -r src; do
      if [ ! -f "$(dirname "$guide")/$src" ]; then
        echo "gate: $guide shows a picture that is not there: $src" >&2
        bad=1
      fi
    done < <(grep -o '<img src="[^"]*"' "$guide" | sed 's/^<img src="//; s/"$//')
  done < <(find "$dir" -type f -path '*/Tutorials/*.html' -print0)
  [ "$bad" = 0 ] || die "gate failed for $dir"
}

# --- neutral PDFs: rendered from the debranded HTML, never copied -------------
# The same command as Tutorials/pdf/HOW-TO-RENDER.md, plus a throwaway Chrome
# profile so the build never touches the user's own. No Chrome: no PDFs, and
# one line saying so — shipping the branded ones instead is not an option.

# One page, one PDF. Chrome prints "N bytes written to file" once the PDF is
# complete, but under load its shutdown can overrun its own teardown watchdog
# ("Teardown watchdog expired"), which kills it with exit 2 after the file is
# done (2026-10-28: 12 of 180 calls with three Chromes in parallel, every PDF
# complete). So the file and that line decide, not the exit code. A render
# without them is tried again with a fresh profile, three times, and then the
# build stops with Chrome's own last lines.

render_one() {
  local page="$1" out="$2" try profile log rc
  log="$(mktemp)"
  for try in 1 2 3; do
    rm -f "$out"
    profile="$(mktemp -d)"
    rc=0
    "$CHROME" --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
      --user-data-dir="$profile" --print-to-pdf="$out" "file://${page// /%20}" \
      >"$log" 2>&1 || rc=$?
    rm -rf "$profile"
    if [ -s "$out" ] && grep -q "bytes written to file" "$log"; then
      [ "$rc" = 0 ] || echo "note: Chrome exited $rc after writing $(basename "$out"), PDF kept" >&2
      rm -f "$log"
      return 0
    fi
    echo "warning: Chrome did not render $(basename "$page") (exit $rc, try $try of 3)" >&2
  done
  echo "--- last lines of Chrome's output:" >&2
  tail -n 15 "$log" >&2
  rm -f "$log"
  die "Chrome failed to render $page"
}

render_pdfs() {
  local inner="$1" page out n_html=0 n_pdf=0
  if [ ! -x "$CHROME" ]; then
    echo "warning: Google Chrome not found, the neutral package ships without Guides (PDF)/" >&2
    return 0
  fi
  mkdir -p "$inner/Guides (PDF)"
  for page in "$inner/Tutorials/"*.html; do
    out="$inner/Guides (PDF)/$(basename "$page" .html).pdf"
    render_one "$page" "$out"
    n_html=$((n_html + 1))
    [ -s "$out" ] && n_pdf=$((n_pdf + 1))
  done
  [ "$n_pdf" = "$n_html" ] || die "rendered $n_pdf of $n_html PDFs"
}

# $1 = root dir, $2 = "macOS" | "Windows", $3 = "pdf" to render the guides

stage_neutral() {
  local root="$1" platform="$2" pdf="${3:-}" flavour=mac
  [ "$platform" = Windows ] && flavour=win
  mkdir -p "$root"
  stage_payload "$root" "$platform"
  debrand "$root"
  if [ "$pdf" = pdf ]; then render_pdfs "$root/$NEUTRAL_INNER"; fi
  write_readme "$root" "$flavour" "$NEUTRAL_TITLE" "$NEUTRAL_INSTALLER" "$NEUTRAL_INNER"
  gate "$root"     # once more: the note was written after the first gate
}

# --- macOS: disk image --------------------------------------------------------
# $1 = "branded" | "neutral"

build_mac() {
  local kind="$1" tmp root dmg name
  tmp="$(mktemp -d)"
  if [ "$kind" = neutral ]; then
    name="$NEUTRAL_NAME"
    dmg="$REPO/dist/LD-Tools-macOS.dmg"
  else
    name="$NAME"
    dmg="$REPO/dist/steelblue-LD-Plugin-Set-macOS.dmg"
  fi
  root="$tmp/$name"
  mkdir -p "$root"

  if [ "$kind" = neutral ]; then
    stage_neutral "$root" "macOS" pdf
  else
    stage_payload "$root" "macOS"
    write_readme "$root" mac "$TITLE" "$INSTALLER" "$INNER"
  fi

  rm -f "$dmg"
  hdiutil create -volname "$name" -srcfolder "$root" -ov -format UDZO -quiet "$dmg"
  rm -rf "$tmp"

  echo "built: $dmg"
  echo "  $(du -h "$dmg" | cut -f1)"
}

# --- Windows: zip -------------------------------------------------------------

build_win() {
  local kind="$1" tmp root zip name
  tmp="$(mktemp -d)"
  if [ "$kind" = neutral ]; then
    name="$NEUTRAL_NAME"
    zip="$REPO/dist/LD-Tools-Windows.zip"
  else
    name="$NAME"
    zip="$REPO/dist/steelblue-LD-Plugin-Set-Windows.zip"
  fi
  root="$tmp/$name"
  mkdir -p "$root"

  if [ "$kind" = neutral ]; then
    stage_neutral "$root" "Windows" pdf
  else
    stage_payload "$root" "Windows"
    write_readme "$root" win "$TITLE" "$INSTALLER" "$INNER"
  fi

  rm -f "$zip"
  # -X drops the resource forks and .DS_Store noise that macOS zip otherwise
  # buries in the archive, where they would show up as junk on a Windows PC.
  ( cd "$tmp" && zip -q -r -X "$zip" "$name" -x '*.DS_Store' )
  rm -rf "$tmp"

  echo "built: $zip"
  echo "  $(du -h "$zip" | cut -f1)"
}

# --- command line ---------------------------------------------------------------

case "${1:-}" in
  stage-neutral)
    { [ $# -ge 2 ] && [ $# -le 3 ]; } || usage
    case "${3:-macOS}" in macOS|Windows) ;; *) usage ;; esac
    stage_neutral "$2" "${3:-macOS}"
    echo "staged (neutral): $2"
    exit 0
    ;;
  debrand)
    [ $# -eq 2 ] || usage
    debrand "$2"
    echo "debranded: $2"
    exit 0
    ;;
  render-pdfs)
    [ $# -eq 2 ] || usage
    render_pdfs "$2"
    echo "rendered: $2"
    exit 0
    ;;
esac

WHAT="all"
KIND="branded"
for arg in "$@"; do
  case "$arg" in
    mac|win|all) WHAT="$arg" ;;
    --neutral)   KIND="neutral" ;;
    *)           usage ;;
  esac
done

mkdir -p "$REPO/dist"

case "$WHAT" in
  mac) build_mac "$KIND" ;;
  win) build_win "$KIND" ;;
  all) build_mac "$KIND"; build_win "$KIND" ;;
esac
