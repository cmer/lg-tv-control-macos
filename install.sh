#!/bin/zsh

# Add Homebrew to PATH if it's installed, but not already in PATH
if ! command -v brew &> /dev/null; then
  if [ -x /opt/homebrew/bin/brew ]; then
    export PATH="/opt/homebrew/bin:$PATH"
  elif [ -x /usr/local/bin/brew ]; then
    export PATH="/usr/local/bin:$PATH"
  fi
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    echo "Installing for Apple Silicon (arm64)"
elif [[ "$ARCH" == "x86_64" ]]; then
    echo "Installing for Intel (x86_64)"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

if [ ! -d "/Applications/Hammerspoon.app" ]; then
  if ! command -v brew &> /dev/null; then
    echo -e "\033[1;31mHomebrew is not installed. Please install Homebrew and try again.\033[0m"
    exit 1
  fi
  echo -e "\033[32mInstalling Hammerspoon...\033[0m"
  brew install -q hammerspoon
fi

if ! command -v wakeonlan &> /dev/null; then
  if ! command -v brew &> /dev/null; then
    echo -e "\033[1;31mHomebrew is not installed. Please install Homebrew and try again.\033[0m"
    exit 1
  fi
  echo -e "\033[32mInstalling wakeonlan...\033[0m"
  brew install -q wakeonlan
fi

# Create symlink for wakeonlan
WAKEONLAN_PATH=$(which wakeonlan)
if [ -n "$WAKEONLAN_PATH" ]; then
    ln -sf "$WAKEONLAN_PATH" ~/bin/wakeonlan
else
    echo -e "\033[1;31mError: Could not find wakeonlan executable\033[0m"
    exit 1
fi

mkdir -p ~/.hammerspoon
touch ~/.hammerspoon/init.lua
if ! grep -q 'require "lgtv"' ~/.hammerspoon/init.lua; then
  echo "require \"lgtv\"" >> ~/.hammerspoon/init.lua
fi
cp ./lgtv.lua ~/.hammerspoon/lgtv.lua

mkdir -p ~/bin
if [ ! -f "./tools/dist/bscpylgtvcommand-$ARCH" ]; then
    echo -e "\033[1;31mError: bscpylgtvcommand-$ARCH not found in tools/dist/ directory.\033[0m"
    echo -e "\033[1;31mPlease run tools/build-bscpylgtv.sh first to compile for your architecture ($ARCH).\033[0m"
    exit 1
fi

# Remove old lgtv_init.lua if it exists
if [ -f ~/.hammerspoon/lgtv_init.lua ]; then
    echo "Removing old version of lgtv_init.lua..."
    rm ~/.hammerspoon/lgtv_init.lua
    # Remove require line from init.lua
    perl -ni -e 'print unless /require "lgtv_init"/' ~/.hammerspoon/init.lua
fi

cp ./tools/dist/bscpylgtvcommand-$ARCH ~/bin/bscpylgtvcommand

# Prompt for TV IP address
echo -n -e "\nPlease enter your LG TV's IP address: "
read TV_IP

echo -e "\033[32mConnecting to LG TV at $TV_IP...\033[0m"
echo -e "\033[33mAccept the connection on the TV...\033[0m"
echo -e "\033[33mPress CTRL-C to abort...\033[0m"

cd ~
bin/bscpylgtvcommand $TV_IP get_apps_all true > /dev/null 2>&1
EXIT_CODE=$?
cd -

if [ $EXIT_CODE -ne 0 ]; then
    echo -e "\033[1;31mError: Failed to connect to LG TV at $TV_IP. Please check the IP address and try again.\033[0m"
    exit 1
fi

if [ -f ~/.aiopylgtv.sqlite ]; then
  echo "Encryption keys stored at ~/.aiopylgtv.sqlite"
fi

# Get MAC address of TV
echo -e "\033[32m\nGetting TV MAC address...\033[0m"
ping -c 1 $TV_IP > /dev/null 2>&1
MAC_ADDRESS=$(arp -n $TV_IP | tail -n1 | awk '{print $4}' | awk '{print toupper($0)}')

if ! [ -n "$MAC_ADDRESS" ] || ! [[ "$MAC_ADDRESS" =~ ^([0-9A-F]{1,2}:){5}[0-9A-F]{2}$ ]]; then
    echo -e "\033[1;33mWarning: Could not determine TV MAC address or format is invalid\033[0m"
    echo -e "\n--> You can find the MAC address of your TV by running \`arp -n $TV_IP\` in a separate Terminal.\n\n"
    echo -n "Please enter your TV's MAC address (format XX:XX:XX:XX:XX:XX): "
    read MAC_ADDRESS
    while ! [[ "$MAC_ADDRESS" =~ ^([0-9A-F]{1,2}:){5}[0-9A-F]{2}$ ]]; do
        echo -e "\033[1;31mInvalid MAC address format. Please use format XX:XX:XX:XX:XX:XX\033[0m"
        echo -n "Please enter your TV's MAC address: "
        read MAC_ADDRESS
    done
fi

echo "TV MAC Address: $MAC_ADDRESS"

# Update TV IP and Mac Address in Hammerspoon config
perl -pi -e "s/tv_ip = \"\"/tv_ip = \"$TV_IP\"/" ~/.hammerspoon/lgtv.lua
perl -pi -e "s/tv_mac_address = \"\"/tv_mac_address = \"$MAC_ADDRESS\"/" ~/.hammerspoon/lgtv.lua


echo -e "\033[32m\n--------------------------------------------------------------------\033[0m"
echo " Installation Complete!"
echo -e "\033[32m--------------------------------------------------------------------\n\033[0m"
