
## Maintenance Tracker (Lua Script)

This script acts as a persistent "Odometer" and health monitor for your ArduPilot vehicle. Unlike Dataflash logs which are rotated and deleted, this script maintains a single, lightweight text file on the SD card that tracks the lifetime history of the airframe.

## Features
It automatically tracks and saves the following data upon every **Disarm**:
* Total Boot Cycles, Total Flight Count, Total Flight Hours.
* Maximum Ground Speed (m/s) and Maximum Altitude (m) ever reached.
* Peak Vibration levels recorded across the airframe's life.
* Cumulative count of Geofence Breaches and Battery Failsafe events.

## Installation

1.  **Prepare the Script:**
    * Download `maintenance_tracker.lua`.
    * Copy the file to the `APM/scripts/` directory on your flight controller's SD card.
    * *Note: If using Simulation (SITL), place it in the `scripts/` folder inside your working directory.*

2.  **Enable Scripting:**
    * Connect to your flight controller.
    * Set the parameter `SCR_ENABLE` to **1**.
    * **Reboot** the flight controller.

3.  **Verify:**
    * After rebooting, check the **Messages** tab in your Ground Control Station (Mission Planner/QGC).
    * You should see the message: `MNT: System Loaded. Boot Count: X`.

## Configuration (Parameters)

Once the script is running, refresh your parameters. You will see a new parameter group starting with `MNT_`.

| Parameter | Description | Default |
| :--- | :--- | :--- |
| **MNT_ENABLE** | Master switch. Set to **0** to disable, **1** to enable logging. | 1 |
| **MNT_LOG_MASK** | Bitmask to select which sensors to monitor (see table below). | 15 |
| **MNT_RESET** | Set to **1** to wipe the log file and reset all counters to zero. | 0 |


## Modifying the Script

If you want to understand how the bitmask logic works, look at the `monitor_sensors()` function inside the script.

Here is a snippet showing how the bitmask is checked using Lua's bitwise operators:

```lua
-- Snippet from maintenance_tracker.lua

-- 1. Get the current value of the parameter
local mask = get_val(LOG_MASK) 

-- 2. Check if the Vibration bit (1) is set
-- (mask & 1) performs a bitwise AND. If the result is not 0, the feature is ON.
if (mask & 1) ~= 0 then
    -- Run Vibration Logic
    local vibe = ahrs:get_vibration()
    if vibe and vibe:length() > session.max_vibe then 
        session.max_vibe = vibe:length() 
    end
end

-- 3. Check if the Performance bit (2) is set
if (mask & 2) ~= 0 then
    -- Run Speed & Altitude Logic
    local speed = gps:ground_speed(0)
    -- ...
end

```

To permanently force a feature **ON** regardless of parameters, you can simply remove the `if` check:

```lua
-- Modified: Always runs vibration check, ignores LOG_MASK
-- if (mask & 1) ~= 0 then  <-- Removed this line
    local vibe = ahrs:get_vibration()
    -- ...
-- end                      <-- Removed this line

```

## Viewing the Data

The data is saved to a file named `maintenance.log` in the root directory of the SD card.

**To view it without removing the SD card:**

1. Open Mission Planner.
2. Press **Ctrl + F**.
3. Click **MAVFtp**.
4. Select the `maintenance.log` file and download/view it.

**Example Output:**

```text
BOOTS=42
FLIGHTS=15
TIME_MIN=124.50
MAX_VIBE=14.20
MAX_SPD=22.50
MAX_ALT=120.00
BREACHES=0
FAILSAFES=1

```

