#!/bin/bash

# --cap-drop ALL \
# --cap-add AUDIT_WRITE \
# --cap-add CHOWN \
# --cap-add DAC_OVERRIDE \
# --cap-add FOWNER \
# --cap-add FSETID \
# --cap-add KILL \
# --cap-add SETGID \
# --cap-add SETPCAP \
# --cap-add SETUID \
# --cap-add SYS_BOOT \

# on local:
# TODO: open monitor automatically
# TODO: poweroff when monitor is dead
# Xephyr -br -ac -noreset -screen 800x600 -listen tcp :127

podman run --rm -it \
    --name "xfce" \
    --net "slirp4netns:allow_host_loopback=true" \
    --previleged \
    --security-opt "label=type:container_runtime_t" \
    --stop-signal "SIGRTMIN+3" \
    --systemd="always" \
    --tmpfs "/run:exec" \
    --tmpfs "/run/lock" \
    --volume "/home/h/.Xauthority:$XAUTHORITY:ro" \
    --workdir "/tmp" \
    -- "localhost/kerryeon/archlinux-xfce"
