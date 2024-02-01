# LG TV Control for macOS

Automatically wake/sleep and change the input of your LG TV when used as a monitor on macOS.

This script uses Hammerspoon to detect system events such as power off, sleep, and wake.

## Pre-installation Requirements

- [Homebrew](https://brew.sh/)

### Installation

Use the installation script for a simple and convenient installation process.

Before proceeding, make sure you have [Homebrew](https://brew.sh) installed. All the other dependencies will be installed automatically:

- [Mise](https://mise.jdx.dev/)
- Python 3.8.18
- [Hammerspoon](https://www.hammerspoon.org/)
- [LGWebOSRemote](https://github.com/klattimer/LGWebOSRemote).

Run the following commands in Terminal:

```bash
cd /tmp
git clone https://github.com/cmer/lg-tv-control-macos.git
cd lg-tv-control-macos
./install.sh
```


#### Removing old versions of LGWebOSRemote

If you had previously installed LGWebOSRemote with PIP,
you can remove the old version by running:

```
rm -fr ~/opt/lgtv
```

### Configuring LGWebOSRemote

By now, you should be able to run

```sh
~/bin/lgtv scan ssl
```

and see some info about your TV. Grab your TV's IP address from the output. Then:

```sh
~/bin/lgtv auth <ip_address_here> MyTV --ssl
```

and follow the instructions on your TV.

Now, try the following:

```sh
~/bin/lgtv --name MyTV --ssl swInfo
~/bin/lgtv --name MyTV --ssl screenOff
```

If everything is working as expected, your screen should turn off.

Change the HDMI input at the top of `~/.hammerspoon/init_lgtv.lua` script, if needed.

## Special Thanks

Thanks to [@greyshi](https://github.com/greyshi) for extending upon my [initial Wake On LAN gist](https://gist.github.com/cmer/bd40d9da0055d257c5aab2e0143ee17b) and introducing LGWebOSRemote.
