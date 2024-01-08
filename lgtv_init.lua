--
-- Tested with LGWebOSRemote as of December 11, 2023. Make sure you're on the right version!
--

local tv_input = "HDMI_1" -- Input to which your Mac is connected
local switch_input_on_wake = true -- Switch input to Mac when waking the TV
local prevent_sleep_when_using_other_input = true -- Prevent sleep when TV is set to other input (ie: you're watching Netflix and your Mac goes to sleep)
local debug = false  -- If you run into issues, set to true to enable debug messages
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


-- Source: https://stackoverflow.com/a/4991602
function lgtv_file_exists(name)
  local f=io.open(name,"r")
  if f~=nil then
    io.close(f)
    return true
  else
    return false
  end
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
      return true
    end
  end

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
  lgtv_log_d("Executing command: "..command)
  return hs.execute(command)
end

function lgtv_disabled()
  return lgtv_file_exists("./disable_lgtv") or lgtv_file_exists(os.getenv('HOME') .. "/.disable_lgtv")
end

function lgtv_is_current_audio_device()
  local current_audio_device = hs.audiodevice.current().name

  for i, v in ipairs(connected_tv_identifiers) do
    if current_audio_device == v then
      lgtv_log_d(v.." is the current audio device")
      return true
    end
  end

  lgtv_log_d(current_audio_device.." is the current audio device.")
  return false
end

function lgtv_log_init()
  lgtv_log_d ("TV name: "..tv_name)
  lgtv_log_d ("TV input: "..tv_input)
  lgtv_log_d ("LGTV path: "..lgtv_path)
  lgtv_log_d ("LGTV command: "..lgtv_cmd)
  lgtv_log_d ("App ID: "..app_id)
  lgtv_log_d("lgtv_disabled: "..tostring(lgtv_disabled()))
  if not lgtv_disabled() then
    lgtv_log_d (lgtv_exec_command("swInfo"))
    lgtv_log_d (lgtv_exec_command("getForegroundAppInfo"))
    lgtv_log_d("Connected screens: "..lgtv_dump_table(hs.screen.allScreens()))
    lgtv_log_d("TV is connected? "..tostring(lgtv_is_connected()))
  end
end

lgtv_log_init()

watcher = hs.caffeinate.watcher.new(function(eventType)
  lgtv_log_d("Received event: "..(eventType or ""))

  if lgtv_disabled() then
    lgtv_log_d("LGTV feature disabled. Skipping.")
    return
  end

  if (eventType == hs.caffeinate.watcher.screensDidWake or
      eventType == hs.caffeinate.watcher.systemDidWake or
      eventType == hs.caffeinate.watcher.screensDidUnlock) and not lgtv_disabled() then
    
    if not lgtv_is_connected() then
      lgtv_log_d("TV is disconnected")
      return
    end
    
    lgtv_exec_command("on") -- wake on lan
    lgtv_exec_command("screenOn") -- turn on screen
    lgtv_log_d("TV was turned on")

    if lgtv_current_app_id() ~= app_id and switch_input_on_wake then
      lgtv_exec_command("startApp "..app_id)
      lgtv_log_d("TV input switched to "..app_id)
    end
  end

  if (lgtv_is_connected() and (eventType == hs.caffeinate.watcher.screensDidSleep or
      eventType == hs.caffeinate.watcher.systemWillPowerOff) and not lgtv_disabled()) then

    if lgtv_current_app_id() ~= app_id and prevent_sleep_when_using_other_input then
      lgtv_log_d("TV is currently on another input ("..lgtv_current_app_id().."). Skipping powering off.")
      return
    end

    -- This puts the TV in standby mode.
    -- For true "power off" use `off` instead of `screenOff`.
    lgtv_exec_command(screen_off_command)
    lgtv_log_d("TV screen was turned off with command `"..screen_off_command.."`.")
  end
end)

audio_event_tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.systemDefined }, function(event)
  local event_type = event:getType()
  if event_type ~= hs.eventtap.event.types.systemDefined or not lgtv_is_current_audio_device() then
    return
  end

  local system_key = event:systemKey()

  local keys_to_commands = {['SOUND_UP']="volumeUp", ['SOUND_DOWN']="volumeDown"}
  local pressed_key = system_key.key

  if system_key.down and (pressed_key == 'MUTE' or keys_to_commands[pressed_key] ~= nil) then
    if pressed_key == 'MUTE' then
      local audio_status = hs.json.decode(exec_command("audioStatus"):gmatch('%b{}')())
      local mute_status = audio_status["payload"]["mute"]
      lgtv_exec_command("mute "..tostring(not mute_status))
    else
      lgtv_exec_command(keys_to_commands[pressed_key])
    end
  end
end)

watcher:start()

if control_audio then
  audio_event_tap:start()
end
