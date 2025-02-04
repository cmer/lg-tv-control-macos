# LG TV Control for macOS

> **IMPORTANT NOTICE:** It is advised to remain on webOS 23 while we determine if webOS 24 is fully compatible. If you upgrade, you cannot roll back, so it's better to hold back for now!

Automatically wake/sleep and change the input of your LG TV when used as a monitor on macOS.

This script uses Hammerspoon to detect system events such as power off, sleep, and wake.

It makes use of [`bscpylgtv`](https://github.com/chros73/bscpylgtv) to control the TV set. It is included in this repository for Apple Silicon but can easily be compiled for Intel if desired.

## Pro Tips

- For the best result, make sure you configure your TV for PC use. [This video](https://youtu.be/zv-2yP7Rumo?si=vlrtGhWwUl8aSjnt) is a great place to start.
- Make sure Wake on LAN is enabled in your TV settings. Settings > Support > IP Control Settings > Wake on LAN = ENABLED.

## Pre-installation Requirements

- [Homebrew](https://brew.sh/)

## Installation

Use the installation script for a simple and convenient installation process.

Before proceeding, make sure you have [Homebrew](https://brew.sh) installed.

Run the following commands in Terminal:

```bash
cd /tmp
git clone https://github.com/cmer/lg-tv-control-macos.git
cd lg-tv-control-macos
./install.sh
```

### Configuration
Change the HDMI input at the top of `~/.hammerspoon/lgtv.lua` script, if needed. Optionally, set `debug` to `true` if you are running into issues.


## Legacy version using LGWebOSRemote

This new and updated version no longer uses LGWebOSRemote, and does not require installing Python. It is therefore much easier to get going. 🎉

