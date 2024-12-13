local tv_ip = ""
local tv_mac_address = ""
local tv_input = "HDMI_1"          -- Input to which your Mac is connected
local switch_input_on_wake = true  -- Switch input to Mac when waking the TV
local debug = false                -- If you run into issues, set to true to enable debug messages
local control_audio = false        -- Control TV volume and mute button events from keyboard
local prevent_sleep_when_using_other_input = true -- Prevent sleep when TV is set to other input (ie: you're watching Netflix and your Mac goes to sleep)
local disable_lgtv = false
-- NOTE: You can disable this script by setting the above variable to true, or by creating a file named
-- `disable_lgtv` in the same directory as this file, or at ~/.disable_lgtv.

-- You likely will not need to change anything below this line
local screen_off_command = "power_off" -- you can also use `turn_screen_off` if you want to turn off the screen but keep the power on
local key_file_path = "~/.aiopylgtv.sqlite"
local connected_tv_identifiers = {"LG TV", "LG TV SSCR2"} -- Used to identify the TV when it's connected to this computer
local bin_path = "~/bin/bscpylgtvcommand" -- Full path to lgtv executable
local wakeonlan_path = "~/bin/wakeonlan" -- Full path to wakeonlan executable
local bin_cmd = bin_path.." -p "..key_file_path.." "..tv_ip.." "
local app_id = "com.webos.app."..tv_input:lower():gsub("_", "")
local set_pc_mode_on_wake = true
local tv_device_name = "Mac"
local before_sleep_command = nil -- A shell command to run before the TV goes to sleep.
local after_sleep_command = nil -- A shell command to run after the TV goes to sleep.
local before_wake_command = nil -- A shell command to run before the TV wakes up.
local after_wake_command = nil -- A shell command to run after the TV wakes up.

function lgtv_log_d(message)
  if debug then print(message) end
end

function lgtv_file_exists(name)
    return io.open(name) ~= nil
end

function lgtv_current_app_id()
  return lgtv_exec_command("get_current_app", true)
end

function lgtv_is_connected()
  for i, v in ipairs(connected_tv_identifiers) do
    if hs.screen.find(v) ~= nil then
      return true
    end
  end

  return false
end

function lgtv_toggle_mute()
  local muted = lgtv_get_muted()
  local new_muted = not muted
  lgtv_exec_command("set_mute "..string.lower(tostring(new_muted)))
  lgtv_log_d("Set muted to: "..tostring(new_muted).." (was "..tostring(muted)..")")
end

function lgtv_get_muted()
  local value = string.gsub(lgtv_exec_command("get_muted"), "^%s*(.-)%s*$", "%1") == "True"
  return value
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

function lgtv_exec_command(command, strip)
  strip = strip or false
  command = bin_cmd.." "..command
  lgtv_log_d("Executing command: "..command)
  local output, status, type, rc = hs.execute(command, 3)
  if rc == nil then
    lgtv_log_d("Command timed out after 3 seconds: " .. command)
    return ""
  end

  if strip then
    return output:gsub("[\r\n]+$", "")
  else
    return output
  end
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
  lgtv_log_d("\n\n-------------------- LGTV DEBUG INFO -----------------------------------------------------------------------------")
  lgtv_log_d ("TV input: "..tv_input)
  lgtv_log_d ("Binary path: "..bin_path)
  lgtv_log_d ("Binary command: "..bin_cmd)
  lgtv_log_d ("App ID: "..app_id)
  lgtv_log_d("lgtv_disabled: "..tostring(lgtv_disabled()))
  if not lgtv_disabled() then
    lgtv_log_d (lgtv_exec_command("get_software_info"))
    lgtv_log_d ("Current app ID: "..lgtv_current_app_id())
    lgtv_log_d("Connected screens: "..lgtv_dump_table(hs.screen.allScreens()))
    lgtv_log_d("TV is connected? "..tostring(lgtv_is_connected()))
  end
  lgtv_log_d("\n-------------------------------------------------------------------------------------------------------------------\n\n")
end

watcher = hs.caffeinate.watcher.new(function(eventType)
  lgtv_log_d("Received event: "..(eventType or ""))

  if lgtv_disabled() then
    lgtv_log_d("LGTV feature disabled. Skipping.")
    return
  end

  if (eventType == hs.caffeinate.watcher.screensDidWake or
      eventType == hs.caffeinate.watcher.systemDidWake or
      eventType == hs.caffeinate.watcher.screensDidUnlock) and not lgtv_disabled() and lgtv_is_connected() then

    if before_wake_command then
      hs.execute(before_wake_command)
      lgtv_log_d("Before wake command executed: "..before_wake_command)
    end

    if tv_mac_address ~= "" then
      local mac = tv_mac_address:gsub("[^%x]", "")
      local command = wakeonlan_path.." "..tv_mac_address
      hs.execute(command)
      lgtv_log_d("Wake on LAN packet sent to "..tv_mac_address)
    end

    lgtv_exec_command("turn_screen_on") -- turn on screen
    lgtv_log_d("TV was turned on")

    if lgtv_current_app_id() ~= app_id and switch_input_on_wake then
      lgtv_exec_command("launch_app "..app_id)
      lgtv_log_d("TV input switched to "..app_id)
    end

    if set_pc_mode_on_wake then
      lgtv_exec_command("set_device_info "..tv_input.." pc '"..tv_device_name.."'")
      lgtv_log_d("TV was set to PC mode")
    end

    if after_wake_command then
      hs.execute(after_wake_command)
      lgtv_log_d("After wake command executed: "..after_wake_command)
    end
  end

  if (lgtv_is_connected() and (eventType == hs.caffeinate.watcher.screensDidSleep or
      eventType == hs.caffeinate.watcher.systemWillPowerOff) and not lgtv_disabled()) then

    lgtv_log_d("TV is connected and going to sleep")
    lgtv_log_d("TV is currently on input "..lgtv_current_app_id())
    lgtv_log_d("TV is configured to prevent sleep when using other input? "..tostring(prevent_sleep_when_using_other_input))
    lgtv_log_d("Computer should be connected to input "..tv_input)

    local current_app_id = lgtv_current_app_id()
    if current_app_id ~= app_id and prevent_sleep_when_using_other_input then
      lgtv_log_d("TV is currently on another input ("..current_app_id.."). Skipping powering off.")
      return
    end

    if before_sleep_command then
      hs.execute(before_sleep_command)
      lgtv_log_d("Before sleep command executed: "..before_sleep_command)
    end

    lgtv_exec_command(screen_off_command)
    lgtv_log_d("TV screen was turned off with command `"..screen_off_command.."`.")

    if after_sleep_command then
      hs.execute(after_sleep_command)
      lgtv_log_d("After sleep command executed: "..after_sleep_command)
    end
  end
end)

audio_event_tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.systemDefined }, function(event)
  local event_type = event:getType()
  if event_type ~= hs.eventtap.event.types.systemDefined or not lgtv_is_current_audio_device() then
    return
  end

  local system_key = event:systemKey()
  local keys_to_commands = {['SOUND_UP']="volume_up", ['SOUND_DOWN']="volume_down"}
  local pressed_key = tostring(system_key.key)
  if system_key.down then
    if pressed_key == 'MUTE' then
      lgtv_toggle_mute()
    elseif keys_to_commands[pressed_key] then
      lgtv_exec_command(keys_to_commands[pressed_key])
    end
  end
end)

lgtv_log_init()

print("Starting LGTV watcher...")
watcher:start()

if control_audio then
  print("Starting LGTV audio events watcher...")
  audio_event_tap:start()
end
