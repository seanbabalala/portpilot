# Contributing to PortPilot

Thanks for improving PortPilot.

## Development Setup

1. Use macOS 15+ and Xcode 16+.
2. Open `PortPilot.xcodeproj`.
3. Run the `PortPilot` scheme with `⌘R`.

## Project Rules

- Keep runtime dependencies zero (no third-party packages by default).
- Data source must remain `lsof -nP -iTCP -sTCP:LISTEN`.
- UI must stay native SwiftUI + MenuBarExtra.
- Do not execute scanning logic in views; keep it in `Services` / `State`.
- Keep sorting stable: `port asc`, then `pid asc`.

## Pull Request Checklist

- [ ] Build succeeds on macOS target.
- [ ] Existing behavior remains stable.
- [ ] New behavior is documented in `README.md` if user-facing.
- [ ] Security defaults are preserved:
  - command line hidden by default
  - kill disabled by default
- [ ] Include clear before/after notes and screenshots for UI changes.

## Commit Style (Recommended)

- `feat: ...` new features
- `fix: ...` bug fixes
- `docs: ...` docs only
- `refactor: ...` code structure changes without behavior change
