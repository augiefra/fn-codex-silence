# Codex Dictate Companion

Personal native macOS menu bar companion for Codex voice input.

Press `Fn/Globe` or the right `Option` key once and the app silences macOS output. Press either shortcut again and every modified output returns to its previous state. The key event is only observed, so Codex receives the same toggle-dictation shortcut.

## Behavior

- Only a physical `Fn/Globe` press from key code `63` or right `Option` press from key code `61` can toggle muting.
- Releasing either shortcut does not change the audio state.
- Left `Option`, arrow keys, and ordinary keyboard events cannot change the mute state.
- Output is restored on the next shortcut press, disable, quit, session lock, sleep, or event-tap failure.
- Bluetooth outputs such as AirPods use output volume `0` when their native mute control is unavailable.
- AirPods Stereo Guard keeps dictation input on the best local non-Bluetooth microphone so AirPods remain in stereo output mode.
- Microphone activity in Discord, Google Meet, Zoom, FaceTime, or another app never triggers output muting.

The app silences system output; it does not pause the playing media.

## Requirements

- Apple Silicon Mac
- macOS 13 or later
- Xcode with the Apple Developer account for team `KX5QF45WFE`
- Codex toggle dictation configured to `Fn/Globe` or right `Option`

## Install

```sh
git clone https://github.com/augiefra/fn-codex-silence.git
cd fn-codex-silence
sh install.sh
```

The installer builds the Release app with Xcode, signs it with the configured development team, copies it to:

```text
~/Applications/Codex Dictate Companion.app
```

The installer creates one LaunchAgent that runs the app executable directly at login. No Hammerspoon helper or secondary process is used.

After a clean macOS installation, grant only:

```text
System Settings > Privacy & Security > Input Monitoring > Codex Dictate Companion
```

Accessibility permission is not required. The app automatically starts monitoring when macOS confirms Input Monitoring access.

## Menu Bar

The menu includes:

- current status, output, input, and shortcuts
- enable or disable the companion
- enable or disable AirPods Stereo Guard
- a 0.5-second mute test
- Input Monitoring status and settings
- three menu bar icons: Micro, Wave, and Command
- logs and quit

## Verification

Run the automated shortcut-state tests:

```sh
swift test
```

Build the signed macOS app without installing or launching it:

```sh
script/build_and_run.sh build
```

Check Input Monitoring:

```sh
"$HOME/Applications/Codex Dictate Companion.app/Contents/MacOS/Codex Dictate Companion" --check-permissions
```

Check launch at login:

```sh
launchctl print "gui/$(id -u)/com.augiefra.codex-dictate-companion"
```

Test audio independently of Fn:

```sh
"$HOME/Applications/Codex Dictate Companion.app/Contents/MacOS/Codex Dictate Companion" --test-mute
```

Show raw shortcut events while debugging:

```sh
open -n "$HOME/Applications/Codex Dictate Companion.app" --args --show-events
```

## Logs

```sh
tail -f "$HOME/Library/Logs/codex-dictate-companion/out.log"
```

Expected transitions:

```text
codex-dictate-companion: output muted by shortcut
codex-dictate-companion: output restored by shortcut
```

## Uninstall

```sh
sh uninstall.sh
```

Remove logs too:

```sh
sh uninstall.sh --remove-logs
```

## Repository Policy

GitHub is the source repository and backup for this personal app. Version `1.1.0` is not packaged or published as a downloadable GitHub Release.
