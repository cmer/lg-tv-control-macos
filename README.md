# LG TV Control for macOS

Automatically wake/sleep and change the input of your LG TV when used as a monitor on macOS.

This script uses Hammerspoon to detect system events such as power off, sleep, and wake.

## Requirements

- [Hammerspoon](https://www.hammerspoon.org/)
- Python 3
- [LGWebOSRemote](https://github.com/klattimer/LGWebOSRemote)

### Installing Requirements

This assumes that you already have [Homebrew](https://brew.sh) installed. If you don't, get it first.

## Installing Hammerspoon

```sh
brew install --cask hammerspoon
```

### Installing Python & LGWebOSRemote

```sh
# You can skip this if you already have Python installed and know what you're doing.
brew install python

# Then install LGWebRemote...
mkdir -p ~/opt
python -m venv ~/opt/lgtv
cd ~/opt/lgtv
source bin/activate
pip install git+https://github.com/klattimer/LGWebOSRemote
```

### Configuring LGWebOSRemote

By now, you should be able to run

```sh
lgtv scan
```

and see some info about your TV. Grab your TV's IP address from the output. Then:

```sh
lgtv auth <ip_address_here> MyTV
```

and follow the instructions on your TV.

Now, try the following:

```sh
lgtv MyTV swInfo
lgtv MyTV screenOff
```

If everything is working as expected, your screen should turn off.

## Installing the Hammerspoon script

1. Copy `lgtv.lua`from this repo to `~/.hammerspoon`
2. Add `require "lgtv"` in `~/.hammerspoon/init.lua`
3. Change

## Special Thanks

Thanks to @greyshi for extending upon my [initial Wake On LAN gist](https://gist.github.com/cmer/bd40d9da0055d257c5aab2e0143ee17b) and introducing LGWebOSRemote.
