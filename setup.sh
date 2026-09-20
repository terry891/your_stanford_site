#!/usr/bin/env bash
# Interactive first-run setup. Asks a few questions, then builds WWW/.
#   ./setup.sh             answer the questions
#   ./setup.sh --rebuild   reuse site.conf and just rebuild WWW/
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/site.conf"
IMG="$HERE/templates/img"

bold=$'\033[1m'; dim=$'\033[2m'; red=$'\033[38;5;131m'; off=$'\033[0m'
[ -t 1 ] || { bold=""; dim=""; red=""; off=""; }

SUNETID=""; NAME=""; ROLE=""; BIO=""; EMAIL=""; STATUS=""
GITHUB=""; LINKEDIN=""; SCHOLAR=""; PHOTO_FILE=""; KEEP="8h"; METHOD="sms"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

if [ "${1:-}" = "--rebuild" ]; then
  python3 "$HERE/build.py"; exit 0
fi

ask() {                       # ask VARNAME "Prompt" "default"
  local var="$1" prompt="$2" default="${3:-}" reply=""
  if [ -n "$default" ]; then
    read -r -p "  $prompt ${dim}[$default]${off} " reply || true
    reply="${reply:-$default}"
  else
    read -r -p "  $prompt " reply || true
  fi
  printf -v "$var" '%s' "$reply"
}

url_for() {                   # url_for <base> <input>  — accepts a handle or a full URL
  case "$2" in
    "")        printf '' ;;
    http*)     printf '%s' "$2" ;;
    *)         printf '%s/%s' "$1" "${2#@}" ;;
  esac
}

printf '\n%s┌────────────────────────────────────────────┐%s\n' "$red" "$off"
printf '%s│%s  %sStanford personal site%s  ·  setup            %s│%s\n' "$red" "$off" "$bold" "$off" "$red" "$off"
printf '%s└────────────────────────────────────────────┘%s\n\n' "$red" "$off"
printf '  %sPress Enter to accept a default. Everything is editable later.%s\n\n' "$dim" "$off"

while :; do
  ask SUNETID "SUNet ID (the part before @stanford.edu)" "$SUNETID"
  SUNETID="$(printf '%s' "$SUNETID" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  [ -n "$SUNETID" ] && break
  printf '  %sA SUNet ID is required.%s\n' "$red" "$off"
done

ask NAME   "Your full name"                    "${NAME:-}"
ask ROLE   "One-line headline"                 "${ROLE:-CS undergraduate, Class of 2030}"
ask BIO    "A sentence about you"              "${BIO:-I build systems, and I am happiest when something that used to be slow suddenly is not.}"
ask EMAIL  "Contact email"                     "${EMAIL:-$SUNETID@stanford.edu}"
ask STATUS "Status badge"                      "${STATUS:-Open to research and internships}"

printf '\n  %sLinks — leave blank to hide the icon.%s\n' "$dim" "$off"
ask GH_IN "GitHub username or URL"   "$GITHUB"
ask LI_IN "LinkedIn username or URL" "$LINKEDIN"
ask GS_IN "Google Scholar URL"       "$SCHOLAR"
GITHUB="$(url_for https://github.com "$GH_IN")"
LINKEDIN="$(url_for https://www.linkedin.com/in "$LI_IN")"
SCHOLAR="$(url_for https://scholar.google.com/citations?user= "$GS_IN")"

printf '\n  %sPhoto — a path to a JPG or PNG. Blank keeps the monogram.%s\n' "$dim" "$off"
ask PHOTO_IN "Path to your photo" ""
PHOTO_IN="${PHOTO_IN/#\~/$HOME}"
if [ -n "$PHOTO_IN" ]; then
  if [ ! -f "$PHOTO_IN" ]; then
    printf '  %sNo file at %s — keeping the monogram.%s\n' "$red" "$PHOTO_IN" "$off"
    PHOTO_FILE=""
  else
    mkdir -p "$IMG"
    if python3 - "$PHOTO_IN" "$IMG/portrait.jpg" <<'PYEOF'
import sys
try:
    from PIL import Image, ImageOps
except ImportError:
    sys.exit(3)
src, dst = sys.argv[1], sys.argv[2]
im = ImageOps.exif_transpose(Image.open(src))
im = ImageOps.fit(im.convert("RGB"), (640, 640), Image.LANCZOS, centering=(0.5, 0.4))
im.save(dst, "JPEG", quality=86, optimize=True, progressive=True)
print("    cropped to a 640x640 square, %.0f KB" % (__import__("os").path.getsize(dst) / 1024))
PYEOF
    then
      PHOTO_FILE="portrait.jpg"
    else
      cp "$PHOTO_IN" "$IMG/portrait.${PHOTO_IN##*.}"
      PHOTO_FILE="portrait.${PHOTO_IN##*.}"
      printf '  %sPillow not installed, copied the file unchanged.%s\n' "$dim" "$off"
    fi
  fi
fi

umask 077
cat > "$CONF" <<EOF
# Answers from ./setup.sh. Edit freely, then run ./setup.sh --rebuild
$(printf 'SUNETID=%q\n'    "$SUNETID")
$(printf 'NAME=%q\n'       "$NAME")
$(printf 'ROLE=%q\n'       "$ROLE")
$(printf 'BIO=%q\n'        "$BIO")
$(printf 'EMAIL=%q\n'      "$EMAIL")
$(printf 'STATUS=%q\n'     "$STATUS")
$(printf 'GITHUB=%q\n'     "$GITHUB")
$(printf 'LINKEDIN=%q\n'   "$LINKEDIN")
$(printf 'SCHOLAR=%q\n'    "$SCHOLAR")
$(printf 'PHOTO_FILE=%q\n' "$PHOTO_FILE")
$(printf 'KEEP=%q\n'       "$KEEP")
$(printf 'METHOD=%q\n'     "$METHOD")
EOF

printf '\n'
python3 "$HERE/build.py"

printf '\n  %sNext%s\n' "$bold" "$off"
printf '    Preview    %scd WWW && python3 -m http.server 8000%s\n' "$dim" "$off"
printf '    Publish    %s./deploy.sh%s\n' "$dim" "$off"
printf '    Re-edit    %s./setup.sh%s   (or edit site.conf, then ./setup.sh --rebuild)\n\n' "$dim" "$off"
