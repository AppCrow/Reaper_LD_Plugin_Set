#!/bin/bash
# reaperldtools.appcrow.at bauen, prüfen und hochladen. Die Arbeit macht das Werkzeug-Repo
# AppCrow/appcrow_webtool, ausgecheckt neben diesem Repo; welche Version, steht
# in website.conf.
#
#   ./scripts/website/veroeffentlichen.sh               Trockenlauf: zeigt, was hochginge
#   ./scripts/website/veroeffentlichen.sh --ausfuehren  lädt wirklich hoch
#   ./scripts/website/veroeffentlichen.sh --nur-bauen   nur website/_bau/ für die Vorschau
set -euo pipefail
WURZEL="$(cd "$(dirname "$0")/../.." && pwd)"
WERKZEUG="${WEB_WERKZEUG:-$(dirname "$WURZEL")/appcrow_webtool}"
[ -f "$WERKZEUG/veroeffentlichen.py" ] || {
    echo "Werkzeug fehlt: $WERKZEUG (git clone https://github.com/AppCrow/appcrow_webtool neben dieses Repo)" >&2
    exit 1
}
exec python3 "$WERKZEUG/veroeffentlichen.py" "$WURZEL" "$@"
