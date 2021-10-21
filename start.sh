#!/bin/bash

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

################################################################################
# Check dependencies
################################################################################

# audio
if [ ! which pipewire ] 2>/dev/null; then
    echo "pipewire is not installed!"
    exit 1
fi
if [ ! systemctl is-active --user pipewire ]; then
    echo "pipewire is not running!"
    exit 1
fi

# system
function getgid() {
    name=$1
    cut -d: -f3 < <(getent group $name)
}

################################################################################
# Prepare modules
################################################################################

# audio
audio_client_ip="10.0.2.100"
audio_host_ip="10.0.2.2"
audio_port="47130"
POD_PULSE_SERVER="tcp:$audio_host_ip:$audio_port"

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
        printf 'Drivers (blueman, cups, ...) is not supported on Nested TTY mode.'
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
POD_XAUTHORITY="/X/Xauthority.client"

if [ -z $HOOST_XAUTHORITY ]; then
    HOST_XAUTHORITY="$HOME/.Xauthority"
fi

# --device "/dev/video0":"/dev/video0":rw \
# --device "/dev/video1":"/dev/video1":rw \
# --user "$(id -u $USER):$(id -g $USER)" \
# --userns="keep-id" \
# --privileged \
# --volume "rbd0:/home/user/Documents" \
podman run --detach --rm -it \
    --cap-add "all" \
    --device "/dev/dri":"/dev/dri":rw \
    --device "/dev/snd":"/dev/snd":rw \
    --device "/dev/vga_arbiter":"/dev/vga_arbiter":rw \
    --env "POD_DISPLAY=$POD_DISPLAY" \
    --env "POD_PULSE_SERVER=$POD_PULSE_SERVER" \
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

# audio
pactl unload-module $audio_id 2>/dev/null || true # unload lastly used module
audio_id=$(pactl load-module module-native-protocol-tcp port=$audio_port auth-ip-acl=$audio_client_ip)

################################################################################
# Wait until one of them is downed
################################################################################

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

################################################################################
# Unload modules
################################################################################

# audio
pactl unload-module $audio_id
