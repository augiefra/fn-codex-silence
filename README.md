# Codex Dictate Companion

Native macOS menu bar companion for Codex dictation.

Hold your Codex dictation shortcut, by default `Fn/Globe`, and Codex Dictate Companion mutes macOS output audio while the key is held. Release the key and your previous mute state is restored instantly.

## Behavior

- Hold `Fn/Globe`: mute all available macOS output devices.
- Release `Fn/Globe`: restore each output device to its previous state immediately.
- Bluetooth outputs such as AirPods may not support the native mute flag, so the app falls back to setting output volume to `0` and restores the previous volume on release.
- While the shortcut is held, the app keeps re-applying silence to all output devices so newly switched outputs are covered.
- If macOS does not deliver the `Fn/Globe` keyboard event reliably, the app also mutes while the default input microphone is active, which covers Codex dictation opening the microphone.
- AirPods Stereo Guard is enabled by default. While the companion is enabled, if the default input is AirPods or another Bluetooth microphone, the app keeps input routed to the best local non-Bluetooth microphone. This prevents Codex from opening the AirPods microphone path before dictation starts.
- The key event is not consumed, so Codex still receives the dictation shortcut.
- It mutes macOS output audio. It does not pause Spotify, MyCanal, YouTube, QuickTime, etc.

## Menu Bar App

Codex Dictate Companion installs as:

```text
~/Applications/Codex Dictate Companion.app
```

The menu bar app includes:

- enable or disable the companion
- enable or disable AirPods Stereo Guard
- a native app icon in Finder and System Settings
- check the active output and input devices
- test mute
- open permissions
- open Codex dictation settings
- open logs
- choose one of three menu bar icons:
  - Micro
  - Wave
  - Command

The selected icon is saved in macOS preferences.

## Install

Requirements:

- macOS 13 or later.
- Apple Silicon Mac only. The app is built for `arm64`, not Intel.
- Xcode, not only Command Line Tools.
- An Apple Developer account signed into Xcode for automatic signing.

```sh
git clone https://github.com/augiefra/fn-codex-silence.git
cd fn-codex-silence
sh install.sh
```

The installer:

- builds the native macOS app with Xcode in release mode
- uses a temporary Xcode DerivedData path outside the repo to avoid macOS Finder metadata breaking code signing
- forces an Apple Silicon-only `arm64` build
- signs the app with the configured Apple Development team
- creates `~/Applications/Codex Dictate Companion.app`
- creates `~/Library/LaunchAgents/com.augiefra.codex-dictate-companion.plist`
- starts the app through LaunchServices with `/usr/bin/open -gj`
- removes older `Fn Codex Silence` / `fn-codex-silence` local installs

The project currently uses Apple Development signing with team `KX5QF45WFE`.
For public distribution to another Mac without Xcode trust prompts, build with a
Developer ID Application certificate and notarize the app.

## Permissions

macOS needs privacy permissions before the app can observe the Codex dictation shortcut.

Grant these to `Codex Dictate Companion`:

- Privacy & Security > Input Monitoring
- Privacy & Security > Accessibility is optional. The app does not need to control the computer, but opening it can help if macOS prompts for both permissions.

If the app does not appear automatically, use the menu bar item:

```text
Permissions > Request Permissions
```

or run:

```sh
open -n "$HOME/Applications/Codex Dictate Companion.app" --args --request-permissions
```

If needed, add the app manually with the `+` button in System Settings.

After replacing an older helper build with this Xcode-signed app, macOS may show
the permission toggles as enabled while the new signed app still reports missing
access. Remove the old entry, add `~/Applications/Codex Dictate Companion.app`
again, then restart the app.

After changing permissions, restart the app from the menu bar or run:

```sh
launchctl kickstart -k "gui/$(id -u)/com.augiefra.codex-dictate-companion"
```

## Configuration

Default:

```sh
sh install.sh
```

This listens for `Fn/Globe`, matching Codex's default hold-to-dictate shortcut.

To use another shortcut:

```sh
sh install.sh --shortcut ctrl+space
```

Supported shortcut formats:

- `fn`
- `globe`
- `ctrl+space`
- `cmd+shift+x`
- `keycode:49`

Use the same shortcut in Codex and Codex Dictate Companion.

## Logs

```sh
tail -f "$HOME/Library/Logs/codex-dictate-companion/out.log"
tail -f "$HOME/Library/Logs/codex-dictate-companion/launchd-error.log"
```

When `Fn` is detected, the log should show lines like:

```text
codex-dictate-companion: muted MacBook Pro Speakers
codex-dictate-companion: restored MacBook Pro Speakers to muted=false
```

## Diagnostics

Check permissions:

```sh
"$HOME/Applications/Codex Dictate Companion.app/Contents/MacOS/Codex Dictate Companion" --check-permissions
```

Trigger permission prompts:

```sh
open -n "$HOME/Applications/Codex Dictate Companion.app" --args --request-permissions
```

Test audio mute only:

```sh
"$HOME/Applications/Codex Dictate Companion.app/Contents/MacOS/Codex Dictate Companion" --test-mute
```

Debug keyboard events:

```sh
open -n "$HOME/Applications/Codex Dictate Companion.app" --args --shortcut fn --show-events
```

## Uninstall

```sh
sh uninstall.sh
```

Remove logs too:

```sh
sh uninstall.sh --remove-logs
```
