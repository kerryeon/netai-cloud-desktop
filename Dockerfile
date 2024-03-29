# Select Desktop Environment
FROM docker.io/lopsided/archlinux:devel

# Set default environment variables
ARG __GRAPHICS_VENDOR_NAME=nvidia

# Configure environment variables
ENV \
  __GRAPHICS_VENDOR_NAME="${__GRAPHICS_VENDOR_NAME}" \
  __GRAPHICS_NVIDIA_HOME="/usr/local/nvidia"

# Configure constant environment variables
ENV \
  no_proxy="0,1,2,3,4,5,6,7,8,9,.netai-cloud,localhost,localdomain" \
  LD_LIBRARY_PATH="${__GRAPHICS_NVIDIA_HOME}/lib:${LD_LIBRARY_PATH}" \
  PATH="${__GRAPHICS_NVIDIA_HOME}/bin:${PATH}" \
  __GLX_VENDOR_LIBRARY_NAME="${__GRAPHICS_VENDOR_NAME}" \
  __NV_PRIME_RENDER_OFFLOAD="1" \
  __NV_PRIME_RENDER_OFFLOAD_PROVIDER="NVIDIA-G0"

# Check environment variables
RUN case "${__GRAPHICS_VENDOR_NAME}" in \
  "") echo "No GPU vendors (Without H/W Acceleration)" ;; \
  "nvidia") echo "Supported GPU Vendor: ${__GRAPHICS_VENDOR_NAME}" ;; \
  *) echo "Unsupported GPU Vendor: ${__GRAPHICS_VENDOR_NAME}" && exit 1 ;; \
  esac

# Reinstall excluded files
RUN true \
  # Configure pacman
  && sed -i 's/^#\(ParallelDownloads.*\)$/\1/g' /etc/pacman.conf \
  && sed -i 's/^#\(IgnorePkg *\)\=/\1 \= cuda nvidia-utils opencl-nvidia/g' /etc/pacman.conf \
  && sed -i 's/^\(NoExtract.*\)$/#\1/g' /etc/pacman.conf \
  # Refresh default hard-coded files
  && rm /etc/locale.gen \
  && pacman -Syy \
  && pacman -Qqn | pacman -S --noconfirm --overwrite="*" - \
  && pacman -Scc --noconfirm \
  && rm -r /var/lib/pacman/sync/*

# Install core packages
RUN pacman -Sy --needed --noconfirm base base-devel glibc shadow systemd sudo wget \
  && pacman -Scc --noconfirm \
  && rm -r /var/lib/pacman/sync/* \
  && touch /etc/subuid /etc/subgid

# Configure system
RUN printf 'LANG=en_US.UTF-8' > /etc/locale.conf \
  && sed -i 's/^#\(en_US\.UTF-8.*\)$/\1/g' /etc/locale.gen \
  && sed -i 's/^#\(ko_KR\.EUC-KR.*\)$/\1/g' /etc/locale.gen \
  && sed -i 's/^#\(ko_KR\.UTF-8.*\)$/\1/g' /etc/locale.gen \
  && locale-gen \
  && ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime

# Create makepkg user and workdir
ARG makepkg=makepkg
RUN useradd --system --create-home $makepkg \
  && printf "$makepkg ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/$makepkg \
  && printf 'Defaults env_keep += "ftp_proxy http_proxy https_proxy no_proxy"' > /etc/sudoers.d/proxy
USER $makepkg
WORKDIR /tmp

# Install dependencies
ADD packages/ ./packages/
RUN sudo mv ./packages/lib/pkgconfig/* /usr/lib/pkgconfig/ \
  && sudo pacman -Sy \
  # Install 3rdparty package: yay-bin
  && curl -s "https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz" | tar xzf - \
  && pushd "yay" \
  && makepkg -scri --noconfirm \
  && popd \
  && rm -rf "yay" "yay.tar.gz" \
  # Install 3rdparty package: nvidia-sdk
  && if [ "${__GRAPHICS_VENDOR_NAME}" = "nvidia" ]; then true \
  && curl -s "https://aur.archlinux.org/cgit/aur.git/snapshot/nvidia-sdk.tar.gz" | tar xzf - \
  && pushd "nvidia-sdk" \
  && sudo mv ../packages/nonfree/Video_Codec_SDK_*.zip . \
  && makepkg -scri --noconfirm \
  && popd \
  && sudo rm -rf "nvidia-sdk" "nvidia-sdk.tar.gz" \
  ; fi \
  # Install packages: Common, Graphics, Xpra
  && /bin/bash ./packages/install.sh ./packages/common \
  && /bin/bash ./packages/install.sh ./packages/graphics-common \
  && if [ ${__GRAPHICS_VENDOR_NAME} = "nvidia" ]; then true \
  && /bin/bash ./packages/install.sh ./packages/graphics-nvidia \
  ; fi \
  && /bin/bash ./packages/install.sh ./packages/xpra \
  # Install 3rdparty package: xpra-git
  && curl -s "https://aur.archlinux.org/cgit/aur.git/snapshot/xpra-git.tar.gz" | tar xzf - \
  && pushd "xpra-git" \
  && patch < ../packages/patches/0001-Add-support-building-without-strict-mode.patch \
  && makepkg -scri --noconfirm \
  && popd \
  && sudo rm -rf "xpra-git" "xpra-git.tar.gz" \
  # Install packages: Applications
  && /bin/bash ./packages/install.sh ./packages/applications \
  # Cleanup
  && yay -Scc --noconfirm \
  # remove the default secret key
  # note: manual key generation is required
  # ex) pacman-key --init
  && sudo rm -rf /etc/pacman.d/gnupg \
  && sudo rm -r /var/lib/pacman/sync/* \
  && sudo rm -r ./packages

# Create normal user account
USER root
ARG user=user
RUN useradd $user -u 1000 -m -g users -s /bin/zsh \
  && printf "$user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$user

# Enable systemd
ADD ./core ./core
RUN true \
  && mkdir -p /etc/conf.d/ \
  && mkdir -p /etc/systemd/system/console-getty.service.d/ \
  && mv ./core/nvidia/*.sh /usr/local/bin/ \
  && mv ./core/init /usr/local/bin/init \
  && mv ./core/systemd/getty_override.conf /etc/systemd/system/console-getty.service.d/override.conf \
  && mv ./core/systemd/pacman-init /usr/local/bin/ \
  && mv ./core/systemd/pacman-init.service /etc/systemd/system/ \
  && mv ./core/systemd/xpra.conf /etc/conf.d/xpra \
  && mv ./core/systemd/xpra@.service /etc/systemd/system/ \
  && chmod +x /usr/local/bin/init \
  && chmod +x /usr/local/bin/pacman-init \
  && systemctl enable pacman-init \
  && systemctl enable xpra@$user \
  && rm -r ./core/

# Delete makepkg user and workdir
RUN userdel $makepkg \
  && rm /etc/sudoers.d/$makepkg \
  && rm -rf /tmp/**/*

# Initiate with systemd
WORKDIR /tmp
ENTRYPOINT [ "/bin/bash" ]
CMD [ "/usr/local/bin/init" ]
