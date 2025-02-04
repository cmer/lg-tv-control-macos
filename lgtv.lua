local LGTVController = {}
LGTVController.__index = LGTVController

-- Configuration
local config = {
    tv_ip = "",
    tv_mac_address = "",
    tv_input = "HDMI_1", -- Input to which your Mac is connected
    switch_input_on_wake = true, -- When computer wakes, switch to `tv_input`
    debug = false, -- Enable debug messages
    control_audio = false, -- Control audio volume/mute with keyboard
    prevent_sleep_when_using_other_input = true, -- Prevent TV sleep if TV is on an input other than `tv_input`
    disable_lgtv = false, -- Disable this script entirely by setting this to true
    -- You can also disable it by creating an empty file  at `~/.disable_lgtv`.

    -- You likely will not need to change anything below this line
    screen_off_command = "screen_off",
    key_file_path = "~/.aiopylgtv.sqlite",
    connected_tv_identifiers = {"LG TV", "LG TV SSCR2"},
    bin_path = "~/bin/bscpylgtvcommand",
    wakeonlan_path = "~/bin/wakeonlan",
    app_id = "com.webos.app." .. ("HDMI_1"):lower():gsub("_", ""),
    set_pc_mode_on_wake = true,
    tv_device_name = "Mac",
    debounce_seconds = 10,
    before_sleep_command = nil,
    after_sleep_command = nil,
    before_wake_command = nil,
    after_wake_command = nil,
}

if config.tv_ip == "" or config.tv_mac_address == "" then
  print("TV IP and MAC address not set. Please set them first.")
  return
end

-- Utility Functions
local function log_debug(message)
    if config.debug then print(message) end
end

local function file_exists(path)
    local file = io.open(path, "r")
    if not file then return false end
    file:close()
    return true
end

local function dump_table(o)
    if type(o) ~= 'table' then return tostring(o) end
    local s = '{ '
    for k, v in pairs(o) do
        s = s .. "[" .. tostring(k) .. "] = " .. dump_table(v) .. ", "
    end
    return s .. '} '
end

-- LGTVController Methods
function LGTVController:new()
    local obj = setmetatable({}, self)
    obj.bin_cmd = config.bin_path .. " -p " .. config.key_file_path .. " " .. config.tv_ip .. " "
    obj.last_wake_execution = 0
    obj.last_sleep_execution = 0
    return obj
end

function LGTVController:execute_command(command, strip)
    strip = strip or false
    local full_command = self.bin_cmd .. command

    local function try_execute()
        log_debug("Executing command: " .. full_command)
        local output, status, _, rc = hs.execute(full_command, 5)
        if rc == 0 then return output end
        log_debug("Command failed or timed out (exit code: " .. rc .. "): " .. full_command)
        log_debug("Command stdout: " .. output)
        return nil
    end

    local output = try_execute()
    if not output then
        hs.timer.usleep(1000000) -- 1 second in microseconds
        log_debug("Retrying command after 1 second delay...")
        output = try_execute()
        if not output then
            return nil
        end
    end

    if strip then
        return output:match("^(.-)%s*$")
    end
    return output
end

function LGTVController:is_connected()
    for _, identifier in ipairs(config.connected_tv_identifiers) do
        if hs.screen.find(identifier) then
            return true
        end
    end
    return false
end

function LGTVController:disabled()
    return config.disable_lgtv or file_exists("./disable_lgtv") or file_exists(os.getenv('HOME') .. "/.disable_lgtv")
end

function LGTVController:current_app_id()
    return self:execute_command("get_current_app", true)
end

function LGTVController:is_current_audio_device()
    local current_time = os.time()
    if not self.last_audio_device_check or current_time - self.last_audio_device_check >= 10 then
        self.last_audio_device_check = current_time
        self.last_audio_device = false

        local current_audio = hs.audiodevice.current().name
        for _, identifier in ipairs(config.connected_tv_identifiers) do
            if current_audio == identifier then
                log_debug(identifier .. " is the current audio device")
                self.last_audio_device = true
                break
            end
        end
        log_debug(current_audio .. " is the current audio device.")
    end
    return self.last_audio_device
end

function LGTVController:get_muted()
    return self:execute_command("get_muted"):trim() == "True"
end

function LGTVController:toggle_mute()
    local muted = self:get_muted()
    local new_muted = not muted
    if self:execute_command("set_mute " .. tostring(new_muted):lower()) then
        log_debug("Set muted to: " .. tostring(new_muted) .. " (was " .. tostring(muted) .. ")")
    end
end

function LGTVController:log_init()
    log_debug("\n\n-------------------- LGTV DEBUG INFO --------------------")
    log_debug("TV input: " .. config.tv_input)
    log_debug("Binary path: " .. config.bin_path)
    log_debug("Binary command: " .. self.bin_cmd)
    log_debug("App ID: " .. config.app_id)
    log_debug("LGTV Disabled: " .. tostring(self:disabled()))
    if not self:disabled() then
        log_debug(self:execute_command("get_software_info"))
        log_debug("Current app ID: " .. tostring(self:current_app_id()))
        log_debug("Connected screens: " .. dump_table(hs.screen.allScreens()))
        log_debug("TV is connected? " .. tostring(self:is_connected()))
    end
    log_debug("------------------------------------------------------------\n\n")
end

-- Event Handlers
function LGTVController:handle_wake_event()
    local current_time = os.time()
    if current_time - self.last_wake_execution < config.debounce_seconds then
        log_debug("Skipping wake execution - debounced.")
        return
    end
    self.last_wake_execution = current_time

    if config.before_wake_command then
        log_debug("Executing before wake command: " .. config.before_wake_command)
        hs.execute(config.before_wake_command)
    end

    if config.tv_mac_address ~= "" then
        local command = config.wakeonlan_path .. " " .. config.tv_mac_address
        hs.execute(command)
        log_debug("Wake on LAN packet sent to " .. config.tv_mac_address)
    end

    if self:execute_command("turn_screen_on") then
        log_debug("TV screen turned on")
    end

    if self:current_app_id() ~= config.app_id and config.switch_input_on_wake then
        if self:execute_command("launch_app " .. config.app_id) then
            log_debug("Switched TV input to " .. config.app_id)
        end
    end

    if config.set_pc_mode_on_wake then
        if self:execute_command("set_device_info " .. config.tv_input .. " pc '" .. config.tv_device_name .. "'") then
            log_debug("Set TV to PC mode")
        end
    end

    if config.after_wake_command then
        log_debug("Executing after wake command: " .. config.after_wake_command)
        hs.execute(config.after_wake_command)
    end
end

function LGTVController:handle_sleep_event()
    local current_time = os.time()
    if current_time - self.last_sleep_execution < config.debounce_seconds then
        log_debug("Skipping sleep execution - debounced.")
        return
    end
    self.last_sleep_execution = current_time

    local current_app = tostring(self:current_app_id())

    log_debug("TV is connected and going to sleep")
    log_debug("Current TV input: " .. current_app)
    log_debug("Prevent sleep on other input: " .. tostring(config.prevent_sleep_when_using_other_input))
    log_debug("Expected computer input: " .. config.tv_input)

    if current_app ~= config.app_id and config.prevent_sleep_when_using_other_input then
        log_debug("TV is on another input (" .. current_app .. "). Skipping power off.")
        return
    end

    if config.before_sleep_command then
        log_debug("Executing before sleep command: " .. config.before_sleep_command)
        hs.execute(config.before_sleep_command)
    end

    if self:execute_command(config.screen_off_command) then
        log_debug("TV screen turned off with command: " .. config.screen_off_command)
    end

    if config.after_sleep_command then
        log_debug("Executing after sleep command: " .. config.after_sleep_command)
        hs.execute(config.after_sleep_command)
    end
end

function LGTVController:setup_watchers()
    self.watcher = hs.caffeinate.watcher.new(function(eventType)
        local event_names = {
            "systemDidWake",
            "systemWillSleep",
            "systemWillPowerOff",
            "screensDidSleep",
            "screensDidWake",
            "sessionDidResignActive",
            "sessionDidBecomeActive",
            "screensaverDidStart",
            "screensaverWillStop",
            "screensaverDidStop",
            "screensDidLock",
            "screensDidUnlock"
        }
        local event_name = eventType and event_names[eventType + 1] or "unknown"
        log_debug("Received event: " .. tostring(eventType) .. " (" .. tostring(event_name) .. ")")

        if self:disabled() then
            log_debug("LGTV feature disabled. Skipping event handling.")
            return
        end

        if self:is_connected() then
            if eventType == hs.caffeinate.watcher.screensDidWake or
               eventType == hs.caffeinate.watcher.systemDidWake or
               eventType == hs.caffeinate.watcher.screensDidUnlock then
                self:handle_wake_event()
            elseif eventType == hs.caffeinate.watcher.screensDidSleep or
                   eventType == hs.caffeinate.watcher.systemWillPowerOff then
                self:handle_sleep_event()
            end
        end
    end)

    self.audio_event_tap = hs.eventtap.new(
        {hs.eventtap.event.types.keyDown, hs.eventtap.event.types.systemDefined},
        function(event)
            local system_key = event:systemKey()
            local key_actions = {['SOUND_UP'] = "volume_up", ['SOUND_DOWN'] = "volume_down"}
            local pressed_key = tostring(system_key.key)

            if system_key.down then
                if pressed_key == 'MUTE' then
                    if not self:is_current_audio_device() then return end
                    self:toggle_mute()
                elseif key_actions[pressed_key] then
                    if not self:is_current_audio_device() then return end
                    self:execute_command(key_actions[pressed_key])
                end
            end
        end
    )
end

function LGTVController:start()
    self:log_init()
    print("Starting LGTV watcher...")
    self.watcher:start()

    if config.control_audio then
        print("Starting LGTV audio events watcher...")
        self.audio_event_tap:start()
    end
end

-- Initialize and start the controller
local controller = LGTVController:new()
controller:setup_watchers()
controller:start()
