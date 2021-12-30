# Select Desktop Environment
FROM docker.io/lopsided/archlinux:devel

# Configure pacman
RUN sed -i 's/^#\(ParallelDownloads.*\)$/\1/g' /etc/pacman.conf

# Configure pacman per platform
ARG reflector_country="KR"
RUN if cat /etc/pacman.conf | grep "auto" > /dev/null; then \
  # platform=linux/amd64
  # Install reflector for faster installation
  pacman -Sy \
  && pacman -S --needed --noconfirm \
  reflector \
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

# Install yay: AUR package manager and cores
RUN wget "https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz" \
  && tar xf "yay.tar.gz" \
  && pushd yay \
  && sudo pacman -Sy \
  && makepkg -scri --noconfirm \
  && popd \
  && rm -rf yay "yay.tar.gz"

# Install dependencies
ADD custom/packages .
RUN yay -Sy --needed --noconfirm $(sudo cat packages | grep -o '^[^#]*') \
  && yay -Scc --noconfirm \
  && sudo rm -r /var/lib/pacman/sync/* \
  && sudo rm packages \
  # remove the default secret key
  # note: manual key generation is required
  # ex) pacman-key --init
  && sudo rm -rf /etc/pacman.d/gnupg

# Enable systemd
USER root
ADD core/getty_override.conf /etc/systemd/system/console-getty.service.d/override.conf
ADD core/pacman-init /usr/local/bin/
ADD core/pacman-init.service /etc/systemd/system/
ADD custom/startx /usr/local/bin/
ADD core/startx.service /etc/systemd/user/
RUN systemctl enable pacman-init \
  && chmod +x /usr/local/bin/pacman-init \
  && chmod +x /usr/local/bin/startx

# Create normal user account
ARG user=user
RUN useradd $user -u 1000 -m -g users -G wheel -s /bin/zsh \
  && echo "%wheel ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$user

# Customize user settings
USER $user
ADD custom/on-startup /usr/local/bin/
RUN sudo chmod +x /usr/local/bin/on-startup

# Delete makepkg user and workdir
RUN sudo userdel $makepkg \
  && sudo rm -rf /tmp/**/*

# Initiate with systemd
USER root
WORKDIR /tmp
ADD core/init /usr/local/bin/init
RUN chmod +x /usr/local/bin/init
ENTRYPOINT [ "/bin/bash" ]
CMD [ "/usr/local/bin/init" ]
