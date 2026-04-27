local M = {}

local config = {
  -- Modes:
  -- "timed": mute on Fn press, then restore after restoreAfterSeconds.
  -- "hold": mute while Fn is held, then restore on release.
  -- "toggle": first Fn press mutes, next Fn press restores.
  mode = "hold",
  restoreAfterSeconds = 2,
  showAlerts = false,
}

local tap = nil
local restoreTimer = nil
local fnWasDown = false
local mutedByFn = false
local previousMuted = nil

local function notify(message)
  if config.showAlerts then
    hs.alert.closeAll()
    hs.alert.show(message, 0.6)
  end
end

local function outputDevice()
  return hs.audiodevice.defaultOutputDevice()
end

local function stopRestoreTimer()
  if restoreTimer then
    restoreTimer:stop()
    restoreTimer = nil
  end
end

local function restore()
  stopRestoreTimer()

  if not mutedByFn then
    return
  end

  local device = outputDevice()
  if device and previousMuted ~= nil then
    device:setMuted(previousMuted)
  end

  mutedByFn = false
  previousMuted = nil
  notify("Audio restored")
end

local function mute()
  stopRestoreTimer()

  local device = outputDevice()
  if not device then
    return
  end

  if not mutedByFn then
    previousMuted = device:muted()
  end

  device:setMuted(true)
  mutedByFn = true
  notify("Audio muted")

  if config.mode == "timed" then
    restoreTimer = hs.timer.doAfter(config.restoreAfterSeconds, restore)
  end
end

local function onFnDown()
  if config.mode == "toggle" and mutedByFn then
    restore()
    return
  end

  mute()
end

local function onFnUp()
  if config.mode == "hold" then
    restore()
  end
end

function M.start(userConfig)
  for key, value in pairs(userConfig or {}) do
    config[key] = value
  end

  if tap then
    tap:stop()
  end

  tap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
    local flags = event:getFlags()
    local fnIsDown = flags.fn == true

    if fnIsDown == fnWasDown then
      return false
    end

    fnWasDown = fnIsDown

    if fnIsDown then
      onFnDown()
    else
      onFnUp()
    end

    -- Do not consume the key event. Codex should still receive Fn.
    return false
  end)

  tap:start()
  notify("Fn mute ready")
end

return M
