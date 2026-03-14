# OpenZotacZone Bazzite Image for the Zotac Zone Handheld

This project builds a **custom** Bazzite image for the Zotac Zone gaming handheld with integrated OpenZotacZone drivers, 144 Hz and HDR fixes, improved fan control, and a preinstalled Decky Loader with a curated plugin set.[page:2]

## Why this image?

OpenZotacZone drivers installed via `build.sh` or manual scripts are only temporary and need to be rebuilt and reinstalled after kernel updates.[page:2]  
A custom Bazzite-based image makes these drivers persistent – they survive system updates, reboots, and rebases within the Universal Blue / bootc workflow.[page:2]

## Based on

- Zotac-specific adjustments: [https://github.com/Reed-Schimmel/ZotacBazzite](https://github.com/Reed-Schimmel/ZotacBazzite)[page:2]  
- Official Universal Blue image template: [https://github.com/ublue-os/image-template](https://github.com/ublue-os/image-template)[page:2]

## Features

- Integrated OpenZotacZone drivers, baked into the image and automatically loaded on boot.[page:2]  
- Zotac Zone–specific functionality:
  - Fully functional back buttons (P4/P3-like).[page:2]
  - RGB lighting controllable via OpenRGB.[page:2]
  - Fan curves (EC fan control) managed via CoolerControl.[page:2]
  - Joystick dials with precise input via rotation and press.[page:2]
  - Extended HID protocol support.[page:2]
  - Touchpad tweaks for more precise input.[page:2]
- Display & gaming:
  - HDR fix scripts for more reliable HDR activation in supported games.[page:2]
  - 144 Hz fixes (X11/Wayland configuration + Gamescope/KWin tuning) so the panel runs consistently at 144 Hz.[page:2]
- Convenience:
  - Preinstalled Decky Loader with a curated plugin selection.[page:2]

## Build note

Before rebuilding: rename `iso-gnome.toml` or `iso-kde.toml` to `iso.toml`, commit the change, then rebuild the image.[page:2]
