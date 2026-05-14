## Third-Party Notices

This repository contains original project code licensed under Apache-2.0, as
described in [LICENSE](./LICENSE).

The built image also redistributes components from
`exodusferret/ZotacZone-Drivers`, which is licensed under GPL-3.0:

- upstream repository: `https://github.com/exodusferret/ZotacZone-Drivers`
- upstream license: GPL-3.0
- redistributed components:
  - `openzone_manager.sh`
  - `uninstall_openzone_drivers.sh`
  - `zotac_dial_daemon.py`
  - OpenZotacZone kernel modules built from the upstream driver sources

`bazzite-zone` applies image-packaging path adjustments to some upstream GPL
scripts so they work correctly on an immutable Bazzite image. Those modified
scripts remain GPL-3.0-covered works.

When the image is built, it ships:

- a copy of the upstream GPL-3.0 license in
  `/usr/share/licenses/bazzite-zone/OpenZotacZone-GPL-3.0.txt`
- source metadata in `/usr/share/doc/bazzite-zone/openzotaczone-source-info.txt`
- a corresponding source bundle for the redistributed OpenZotacZone GPL
  components in
  `/usr/share/doc/bazzite-zone/openzotaczone-corresponding-source.tar.gz`

The Apache-2.0 license for this repository does not relicense the included or
redistributed OpenZotacZone GPL components.
