# Select Desktop Environment
FROM docker.io/ubuntu:20.04

# Install core dependencies
RUN apt-get update \
  && apt-get install -y \
    locales \
    software-properties-common \
  && apt-get clean

# Configure system
RUN printf 'LANG=en_US.UTF-8' > /etc/locale.conf \
  && sed -i 's/^#\(en_US\.UTF-8.*\)$/\1/g' /etc/locale.gen \
  && sed -i 's/^#\(ko_KR\.EUC-KR.*\)$/\1/g' /etc/locale.gen \
  && sed -i 's/^#\(ko_KR\.UTF-8.*\)$/\1/g' /etc/locale.gen \
  && locale-gen \
  && ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime

# Install dependencies
WORKDIR /tmp
ADD custom/packages .
ADD custom/repos .
RUN add-apt-repository $(cat repos | grep -o '^[^#]*') \
  && apt-get update \
  && apt-get install -y $(cat packages | grep -o '^[^#]*') \
  && apt-get clean

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

# Initiate with systemd
USER root
WORKDIR /tmp
ADD core/init /usr/local/bin/init
RUN chmod +x /usr/local/bin/init
ENTRYPOINT [ "/bin/bash" ]
CMD [ "/usr/local/bin/init" ]
