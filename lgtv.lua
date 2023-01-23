local tv_input = "HDMI_1" -- Input to which your Mac is connected
local switch_input_on_wake = true -- Switch input to Mac when waking the TV
local prevent_sleep_when_using_other_input = true -- Prevent sleep when using other input (ie: watching TV)
local debug = false  -- If you run into issues, set to true to enable debug messages

-- You likely will not need to change anything below this line
local tv_name = "MyTV" -- Name of your TV, set when you run `lgtv auth`
local connected_tv_identifiers = {"LG TV", "LG TV SSCR2"} -- Used to identify the TV when it's connected to this computer
local screen_off_command = "off" -- use "screenOff" to keep the TV on, but turn off the screen.
local lgtv_path = "~/opt/lgtv/bin/lgtv" -- Full path to lgtv executable
local lgtv_cmd = lgtv_path.." "..tv_name.." "
local app_id = "com.webos.app."..tv_input:lower():gsub("_", "")

function lgtv_current_app_id()
  local foreground_app_info = hs.execute(lgtv_cmd.." getForegroundAppInfo")
  foreground_app_info = string.match(foreground_app_info, '^%b{}')
  foreground_app_info = hs.json.decode(foreground_app_info)
  return foreground_app_info["payload"]["appId"]
end

function tv_is_connected()
  for i, v in ipairs(connected_tv_identifiers) do
    if hs.screen.find(v) ~= nil then
      return true
    end
  end

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

if debug then
  print ("TV name: "..tv_name)
  print ("TV input: "..tv_input)
  print ("LGTV path: "..lgtv_path)
  print ("LGTV command: "..lgtv_cmd)
  print ("App ID: "..app_id)
  print ("Running `"..lgtv_cmd.."swInfo`...")
  print (hs.execute(lgtv_cmd.."swInfo"))
  print ("Running `"..lgtv_cmd.."getForegroundAppInfo`...")
  print (hs.execute(lgtv_cmd.."getForegroundAppInfo"))
  print("Connected screens: "..dump_table(hs.screen.allScreens()))
  print("TV is connected? "..tostring(tv_is_connected()))
end

watcher = hs.caffeinate.watcher.new(function(eventType)
  if debug then print("Received event: "..eventType) end

  if not tv_is_connected() then
    if debug then print("TV is not connected. Skipping.") end
    return
  end

  if (eventType == hs.caffeinate.watcher.screensDidWake or
      eventType == hs.caffeinate.watcher.systemDidWake or
      eventType == hs.caffeinate.watcher.screensDidUnlock) then

    hs.execute(lgtv_cmd.." on") -- wake on lan
    hs.execute(lgtv_cmd.." screenOn") -- turn on screen
    if debug then print("TV was turned on") end

    if lgtv_current_app_id() ~= app_id and switch_input_on_wake then
      hs.execute(lgtv_cmd.." startApp "..app_id)
      if debug then print("TV input switched to "..app_id) end
    end
  end

  if (eventType == hs.caffeinate.watcher.screensDidSleep or
      eventType == hs.caffeinate.watcher.systemWillPowerOff) then

    if lgtv_current_app_id() ~= app_id and prevent_sleep_when_using_other_input then
      if debug then print("TV is currently on another input ("..current_app_id.."). Skipping powering off.") end
      return
    end

    -- This puts the TV in standby mode.
    -- For true "power off" use `off` instead of `screenOff`.
    hs.execute(lgtv_cmd.." "..screen_off_command)
    if debug then print("TV screen was turned off with command `"..screen_off_command.."`.") end
  end
end)
watcher:start()
