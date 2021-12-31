#!/bin/bash
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

################################################################################
# Check dependencies
################################################################################

# audio
if [[ ! $(which pipewire || which pulseaudio) ]] 2>/dev/null; then
    echo "warn: pipewire (pulseaudio) is not installed!"
fi
if [[ ! $(systemctl is-active --user pipewire || systemctl is-active --user pulseaudio) ]]; then
    echo "warn: pipewire (pulseaudio) is not running!"
fi

# system
function getuid() {
    cat /etc/subuid | grep "^$(whoami):" | cut -d: -f2
}

function getgid() {
    name=$1
    getent group $name | cut -d: -f3
}

################################################################################
# Prepare modules
################################################################################

# audio
audio_host_ip="$(ip -4 -o a | awk '{print $4}' | cut -d/ -f1 | grep -v 127.0.0.1 | head -n1)"
audio_client_ip=$audio_host_ip
audio_port="47130"
POD_PULSE_SERVER="tcp:$audio_host_ip:$audio_port"

# home directory
if [ ! -d ./home/ ]; then
    echo Creating default home directory...
    cp -r ./custom/home/ ./home/
    # TODO: check user subuid/subgids
    # note: uid (user) = 1000, gid (users) = 984
    sudo chown -R $(($(getuid) + 999)):$(($(getuid) + 983)) ./home/
fi

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
        Xephyr -br -ac -noreset -resizeable -screen 800x600 -listen tcp :$POD_TTY 2>/dev/null &
        screen=$!
    fi
else
    # tty mode
    POD_TTY=$(expr $tty_num - 1)
    Xorg -listen tcp -nolisten local "vt$tty_num" 2>/dev/null &
    screen=$!
fi

# container
POD_NAME="netai-cloud-desktop"
POD_GATEWAY="10.0.2.2"
POD_DISPLAY="$POD_GATEWAY:$POD_TTY"
POD_XAUTHORITY="/X/Xauthority.client"

if [[ -z $HOST_XAUTHORITY ]]; then
    HOST_XAUTHORITY="$HOME/.Xauthority"
fi

# TODO: share all NVIDIA modules
# note: https://github.com/mviereck/x11docker/wiki/Hardware-acceleration#share-nvidia-device-files-with-container

# TODO: share all video devices
# note: https://github.com/mviereck/x11docker/wiki/Hardware-acceleration#share-nvidia-device-files-with-container

# TODO: share other modules - bluetooth, USB,

# --device "/dev/video0":"/dev/video0":rw \
# --device "/dev/video1":"/dev/video1":rw \
# --user "$(id -u $USER):$(id -g $USER)" \
# --userns="keep-id" \
# --privileged \
# --volume "rbd0:/home/user/Documents" \
podman run --detach --rm -it \
    --cap-add "all" \
    --device "/dev/dri":"/dev/dri":rw \
    --device "/dev/vga_arbiter":"/dev/vga_arbiter":rw \
    --env "POD_DISPLAY=$POD_DISPLAY" \
    --env "POD_PULSE_SERVER=$POD_PULSE_SERVER" \
    --env "POD_XAUTHORITY=$POD_XAUTHORITY" \
    --group-add "$(getgid audio)" \
    --group-add "$(getgid render)" \
    --group-add "$(getgid video)" \
    --name "$POD_NAME" \
    --net "slirp4netns:allow_host_loopback=true" \
    --security-opt "label=type:container_runtime_t" \
    --stop-signal "SIGRTMIN+3" \
    --systemd="always" \
    --tmpfs "/run:exec" \
    --tmpfs "/run/lock" \
    --volume "$HOST_XAUTHORITY:$POD_XAUTHORITY:ro" \
    --volume "/var/run/libvirt:/var/run/libvirt:rw" \
    --volume "$(pwd)/home:/home/user/:rw" \
    --workdir "/tmp" \
    -- "localhost/kerryeon/netai-cloud-desktop" >/dev/null
podman wait "$POD_NAME" >/dev/null 2>/dev/null &
container=$!

# audio
if [[ $(which pactl) ]] 2>/dev/null; then
    audio_id=$(pactl load-module module-native-protocol-tcp port=$audio_port auth-ip-acl=$audio_client_ip/32)
fi

################################################################################
# Wait until one of them is downed
################################################################################

echo Waiting until system is downed...
while true; do
    if ! ps $screen >/dev/null; then
        echo Screen is downed.
        podman stop "$POD_NAME" >/dev/null 2>/dev/null
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
if [[ $(which pactl) ]] 2>/dev/null; then
    pactl unload-module module-native-protocol-tcp $audio_id
fi
