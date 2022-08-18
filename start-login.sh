#!/bin/bash

################################################################################
# Check dependencies
################################################################################

################################################################################
# Prepare modules
################################################################################

################################################################################
# Load modules
################################################################################

# screen
tty_num=$(tty | sed 's/\/dev\/tty\([0-9]\)*/\1/')
if [[ "$tty_num" =~ ^/.* ]]; then
    if [ -z "$DISPLAY" ]; then
        # pts mode
        echo Not Implement Yet!
        exit 1
    else
        # nested tty mode
        POD_TTY="127"
        Xephyr -br -ac -noreset -screen 800x600 -listen tcp :$POD_TTY 2>/dev/null &
        screen=$!
    fi
else
    # tty mode
    POD_TTY=$(expr $tty_num - 1)
    Xorg -listen tcp -nolisten local "vt$tty_num" 2>/dev/null &
    screen=$!
fi

# container
POD_GATEWAY="10.0.2.2"
POD_DISPLAY="$POD_GATEWAY:$POD_TTY"

podman run --detach --rm -it \
    --env "DISPLAY=127.0.0.1:127" \
    --name "login" \
    "localhost/kerryeon/archlinux-xfce-login"
podman wait login >/dev/null 2>/dev/null &
container=$!

################################################################################
# Wait until one of them is downed
################################################################################

echo Waiting until system is downed...
while true; do
    if ! ps $screen >/dev/null; then
        echo Screen is downed.
        podman stop xfce >/dev/null 2>/dev/null
        wait $container
        exec false
    fi

    if ! ps $container >/dev/null; then
        echo Container is downed.
        if [[ "$screen" != "1" ]]; then
            kill $screen 2>/dev/null
        fi
        exec true
    fi

    sleep 1
done
