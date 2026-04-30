# dpadr

A tiny D-pad remote for any ADB-connected Android device. Single Go binary, web UI, no dependencies.

## Features

- D-pad (Up / Down / Left / Right / OK) plus Back, Home, Recents
- Numpad (0–9, ∗, ⌫) for dialer / PIN entry
- Speaks the ADB protocol directly over TCP — no `adb.exe` shell-out
- Embedded web UI — single self-contained executable
- Light + dark theme with toggle
- Mobile-responsive layout
- Keyboard input: arrow keys, Enter / Space, Esc / Backspace, H, R
- Multi-device picker
- Multi-display picker (Android 10+) — routes via `input -d <id>`
- LAN-accessible — bind `-addr 0.0.0.0:7878` to control from your phone
