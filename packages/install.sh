#!/bin/bash

exec yay -S --needed --noconfirm \
    --assume-installed nvidia-utils \
    --assume-installed opencl-nvidia \
    $(sudo cat $1 | grep -o '^[^#]*')
