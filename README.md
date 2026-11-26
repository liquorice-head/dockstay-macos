# DockStay

A small macOS menu-bar app. Choose the display for your Dock and switch blocking on or off.

- Native SwiftUI `MenuBarExtra`; no window or onboarding.
- Display selection with a standard checkmark.
- A green status indicator means Dock blocking is active. A red indicator means blocking is off or paused. The text beside it explains the current state.
- A second indicator shows whether DockStay has Accessibility permission. Green means access is granted. Red means access is missing. Click the row to open Accessibility settings.
- **Launch at Login** toggles automatic startup using macOS Service Management. The menu reads the system state and offers a link to Login Items settings if approval is required.
- **Saved Configurations** lists the saved sets of screens. Choose a display once per setup with **Remember Configurations** on to restore the choice across launches and reconnections.
- Remembers one **Lock Dock** setting across all setups. Choosing another display while it is off does not request permission or move the pointer.
- No accounts, subscriptions, or telemetry. Network access is limited to manual update checks and downloads through Sparkle.
- **Check for Updates…** checks the public release feed and offers to install a signed update when a newer version is available.
- macOS 14+, English and Russian. Releases target Apple Silicon.

## Download

Download the DMG from [GitHub Releases](https://github.com/liquorice-head/dockstay-macos/releases/latest), open it, and drag **DockStay.app** to **Applications**. A ZIP of the same app is also available. Releases require an Apple Silicon Mac running macOS 14 or later and are Developer ID signed and notarized by Apple.

Open DockStay, select a display, and enable **Lock Dock**. Click the Accessibility permission row to grant access in System Settings. If you already have version 0.1.2 or earlier, replace it manually once. Starting with 0.1.3, choose **Check for Updates…** from the DockStay menu to get a newer release.

## Build and run

Requires Xcode or the Swift 6 command-line tools:

```sh
swift test
bash scripts/build.sh
open build/DockStay.app
```

Select a display and enable **Lock Dock**. Click the Accessibility row to open System Settings and enable DockStay. This is the only required permission. The indicator updates when permission changes, including while blocking is off. You can return to the same row to review or revoke access.

Turn off **Remember Configurations** under **Saved Configurations** to choose screens without saving or restoring setups. Previously saved configurations stay available. To remove one, open the submenu for that set of screens and choose **Delete Configuration**. If that configuration is in use, DockStay keeps the current screen for the connected setup until you disconnect or relaunch.

Permission navigation uses the macOS System Settings Accessibility URL, with a native authorization prompt and the Settings app as fallbacks. DockStay does not grant access itself.

For stable permission grants between rebuilds, sign with your development identity:

```sh
CODE_SIGN_IDENTITY='Apple Development: Your Name (TEAMID)' bash scripts/build.sh
```

Without an identity the script uses ad-hoc signing. macOS may require removing and re-adding the app in Accessibility after a rebuild, move, or switch from a local build to the release signature. Local builds are not notarized; published releases are.

Build for Apple Silicon with `ARCH=arm64 bash scripts/build.sh`. Open `Package.swift` in Xcode to edit the project. The script creates the runnable `.app` bundle in `build/`.

## How it works

There is no public macOS API that permanently assigns Dock to a display. DockStay filters only mouse-motion and mouse-drag events with a session-level `CGEventTap`. On other displays, it keeps the pointer four logical points short of the Dock activation edge. It leaves shared edges between displays open, so moving between vertically or horizontally arranged monitors still works.

When selecting a display, the app briefly replays the normal pointer-push gesture at a free edge, then restores the pointer if the user has not moved it. It never clicks. User movement or a click cancels the gesture. This placement gesture is best-effort and needs validation on your hardware; if Dock does not follow, move the pointer to the selected screen's Dock edge once. The guard then prevents accidental transfers elsewhere.

The Dock's existing bottom/left/right preference is respected. If the selected edge is completely covered by another display, macOS may not allow Dock there; the app reports this instead of rearranging your displays. **Displays have separate Spaces** must be on to move Dock independently of the main display. DockStay never changes that setting.

Sleep, display reconnection, system transitions, other pointer utilities, and macOS updates can affect Dock behavior. This is a pointer guard, not an OS-level lock. Switching blocking off or quitting removes the event tap immediately. Nothing in Dock preferences is modified.

## Verification

```sh
swift test
bash scripts/build.sh
git diff --check
```

For the real hardware check:

1. Select each connected display. Verify Dock follows and the menu checkmark updates.
2. Push against the Dock edge on every other display, including while dragging a file.
3. Cross a shared display edge in both directions; it must remain accessible.
4. Save different Dock displays for two sets of connected screens. Switch between the sets and relaunch DockStay. Verify each set restores its own choice. Connect a set with no saved choice and verify blocking pauses until you pick a display.
5. Sleep and wake, revoke and restore Accessibility, and quit. The cursor must always remain usable.
6. Turn blocking off, switch the selected display, sleep/wake, and relaunch. Blocking must remain off, the selection must be remembered, and there must be no permission prompts or pointer movement until explicitly re-enabled.
7. With blocking off and on, click the permission row and verify it opens the Accessibility permission list. Change the grant there and verify the row updates when reopening the menu.
8. In the installed app, enable **Launch at Login**, approve it in Login Items settings if requested, and log out and back in. Verify DockStay starts with the saved display and blocking state. Disable autostart and repeat; DockStay must not launch. Change the login item in System Settings and verify the menu reflects it when reopened.
9. In **Saved Configurations**, turn off **Remember Configurations** and select a different display. Verify saved entries are unchanged and are skipped on relaunch. Delete one entry, re-enable remembering, and verify the other entries still restore their displays.

CI runs the geometry tests and uploads a ZIP of the ad-hoc signed app, preserving executable permissions. For local sharing, use `ditto -c -k --keepParent build/DockStay.app DockStay.zip`.

## Updates and icon concepts

The updater uses [Sparkle 2](https://sparkle-project.org/documentation/) with HTTPS and Ed25519 archive verification before extraction. Checks are manual, installation requires confirmation, and system profiling is disabled. The native update dialogs support English and Russian. The [public update feed](https://github.com/liquorice-head/dockstay-macos/releases/latest/download/appcast.xml) points to signed release archives. See [RELEASING.md](RELEASING.md) for the signing and publication process.

Ten generated icon concepts are in [the local gallery](design/icon-concepts/index.html), with separate full-size PNGs and the generation prompts in `design/icon-concepts/prompts.json`. Concept **08, D monogram**, is the selected application icon. Its approved artwork is preserved in `Resources/AppIcon.png`; run `bash scripts/build-icon.sh` to regenerate `Resources/AppIcon.icns` with all standard sizes from 16 to 1024 pixels. The build bundles this icon for Finder and native application dialogs. The menu bar continues to use the native monochrome symbol.
