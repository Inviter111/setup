#!/bin/bash

set -eo pipefail

TEMP_FILE=temp
DOWNLOADS=downloads
INSTALL_FOLDER=$(pwd)
mkdir ./$DOWNLOADS 2>/dev/null || true

GO_VERSION="1.22.5"

if [ -n "$DEBUG" ]; then
    set -x
fi



trap 'echo "Error: $? at line $LINENO" >&2' ERR

function cleanup() {
    echo "Cleaning up..."

#     rm -r $DOWNLOADS
}

trap 'cleanup' EXIT

function setup {
    echo ""
    add_to_sudoers

    echo ""
    install_zsh

    echo ""
    install_initials

    echo ""
    install_neovim

    echo ""
    install_alacritty

    echo ""
    install_tmux

    echo ""
    install_ssh_keys

    echo ""
    install_dotfiles

    echo ""
    install_postgresql

    echo ""
#     setup_kde
#     setup_vmware
#     populate_sources_list
}

function install_postgresql {
    if [[ -z $(psql -c "select version();" 2>/dev/null) ]]; then
        echo "Installing postgresql..."

        if [[ -z $(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep postgres) ]]; then
            sudo apt install -y postgresql-common
            sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
        fi

        sudo apt install -y postgresql

        echo "Postgresql installed, lets set up user with database"
        read -p "Enter username (default is $USER): " pg_user
        read -s -p "Enter password (if empty, same as username): " pg_password
        echo ""
        read -p "Enter database name (if empty, same as username): " pg_db
        pg_user=${pg_user:-$USER}
        pg_password=${pg_password:-$USER}
        pg_db=${pg_db:-$USER}

        psql_command="psql -c \"CREATE ROLE $pg_user WITH LOGIN SUPERUSER PASSWORD '$pg_password';\""
        sudo su -c "$psql_command" postgres
        sudo su -c "createdb -O $pg_user $pg_db" postgres

        echo "Postgresql installed"
    else
        echo "Postgresql already installed, skipping"
    fi
}

function install_dotfiles {
    dotfiles_dir="$HOME/.dotfiles"
    default_dotfiles_link="git@github.com:Inviter111/dotfiles.git"

    if [[ ! -d $dotfiles_dir ]]; then
        echo -e "Installing dotfiles..."
        echo "Dotfiles dir was not found, should download"
        read -p "Provide a link to github repo or use default ($default_dotfiles_link): " dotfiles_link
        dotfiles_link="${dotfiles_link:-${default_dotfiles_link}}"
        echo "Cloning from $dotfiles_link"
        git clone --depth 1 $dotfiles_link $dotfiles_dir

        if [[ ! $(which stow) ]]; then
            echo "Stow was not installed, it can be installed with `install_initials` function"
            exit 1
        fi

        stow --dir $dotfiles_dir --target $HOME .

        echo "Dotfiles linked"
    else
        echo "Dotfiles already installed, skipping"
    fi
}

function install_ssh_keys {
    if [[ ! $(find $HOME/.ssh/ -iname '*.pub') ]]; then
        echo -e "Installing ssh keys..."

        ssh_key_file="$HOME/.ssh/id_ed25519"
        echo "SSH keys was not found, generating new ones"
        ssh-keygen -N "" -t ed25519 -a 32 -C "$USER" -f $HOME/.ssh/id_ed25519 1>/dev/null

        echo -e "\nGenerated public ssh key\n$(cat $ssh_key_file.pub)\n"
        read -p "Press enter to continue"

        echo "SSH keys installed"
    else
        echo "SSH keys already installed, skipping"
    fi
}

function install_tmux {
    if [[ ! $(which tmux) ]]; then
        echo "Installing tmux..."

        sudo apt install -yq tmux

        echo "Tmux installed"
    else
        echo "Tmux already installed, skipping"
    fi
}

function install_alacritty {
    alacritty_source_folder="$DOWNLOADS/alacritty"
    alacritty_installed_bin="$alacritty_source_folder/target/release/alacritty"
    alacritty_bin="/usr/bin/alacritty"
    alacritty_icon_path="/usr/share/icons/alacritty/alacritty.png"

    if [[ ! -e $alacritty_bin || ! -e $alacritty_icon_path ]]; then
        echo -e "Installing alacritty..."

        echo "Installing deps"
        sudo apt install -yq cmake pkg-config libfreetype6-dev libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev python3
        echo "Deps installed"


        if [[ ! -d "$alacritty_source_folder" ]]; then
            echo "Cloning alacritty"
            git clone https://github.com/alacritty/alacritty.git $alacritty_source_folder
        fi

        if [[ ! -e "$alacritty_installed_bin" ]]; then
            echo "Builded binary not found, building now"
            xdg_session=$(echo "$XDG_SESSION_TYPE")
            cd $alacritty_source_folder
            if [[ $xdg_session == "wayland" ]]; then
                echo "Installing alacritty for Wayland"
                cargo build --release --no-default-features --features=wayland 1>/dev/null
            elif [[ $xdg_session == "x11" ]]; then
                echo "Installing alacritty for X11"
                cargo build --release --no-default-features --features=x11 1>/dev/null
            else
                echo "No XDG_SESSION_TYPE was found, installing alacritty with default options"
                cargo build --release 1>/dev/null
            fi
        else
            echo "Alacritty already built"
        fi

        if [[ ! -e "$alacritty_bin" ]]; then
            echo "Copying built binary to $alacritty_bin"
            sudo cp $alacritty_installed_bin $alacritty_bin
        else
            echo "Alacritty binary already exists"
        fi

        desktop_entry_filepath=$(find $alacritty_source_folder -iname '*.desktop')
        desktop_entry_file=$(echo "$desktop_entry_filepath" | awk -F'/' '{print $NF}')
        if [[ ! -e $(find /usr/share/application -iname "$desktop_entry_file") ]]; then
            echo "Copying icon to $alacritty_icon_path"
            sudo rsync -abuP --mkpath $(find $alacritty_source_folder -iname 'alacritty-term.png') $alacritty_icon_path

            echo "Copying $desktop_entry_filepath -> /usr/share/applications/$desktop_entry_file"
            sudo cat $desktop_entry_filepath | sed "s|Icon=.*|Icon=$alacritty_icon_path|g" > /usr/share/applications/$desktop_entry_file

            if [[ $(which kbuildsycoca5) ]]; then
                # Update desktop entries
                kbuildsycoca5 --noincremental
            fi
        fi

        if [[ -d $alacritty_source_folder ]]; then
            echo "Cleaning alacritty downloads"
            rm -rf $alacritty_source_folder
        fi

        echo "Alacritty installed"
    else
        echo "Alacritty already installed, skipping"
    fi
}

function install_zsh {
    if [ -n "$ZDOTDIR" ] && [ "$ZDOTDIR" != "$HOME" ]; then
        OH_MY_ZSH="${OH_MY_ZSH:-$ZDOTDIR/ohmyzsh}"
    fi
    OH_MY_ZSH="${OH_MY_ZSH:-$HOME/.oh-my-zsh}"

    if [[ $(which zsh) && -d "$OH_MY_ZSH" ]]; then
        echo "Zsh already installed, skipping"
    else
        echo -e "\nInstalling Zsh..."

        if [[ -z $(which zsh) ]]; then
            sudo apt install -yq zsh
        else
            echo "Zsh already installed, skipping"
        fi

        if [[ -z $(cat /etc/shells | grep "zsh") ]]; then
            echo "Zsh not added in verified shells, check your /etc/shells file"
            exit 1
        else
            if [[ "$SHELL" != "$(which zsh)" ]]; then
                sudo chsh -s $(which zsh)
                echo "Zsh set as default editor, relogin and rerun script from zsh"
                exit 1
            fi
        fi

        if [[ -d "$OH_MY_ZSH" ]]; then
            echo "oh-my-zsh already installed, skipping"
        else
            wget \
                --directory-prefix=./$DOWNLOADS/oh-my-zsh \
                https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
            sh $DOWNLOADS/oh-my-zsh/install.sh
        fi

        rm -r $DOWNLOADS/oh-my-zsh

        echo "Zsh installed"
    fi
}

function install_neovim {
    if [[ $(which nvim) ]]; then
        echo "Neovim already installed, skipping"
    else
        echo -e "\nInstalling Neovim..."

        if ! test -f ./$DOWNLOADS/nvim-linux64.tar.gz; then
            echo "Downloading prebuilt archive"
            curl -LO --output-dir "./$DOWNLOADS" https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
        else
            echo "Archive already exists"
        fi

        if ! test -d ./$DOWNLOADS/nvim; then
            echo "Unzipping archive"
            mkdir ./$DOWNLOADS/nvim
            tar xvf ./$DOWNLOADS/nvim-linux64.tar.gz --directory ./$DOWNLOADS/nvim 1>/dev/null
        else
            echo "Archive already unzipped, skipping"
        fi

        if ! test -f /usr/bin/nvim && ! test -d /usr/lib/nvim && ! test -d /usr/share/nvim; then
            echo "Copying Neovim files"
            sudo rsync -abuP $DOWNLOADS/nvim/nvim-linux64/ /usr/ 1>/dev/null
        else
            echo "Nvim already installed!"
        fi

        if [[ -z $(which vim) ]]; then
            echo "Setting alternatives to vim"
            sudo update-alternatives --install /usr/bin/vim vim /usr/bin/nvim 100
        fi

        echo "Neovim installed"

        rm ./$DOWNLOADS/nvim-linux64.tar.gz
        rm -r ./$DOWNLOADS/nvim
    fi
}

function install_initials {
    echo "Installing initial packages"

    sudo apt install -yq build-essential aptitude-common curl tldr tree stow

    if [[ -z $(which cargo) ]]; then
        echo "Installing rustup"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile default
        source "$HOME/.cargo/env"
        echo "Rustup installed"
    fi

    if [[ -z $(which node) ]]; then
        echo "Installing nvm"

        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
        export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

        nvm install --lts

        echo "Nodejs and NVM installed"
    fi

    if [[ -z $(which go) ]]; then
        echo "Installing golang"

        if [[ -d "/usr/local/go" ]]; then
            echo "Found an existing go installation, removing it"
            sudo rm -rf /usr/local/go
        fi

        if [[ ! -e "./$DOWNLOADS/go$GO_VERSION.linux-amd64.tar.gz" ]]; then
            curl -LO --output-dir "./$DOWNLOADS" https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz
        fi

        sudo tar -C /usr/local -xzf $DOWNLOADS/go$GO_VERSION.linux-amd64.tar.gz
        echo 'PATH="$PATH:/usr/local/go/bin"' >> $HOME/.profile
        echo 'PATH="$PATH:/usr/local/go/bin"' >> $HOME/.zshrc
        source ~/.profile

        echo "Installed go version"
        go version

        rm "./$DOWNLOADS/go$GO_VERSION.linux-amd64.tar.gz" 2>/dev/null || true
    fi

    read -p "Install fonts? ([Y]es/[N]o - default)" response
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    if [[ "$response" == "yes" || "$response" == "y" ]]; then
        echo "Installing fonts"

        fonts_dir="$HOME/.local/share/fonts"
        mkdir -p $fonts_dir
        declare -a font_families=(
            "JetBrainsMono"
        )
        for font_family in "${font_families[@]}"; do
            if [[ ! -e "$fonts_dir/$font_family" ]]; then
                mkdir $fonts_dir/$font_family
            fi

            if [[ ! -e "$DOWNLOADS/fonts/$font_family/$font_family.tar.xz" ]]; then
                echo "Downloading font $font_family"
                mkdir -p $DOWNLOADS/fonts/$font_family
                curl -fLO --output-dir "$DOWNLOADS/fonts/$font_family" https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/$font_family.tar.xz
            fi

            if [[ -z $(ls -A "$fonts_dir/$font_family") ]]; then
                echo "Extracting font $font_family to $fonts_dir/$font_family"
                tar xf ./$DOWNLOADS/fonts/$font_family/$font_family.tar.xz --directory $fonts_dir/$font_family
                fc-cache $fonts_dir
            fi
        done

        echo "Fonts installed"

        rm -rf $DOWNLOADS/fonts
    else
        echo "Skipping fonts"
    fi

    echo "Initial packages installed"
}

function setup_kde {
    echo "Checking KDE for setup"

    KDE_THEME="org.kde.breezedark.desktop"

    if [[ $(which lookandfeeltool) ]]; then
        echo "KDE found"

        if [[ $(lookandfeeltool --list | grep $KDE_THEME) ]]; then
            echo "Setting dark theme"
            lookandfeeltool -a $KDE_THEME
        fi
    else
        echo "KDE not found"
    fi
}

function add_to_sudoers {
    if [[ ! $(groups $USER | grep sudo) ]]; then
        echo "Adding to sudoers"

        su root -c "sudo usermod -aG sudo $USER"
        su $USER

        echo "User $USER added to sudoers"
    else
        echo "$USER already in sudoers, skipping"
    fi
}

function setup_vmware {
    if [[ $(sudo dmesg | grep -i hypervisor | grep vmware) ]]; then
        echo ""
        read -p "Looks like you are running in VMWare, setup tools for it? ([Y]es/[N]o) " response
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
        if [[ "$response" == "yes" || "$response" == "y" ]]; then

            read -p "Delete old tools? ([Y]es/[N]o - default) " response
            response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
            if [[ "$response" == "yes" || "$response" == y ]]; then
#                 sudo apt autoremove open-vm-tools open-vm-tools-desktop

                echo "Uninstalled old packages. Reboot your VM now and go VM > Install VMWare Tools"
                echo "PS: Sometimes vmware-tools.service could crash, investigate later"
                exit 1
            fi

            tools_archive=$(sudo find /media/ -iname 'vmwaretools*.tar.gz')

            if [ "true" ]; then
                tools_archive=$(sudo find /media/ -iname 'vmwaretools*.tar.gz')

                if [[ "$tools_archive" ]]; then
                    if ! test -f ./$DOWNLOADS/vmware-tools.tar.gz; then
                        cp $tools_archive ./$DOWNLOADS/vmware-tools.tar.gz
                    else
                        echo "Archive ./$DOWNLOADS/vmware-tools.tar.gz already exists, skipping"
                    fi

                    if ! test -d ./$DOWNLOADS/vmware-tools; then
                        mkdir ./$DOWNLOADS/vmware-tools
                        tar xvf ./$DOWNLOADS/vmware-tools.tar.gz --directory=./$DOWNLOADS/vmware-tools 1>/dev/null
                    else
                        echo "Archive already unzipped, skipping"
                    fi

                    installer=$(find ./$DOWNLOADS/vmware-tools -name 'vmware-install.pl')
                    sudo chmod +x $installer
                    sudo bash -c "sudo $installer"
                    sudo apt install -yq open-vm-tools-desktop

                    mount_point="/media/$(echo $tools_archive | awk -F' |/' '{print $3}')"
                    if test -d $tools_archive; then
                        sudo umount $mount_point
                        echo "$mount_point unmounted"
                    fi
                else
                    echo "VMware tools archive not found, check mounted devices"
                    echo "Goto VM > Install VMVare Tools and run again"
                    exit 1
                fi
            else
                echo "Unmounting everything on /mnt/"
                # TODO
            fi

            echo "Deleting vmware tools downloads"

            rm -rf \
                ./$DOWNLOADS/vmware-tools.tar.gz \
                ./$DOWNLOADS/vmware-tools 2>/dev/null || true
        else
            echo "VMWare tools instalation skipped"
        fi
    fi
}

echo "Setting up..."

setup
























function populate_sources_list {
    SOURCES_LIST_FILE=/etc/apt/sources.list
    PREFERENCES_DIR=/etc/apt/preferences.d

    CURRENT_RELEASE=$(lsb_release -a | grep Codename: | awk '{print $2}')

    MAIN_REPO="deb http://deb.debian.org/debian/ $CURRENT_RELEASE main non-free-firmware
deb-src http://deb.debian.org/debian/ $CURRENT_RELEASE main non-free-firmware
    "
    SECURITY_REPO="deb http://security.debian.org/debian-security $CURRENT_RELEASE-security main non-free-firmware
deb-src http://security.debian.org/debian-security $CURRENT_RELEASE-security main non-free-firmware
    "
    UPDATES_REPO="# Debian Updates
deb http://deb.debian.org/debian/ $CURRENT_RELEASE-updates main non-free-firmware
deb-src http://deb.debian.org/debian/ $CURRENT_RELEASE-updates main non-free-firmware
    "

    echo "Current release $CURRENT_RELEASE"

    echo "Populating sources"

    if test -f $SOURCES_LIST_FILE && ! test -f $SOURCES_LIST_FILE.old; then
        echo "Backing up $SOURCES_LIST_FILE > $SOURCES_LIST_FILE.old"
        sudo mv $SOURCES_LIST_FILE $SOURCES_LIST_FILE.old
    else
        echo "Backup already exists in $SOURCES_LIST_FILE.old"
    fi

    echo "Populating $PREFERENCES_DIR"
    echo "Delete existing files"
    sudo rm \
        $PREFERENCES_DIR/stable.pref \
        $PREFERENCES_DIR/testing.pref \
        $PREFERENCES_DIR/unstable.pref \
        $PREFERENCES_DIR/experimental.pref 2>/dev/null || true # We dont care if it fails

    sudo tee $PREFERENCES_DIR/stable.pref <<< "Package: *
Pin: release a=stable n=$CURRENT_RELEASE
Pin-Priority: 900
    " 1>/dev/null

    sudo tee $PREFERENCES_DIR/testing.pref <<< "Package: *
Pin: release a=testing
Pin-Priority: 400
    " 1>/dev/null

    sudo tee $PREFERENCES_DIR/unstable.pref <<< "Package: *
Pin: release a=unstable
Pin-Priority: 50
    " 1>/dev/null

    sudo tee $PREFERENCES_DIR/experimental.pref <<< "Package: *
Pin: release a=experimental
Pin-Priority: 1
    " 1>/dev/null

    echo "Populating sources directory $SOURCES_LIST_FILE.d/"

    sudo rm \
        $SOURCES_LIST_FILE.d/stable.pref \
        $SOURCES_LIST_FILE.d/testing.pref \
        $SOURCES_LIST_FILE.d/unstable.pref \
        $SOURCES_LIST_FILE.d/experimental.pref 2>/dev/null || true # We dont care if it fails

    sudo tee $SOURCES_LIST_FILE.d/stable.list <<< "$MAIN_REPO" 1>/dev/null
    sudo tee $SOURCES_LIST_FILE.d/stable.list <<< "$SECURITY_REPO" 1>/dev/null
    sudo tee $SOURCES_LIST_FILE.d/stable.list <<< "$UPDATES_REPO" 1>/dev/null

    sudo tee $SOURCES_LIST_FILE.d/testing.list <<< "${MAIN_REPO//$CURRENT_RELEASE/testing}" 1>/dev/null
    sudo tee $SOURCES_LIST_FILE.d/testing.list <<< "${SECURITY_REPO//$CURRENT_RELEASE/testing}" 1>/dev/null
    sudo tee $SOURCES_LIST_FILE.d/testing.list <<< "${UPDATES_REPO//$CURRENT_RELEASE/testing}" 1>/dev/null

    sudo tee $SOURCES_LIST_FILE.d/unstable.list <<< "${MAIN_REPO//$CURRENT_RELEASE/unstable}" 1>/dev/null

    sudo tee $SOURCES_LIST_FILE.d/experimental.list <<< "${MAIN_REPO//$CURRENT_RELEASE/experimental}" 1>/dev/null

    echo "Sources lists are set, updating apt"

    sudo apt update
}
