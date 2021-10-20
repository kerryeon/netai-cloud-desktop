#!/bin/bash

# screen
Xephyr -br -ac -noreset -screen 800x600 -listen tcp :127 2>/dev/null &
screen=$!

# container
podman run --detach --rm -it \
    --name "xfce" \
    --net "slirp4netns:allow_host_loopback=true" \
    --privileged \
    --security-opt "label=type:container_runtime_t" \
    --stop-signal "SIGRTMIN+3" \
    --systemd="always" \
    --tmpfs "/run:exec" \
    --tmpfs "/run/lock" \
    --volume "/home/h/.Xauthority:$XAUTHORITY:ro" \
    --workdir "/tmp" \
    -- "localhost/kerryeon/archlinux-xfce" >/dev/null
podman wait xfce >/dev/null 2>/dev/null &
container=$!

# Wait until one of them is downed
echo Waiting until system is downed...
while true; do
    if ! ps $screen >/dev/null; then
        echo Xephyr is downed.
        podman stop xfce >/dev/null 2>/dev/null
        wait $container
        break
    fi

    if ! ps $container >/dev/null; then
        echo Container is downed.
        kill $screen 2>/dev/null
        break
    fi

    sleep 1
done
