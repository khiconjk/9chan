#!/system/bin/sh
# S9 Ghost Humanized Touch Injector
# Injects hardware-level touch events into /dev/input/event1 (sec_touchscreen)
# EventHub assigns hardware deviceId (5), source 0x1002, toolType TOOL_TYPE_FINGER.

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <x> <y> [count] [interval_ms]"
    echo "Example: $0 523 1997 1 200"
    exit 1
fi

IN_X=$1
IN_Y=$2
COUNT=${3:-1}
INTERVAL_MS=${4:-210}

# Auto-detect device node
EVENT_DEV="/dev/input/event1"
if [ ! -w "$EVENT_DEV" ]; then
    EVENT_DEV="/dev/input/event2"
fi

# Convert 1440x2960 screen coordinates to 0-4095 touch IC coordinates
if [ "$IN_X" -le 1440 ] && [ "$IN_Y" -le 2960 ]; then
    BASE_X=$(( IN_X * 4095 / 1440 ))
    BASE_Y=$(( IN_Y * 4095 / 2960 ))
else
    BASE_X=$IN_X
    BASE_Y=$IN_Y
fi

TRACKING_ID=1000

i=0
while [ "$i" -lt "$COUNT" ]; do
    # Micro-jitter (+- 1 to 2 raw pixels)
    JITTER_X=$(( (RANDOM % 5) - 2 ))
    JITTER_Y=$(( (RANDOM % 5) - 2 ))
    PX=$(( BASE_X + JITTER_X ))
    PY=$(( BASE_Y + JITTER_Y ))

    MAJOR=$(( 9 + (RANDOM % 4) ))
    MINOR=$(( MAJOR - (RANDOM % 2) ))

    TRACKING_ID=$(( TRACKING_ID + 1 ))

    # 1. DOWN
    sendevent "$EVENT_DEV" 3 47 0
    sendevent "$EVENT_DEV" 3 57 "$TRACKING_ID"
    sendevent "$EVENT_DEV" 3 53 "$PX"
    sendevent "$EVENT_DEV" 3 54 "$PY"
    sendevent "$EVENT_DEV" 3 48 "$MAJOR"
    sendevent "$EVENT_DEV" 3 49 "$MINOR"
    sendevent "$EVENT_DEV" 1 330 1
    sendevent "$EVENT_DEV" 1 325 1
    sendevent "$EVENT_DEV" 0 0 0

    # 2. Realistic human finger hold duration (~75-100ms)
    sleep 0.08

    # 3. UP
    sendevent "$EVENT_DEV" 3 57 -1
    sendevent "$EVENT_DEV" 1 330 0
    sendevent "$EVENT_DEV" 0 0 0

    i=$(( i + 1 ))
    if [ "$i" -lt "$COUNT" ]; then
        # Natural human inter-click delay (interval_ms + Gaussian-like jitter)
        JITTER_MS=$(( (RANDOM % 50) - 20 ))
        SLEEP_SEC=$(awk "BEGIN {printf \"%.3f\", ($INTERVAL_MS + $JITTER_MS)/1000}")
        sleep "$SLEEP_SEC"
    fi
done
