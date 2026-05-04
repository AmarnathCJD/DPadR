# dpadr

A tiny D-pad remote for any ADB-connected Android device. Single Go binary, web UI, no dependencies. Optional Flutter Android app over Bluetooth.

<p align="center">
  <img src="assets/home.png" alt="Connect screen" width="320">
  <img src="assets/remote.png" alt="Remote screen" width="320">
</p>

## Features

### Server (Go)

- D-pad (Up / Down / Left / Right / OK) plus Back, Home, Recents
- Numpad (0–9, ∗, ⌫) for dialer / PIN entry
- Free-text input — types into the focused EditText via `input text`
- Speaks the ADB protocol directly over TCP — no `adb.exe` shell-out
- Embedded web UI — single self-contained executable
- Light + dark theme with toggle
- Mobile-responsive layout
- Keyboard input: arrow keys, Enter / Space, Esc / Backspace, H, R
- Multi-device picker
- Multi-display picker (Android 10+) — routes via `input -d <id>`
- LAN-accessible — bind `-addr 0.0.0.0:7878` to control from your phone

### Android app (Flutter, optional)

- Bluetooth Classic / SPP transport — no LAN required
- Auto-discovers paired computers; the laptop's dpadr server registers an SPP UUID via Winsock so the phone resolves it by service, not channel
- Same key set as the web UI — D-pad, navigation, numpad, free-text
- Live device + display picker on the remote screen
- Last-connected device pinned to a hero card on launch
- Light + dark theme, persisted across launches
