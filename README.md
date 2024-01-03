# LG TV Control for macOS

Automatically wake/sleep and change the input of your LG TV when used as a monitor on macOS.

This script uses Hammerspoon to detect system events such as power off, sleep, and wake.

## Requirements

- [Hammerspoon](https://www.hammerspoon.org/)
- Python 3.11
- [LGWebOSRemote](https://github.com/klattimer/LGWebOSRemote) (version 2023-12-11 or newer)

### Installing Requirements

This assumes that you already have [Homebrew](https://brew.sh) installed. If you don't, get it first.

## Installing Hammerspoon

```sh
brew install --cask hammerspoon
```

### Installing Python & LGWebOSRemote

```sh
# You can skip this if you already have Python installed and know what you're doing.
brew install python@3.11
pip install pipx

# Then install LGWebRemote...
pipx install git+https://github.com/klattimer/LGWebOSRemote.git
pipx ensurepath
```

#### Removing old versions of LGWebOSRemote

If you had previously installed LGWebOSRemote with pip (rather than pipx),
you can remove the old version by running:

```
rm -fr ~/opt/lgtv
```

### Configuring LGWebOSRemote

By now, you should be able to run

```sh
lgtv scan ssl
```

and see some info about your TV. Grab your TV's IP address from the output. Then:

```sh
lgtv auth <ip_address_here> MyTV --ssl
```

and follow the instructions on your TV.

Now, try the following:

```sh
lgtv --name MyTV --ssl swInfo
lgtv --name MyTV --ssl screenOff
```

If everything is working as expected, your screen should turn off.

## Installing the Hammerspoon script

1. Copy `lgtv_init.lua`from this repo to `~/.hammerspoon`
2. Run the following

```sh
mkdir -p ~/.hammerspoon
touch ~/.hammerspoon/init.lua
echo "require \"lgtv_init\"" >> ~/.hammerspoon/init.lua
```

3. Change the HDMI input at the top of the Lua script, if needed.

## Special Thanks

Thanks to [@greyshi](https://github.com/greyshi) for extending upon my [initial Wake On LAN gist](https://gist.github.com/cmer/bd40d9da0055d257c5aab2e0143ee17b) and introducing LGWebOSRemote.
