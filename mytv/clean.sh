#!/usr/bin/env bash
# Free memory and storage on this TV over ADB: force-stop apps idling in the background and trim every
# app's cache. Nothing is uninstalled or disabled; a stopped app starts again the next time it is opened.
#
# Kept running: the launcher and its remote-key helpers (a force stop switches those off), AirCast
# (AirPlay receiver), Chromecast, Miracast, the voice assistant, Google services and the app on screen.
#
# Usage: TV_HOST=<tv ip> mytv/clean.sh            stop background apps and trim caches
#        TV_HOST=<tv ip> mytv/clean.sh --no-cache  stop background apps only
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TV_HOST:?set TV_HOST to the IP address of the TV}"
PY=tools/venv/bin/python
tv() { "$PY" -I tools/tv.py "$@"; }

# Apps that are safe to stop: everything third-party plus the preinstalled streaming apps and Play Store.
STOPPABLE_SYSTEM="com.google.android.youtube.tv com.google.android.youtube.tvmusic com.netflix.ninja
com.amazon.amazonvideo.livingroom com.android.vending com.xiaomi.mitv.mediaexplorer"
KEEP="com.gathin.tvhome com.smartdevice.tv.aircast"

report() {
  tv 'echo "Memory free: $(( $(grep MemAvailable /proc/meminfo | tr -s " " | cut -d" " -f2) / 1024 )) MB"; df -h /data | tail -1 | awk "{print \"Storage free: \" \$4}"'
}

echo "Before:"; report

FOREGROUND=$(tv "dumpsys activity activities | grep -m1 mResumedActivity" | grep -oE ' [a-z][a-zA-Z0-9_.]+/' | tr -d ' /' || true)
[ -n "$FOREGROUND" ] && echo "On screen, left running: $FOREGROUND"

CANDIDATES=$( { tv 'pm list packages -3' | sed 's/^package://'; printf '%s\n' $STOPPABLE_SYSTEM; } | sort -u)
RUNNING=$(tv 'ps -A -o NAME' | sed 's/:.*//' | sort -u)
STOP=()
for pkg in $CANDIDATES; do
  case " $KEEP $FOREGROUND " in *" $pkg "*) continue ;; esac
  printf '%s\n' "$RUNNING" | grep -qx "$pkg" && STOP+=("$pkg")
done

if [ ${#STOP[@]} -eq 0 ]; then
  echo "No background apps to stop."
else
  echo "Stopping: ${STOP[*]}"
  printf 'am force-stop %s\n' "${STOP[@]}" | tv --batch >/dev/null
fi

if [ "${1:-}" != "--no-cache" ]; then
  echo "Trimming app caches..."
  # Asks Android to free this many bytes from app caches; it clears what it can and stops there.
  tv 'pm trim-caches 999G' >/dev/null
fi

sleep 3
echo "After:"; report
