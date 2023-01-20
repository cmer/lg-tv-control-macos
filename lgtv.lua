local tv_input = "HDMI_1" -- Input to switch to when waking the TV
local debug = false  -- If you run into issues, set to true to enable debug messages

-- You likely will not need to change anything below this line
local tv_name = "MyTV" -- Name of your TV, set when you run `lgtv auth`
local lgtv_path = "~/opt/lgtv/bin/lgtv" -- Full path to lgtv executable
local lgtv_cmd = lgtv_path.." "..tv_name.." "

if debug then
  print ("TV name: "..tv_name)
  print ("TV input: "..tv_input)
  print ("LGTV path: "..lgtv_path)
  print ("LGTV command: "..lgtv_cmd)
  print ("Running `"..lgtv_cmd.." swInfo`...")
  print (hs.execute(lgtv_cmd.." swInfo"))
end

watcher = hs.caffeinate.watcher.new(function(eventType)
  if (eventType == hs.caffeinate.watcher.screensDidWake or
      eventType == hs.caffeinate.watcher.systemDidWake or
      eventType == hs.caffeinate.watcher.screensDidUnlock) then

    hs.execute(lgtv_cmd.." on") -- wake on lan
    hs.execute(lgtv_cmd.." screenOn") -- turn on screen
    hs.execute(lgtv_cmd.." setInput "..tv_input)
    if debug then print("TV was turned on and input switched to "..tv_input) end
  end

  if (eventType == hs.caffeinate.watcher.screensDidSleep or
      eventType == hs.caffeinate.watcher.systemWillPowerOff) then

    -- This puts the TV in standby mode.
    -- For true "power off" use `off` instead of `screenOff`.
    hs.execute(lgtv_cmd.." screenOff")
    if debug then print("TV screen was turned off.") end
  end
end)
watcher:start()
