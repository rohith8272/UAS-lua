-- maintenance_tracker.lua
-- Saves a summary file "maintenance.log" to the SD card root 
-- Logger (Speed, Alt, Vibe, Breaches, Failsafes)
-- rohith8272@gmail.com

local file_name = "maintenance.log"

-- Message Severity Levels
local MAV_SEVERITY_INFO = 6
local MAV_SEVERITY_NOTICE = 5
local MAV_SEVERITY_ERROR = 3


local state = {
    boots = 0,
    flights = 0,
    total_time_min = 0,
    max_vibe = 0,
    max_speed_mps = 0,
    max_alt_m = 0,
    breaches = 0,
    failsafes = 0
}


local session = {
    start_time_ms = nil,
    max_vibe = 0,
    max_speed_mps = 0,
    max_alt_m = 0,
    breach_triggered = false,
    failsafe_triggered = false
}

local is_armed_prev = false

--fix write errors from types
local function safe_num(val)
    if not val then return 0 end
    if type(val) == "number" then return val end
    return tonumber(tostring(val)) or 0
end


-- PARAMETER SETUP (Enable/Disable & Log Selection)
local PARAM_TABLE_KEY = 75
local PARAM_TABLE_PREFIX = "MNT_"
param:add_table(PARAM_TABLE_KEY, PARAM_TABLE_PREFIX, 6)

-- Helper: Bind param safely
local function bind_param(key, index, name, default_val)
    local p = param:add_param(key, index, name, default_val)
    if type(p) ~= "userdata" then
        local p_fetched = param:get(PARAM_TABLE_PREFIX .. name)
        if p_fetched and type(p_fetched) == "userdata" then p = p_fetched end
    end
    return p
end

-- Helper: Get Param Value (Handles numbers/objects safely)
local function get_val(p)
    if type(p) == "userdata" then return p:get()
    elseif type(p) == "number" then return p
    else return 0 end
end

-- PARAMS:
-- 1. Enable Script (0=Disabled, 1=Enabled)
local ENABLE = bind_param(PARAM_TABLE_KEY, 1, 'ENABLE', 1)

-- 2. Log Bitmask (Add numbers to select features)
-- 1 = Vibration
-- 2 = Speed & Altitude
-- 4 = Fence Breaches
-- 8 = Battery Failsafes
-- Default 15 = All Enabled (1+2+4+8)
local LOG_MASK = bind_param(PARAM_TABLE_KEY, 2, 'LOG_MASK', 15)


local function save_state()
    local file = io.open(file_name, "w")
    if not file then
        gcs:send_text(MAV_SEVERITY_ERROR, "MNT: Error! SD Card Write Failed.")
        return
    end

    file:write("BOOTS=" .. tostring(state.boots) .. "\n")
    file:write("FLIGHTS=" .. tostring(state.flights) .. "\n")
    file:write("TIME_MIN=" .. string.format("%.2f", safe_num(state.total_time_min)) .. "\n")
    file:write("MAX_VIBE=" .. string.format("%.2f", safe_num(state.max_vibe)) .. "\n")
    file:write("MAX_SPD=" .. string.format("%.2f", safe_num(state.max_speed_mps)) .. "\n")
    file:write("MAX_ALT=" .. string.format("%.2f", safe_num(state.max_alt_m)) .. "\n")
    file:write("BREACHES=" .. tostring(state.breaches) .. "\n")
    file:write("FAILSAFES=" .. tostring(state.failsafes) .. "\n")
    
    file:close()
    gcs:send_text(MAV_SEVERITY_NOTICE, "MNT: Log Saved. (Flights: " .. tostring(state.flights) .. ")")
end

local function load_state()
    local file = io.open(file_name, "r")
    if not file then
        gcs:send_text(MAV_SEVERITY_NOTICE, "MNT: No log found. Creating new.")
        return 
    end

    local content = file:read("*all")
    file:close()
    if not content then return end

    local function parse(pattern)
        local v = string.match(content, pattern)
        return tonumber(v)
    end

    local b = parse("BOOTS=(%d+)")
    if b then state.boots = b end

    local f = parse("FLIGHTS=(%d+)")
    if f then state.flights = f end

    local t = parse("TIME_MIN=([%d%.]+)")
    if t then state.total_time_min = t end

    local v = parse("MAX_VIBE=([%d%.]+)")
    if v then state.max_vibe = v end

    local s = parse("MAX_SPD=([%d%.]+)")
    if s then state.max_speed_mps = s end

    local a = parse("MAX_ALT=([%d%.]+)")
    if a then state.max_alt_m = a end

    local br = parse("BREACHES=(%d+)")
    if br then state.breaches = br end

    local fs = parse("FAILSAFES=(%d+)")
    if fs then state.failsafes = fs end

    gcs:send_text(MAV_SEVERITY_INFO, "MNT: Loaded. Boot Count: " .. tostring(state.boots))
end



local function monitor_sensors()
    local mask = get_val(LOG_MASK) -- Read the bitmask parameter

    -- 1. Vibration Check (Bit 0 = 1)
    if (mask & 1) ~= 0 and ahrs and ahrs.get_vibration then
        local vibe = ahrs:get_vibration()
        if vibe then
            local v_len = vibe:length()
            if v_len > session.max_vibe then 
                session.max_vibe = v_len 
            end
        end
    end

    -- 2. Performance Check (Speed & Alt) (Bit 1 = 2)
    if (mask & 2) ~= 0 then
        -- Speed
        if gps and gps.ground_speed then
            local speed = gps:ground_speed(0)
            if speed and speed > session.max_speed_mps then
                session.max_speed_mps = speed
            end
        end
        -- Altitude
        if ahrs and ahrs.get_position and ahrs.get_home then
            local current_pos = ahrs:get_position()
            local home_pos = ahrs:get_home()
            if current_pos and home_pos then
                local alt_m = (current_pos:alt() - home_pos:alt()) * 0.01
                if alt_m > session.max_alt_m then session.max_alt_m = alt_m end
            end
        end
    end

    -- 3. Fence Breach Check (Bit 2 = 4)
    if (mask & 4) ~= 0 and fence and fence.get_breaches then
        local breach_type = fence:get_breaches() 
        if breach_type and breach_type > 0 then
            if not session.breach_triggered then
                state.breaches = state.breaches + 1
                session.breach_triggered = true
                gcs:send_text(MAV_SEVERITY_NOTICE, "MNT: Fence Breach Recorded!")
            end
        else
            session.breach_triggered = false
        end
    end

    -- 4. Battery Failsafe Check (Bit 3 = 8)
    if (mask & 8) ~= 0 and battery and battery.has_failsafed then
        if battery:has_failsafed() then
            if not session.failsafe_triggered then
                state.failsafes = state.failsafes + 1
                session.failsafe_triggered = true
                gcs:send_text(MAV_SEVERITY_NOTICE, "MNT: Battery Failsafe Recorded!")
            end
        end
    end
end

--startup Routine
load_state()
state.boots = state.boots + 1
save_state()

--main runs at 1 Hz 
function update()

    -- Check if script is enabled via Parameter
    if get_val(ENABLE) ~= 1 then 
        return update, 1000 -- Check again in 1 second
    end

    local is_armed = arming:is_armed()

    -- EVENT: Armed
    if is_armed and not is_armed_prev then
        session.start_time_ms = millis() 
        session.max_vibe = 0
        session.max_speed_mps = 0
        session.max_alt_m = 0
        session.breach_triggered = false
        session.failsafe_triggered = false
        gcs:send_text(MAV_SEVERITY_INFO, "MNT: Armed. Tracking Stats")
    end

    -- STATE: Flying
    if is_armed then
        monitor_sensors()
    end

    -- EVENT: Disarmed
    if is_armed_prev and not is_armed then
        if session.start_time_ms then
            local now = millis()
            local duration_ms = now - session.start_time_ms
            local duration_sec = safe_num(duration_ms) / 1000.0
            local duration_min = duration_sec / 60.0

            state.flights = state.flights + 1
            state.total_time_min = state.total_time_min + duration_min

            if session.max_vibe > state.max_vibe then state.max_vibe = session.max_vibe end
            if session.max_speed_mps > state.max_speed_mps then state.max_speed_mps = session.max_speed_mps end
            if session.max_alt_m > state.max_alt_m then state.max_alt_m = session.max_alt_m end

            gcs:send_text(MAV_SEVERITY_NOTICE, "MNT: Time: " .. string.format("%.2f", duration_min) .. " min")
            gcs:send_text(MAV_SEVERITY_NOTICE, "MNT: Max Spd: " .. string.format("%.1f", session.max_speed_mps) .. " m/s")
            gcs:send_text(MAV_SEVERITY_NOTICE, "MNT: Max Alt: " .. string.format("%.1f", session.max_alt_m) .. " m")
            
            save_state()
        else
            gcs:send_text(MAV_SEVERITY_NOTICE, "MNT: Error, no start time.")
        end
    end

    is_armed_prev = is_armed
    return update, 1000 --1 hz (1000ms/samples per sec)
end

return update()
