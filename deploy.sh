#!/usr/bin/env bash
# Deploy WWW/ to a Stanford AFS home directory and fix the web-server ACLs.
#
#   ./deploy.sh [sunetid] [options]
#
# The first run asks for your password and one SMS passcode. It then keeps the
# authenticated SSH session open, so later runs upload with no prompt at all.
#
#   --save            remember your SUNet ID and settings in site.conf
#   --keep <dur>      how long a cached session lives (default 8h)
#   --method <m>      duo method: sms (default), push, call, ask
#   --status          report whether a cached session is live, then exit
#   --logout          close the cached session now, then exit
#   --no-cache        ignore any cached session and authenticate again
#   --delete          wipe ~/WWW on the server before uploading
#   --fix-only        repair AFS permissions, upload nothing
#   --upload-only     skip the permission step
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/site.conf"
SRC="$HERE/WWW"
HOST="cardinal.stanford.edu"

SUNETID=""; KEEP="8h"; METHOD="sms"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

DELETE=0; DO_FIX=1; DO_UPLOAD=1; NOCACHE=0; LOGOUT=0; STATUS=0; SAVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --save)        SAVE=1 ;;
    --keep)        KEEP="${2:?--keep needs a duration}"; shift ;;
    --method)      METHOD="${2:?--method needs a value}"; shift ;;
    --status)      STATUS=1 ;;
    --logout)      LOGOUT=1 ;;
    --no-cache)    NOCACHE=1 ;;
    --delete)      DELETE=1 ;;
    --fix-only)    DO_UPLOAD=0 ;;
    --upload-only) DO_FIX=0 ;;
    -h|--help)     awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)            echo "unknown option: $1" >&2; exit 2 ;;
    *)             SUNETID="$1" ;;
  esac
  shift
done

if [ -z "$SUNETID" ]; then
  echo "error: no SUNet ID. Run ./setup.sh, or './deploy.sh <sunetid> --save' once." >&2
  exit 2
fi

# The cached session is a unix socket, not a stored password. Keep it private.
CTLDIR="$HOME/.ssh/cm"
mkdir -p "$CTLDIR"; chmod 700 "$CTLDIR"
CTL="$CTLDIR/stanford-$SUNETID.sock"
SSHO=(-o "ControlPath=$CTL")

session_live() { ssh -O check "${SSHO[@]}" "$SUNETID@$HOST" >/dev/null 2>&1; }
session_kill() { ssh -O exit "${SSHO[@]}" "$SUNETID@$HOST" >/dev/null 2>&1 || true; rm -f "$CTL"; }

if [ "$SAVE" = 1 ]; then
  umask 077
  tmp="$CONF.tmp.$$"
  { [ -f "$CONF" ] && grep -Ev '^(SUNETID|KEEP|METHOD)=' "$CONF" || true; } > "$tmp"
  printf 'SUNETID=%q\nKEEP=%q\nMETHOD=%q\n' "$SUNETID" "$KEEP" "$METHOD" >> "$tmp"
  mv "$tmp" "$CONF"
  echo "==> Saved $CONF (no password is stored; it holds your SUNet ID only)"
fi

if [ "$STATUS" = 1 ]; then
  if session_live; then echo "cached session for $SUNETID@$HOST: LIVE  ($CTL)"
  else echo "cached session for $SUNETID@$HOST: none"; fi
  exit 0
fi

if [ "$LOGOUT" = 1 ]; then
  session_kill; echo "==> Cached session closed."; exit 0
fi

if [ ! -f "$SRC/index.html" ] && [ -f "$HERE/build.py" ]; then
  echo "==> No build yet, rendering templates first"
  python3 "$HERE/build.py"
fi
[ -f "$SRC/index.html" ] || { echo "error: nothing to deploy at $SRC" >&2; exit 1; }

[ "$NOCACHE" = 1 ] && session_kill

# ---------------------------------------------------------------- connect ---
if session_live; then
  echo "==> Reusing cached session for $SUNETID (no password needed)"
else
  echo "==> Connecting to $HOST as $SUNETID"
  rm -f "$CTL"
  if command -v python3 >/dev/null && [ -x "$HERE/duossh.py" ]; then
    "$HERE/duossh.py" --control-path "$CTL" --persist "$KEEP" --method "$METHOD" "$SUNETID@$HOST"
  else
    echo "    (duossh.py unavailable, falling back to the raw ssh prompts)"
    ssh -f -N -M "${SSHO[@]}" -o "ControlPersist=$KEEP" "$SUNETID@$HOST"
  fi
  session_live || { echo "error: could not establish a session" >&2; exit 1; }
  echo "    session cached for $KEEP. Close it early with: $0 --logout"
fi

# ------------------------------------------------------------ permissions ---
if [ "$DO_FIX" = 1 ]; then
  echo "==> Checking and repairing AFS permissions"
  ssh "${SSHO[@]}" "$SUNETID@$HOST" 'bash -s' <<'REMOTE'
set -e
cd "$HOME"
# The web server must be able to LIST the parent to find WWW inside it.
fs setacl . system:anyuser l
if [ ! -d WWW ]; then echo "--- WWW missing, creating it"; mkdir WWW; fi
cd WWW
# Readable by the web servers, and by nobody else at the filesystem level.
fs setacl . system:www-servers rl
fs setacl . system:anyuser none
echo "--- WWW ACL is now:"; fs listacl .
REMOTE
fi

# ---------------------------------------------------------------- upload ----
if [ "$DO_UPLOAD" = 1 ]; then
  echo "==> Uploading $(find "$SRC" -type f | wc -l) files"
  if [ "$DELETE" = 1 ]; then
    echo "    (--delete: clearing ~/WWW on the server first)"
    ssh "${SSHO[@]}" "$SUNETID@$HOST" 'rm -rf -- "$HOME/WWW"/* 2>/dev/null || true'
  fi
  tar -C "$SRC" -cf - . | ssh "${SSHO[@]}" "$SUNETID@$HOST" 'cd "$HOME/WWW" && tar -xf - && echo "    files written"'
  # Subdirectories do not inherit an ACL set on the parent after they existed.
  ssh "${SSHO[@]}" "$SUNETID@$HOST" 'bash -s' <<'REMOTE'
set -e
cd "$HOME/WWW"
find . -type d -print0 | while IFS= read -r -d '' d; do
  fs setacl "$d" system:www-servers rl 2>/dev/null || true
  fs setacl "$d" system:anyuser none   2>/dev/null || true
done
chmod -R u+rw,a+r . 2>/dev/null || true
REMOTE
fi

# ---------------------------------------------------------------- verify ----
echo "==> Verifying https://web.stanford.edu/~$SUNETID/"
sleep 2
code=$(curl -sS -o /dev/null -w '%{http_code}' "https://web.stanford.edu/~$SUNETID/" || echo "000")
echo "    HTTP $code"
case "$code" in
  200) echo "    Live: https://web.stanford.edu/~$SUNETID/" ;;
  403) echo "    Still forbidden. Inspect with: ssh $SUNETID@$HOST 'fs listacl ~ ~/WWW'" ;;
  *)   echo "    Unexpected response. Open the URL in a browser." ;;
esac
