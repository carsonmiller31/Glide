# Glide

macOS menu bar app (macOS 14+) that makes a normal mouse wheel scroll smoothly, like Windows. Bundle ID `dev.waveflow.Glide`.

## How it works

- `ScrollEngine` installs a CGEventTap on scroll-wheel events (needs Accessibility permission).
- Continuous events (trackpad, Magic Mouse) and our own synthetic events (`eventSourceUserData == "GLID"`) pass through. ⌘/⌃/⌥ + wheel passes through so zoom shortcuts work.
- Each wheel notch is swallowed and fed to `GlideCore.ScrollAnimator` (pure, unit-tested): distance per notch × acceleration, exponential ease-out over the Smoothness duration, reversing cancels the glide.
- A `CADisplayLink` on the fastest screen posts one pixel-unit, `isContinuous = 1` scroll event per frame, so apps treat it like a trackpad. Integer deltas carry their fraction so nothing drifts. The link pauses when idle.
- "Elastic page edges" adds scroll phases (began/changed/ended) for rubber-banding; never on sideways glides, which would trigger swipe-between-pages.

## Build

- Tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (the default toolchain is Command Line Tools, which lacks XCTest).
- App: `zsh scripts/build.sh` → `build/Glide.app`; `--install` replaces `/Applications/Glide.app` and relaunches.
- Always sign with the Apple Development identity (the script does): Accessibility permission is tied to the signature, so ad-hoc builds lose it every time.
- Icon: `swift scripts/make-icon.swift Resources/AppIcon.icns`.
- Screenshot: `GLIDE_SNAPSHOT=docs/menu.png build/Glide.app/Contents/MacOS/Glide` renders the menu and exits without starting the tap.

## Open source

Public at github.com/carsonmiller31/Glide under MIT. No CI yet: pushing a workflow file needs a `gh` token with the `workflow` scope. Keep README.md in step with settings and behaviour.
