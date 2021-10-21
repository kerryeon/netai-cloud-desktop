#!/bin/bash

# Halt commands if an error occured
set -e

# bash -x x11docker --desktop \
#     --backend=podman \
#     --clipboard \
#     --gpu \
#     --printer \
#     --pulseaudio \
#     --webcam \
#     -- --privileged \
#     -- x11docker/xfce >output 2>outerr
# exit 1

# get prerequisites
function getgid() {
    name=$1
    cut -d: -f3 < <(getent group $name)
}

# screen
tty_num=$(tty | sed 's/\/dev\/tty\([0-9]\)*/\1/')
if [[ "$tty_num" =~ ^/.* ]]; then
    if [ -z "$DISPLAY" ]; then
        # pts mode
        echo Not Implement Yet!
        exit 1
    else
        # nested tty mode
        printf 'Drivers (blueman, pulseaudio, cups, ...) is not supported on Nested TTY mode.'
        POD_TTY="127"
        Xephyr -br -ac -noreset -screen 800x600 -listen tcp :$POD_TTY 2>/dev/null &
        screen=$!
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

# --user "$(id -u $USER):$(id -g $USER)" \
# --userns="keep-id" \
# --privileged \
# --volume "rbd0:/home/user/Documents" \
podman run --detach --rm -it \
    --cap-add "all" \
    --device "/dev/dri":"/dev/dri":rw \
    --device "/dev/snd":"/dev/snd":rw \
    --device "/dev/vga_arbiter":"/dev/vga_arbiter":rw \
    --device "/dev/video0":"/dev/video0":rw \
    --device "/dev/video1":"/dev/video1":rw \
    --env "POD_DISPLAY=$POD_DISPLAY" \
    --env "POD_XAUTHORITY=$POD_XAUTHORITY" \
    --group-add "$(getgid audio)" \
    --group-add "$(getgid render)" \
    --group-add "$(getgid video)" \
    --name "xfce" \
    --net "slirp4netns:allow_host_loopback=true" \
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
