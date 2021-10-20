function __init__() {
    # Generate a default secret key
    sudo pacman-key --init
    sudo pacman-key --populate archlinux
    sudo pacman-key --populate archlinuxcn

    # Disable default compositor
    Configfile="~/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    [ -e $Configfile ] || {
        mkdir -p $(dirname $Configfile)
        echo '<?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <channel name=\"xfwm4\" version=\"1.0\">

        <property name=\"general\" type=\"empty\">
            <property name=\"use_compositing\" type=\"bool\" value=\"false\"/>
        </property>
    </channel>
    ' >$Configfile
    }
}

if [ ! -f /etc/pacman.d/gnupg ]; then
    __init__
fi

export GTK_IM_MODULE=nimf
export QT4_IM_MODULE="nimf"
export QT_IM_MODULE=nimf
export XMODIFIERS="@im=nimf"
nimf

export $(/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator)

picom -b --experimental-backends
plank &
