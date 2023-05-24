local tv_input = "HDMI_2" -- Input to which your Mac is connected
local switch_input_on_wake = true -- Switch input to Mac when waking the TV
local prevent_sleep_when_using_other_input = true -- Prevent sleep when TV is set to other input (ie: you're watching Netflix and your Mac goes to sleep)
local debug = true -- If you run into issues, set to true to enable debug messages
local disable_lgtv = false
-- NOTE: You can disable this script by setting the above variable to true, or by creating a file named
-- `disable_lgtv` in the same directory as this file, or at ~/.disable_lgtv.

-- You likely will not need to change anything below this line
local tv_name = "LGC1" -- Name of your TV, set when you run `lgtv auth`
local connected_tv_identifiers = {"LG TV", "LG TV SSCR2"} -- Used to identify the TV when it's connected to this computer
local screen_off_command = "off" -- use "screenOff" to keep the TV on, but turn off the screen.
local lgtv_path = "~/opt/lgtv/bin/lgtv" -- Full path to lgtv executable
local lgtv_cmd = lgtv_path.." "..tv_name
local app_id = "com.webos.app."..tv_input:lower():gsub("_", "")
local lgtv_ssl = true -- Required for firmware 03.30.16 and up. Also requires LGWebOSRemote version 2023-01-27 or newer.

-- A convenience function for printing debug messages. 
function log_d(message)
  if debug then print(message) end
end

function lgtv_current_app_id()
  local foreground_app_info = exec_command("getForegroundAppInfo")
  for w in foreground_app_info:gmatch('%b{}') do
    if w:match('\"response\"') then
      local match = w:match('\"appId\"%s*:%s*\"([^\"]+)\"')
      if match then
        return match
      end
    end
  end
end

function tv_is_connected()
  for i, v in ipairs(connected_tv_identifiers) do
    if hs.screen.find(v) ~= nil then
      log_d(v.." is connected")
      return true
    end
  end

  log_d("No screens are connected")
  return false
end

function dump_table(o)
  if type(o) == 'table' then
    local s = '{ '
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. dump_table(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end

function exec_command(command)
  if lgtv_ssl then
    space_loc = command:find(" ")

    --- "ssl" must be the first argument for commands like 'startApp'. Advance it to the expected position.
    if space_loc then
      command = command:sub(1,space_loc).."ssl "..command:sub(space_loc+1)
    else
      command = command.." ssl"
    end
  end

  command = lgtv_cmd.." "..command
  log_d("Executing command: "..command)

  response = hs.execute(command)
  log_d(response)

  return response
end

-- Source: https://stackoverflow.com/a/4991602
function file_exists(name)
  local f=io.open(name,"r")
  if f~=nil then
    io.close(f)
    return true
  else
    return false
  end
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
  log_d("TV name: "..tv_name)
  log_d("TV input: "..tv_input)
  log_d("LGTV path: "..lgtv_path)
  log_d("LGTV command: "..lgtv_cmd)
  log_d("SSL: "..tostring(lgtv_ssl))
  log_d("App ID: "..app_id)
  log_d("lgtv_disabled: "..tostring(lgtv_disabled()))
  if not lgtv_disabled() then
    exec_command("swInfo")
    exec_command("getForegroundAppInfo")
    log_d("Connected screens: "..dump_table(hs.screen.allScreens()))
    log_d("TV is connected? "..tostring(tv_is_connected()))
  end
end

watcher = hs.caffeinate.watcher.new(
  function(event_type)
    event_name = event_type_description(event_type)
    log_d("Received event: "..(event_type or "").." "..(event_name))

    if lgtv_disabled() then
      log_d("LGTV feature disabled. Skipping.")
      return
    end

    if (event_type == hs.caffeinate.watcher.screensDidWake or
        event_type == hs.caffeinate.watcher.systemDidWake or
        event_type == hs.caffeinate.watcher.screensDidUnlock) then

      if not tv_is_connected() then
        log_d("TV was not turned on because it is not connected")
        return
      end
      
      if screen_off_command == 'screenOff' then
        exec_command("screenOn") -- turn on screen
      else
        exec_command("on") -- wake on lan
      end
      log_d("TV was turned on")

      if lgtv_current_app_id() ~= app_id and switch_input_on_wake then
        exec_command("startApp "..app_id)
        log_d("TV input switched to "..app_id)
      end
    end

    if (event_type == hs.caffeinate.watcher.screensDidSleep or 
        event_type == hs.caffeinate.watcher.systemWillPowerOff or 
        event_type == hs.caffeinate.watcher.systemWillSleep) then

      if not tv_is_connected() then
        log_d("TV was not turned off because it is not connected")
        return
      end

      -- current_app_id returns empty string on some events like screensDidSleep
      current_app_id = lgtv_current_app_id()
      if current_app_id ~= app_id and prevent_sleep_when_using_other_input then
        log_d("TV is currently on another input ("..(current_app_id or "?").."). Skipping powering off.")
        return
      else
        exec_command(screen_off_command)
        log_d("TV screen was turned off with command `"..screen_off_command.."`.")
      end
    else 
      log_d("Event ignored")
    end
  end
)
watcher:start()
