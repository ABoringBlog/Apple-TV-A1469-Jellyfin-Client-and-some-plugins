# Third-party notices

## atvr4samsung

The native iPhone Control Center Companion Link server is based on:

- Project: atvr4samsung
- Upstream: https://github.com/vb3/atvr4samsung
- Pinned commit: `7673178729a12b20c7d7a0bc968fc1786cbf2567`
- Copyright: Copyright (c) 2026 vb3
- License: MIT

This repository does **not** vendor the upstream Git repository. `Scripts/setup_mac.sh` clones the pinned commit and applies `Patches/atvr4samsung-atv3.patch`.

The patch adds the ATV3-specific behavior used by this project, including Select press/release edges, directional hold timing, Play short/long behavior, media Next/Previous capabilities, and IME `textToCommit` handling for committed CJK input.

The upstream MIT license is reproduced in `ThirdParty/atvr4samsung-LICENSE`.

## pyatv

The Mac-to-Apple-TV-3 legacy DMAP side uses `pyatv==0.18.0`, installed as a runtime dependency by the setup script. pyatv is not vendored in this repository.

Users are responsible for reviewing and complying with the licenses and terms of all third-party dependencies installed on their systems.
