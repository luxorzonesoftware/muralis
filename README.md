# muralis
**muralis** is a minimal, flexible wallpaper manager for X11 and Wayland. It uses `feh` on X11 and `swaymsg` on Wayland. Originally created for an i3 setup, it now targets compatibility with any desktop environment, display manager, or window manager.

Key features:

- **Multi-monitor support:** Uses XRandR or Wayland output queries to detect displays and allows both per-monitor and global wallpaper directories.
- **Randomized wallpapers:** Automatically selects and sets random backgrounds.
- **Automation:** Integrates with systemd user services and timers to change wallpapers at configurable intervals.
- **Easy setup:** Build from source or install via an Arch PKGBUILD.
- **Broad compatibility:** Works across X11 and Wayland setups, making it suitable for virtually any desktop environment, display manager, or window manager.

muralis is designed for simplicity and minimalism, making it easy to keep your desktop fresh with minimal resource usage.

## Installation

### Arch Linux

An example `PKGBUILD` is provided. To build and install:

```sh
makepkg -si
```

When publishing to the AUR, replace `OWNER` in the `source` URL with your GitHub username.

### From source

Run the script directly or install into `~/.local/bin`:

```sh
./muralis.sh --install
```
