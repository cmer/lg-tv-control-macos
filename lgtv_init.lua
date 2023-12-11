--
-- Tested with LGWebOSRemote as of December 11, 2023. Make sure you're on the right version!
-- See README for installation instructions.
--

local tv_input = "HDMI_1" -- Input to which your Mac is connected
local switch_input_on_wake = true -- Switch input to Mac when waking the TV
local prevent_sleep_when_using_other_input = true -- Prevent sleep when TV is set to other input (ie: you're watching Netflix and your Mac goes to sleep)
local debug = false -- If you run into issues, set to true to enable debug messages
local control_audio = true -- Control TV volume and mute button events from keyboard
local disable_lgtv = false
-- NOTE: You can disable this script by setting the above variable to true, or by creating a file named
-- `disable_lgtv` in the same directory as this file, or at ~/.disable_lgtv.

-- You likely will not need to change anything below this line
local tv_name = "MyTV" -- Name of your TV, set when you run `lgtv auth`
local connected_tv_identifiers = {"LG TV", "LG TV SSCR2"} -- Used to identify the TV when it's connected to this computer
local screen_off_command = "off" -- use "screenOff" to keep the TV on, but turn off the screen.
local lgtv_path = "~/.local/bin/lgtv" -- Full path to lgtv executable
local lgtv_cmd = lgtv_path.." --ssl --name "..tv_name
local app_id = "com.webos.app."..tv_input:lower():gsub("_", "")

function lgtv_log_d(message)
  if debug then print(message) end
end

function lgtv_current_app_id()
  local foreground_app_info = lgtv_exec_command("getForegroundAppInfo")
  for w in foreground_app_info:gmatch('%b{}') do
    if w:match('\"response\"') then
      local match = w:match('\"appId\"%s*:%s*\"([^\"]+)\"')
      if match then
        return match
      end
    end
  end
end

function lgtv_is_connected()
  for i, v in ipairs(connected_tv_identifiers) do
    if hs.screen.find(v) ~= nil then
      log_d(v.." is connected")
      return true
    end
  end

  log_d("No screens are connected. Please check the 'connected_tv_identifier' in the 'lgtv_init.lua' script matches your connected screen.")
  return false
end

function tv_is_current_audio_device()
  local current_audio_device = hs.audiodevice.current().name

  for i, v in ipairs(connected_tv_identifiers) do
    if current_audio_device == v then
      log_d(v.." is the current audio device")
      return true
    end
  end

  log_d(current_audio_device.." is the current audio device.")
  return false
end

function lgtv_dump_table(o)
  if type(o) == 'table' then
    local s = '{ '
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. lgtv_dump_table(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end

function lgtv_exec_command(command)
  command = lgtv_cmd.." "..command

  if debug then
    print("Executing command: "..command)
  end

  return hs.execute(command)
end

function lgtv_disabled()
  return disable_lgtv or file_exists("./disable_lgtv") or file_exists(os.getenv('HOME') .. "/.disable_lgtv")
end

-- Converts an event_type (int) into a debug friendly description (string).
-- Source (look for `add_event_enum(lua_State* L)`): https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/caffeinate/libcaffeinate_watcher.m
function event_type_description(event_type)
  if event_type == hs.caffeinate.watcher.systemDidWake then
    return "systemDidWake"
  elseif event_type == hs.caffeinate.watcher.systemWillSleep then
    return "systemWillSleep"
  elseif event_type == hs.caffeinate.watcher.systemWillPowerOff then
    return "systemWillPowerOff"
  elseif event_type == hs.caffeinate.watcher.screensDidSleep then
    return "screensDidSleep"
  elseif event_type == hs.caffeinate.watcher.screensDidWake then
    return "screensDidWake"
  elseif event_type == hs.caffeinate.watcher.sessionDidResignActive then
    return "sessionDidResignActive"
  elseif event_type == hs.caffeinate.watcher.sessionDidBecomeActive then
    return "sessionDidBecomeActive"
  elseif event_type == hs.caffeinate.watcher.screensaverDidStart then
    return "screensaverDidStart"
  elseif event_type == hs.caffeinate.watcher.screensaverWillStop then
    return "screensaverWillStop"
  elseif event_type == hs.caffeinate.watcher.screensaverDidStop then
    return "screensaverDidStop"
  elseif event_type == hs.caffeinate.watcher.screensDidLock then
    return "screensDidLock"
  elseif event_type == hs.caffeinate.watcher.screensDidUnlock then
    return "screensDidUnlock"
  else
    return "unknown"
  end
end

if debug then
  print ("TV name: "..tv_name)
  print ("TV input: "..tv_input)
  print ("LGTV path: "..lgtv_path)
  print ("LGTV command: "..lgtv_cmd)
  print ("SSL: "..tostring(lgtv_ssl))
  print ("App ID: "..app_id)
  print("lgtv_disabled: "..tostring(lgtv_disabled()))
  if not lgtv_disabled() then
    print (exec_command("swInfo"))
    print (exec_command("getForegroundAppInfo"))
    print("Connected screens: "..dump_table(hs.screen.allScreens()))
    print("TV is connected? "..tostring(tv_is_connected()))
  end
end

watcher = hs.caffeinate.watcher.new(function(eventType)
  if debug then print("Received event: "..(eventType or "")) end

  if lgtv_disabled() then
    if debug then print("LGTV feature disabled. Skipping.") end
    return
  end

  if (eventType == hs.caffeinate.watcher.screensDidWake or
      eventType == hs.caffeinate.watcher.systemDidWake or
      eventType == hs.caffeinate.watcher.screensDidUnlock) and not lgtv_disabled() then

    exec_command("on") -- wake on lan
    exec_command("screenOn") -- turn on screen
    if debug then print("TV was turned on") end

    if lgtv_current_app_id() ~= app_id and switch_input_on_wake then
      exec_command("startApp "..app_id)
      if debug then print("TV input switched to "..app_id) end
    end
  end

  if (tv_is_connected() and (eventType == hs.caffeinate.watcher.screensDidSleep or
      eventType == hs.caffeinate.watcher.systemWillPowerOff) and not lgtv_disabled()) then

    if lgtv_current_app_id() ~= app_id and prevent_sleep_when_using_other_input then
      if debug then print("TV is currently on another input ("..lgtv_current_app_id().."). Skipping powering off.") end
      return
    end

    -- This puts the TV in standby mode.
    -- For true "power off" use `off` instead of `screenOff`.
    exec_command(screen_off_command)
    if debug then print("TV screen was turned off with command `"..screen_off_command.."`.") end
  end
end)

watcher:start()

if control_audio then
  tap:start()
end
