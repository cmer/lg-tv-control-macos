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
    set_pc_mode_on_wake = true,
    tv_device_name = "Mac",
    debounce_seconds = 10,
    before_sleep_command = nil,
    after_sleep_command = nil,
    before_wake_command = nil,
    after_wake_command = nil,
}

-- FIX: app_id must be derived from config.tv_input, not a hardcoded literal.
-- (A Lua table constructor can't reference its own sibling fields, so this
-- has to happen after the table closes.) Previously this was hardcoded to
-- "HDMI_1" regardless of the tv_input setting above, silently breaking
-- input-switching/current-input comparisons for anyone on HDMI_2/3/4.
config.app_id = "com.webos.app." .. config.tv_input:lower():gsub("_", "")

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

-- Expands a leading "~" to $HOME for Lua-side file checks (the shell does
-- this natively for the commands we run, but io.open does not).
local function expand_path(path)
    if path:sub(1, 1) == "~" then
        return (os.getenv("HOME") or "") .. path:sub(2)
    end
    return path
end

-- Wraps a value in single quotes for safe inclusion in a shell command,
-- escaping any embedded single quotes. Only used for values that don't
-- need shell tilde (~) expansion, since quoting would suppress that.
local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function dump_table(o)
    if type(o) ~= 'table' then return tostring(o) end
    local s = '{ '
    for k, v in pairs(o) do
        s = s .. "[" .. tostring(k) .. "] = " .. dump_table(v) .. ", "
    end
    return s .. '} '
end

-- Names for hs.caffeinate.watcher event codes, hoisted out of the watcher
-- callback so the table isn't reallocated on every system event.
local CAFFEINATE_EVENT_NAMES = {
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

-- Media-key name -> TV command, hoisted out of the audio event tap callback
-- so the table isn't reallocated on every keystroke.
local AUDIO_KEY_ACTIONS = {['SOUND_UP'] = "volume_up", ['SOUND_DOWN'] = "volume_down"}

-- Default timeout for any single shelled-out command. hs.task has no
-- built-in timeout, so without this, a hung subprocess (e.g. a TV that
-- accepts the TCP connection but never responds) would stall its async
-- chain forever. Raise this if your TV is slow to respond over Wi-Fi.
local DEFAULT_TASK_TIMEOUT_SECONDS = 5

-- Runs `/bin/sh -c command` asynchronously with a timeout. callback(exitCode,
-- stdOut, stdErr) is always invoked exactly once — either on the process's
-- own completion, or on timeout (exitCode -1, stdErr "timeout"), in which
-- case the process is sent SIGTERM. This guarantees callers can always
-- chain off the callback without risking an indefinite stall.
local function run_task_async(command, timeout_seconds, callback)
    timeout_seconds = timeout_seconds or DEFAULT_TASK_TIMEOUT_SECONDS
    local completed = false
    local task

    local function finish_once(exitCode, stdOut, stdErr)
        if completed then return end
        completed = true
        if callback then callback(exitCode, stdOut, stdErr) end
    end

    local timeout_timer = hs.timer.doAfter(timeout_seconds, function()
        if completed then return end
        log_debug("Command timed out after " .. timeout_seconds .. "s: " .. command)
        if task then task:terminate() end
        finish_once(-1, "", "timeout")
    end)

    task = hs.task.new("/bin/sh", function(exitCode, stdOut, stdErr)
        timeout_timer:stop()
        finish_once(exitCode, stdOut, stdErr)
    end, {"-c", command})
    task:start()
    return task
end

-- Runs an arbitrary shell command asynchronously (non-blocking), with the
-- same timeout protection as run_task_async.
-- callback(exitCode, stdOut, stdErr) is invoked on completion; optional.
local function run_shell_async(command, callback, timeout_seconds)
    log_debug("Executing (async): " .. command)
    return run_task_async(command, timeout_seconds, callback)
end

-- LGTVController Methods
function LGTVController:new()
    local obj = setmetatable({}, self)
    obj.bin_cmd = config.bin_path .. " -p " .. config.key_file_path .. " " .. config.tv_ip .. " "
    obj.last_wake_execution = 0
    obj.last_sleep_execution = 0
    obj.busy = false
    return obj
end

-- Async, non-blocking replacement for the old synchronous execute_command.
-- Preserves the original retry-once-after-1-second behavior, but the retry
-- delay is scheduled via hs.timer.doAfter instead of a blocking usleep, and
-- the subprocess itself runs on a background thread via hs.task — with a
-- real timeout this time, unlike the original's non-functional "5" argument
-- to hs.execute — instead of the blocking hs.execute. callback(output)
-- receives nil on failure.
function LGTVController:execute_command_async(command, strip, callback)
    strip = strip or false
    local full_command = self.bin_cmd .. command

    local function finish(output)
        if output and strip then
            output = output:match("^%s*(.-)%s*$")
        end
        if callback then callback(output) end
    end

    local function attempt(is_retry)
        log_debug("Executing command" .. (is_retry and " (retry)" or "") .. ": " .. full_command)
        run_task_async(full_command, DEFAULT_TASK_TIMEOUT_SECONDS, function(exitCode, stdOut, stdErr)
            if exitCode == 0 then
                finish(stdOut)
            else
                log_debug("Command failed or timed out (exit code: " .. tostring(exitCode) .. "): " .. full_command)
                log_debug("Command stdout: " .. tostring(stdOut))
                if is_retry then
                    finish(nil)
                else
                    log_debug("Retrying command after 1 second delay...")
                    hs.timer.doAfter(1, function() attempt(true) end)
                end
            end
        end)
    end

    attempt(false)
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

function LGTVController:current_app_id_async(callback)
    self:execute_command_async("get_current_app", true, callback)
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

function LGTVController:get_muted_async(callback)
    self:execute_command_async("get_muted", true, function(output)
        callback(output == "True")
    end)
end

function LGTVController:toggle_mute_async()
    self:get_muted_async(function(muted)
        local new_muted = not muted
        self:execute_command_async("set_mute " .. tostring(new_muted):lower(), false, function(output)
            if output then
                log_debug("Set muted to: " .. tostring(new_muted) .. " (was " .. tostring(muted) .. ")")
            end
        end)
    end)
end

function LGTVController:log_init()
    -- FIX: bail out up front when debug is off, so none of the exec calls
    -- below are ever evaluated (previously they ran unconditionally because
    -- they were passed as arguments to log_debug, which only gates the
    -- print — not the argument evaluation).
    if not config.debug then return end

    log_debug("\n\n-------------------- LGTV DEBUG INFO --------------------")
    log_debug("TV input: " .. config.tv_input)
    log_debug("Binary path: " .. config.bin_path)
    log_debug("Binary command: " .. self.bin_cmd)
    log_debug("App ID: " .. config.app_id)
    log_debug("LGTV Disabled: " .. tostring(self:disabled()))
    if not self:disabled() then
        self:execute_command_async("get_software_info", false, function(out)
            log_debug(out)
        end)
        self:current_app_id_async(function(app_id)
            log_debug("Current app ID: " .. tostring(app_id))
        end)
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
    if self.busy then
        log_debug("Skipping wake execution - a wake/sleep sequence is already in progress.")
        return
    end
    self.last_wake_execution = current_time
    self.busy = true

    -- Steps run in the same order as before, but chained as async
    -- callbacks instead of blocking the main thread at each step.
    local function do_after_wake()
        self.busy = false
        if config.after_wake_command then
            log_debug("Executing after wake command: " .. config.after_wake_command)
            run_shell_async(config.after_wake_command)
        end
    end

    local function do_pc_mode()
        if config.set_pc_mode_on_wake then
            self:execute_command_async("set_device_info " .. config.tv_input .. " pc " .. shell_quote(config.tv_device_name), false, function(output)
                if output then log_debug("Set TV to PC mode") end
                do_after_wake()
            end)
        else
            do_after_wake()
        end
    end

    local function do_switch_input()
        if config.switch_input_on_wake then
            self:current_app_id_async(function(current_app)
                if current_app ~= config.app_id then
                    self:execute_command_async("launch_app " .. config.app_id, false, function(output)
                        if output then log_debug("Switched TV input to " .. config.app_id) end
                        do_pc_mode()
                    end)
                else
                    do_pc_mode()
                end
            end)
        else
            do_pc_mode()
        end
    end

    local function do_screen_on()
        self:execute_command_async("turn_screen_on", false, function(output)
            if output then log_debug("TV screen turned on") end
            do_switch_input()
        end)
    end

    local function do_wol()
        if config.tv_mac_address ~= "" then
            local command = config.wakeonlan_path .. " " .. config.tv_mac_address
            run_shell_async(command, function()
                log_debug("Wake on LAN packet sent to " .. config.tv_mac_address)
                do_screen_on()
            end)
        else
            do_screen_on()
        end
    end

    if config.before_wake_command then
        log_debug("Executing before wake command: " .. config.before_wake_command)
        run_shell_async(config.before_wake_command, do_wol)
    else
        do_wol()
    end
end

function LGTVController:handle_sleep_event()
    local current_time = os.time()
    if current_time - self.last_sleep_execution < config.debounce_seconds then
        log_debug("Skipping sleep execution - debounced.")
        return
    end
    if self.busy then
        log_debug("Skipping sleep execution - a wake/sleep sequence is already in progress.")
        return
    end
    self.last_sleep_execution = current_time
    self.busy = true

    self:current_app_id_async(function(current_app_raw)
        local current_app = tostring(current_app_raw)

        log_debug("TV is connected and going to sleep")
        log_debug("Current TV input: " .. current_app)
        log_debug("Prevent sleep on other input: " .. tostring(config.prevent_sleep_when_using_other_input))
        log_debug("Expected computer input: " .. config.tv_input)

        if current_app ~= config.app_id and config.prevent_sleep_when_using_other_input then
            log_debug("TV is on another input (" .. current_app .. "). Skipping power off.")
            self.busy = false
            return
        end

        local function do_after_sleep()
            self.busy = false
            if config.after_sleep_command then
                log_debug("Executing after sleep command: " .. config.after_sleep_command)
                run_shell_async(config.after_sleep_command)
            end
        end

        local function do_screen_off()
            self:execute_command_async(config.screen_off_command, false, function(output)
                if output then log_debug("TV screen turned off with command: " .. config.screen_off_command) end
                do_after_sleep()
            end)
        end

        if config.before_sleep_command then
            log_debug("Executing before sleep command: " .. config.before_sleep_command)
            run_shell_async(config.before_sleep_command, do_screen_off)
        else
            do_screen_off()
        end
    end)
end

function LGTVController:setup_watchers()
    self.watcher = hs.caffeinate.watcher.new(function(eventType)
        local event_name = eventType and CAFFEINATE_EVENT_NAMES[eventType + 1] or "unknown"
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

    -- FIX: media keys (mute/volume) arrive as `systemDefined` events on
    -- macOS; `:systemKey()` is only valid for that event type (Hammerspoon's
    -- own docs call the result "unspecified" for any other type). The
    -- previous version also subscribed to plain `keyDown` and called
    -- `:systemKey()` unconditionally on every keystroke with no nil check —
    -- undefined behavior on every regular key press whenever control_audio
    -- was enabled. Now we only subscribe to systemDefined and guard against
    -- a nil result.
    self.audio_event_tap = hs.eventtap.new(
        {hs.eventtap.event.types.systemDefined},
        function(event)
            local system_key = event:systemKey()
            if not system_key then return end
            local pressed_key = tostring(system_key.key)

            if system_key.down then
                if pressed_key == 'MUTE' then
                    if not self:is_current_audio_device() then return end
                    self:toggle_mute_async()
                elseif AUDIO_KEY_ACTIONS[pressed_key] then
                    if not self:is_current_audio_device() then return end
                    self:execute_command_async(AUDIO_KEY_ACTIONS[pressed_key], false, nil)
                end
            end
        end
    )
end

function LGTVController:start()
    -- Surface misconfiguration immediately and unconditionally (not gated
    -- behind config.debug) instead of letting every command silently fail
    -- and retry forever.
    if not file_exists(expand_path(config.bin_path)) then
        print("LGTV WARNING: bin_path '" .. config.bin_path .. "' not found. TV commands will fail until this is fixed.")
    end
    if config.tv_mac_address ~= "" and not file_exists(expand_path(config.wakeonlan_path)) then
        print("LGTV WARNING: wakeonlan_path '" .. config.wakeonlan_path .. "' not found. Wake-on-LAN will not work until this is fixed.")
    end

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
