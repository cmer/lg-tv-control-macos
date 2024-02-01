#!/bin/zsh

if [[ " $* " =~ " --help " ]]; then
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --skip-homebrew  Skip Homebrew detection"
  echo "  --skip-mise      Skip Mise detection and installation"
  echo "  --help           Show this help message"
  exit 0
fi

if [[ ! " $* " =~ " --skip-homebrew " ]]; then
  if ! command -v brew &> /dev/null
  then
    echo -e "\033[1;31mHomebrew is not installed. Please install Homebrew and try again.\033[0m"
    exit 1
  fi
fi

if [[ ! " $* " =~ " --skip-mise " ]]; then
  if ! command -v mise &> /dev/null
  then
    echo -e "\033[1;33mMise is not installed. Preparing to install it... CTRL-C to abort.\033[0m"
    sleep 3

    echo -e "\033[32mInstalling Mise...\033[0m"
    brew install mise

    echo 'eval "$(mise activate bash)"' >> ~/.bashrc
    echo 'eval "$(mise activate zsh)"' >> ~/.zshrc

    if [ -f ~/.config/fish/config.fish ]; then
      echo 'eval mise activate fish | source' >> ~/.config/fish/config.fish
    fi
  fi
fi

echo -e "\033[32mInstalling Hammerspoon...\033[0m"
brew install -q hammerspoon
mkdir -p ~/.hammerspoon
touch ~/.hammerspoon/init.lua
if ! grep -q 'require "lgtv_init"' ~/.hammerspoon/init.lua; then
  echo "require \"lgtv_init\"" >> ~/.hammerspoon/init.lua
fi
cp ./lgtv_init.lua ~/.hammerspoon/lgtv_init.lua

echo -e "\033[32mDownloading LGWebOSRemote...\033[0m"
mkdir -p ~/opt
cd ~/opt
rm -rf LGWebOSRemote
git clone  --quiet https://github.com/klattimer/LGWebOSRemote.git

echo -e "\033[32mInstalling Python...\033[0m"
cd LGWebOSRemote
mise use python@3.8.18
mise install
mise exec -- python -V

echo -e "\033[32mInstalling LGWebOSRemote...\033[0m"
mise exec -- pip install --upgrade pip > /dev/null
mise exec -- pip install setuptools > /dev/null
mise exec -- python setup.py install > /dev/null

LGTVPATH=$(mise exec -- which lgtv)
echo "lgtv executable can be found at $LGTVPATH"
mkdir -p ~/bin
rm -f ~/bin/lgtv
ln -s $LGTVPATH ~/bin/lgtv

$LGTVPATH scan ssl

echo -e "\033[32m\n--------------------------------------------------------------------\033[0m"
echo " Installation Complete!"
echo " You can now use the '~/bin/lgtv' command to control your LG TV."
echo -e "\033[32m--------------------------------------------------------------------\n\033[0m"
