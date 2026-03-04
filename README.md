# PortPilot

A lightweight macOS menu bar app that monitors local TCP listening ports in real time.

PortPilot is built with **SwiftUI + MenuBarExtra** for macOS 15+, with zero third-party runtime dependencies.

---

## Features

- Menu bar summary: `: N`
- Real-time scan (default every 2s) using:
  - `lsof -nP -iTCP -sTCP:LISTEN`
- Unified light **Bento Grid** window with integrated controls and settings
- Smooth trend chart (spline curve) for global occupied ports
- Port list with process info:
  - Port / Process / PID / User / usage hint
- Friendly interpretation:
  - e.g. SSH tunnel, local dev service, database hints
- Search by:
  - port / process / PID / friendly label / usage hint
- Sort and focus:
  - sort by port / process / recent activity
- "New" badge for newly discovered listeners (5 seconds)
- Context menu actions:
  - Copy URL / Copy PID / Copy kill command
- Optional command-line detail display (for disambiguating multiple `ssh` processes)
- Optional kill action with safety controls:
  - disabled by default
  - explicit inline settings enable
  - confirmation required before each kill
  - async termination pipeline (`SIGTERM` → fallback `SIGKILL`) with immediate UI refresh

---

## Security Defaults

- **Show command line**: OFF by default
- **Enable Kill**: OFF by default
- Kill is destructive and guarded by:
  1. explicit opt-in in Settings
  2. per-action confirmation dialog

---

## Requirements

- macOS 15+
- Xcode 16+

---

## Run in Xcode

1. Open:
   - `PortPilot.xcodeproj`
2. Select scheme:
   - `PortPilot`
3. Run:
   - `⌘R`

If your machine is still bound to Command Line Tools, switch to full Xcode first:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

---

## Settings

- Integrated in the main panel (no separate settings scene)
- Refresh interval: `1 / 2 / 5 / 10` seconds
- Count mode:
  - **Mode A**: `(protocol, port, pid)`
  - **Mode B**: `(protocol, port)`
- Show command line: OFF by default
- Enable Kill: OFF by default

---

## How PortPilot Works

1. `LsofRunner` runs `lsof` in background.
2. `LsofParser` loosely parses output and extracts listening port data.
3. `PortsScanner` periodically refreshes and updates scanner state.
4. `PortsStore` handles dedupe, sorting, and “new item” lifecycle.
5. SwiftUI menu UI renders results with a modern, border-light Bento layout.

---

## Project Structure

```text
PortPilot/
  PortPilotApp.swift
  Model/
    PortListener.swift
  Services/
    LsofRunner.swift
    LsofParser.swift
    PortsScanner.swift
    ProcessActions.swift
  State/
    PortsStore.swift
    SettingsStore.swift
  UI/
    PortsView.swift
    SettingsView.swift (legacy / currently not mounted)
  Resources/
    Info.plist
```

---

## Notes

- Data source is intentionally constrained to `lsof`.
- Parsing is defensive: malformed lines are skipped (no crash).
- Menu summary fallback:
  - after 3 consecutive scan failures, summary shows `: —`
  - recovers automatically on next successful scan

---

## License

MIT (recommended). Add a `LICENSE` file before public release.
