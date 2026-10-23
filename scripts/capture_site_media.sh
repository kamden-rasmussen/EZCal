#!/usr/bin/env bash
# Regenerates every screenshot and clip used by site/ from EZCal's built-in demo data
# (EZCAL_DEMO=1: fake calendars, nothing read from your accounts).
#
# One-time setup: System Settings → Privacy & Security → grant your terminal both
#   • Screen & System Audio Recording (screencapture)
#   • Accessibility (osascript key presses / window sizing)
# Needs build/EZCal.app (scripts/build_app.sh) and ffmpeg (brew install ffmpeg).
#
#   scripts/capture_site_media.sh            # everything
#   scripts/capture_site_media.sh palette    # only shots/clips whose name contains "palette"
#
# Don't touch the mouse/keyboard while it runs. Your real EZCal can stay open; the script only
# captures the demo process it launches.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=site/assets
TMP=$(mktemp -d)
FILTER="${1:-}"
APP=build/EZCal.app/Contents/MacOS/EZCal
[ -x "$APP" ] || { echo "Build first: scripts/build_app.sh"; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg missing: brew install ffmpeg"; exit 1; }
mkdir -p "$OUT"

W=1400; H=1000; X=120; Y=60   # window size/position (points) on the main display

EZCAL_DEMO=1 "$APP" >/dev/null 2>&1 &
PID=$!
cleanup() { kill "$PID" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT
sleep 2
swiftc -O -o "$TMP/input" scripts/ezcal_input.swift

sys() { osascript -e "tell application \"System Events\" to $1"; }
proc() { echo "(first process whose unix id is $PID)"; }
focus() { sys "set frontmost of $(proc) to true"; sleep 0.3; }
retry() { local n; for n in 1 2 3 4 5 6 7 8; do "$@" >/dev/null 2>&1 && return 0; sleep 1.5; done; return 1; }
place() { sleep 2; retry sys "tell $(proc) to set position of window 1 to {$X, $Y}" || true; sleep 1; retry sys "tell $(proc) to set size of window 1 to {$W, $H}" || true; sleep 1.5; }
key() { focus; sys "keystroke \"$1\""; sleep "${2:-0.5}"; }
cmdkey() { focus; sys "keystroke \"$1\" using {command down}"; sleep "${2:-0.5}"; }
code() { focus; local m=""; [ -n "${2:-}" ] && m="using {$2}"; sys "key code $1 $m"; sleep "${3:-0.5}"; }   # 36 return · 53 esc · 125 down · 126 up · 123/124 left/right
typing() { local s="$1" i; for ((i = 0; i < ${#s}; i++)); do key "${s:$i:1}" 0.06; done; }
appearance() { osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1"; sleep 1.5; }

window_id() {
  swift -e 'import CoreGraphics
for w in CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String:Any]] {
  if (w["kCGWindowOwnerPID"] as? Int) == '"$PID"' && (w["kCGWindowLayer"] as? Int) == 0 { print(w["kCGWindowNumber"]!); break } }'
}
want() { [ -z "$FILTER" ] || [[ "$1" == *"$FILTER"* ]]; }

shot() {   # shot <name>   (call after setting up the state)
  want "$1" || return 0
  screencapture -x -o -l "$(window_id)" "$TMP/$1.png"
  ffmpeg -loglevel error -y -i "$TMP/$1.png" -vf "scale=2000:-2:flags=lanczos" -q:v 3 "$OUT/$1.jpg"
  echo "  shot  $1"
}
# clip <name> <seconds> <command>   runs <command> (a shell function) while recording
clip() {
  want "$1" || return 0
  local name=$1 secs=$2; shift 2
  park
  screencapture -x -v -V "$secs" -l "$(window_id)" "$TMP/$name.mov" &
  local rec=$!
  sleep 1.2; "$@"; wait "$rec" || true
  local crop; crop=$(ffmpeg -i "$TMP/$name.mov" -vf cropdetect=30:2:0 -f null - 2>&1 | grep -o 'crop=[0-9:]*' | tail -1)
  ffmpeg -loglevel error -y -i "$TMP/$name.mov" -an -vf "${crop:-crop=iw:ih},crop=iw-12:ih-12,scale=1600:-2:flags=lanczos,fps=30" \
    -c:v libx264 -crf 25 -preset slow -pix_fmt yuv420p -movflags +faststart "$OUT/$name.mp4"
  ffmpeg -loglevel error -y -ss 0.2 -i "$OUT/$name.mp4" -frames:v 1 -vf scale=1600:-2 -q:v 3 "$OUT/$name-poster.jpg"
  echo "  clip  $name"
}

park() { "$TMP/input" mouse $((X + W + 150)) $((Y + H + 100)); }
top() { "$TMP/input" scroll 40 $((X + W / 2 + 150)) $((Y + 500)); park; sleep 0.5; }
view() { cmdkey "$1" 1.0; }                         # 1 day · 2 work week · 3 week · 4 month
reset() { code 53 "" 0.3; code 53 "" 0.3; key t 0.3; view 3; top; }   # esc, today, week view, scrolled to the morning

# ---- clip bodies -----------------------------------------------------------------------------
c_views()   { view 1; top; sleep 0.8; view 2; sleep 1.2; view 3; sleep 1.2; view 4; sleep 1.6; view 3; top; sleep 1; }
c_palette() { cmdkey k 1; typing "next fri"; sleep 1; code 36 "" 1.2; cmdkey k 1; typing "show"; sleep 1.4; code 53 "" 0.5; }
c_create()  { key n 1; typing "Design sync"; sleep 0.6; code 36 "command down" 1.5; }
c_nudge()   { code 125 "" 0.6; code 125 "" 0.6; for _ in 1 2 3 4; do code 125 "option down" 0.45; done; for _ in 1 2; do code 126 "option down, shift down" 0.45; done; sleep 0.8; }
c_findtime(){ key n 1; typing "Planning"; sleep 0.5; cmdkey f 1.5; code 125 "" 0.7; code 125 "" 0.7; sleep 1; }
c_tasks()   { cmdkey k 1; typing "task: call dentist tomorrow 3pm"; sleep 1; code 36 "" 1.8; }

# ---- screenshots -----------------------------------------------------------------------------
for _ in $(seq 1 30); do sys "tell $(proc) to get window 1" >/dev/null 2>&1 && break; sleep 1; done
place
echo "Light mode"; appearance false; reset
shot hero-week-light
view 1; top; shot view-day
view 4; shot view-month
reset
code 125 "" 0.6; code 125 "" 0.6; code 36 "" 1; shot event-detail; code 53 "" 0.5
key n 1; shot event-editor; code 53 "" 0.5
cmdkey k 1; typing "go to"; shot command-palette; code 53 "" 0.4
key "?" 1; shot shortcuts; code 53 "" 0.4
cmdkey "," 1.2; shot settings; code 53 "" 0.4; reset

echo "Dark mode"; appearance true; reset
shot hero-week-dark
view 4; shot view-month-dark; reset

appearance false; reset

# ---- clips -----------------------------------------------------------------------------------
echo "Clips"
clip demo-views 9 c_views;          reset
clip demo-palette 10 c_palette;     reset
clip demo-create 8 c_create;        reset
clip demo-keyboard-move 9 c_nudge;  reset
clip demo-find-time 8 c_findtime;   code 53 "" 0.3; code 53 "" 0.3; reset
clip demo-tasks 7 c_tasks;          reset

echo "Done → $OUT"
ls -la "$OUT"
