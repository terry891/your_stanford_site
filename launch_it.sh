#!/usr/bin/env bash
# launch_it.sh — set up and publish your Stanford personal site with one command.
#
#   ./launch_it.sh          first run asks the questions, then publishes.
#                           every run after that just publishes.
#
#   --edit          re-answer the site questions (name, links, photo)
#   --rebuild       rebuild WWW/ and stop, publish nothing
#   --status        show what is remembered, then stop
#   --forget        erase everything remembered, then stop
#   --delete        wipe ~/WWW on the server before uploading
#   --fix-only      repair the AFS permissions, upload nothing
#   --upload-only   skip the permission step
#   --logout        close the cached session, keep what is remembered
#   --no-cache      ignore the cached session and authenticate again
#   --method <m>    duo method: sms (default), push, call, ask
#   --keep <dur>    how long a cached session lives (default 8h)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/site.conf"
SRC="$HERE/WWW"
IMG="$HERE/templates/img"
HOST="cardinal.stanford.edu"
KEYFILE="$HOME/.ssh/id_ed25519_stanford"
KRSERVICE="stanford-afs"

bold=$'\033[1m'; dim=$'\033[2m'; red=$'\033[38;5;131m'; grn=$'\033[38;5;65m'; off=$'\033[0m'
[ -t 1 ] || { bold=""; dim=""; red=""; grn=""; off=""; }

say()  { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
ok()   { printf '    %s%s%s\n' "$grn" "$*" "$off"; }
warn() { printf '    %s%s%s\n' "$red" "$*" "$off"; }

SUNETID=""; NAME=""; ROLE=""; BIO=""; EMAIL=""; STATUS=""
GITHUB=""; LINKEDIN=""; SCHOLAR=""; PHOTO_FILE=""; KEEP="8h"; METHOD="sms"; REMEMBER=""
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

EDIT=0; REBUILD=0; SHOW=0; FORGET=0; DELETE=0; DO_FIX=1; DO_UPLOAD=1; NOCACHE=0; LOGOUT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --edit)        EDIT=1 ;;
    --rebuild)     REBUILD=1 ;;
    --status)      SHOW=1 ;;
    --forget)      FORGET=1 ;;
    --delete)      DELETE=1 ;;
    --fix-only)    DO_UPLOAD=0 ;;
    --upload-only) DO_FIX=0 ;;
    --logout)      LOGOUT=1 ;;
    --no-cache)    NOCACHE=1 ;;
    --method)      METHOD="${2:?--method needs a value}"; shift ;;
    --keep)        KEEP="${2:?--keep needs a duration}"; shift ;;
    -h|--help)     awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)            echo "unknown option: $1" >&2; exit 2 ;;
    *)             SUNETID="$1" ;;
  esac
  shift
done

CTLDIR="$HOME/.ssh/cm"; mkdir -p "$CTLDIR"; chmod 700 "$CTLDIR"
ctl_path()     { printf '%s/stanford-%s.sock' "$CTLDIR" "$SUNETID"; }
session_live() { ssh -O check -o "ControlPath=$(ctl_path)" "$SUNETID@$HOST" >/dev/null 2>&1; }
session_kill() { ssh -O exit -o "ControlPath=$(ctl_path)" "$SUNETID@$HOST" >/dev/null 2>&1 || true
                 rm -f "$(ctl_path)"; }
on_master()    { ssh -o "ControlPath=$(ctl_path)" "$SUNETID@$HOST" "$@"; }

# ------------------------------------------------------------- the keyring ---
# The password, if it is kept at all, lives in the OS keyring. Never in a file.
kr_backend() {
  if command -v secret-tool >/dev/null 2>&1;                          then echo secret-tool
  elif [ "$(uname)" = Darwin ] && command -v security >/dev/null 2>&1; then echo keychain
  else echo none; fi
}
kr_set() {                                   # password arrives on stdin
  case "$(kr_backend)" in
    secret-tool) secret-tool store --label="Stanford SUNet ($SUNETID)" \
                   service "$KRSERVICE" account "$SUNETID" ;;
    keychain)    security add-generic-password -U -a "$SUNETID" -s "$KRSERVICE" -w "$(cat)" ;;
    *)           return 1 ;;
  esac
}
kr_get() {
  case "$(kr_backend)" in
    secret-tool) secret-tool lookup service "$KRSERVICE" account "$SUNETID" 2>/dev/null ;;
    keychain)    security find-generic-password -a "$SUNETID" -s "$KRSERVICE" -w 2>/dev/null ;;
    *)           return 1 ;;
  esac
}
kr_del() {
  case "$(kr_backend)" in
    secret-tool) secret-tool clear service "$KRSERVICE" account "$SUNETID" 2>/dev/null || true ;;
    keychain)    security delete-generic-password -a "$SUNETID" -s "$KRSERVICE" >/dev/null 2>&1 || true ;;
  esac
}

save_conf() {
  umask 077
  cat > "$CONF" <<EOF
# Answers from ./launch_it.sh. Edit freely, then ./launch_it.sh --rebuild
# No password is stored here. See --status for what is remembered where.
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
$(printf 'REMEMBER=%q\n'   "$REMEMBER")
EOF
}

# --------------------------------------------------------------- questions ---
ask() {                                      # ask VARNAME "Prompt" "default"
  local var="$1" prompt="$2" default="${3:-}" reply=""
  if [ -n "$default" ]; then
    read -r -p "  $prompt ${dim}[$default]${off} " reply || true
    reply="${reply:-$default}"
  else
    read -r -p "  $prompt " reply || true
  fi
  printf -v "$var" '%s' "$reply"
}
yes_no() {                                   # yes_no "Question" <default y|n>
  local reply="" d="${2:-y}"
  read -r -p "  $1 ${dim}[$( [ "$d" = y ] && echo 'Y/n' || echo 'y/N' )]${off} " reply || true
  reply="${reply:-$d}"
  case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}
url_for() {                                  # accepts a handle or a full URL
  case "$2" in "") printf '' ;; http*) printf '%s' "$2" ;; *) printf '%s/%s' "$1" "${2#@}" ;; esac
}

ask_questions() {
  printf '\n%s┌────────────────────────────────────────────┐%s\n' "$red" "$off"
  printf '%s│%s  %sStanford personal site%s  ·  launch          %s│%s\n' "$red" "$off" "$bold" "$off" "$red" "$off"
  printf '%s└────────────────────────────────────────────┘%s\n\n' "$red" "$off"
  printf '  %sPress Enter to accept a default. Everything is editable later.%s\n\n' "$dim" "$off"

  while :; do
    ask SUNETID "SUNet ID (the part before @stanford.edu)" "$SUNETID"
    SUNETID="$(printf '%s' "$SUNETID" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    [ -n "$SUNETID" ] && break
    warn "A SUNet ID is required."
  done

  ask NAME   "Your full name"      "${NAME:-}"
  ask ROLE   "One-line headline"   "${ROLE:-CS undergraduate, Class of 2030}"
  ask BIO    "A sentence about you" "${BIO:-I build systems, and I am happiest when something that used to be slow suddenly is not.}"
  ask EMAIL  "Contact email"       "${EMAIL:-$SUNETID@stanford.edu}"
  ask STATUS "Status badge"        "${STATUS:-Open to research and internships}"

  printf '\n  %sLinks — leave blank to hide the icon.%s\n' "$dim" "$off"
  ask GH_IN "GitHub username or URL"   "$GITHUB"
  ask LI_IN "LinkedIn username or URL" "$LINKEDIN"
  ask GS_IN "Google Scholar URL"       "$SCHOLAR"
  GITHUB="$(url_for https://github.com "$GH_IN")"
  LINKEDIN="$(url_for https://www.linkedin.com/in "$LI_IN")"
  SCHOLAR="$(url_for 'https://scholar.google.com/citations?user=' "$GS_IN")"

  printf '\n  %sPhoto — a path to a JPG or PNG. Blank keeps the monogram.%s\n' "$dim" "$off"
  ask PHOTO_IN "Path to your photo" ""
  PHOTO_IN="${PHOTO_IN/#\~/$HOME}"
  if [ -n "$PHOTO_IN" ]; then
    if [ ! -f "$PHOTO_IN" ]; then
      warn "No file at $PHOTO_IN — keeping the monogram."
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
      then PHOTO_FILE="portrait.jpg"
      else
        cp "$PHOTO_IN" "$IMG/portrait.${PHOTO_IN##*.}"
        PHOTO_FILE="portrait.${PHOTO_IN##*.}"
        note "Pillow not installed, copied the file unchanged."
      fi
    fi
  fi
  save_conf
}

# ----------------------------------------------------------------- connect ---
key_works() {                                # can we get in with the key alone?
  [ -f "$KEYFILE" ] || return 1
  ssh -q -o BatchMode=yes -o PreferredAuthentications=publickey \
      -o IdentitiesOnly=yes -i "$KEYFILE" \
      -o StrictHostKeyChecking=accept-new -o ConnectTimeout=12 \
      "$SUNETID@$HOST" true 2>/dev/null
}

open_master_with_key() {
  ssh -f -N -M -o "ControlPath=$(ctl_path)" -o "ControlPersist=$KEEP" \
      -o BatchMode=yes -o PreferredAuthentications=publickey \
      -o IdentitiesOnly=yes -i "$KEYFILE" \
      -o StrictHostKeyChecking=accept-new "$SUNETID@$HOST" 2>/dev/null
}

interactive_login() {
  rm -f "$(ctl_path)"
  local pw=""
  if [ "$REMEMBER" = keyring ] && pw="$(kr_get)" && [ -n "$pw" ]; then
    note "Using the password from your keyring. Duo still needs one code."
    DUOSSH_PASSWORD="$pw" "$HERE/duossh.py" \
      --control-path "$(ctl_path)" --persist "$KEEP" --method "$METHOD" "$SUNETID@$HOST"
  elif [ -x "$HERE/duossh.py" ] && command -v python3 >/dev/null; then
    "$HERE/duossh.py" \
      --control-path "$(ctl_path)" --persist "$KEEP" --method "$METHOD" "$SUNETID@$HOST"
  else
    note "(duossh.py unavailable, falling back to the raw ssh prompts)"
    ssh -f -N -M -o "ControlPath=$(ctl_path)" -o "ControlPersist=$KEEP" "$SUNETID@$HOST"
  fi
}

connect() {
  [ "$NOCACHE" = 1 ] && session_kill
  if session_live; then
    say "Reusing the open session for $SUNETID — nothing to type"
    return 0
  fi
  if [ "$REMEMBER" = key ] && key_works; then
    say "Logging in with your saved key — no password, no Duo"
    open_master_with_key && session_live && return 0
    warn "The key stopped working. Falling back to a password login."
  fi
  say "Connecting to $HOST as $SUNETID"
  interactive_login
  session_live || { echo "error: could not establish a session" >&2; exit 1; }
  ok "Session cached for $KEEP."
  return 0
}

# ---------------------------------------------------------------- remember ---
install_key() {
  [ -f "$KEYFILE" ] || {
    ssh-keygen -t ed25519 -f "$KEYFILE" -N "" -C "stanford-$SUNETID" -q
    chmod 600 "$KEYFILE"
  }
  # Append only once, and keep the remote permissions sshd insists on.
  on_master 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys
             chmod 600 ~/.ssh/authorized_keys
             k="$(cat)"
             grep -qxF "$k" ~/.ssh/authorized_keys || printf "%s\n" "$k" >> ~/.ssh/authorized_keys
             command -v fs >/dev/null && fs setacl ~/.ssh system:anyuser l 2>/dev/null || true' \
    < "$KEYFILE.pub"
}

remove_remote_key() {
  [ -f "$KEYFILE.pub" ] || return 0
  session_live || return 1
  # grep -v exits 1 when nothing is left, which must not abort the rewrite.
  on_master 'k="$(cat)"; f=~/.ssh/authorized_keys
             if [ -f "$f" ]; then
               grep -vxF "$k" "$f" > "$f.tmp" || true
               mv "$f.tmp" "$f"; chmod 600 "$f"
             fi' < "$KEYFILE.pub" 2>/dev/null
}

offer_remember() {
  printf '\n'
  say "Remembering your login"
  note "Duo codes can never be stored — a second factor you could replay"
  note "from disk would not be a second factor. So the best case is a login"
  note "key, which replaces the password and the Duo code together."
  printf '\n'
  yes_no "Set that up now, so future deploys ask for nothing?" y || {
    REMEMBER=session; save_conf
    note "Nothing stored. The open session lasts $KEEP; after that it asks again."
    return 0
  }

  printf '\n'
  say "Installing a login key on $HOST"
  if install_key && key_works; then
    REMEMBER=key; save_conf
    ok "Done. Future runs need no password and no Duo code."
    note "Key: $KEYFILE  (remove it everywhere with --forget)"
    return 0
  fi

  # Leave nothing behind that does not work.
  remove_remote_key || true
  rm -f "$KEYFILE" "$KEYFILE.pub"
  warn "Stanford did not accept key-only login for this account."
  note "That is expected on AFS: sshd cannot read ~/.ssh before you hold a"
  note "token. The unused key has been removed from the server again."
  note "Falling back to remembering just the password."
  if [ "$(kr_backend)" = none ]; then
    REMEMBER=session; save_conf
    note "No system keyring here either, so nothing is stored."
    note "Deploys inside the next $KEEP stay promptless; after that, both questions return."
    return 0
  fi
  printf '\n'
  yes_no "Save your SUNet password in the system keyring ($(kr_backend))?" y || {
    REMEMBER=session; save_conf; note "Nothing stored."; return 0
  }
  local pw="" pw2=""
  read -r -s -p "  SUNet password: " pw; printf '\n'
  read -r -s -p "  Again: " pw2; printf '\n'
  [ -n "$pw" ] && [ "$pw" = "$pw2" ] || { warn "Passwords did not match. Nothing stored."
                                          REMEMBER=session; save_conf; return 0; }
  if printf '%s' "$pw" | kr_set; then
    REMEMBER=keyring; save_conf
    ok "Saved to the keyring, encrypted at rest. Future deploys ask only for a Duo code."
  else
    REMEMBER=session; save_conf; warn "The keyring refused to store it. Nothing saved."
  fi
  unset pw pw2
}

# ------------------------------------------------------------------ status ---
show_status() {
  printf '\n  %sSUNet ID%s     %s\n' "$bold" "$off" "${SUNETID:-(not set yet)}"
  printf '  %sRemembering%s  ' "$bold" "$off"
  case "$REMEMBER" in
    key)     printf 'a login key — no password, no Duo\n' ;;
    keyring) printf 'your password in the %s keyring — Duo still asked\n' "$(kr_backend)" ;;
    session) printf 'nothing on disk; only the open session\n' ;;
    *)       printf 'nothing yet (first run has not finished)\n' ;;
  esac
  printf '  %sKey file%s     %s\n' "$bold" "$off" \
    "$( [ -f "$KEYFILE" ] && echo "$KEYFILE" || echo '(none)')"
  printf '  %sKeyring%s      %s\n' "$bold" "$off" \
    "$( [ -n "$SUNETID" ] && kr_get >/dev/null 2>&1 && echo 'password stored' || echo 'empty')"
  printf '  %sSession%s      %s\n' "$bold" "$off" \
    "$( [ -n "$SUNETID" ] && session_live && echo 'live' || echo 'none')"
  printf '  %sOn disk%s      no password, ever — this project never writes one\n\n' "$bold" "$off"
}

do_forget() {
  [ -n "$SUNETID" ] || { echo "nothing to forget"; exit 0; }
  say "Forgetting everything for $SUNETID"
  if [ -f "$KEYFILE.pub" ]; then
    if remove_remote_key; then
      note "removed the key from $HOST"
    else
      note "no live session, so the key on $HOST was left in place"
      note "remove it later: ssh $SUNETID@$HOST, then edit ~/.ssh/authorized_keys"
    fi
  fi
  kr_del;                    note "cleared the keyring entry"
  rm -f "$KEYFILE" "$KEYFILE.pub"; note "deleted the local key"
  session_kill;              note "closed the cached session"
  REMEMBER=""; [ -f "$CONF" ] && save_conf
  ok "Done. The next run will ask again."
}

# -------------------------------------------------------------------- main ---
[ "$SHOW"   = 1 ] && { show_status; exit 0; }
[ "$FORGET" = 1 ] && { do_forget;   exit 0; }
[ "$LOGOUT" = 1 ] && { session_kill; say "Session closed. What you saved is untouched."; exit 0; }

FIRST_RUN=0
if [ -z "$SUNETID" ] || [ "$EDIT" = 1 ]; then
  [ -z "$SUNETID" ] && FIRST_RUN=1
  ask_questions
fi

printf '\n'
say "Building the site"
python3 "$HERE/build.py"
[ "$REBUILD" = 1 ] && { printf '\n'; note "Preview: cd WWW && python3 -m http.server 8000"; exit 0; }
[ -f "$SRC/index.html" ] || { echo "error: nothing to deploy at $SRC" >&2; exit 1; }

printf '\n'
connect

# Offer to remember only after a login that actually worked.
if [ -z "$REMEMBER" ]; then
  offer_remember
fi

# ------------------------------------------------------------- permissions ---
if [ "$DO_FIX" = 1 ]; then
  printf '\n'
  say "Checking and repairing AFS permissions"
  on_master 'bash -s' <<'REMOTE'
set -e
cd "$HOME"
# The web server must be able to LIST the parent to find WWW inside it.
fs setacl . system:anyuser l
if [ ! -d WWW ]; then echo "--- WWW missing, creating it"; mkdir WWW; fi
cd WWW
# Readable by the web servers, and by nobody else at the filesystem level.
fs setacl . system:www-servers rl
fs setacl . system:anyuser none
REMOTE
  ok "ACLs set."
fi

# ------------------------------------------------------------------ upload ---
if [ "$DO_UPLOAD" = 1 ]; then
  printf '\n'
  say "Uploading $(find "$SRC" -type f | wc -l | tr -d ' ') files"
  if [ "$DELETE" = 1 ]; then
    note "(--delete: clearing ~/WWW on the server first)"
    on_master 'rm -rf -- "$HOME/WWW"/* 2>/dev/null || true'
  fi
  tar -C "$SRC" -cf - . | on_master 'cd "$HOME/WWW" && tar -xf -'
  # Subdirectories do not inherit an ACL set on the parent after they existed.
  on_master 'bash -s' <<'REMOTE'
set -e
cd "$HOME/WWW"
find . -type d -print0 | while IFS= read -r -d '' d; do
  fs setacl "$d" system:www-servers rl 2>/dev/null || true
  fs setacl "$d" system:anyuser none   2>/dev/null || true
done
chmod -R u+rw,a+r . 2>/dev/null || true
REMOTE
  ok "Files written."
fi

# ------------------------------------------------------------------ verify ---
printf '\n'
say "Verifying https://web.stanford.edu/~$SUNETID/"
sleep 2
code=$(curl -sS -o /dev/null -w '%{http_code}' "https://web.stanford.edu/~$SUNETID/" || echo "000")
case "$code" in
  200) ok "HTTP 200 — live at https://web.stanford.edu/~$SUNETID/" ;;
  403) warn "HTTP 403 — still forbidden. Inspect with: ssh $SUNETID@$HOST 'fs listacl ~ ~/WWW'" ;;
  *)   warn "HTTP $code — unexpected. Open the URL in a browser." ;;
esac

if [ "$FIRST_RUN" = 1 ]; then
  printf '\n  %sFrom now on%s\n' "$bold" "$off"
  printf '    Publish again   %s./launch_it.sh%s\n' "$dim" "$off"
  printf '    Change details  %s./launch_it.sh --edit%s\n' "$dim" "$off"
  printf '    What is saved   %s./launch_it.sh --status%s\n' "$dim" "$off"
  printf '    Erase it all    %s./launch_it.sh --forget%s\n' "$dim" "$off"
fi
printf '\n'
