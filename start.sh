#!/bin/bash

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
        exit 1
    fi
else
    # tty mode
    POD_TTY="0"
    Xorg -listen tcp -nolisten local vt1 2>/dev/null &
    screen=$!
fi

# container
POD_GATEWAY="10.0.2.2"
POD_DISPLAY="$POD_GATEWAY:$POD_TTY"
POD_XAUTHORITY="/X/Xauthority.client"

if [ -z $HOOST_XAUTHORITY ]; then
    HOST_XAUTHORITY="$HOME/.Xauthority"
fi

#--volume "rbd0:/home/user/Documents" \
podman run --detach --rm -it \
    --env POD_DISPLAY=$POD_DISPLAY \
    --env POD_XAUTHORITY=$POD_XAUTHORITY \
    --name "xfce" \
    --net "slirp4netns:allow_host_loopback=true" \
    --privileged \
    --security-opt "label=type:container_runtime_t" \
    --stop-signal "SIGRTMIN+3" \
    --systemd="always" \
    --tmpfs "/run:exec" \
    --tmpfs "/run/lock" \
    --volume "$HOST_XAUTHORITY:$POD_XAUTHORITY:ro" \
    --workdir "/tmp" \
    -- "localhost/kerryeon/archlinux-xfce" >/dev/null
podman wait xfce >/dev/null 2>/dev/null &
container=$!

# Wait until one of them is downed
echo Waiting until system is downed...
while true; do
    if ! ps $screen >/dev/null; then
        echo Screen is downed.
        podman stop xfce >/dev/null 2>/dev/null
        wait $container
        break
    fi

    if ! ps $container >/dev/null; then
        echo Container is downed.
        if [[ "$screen" != "1" ]]; then
            kill $screen 2>/dev/null
        fi
        break
    fi

    sleep 1
done
