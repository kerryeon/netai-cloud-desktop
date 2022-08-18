# Select Desktop Environment
FROM docker.io/lopsided/archlinux:devel

# Configure environment variables
ENV \
  NO_PROXY=0,1,2,3,4,5,6,7,8,9,.netai-cloud,localhost,localdomain \
  __GLX_VENDOR_LIBRARY_NAME=nvidia \
  __NV_PRIME_RENDER_OFFLOAD=1 \
  __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0

# Configure pacman
RUN sed -i 's/^#\(ParallelDownloads.*\)$/\1/g' /etc/pacman.conf

# Configure pacman per platform
ARG reflector_country="KR"
RUN if cat /etc/pacman.conf | grep "auto" > /dev/null; then \
  # platform=linux/amd64
  # Install reflector for faster installation
  pacman -Sy \
  && pacman -S --needed --noconfirm \
  glibc reflector systemd \
  && pacman -Scc --noconfirm \
  && rm -r /var/lib/pacman/sync/* \
  && sed -i "s/\(^# --country.*\$\)/\1\n--country $reflector_country/g" /etc/xdg/reflector/reflector.conf \
  && systemctl enable reflector.timer \
  && reflector --country $reflector_country > /etc/pacman.d/mirrorlist \
  # Support x86 binaries
  && printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist' >> /etc/pacman.conf; \
  else \
  # platform=linux/arm64 (supposed)
  # Set package repositories manually
  printf 'Server = http://jp.mirror.archlinuxarm.org/$arch/$repo' > /etc/pacman.d/mirrorlist; \
  fi

# Add more package repositories
RUN printf '\n[archlinuxcn]\nServer = https://repo.archlinuxcn.org/$arch' >> /etc/pacman.conf \
  # generate a default secret key
  && pacman-key --init \
  # refresh database because of changing mirrorlists
  && pacman -Syy \
  # import PGP keys
  && pacman -Sy --noconfirm archlinux-keyring \
  && pacman -Sy --noconfirm archlinuxcn-keyring \
  && pacman -Scc --noconfirm \
  && rm -r /var/lib/pacman/sync/*

# Reinstall excluded files
RUN sed -i 's/^NoExtract\(.*\)$//g' /etc/pacman.conf \
  && rm /etc/locale.gen \
  && pacman -Syy \
  && pacman -Qqn | pacman -S --noconfirm --overwrite="*" - \
  && pacman -Scc --noconfirm \
  && rm -r /var/lib/pacman/sync/*

# Install core packages
RUN pacman -Sy --needed --noconfirm \
  base base-devel shadow sudo wget \
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
  && echo "$makepkg ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/$makepkg
USER $makepkg
WORKDIR /tmp

# Install dependencies
ADD packages/ ./packages/
RUN sudo mv ./packages/lib/pkgconfig/* /usr/lib/pkgconfig/ \
  # Install 3rdparty package: yay-bin
  && curl -s "https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz" | tar xzf - \
  && pushd "yay" \
  && sudo pacman -Sy \
  && makepkg -scri --noconfirm \
  && popd \
  && rm -rf "yay" "yay.tar.gz" \
  # Install 3rdparty package: nvidia-sdk
  && curl -s "https://aur.archlinux.org/cgit/aur.git/snapshot/nvidia-sdk.tar.gz" | tar xzf - \
  && pushd "nvidia-sdk" \
  && sudo mv ../packages/nonfree/Video_Codec_SDK_*.zip . \
  && makepkg -scri --noconfirm \
  && popd \
  && sudo rm -rf "nvidia-sdk" "nvidia-sdk.tar.gz" \
  # Install packages: Common, Graphics, Xpra
  && /bin/bash ./packages/install.sh ./packages/common \
  && /bin/bash ./packages/install.sh ./packages/graphics \
  && /bin/bash ./packages/install.sh ./packages/xpra \
  # Install 3rdparty package: xpra-git
  && curl -s "https://aur.archlinux.org/cgit/aur.git/snapshot/xpra-git.tar.gz" | tar xzf - \
  && pushd "xpra-git" \
  && patch < ../packages/patches/0001-Add-support-building-without-strict-mode.patch \
  && makepkg -scri --noconfirm \
  && popd \
  && sudo rm -rf "xpra-git" "nvidia-sdk.tar.gz" \
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

# Enable systemd
USER root
ADD ./core ./core
RUN true \
  && mv ./core/init /usr/local/bin/init \
  && mv ./core/profile.d/* /etc/profile.d/ \
  && mv ./core/systemd/getty_override.conf /etc/systemd/system/console-getty.service.d/override.conf \
  && mv ./core/systemd/pacman-init /usr/local/bin/ \
  && mv ./core/systemd/pacman-init.service /etc/systemd/system/ \
  && mv ./core/systemd/xpra.conf /etc/conf.d/xpra \
  && mv ./core/systemd/xpra@.service /etc/systemd/user/ \
  && chmod a+x /core/profile.d/*.sh \
  && chmod +x /usr/local/bin/init \
  && chmod +x /usr/local/bin/pacman-init \
  && systemctl enable pacman-init \
  && systemctl xpra@user \
  && rm -r ./core/

# Create normal user account
ARG user=user
RUN useradd $user -u 1000 -m -g users -G wheel -s /bin/zsh \
  && echo "%wheel ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$user

# Delete makepkg user and workdir
RUN sudo userdel $makepkg \
  && sudo rm -rf /tmp/**/*

# Initiate with systemd
WORKDIR /tmp
ENTRYPOINT [ "/bin/bash" ]
CMD [ "/usr/local/bin/init" ]
