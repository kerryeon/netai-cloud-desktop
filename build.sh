#!/bin/bash

# Halt commands if an error occured
set -e

# Prepare 3rd-party prerequisites
## nvidia-sdk
NVIDIA_SDK_PKGBUILD="https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=nvidia-sdk"
NVIDIA_SDK_VERSION=$(curl $NVIDIA_SDK_PKGBUILD 2>/dev/null | grep -Eo '^pkgver=.+$' | grep -Eo '[0-9\.]+$')
NVIDIA_SDK_URL=$(curl $NVIDIA_SDK_PKGBUILD 2>/dev/null | grep -Eo '^url=.+$' | grep -Eo "'.+\'\$")
if [ ! -f ./packages/nonfree/Video_Codec_SDK_$NVIDIA_SDK_VERSION.zip ]; then
    echo "error: nvidia-sdk=$NVIDIA_SDK_VERSION not found!"
    echo "note: You can download it manually: $NVIDIA_SDK_URL"
    exit 1
fi

# Build a image
podman build \
    --tag localhost/kerryeon/netai-cloud-desktop \
    --network host \
    .
