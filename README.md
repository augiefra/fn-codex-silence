# Fn Codex Silence

Mute your Mac while the `Fn/Globe` key is held, then restore audio as soon as the key is released.

This is useful when `Fn` starts voice input in Codex and you want music, video, or any other system audio to stop leaking into the microphone.

## Behavior

- Hold `Fn/Globe`: mute the default macOS output device.
- Release `Fn/Globe`: restore the previous mute state immediately.
- The key event is not consumed, so Codex still receives `Fn`.
- It mutes macOS output audio. It does not pause Spotify, YouTube, QuickTime, etc.

## Install

Hammerspoon is required because macOS treats `Fn/Globe` as a special system key.

```sh
git clone https://github.com/augiefra/fn-codex-silence.git
cd fn-codex-silence
sh install.sh
```

If Hammerspoon is not installed yet:

```sh
sh install.sh --install-hammerspoon
```

That uses Homebrew when available. You can also install Hammerspoon manually from https://www.hammerspoon.org/.

After installation, macOS may ask for Accessibility permission for Hammerspoon. Accept it, then reload Hammerspoon if needed.

## Uninstall

```sh
sh uninstall.sh
```

## What the installer does

- Copies `hammerspoon/fn-mute.lua` to `~/.hammerspoon/fn-mute.lua`.
- Adds a managed config block to `~/.hammerspoon/init.lua`.
- Opens or reloads Hammerspoon when possible.

Managed block:

```lua
-- >>> fn-codex-silence >>>
package.loaded["fn-mute"] = nil
require("fn-mute").start({
  mode = "hold",
  showAlerts = false,
})
-- <<< fn-codex-silence <<<
```

The installer is idempotent: running it again updates the managed block instead of duplicating it.

## Configuration

Edit `~/.hammerspoon/init.lua` if you want to change behavior:

```lua
require("fn-mute").start({
  mode = "hold",
  showAlerts = false,
})
```

Available modes:

- `hold`: mute while `Fn` is held, restore on release.
- `timed`: mute on `Fn` press, restore after `restoreAfterSeconds`.
- `toggle`: first `Fn` press mutes, next `Fn` press restores.

Example timed mode:

```lua
require("fn-mute").start({
  mode = "timed",
  restoreAfterSeconds = 2,
  showAlerts = false,
})
```
