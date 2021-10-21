# Select Desktop Environment
FROM docker.io/archlinux:base-devel

# Install reflector for faster installation
ARG reflector_country="KR"
RUN pacman -Sy \
  && pacman -S --needed --noconfirm \
  reflector \
  && pacman -Sc --noconfirm \
  && sed -i "s/\(^# --country.*\$\)/\1\n--country $reflector_country/g" /etc/xdg/reflector/reflector.conf \
  && systemctl enable reflector.timer \
  && reflector --country $reflector_country > /etc/pacman.d/mirrorlist

# Add more package repositories
RUN printf '\n[archlinuxcn]\nServer = https://repo.archlinuxcn.org/$arch' >> /etc/pacman.conf \
  && printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist' >> /etc/pacman.conf \
  # generate a default secret key
  && pacman-key --init \
  # refresh database because of changing mirrorlists
  && pacman -Syy \
  # import PGP keys
  && pacman -S --noconfirm \
  archlinux-keyring \
  archlinuxcn-keyring \
  && pacman -Sc --noconfirm

# Reinstall excluded files
RUN sed -i 's/^NoExtract\(.*\)$//g' /etc/pacman.conf \
  && rm /etc/locale.gen \
  && pacman -Syy \
  && pacman -Qqn | pacman -S --noconfirm --overwrite="*" - \
  && pacman -Sc --noconfirm

# Install yay: AUR package manager
RUN pacman -S --noconfirm \
  yay \
  && pacman -Sc --noconfirm

# Create makepkg user and workdir
ARG makepkg=makepkg
RUN useradd --system --create-home $makepkg \
  && echo "$makepkg ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/$makepkg

# Create normal user account
ARG user=user
RUN useradd $user -m -g users -G wheel -s /bin/zsh \
  && echo "%wheel ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$user

# Configure system
RUN printf 'LANG=en_US.UTF-8' > /etc/locale.conf \
  && sed -i 's/^#\(en_US\.UTF-8.*\)$/\1/g' /etc/locale.gen \
  && sed -i 's/^#\(ko_KR\.EUC-KR.*\)$/\1/g' /etc/locale.gen \
  && sed -i 's/^#\(ko_KR\.UTF-8.*\)$/\1/g' /etc/locale.gen \
  && locale-gen \
  && ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime

# Install dependencies
USER $makepkg
WORKDIR /tmp
ADD custom/packages .
RUN yay -S --needed --noconfirm $(sudo cat packages | grep -o '^[^#]*') \
  && yay -Sc --noconfirm \
  && yay -Scc --noconfirm \
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

# Customize user settings
USER $user
ADD custom/autostart/ /home/$user/.config/autostart/
ADD custom/on-startup /usr/local/bin/
RUN sudo chown -R $user:users /home/$user \
  # Enable starting X
  && systemctl enable --user startx.service \
  # settings
  && sudo chmod +x /usr/local/bin/on-startup \
  # zsh
  && cp /usr/share/oh-my-zsh/zshrc /home/$user/.zshrc \
  # nimf
  && printf 'export GTK_IM_MODULE="nimf"' >> /home/$user/.zshrc \
  && printf 'export QT4_IM_MODULE="nimf"' >> /home/$user/.zshrc \
  && printf 'export QT_IM_MODULE="nimf"' >> /home/$user/.zshrc \
  && printf 'export XMODIFIERS="@im=nimf"' >> /home/$user/.zshrc

# Initiate with systemd
USER root
WORKDIR /tmp
ADD core/init /usr/local/bin/init
RUN chmod +x /usr/local/bin/init
ENTRYPOINT [ "/bin/bash" ]
CMD [ "/usr/local/bin/init" ]
