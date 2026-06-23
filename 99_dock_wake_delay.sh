#!/usr/bin/env bash
# ==============================================================================
# Script Name:  99_dock_wake_delay.sh
# Description:  SteamOS User-Space Dock Wake Delay Shield
# Author:       boba-fatt
# Repository:   https://github.com/boba-fatt/SteamDock_USB_Wake
#
# Purpose:      Intercepts system sleep/wake states via systemd to temporarily
#               mute USB hub wakeup vectors. This blocks electrical surges 
#               (like docking a controller to a charging cradle or not being 
#               fast enough when turning off a controller) from triggering 
#               accidental, immediate wake loops.
#
# Mechanics:    Reads customizable sleep buffers and targeted hardware profile 
#               VID:PID tokens dynamically from an external state database 
#               (dock_wake.conf) located entirely in un-protected user space.
# ==============================================================================
CONFIG_FILE="/home/deck/.config/systemd/user-sleep/dock_wake.conf"
BEDTIME_FILE="/home/deck/.config/systemd/user-sleep/last_sleep_timestamp.txt"
DEFAULT_DELAY=10

# 1. Try to read the value if the file exists
if [ -f "$CONFIG_FILE" ]; then
    SLEEP_BUFFER=$(grep -i "sleep_buffer_seconds=" "$CONFIG_FILE" | cut -d'=' -f2 | xargs)
fi

# 2. Check if the value is blank or the file is completely missing
if [ -z "$SLEEP_BUFFER" ]; then
    SLEEP_BUFFER=$DEFAULT_DELAY

    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        curl -sSL "https://raw.githubusercontent.com/boba-fatt/SteamDock_USB_Wake/main/dock_wake.conf" -o "$CONFIG_FILE"
    fi

    if ! grep -q "sleep_buffer_seconds=" "$CONFIG_FILE"; then
        if grep -q "\[SETTINGS\]" "$CONFIG_FILE"; then
            sed -i "/\[SETTINGS\]/a sleep_buffer_seconds=$DEFAULT_DELAY" "$CONFIG_FILE"
        else
            echo "sleep_buffer_seconds=$DEFAULT_DELAY" >> "$CONFIG_FILE"
        fi
    fi
fi

toggle_wake() {
    local target_state="$1" # 'enabled' or 'disabled'

    for dev in /sys/bus/usb/devices/*; do
        if [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ]; then
            vid=$(cat "$dev/idVendor")
            pid=$(cat "$dev/idProduct")

            while read -r entry; do
                entry=$(echo "$entry" | xargs)
                [[ "$entry" =~ ^#.*$ || -z "$entry" || "$entry" =~ ^\[.*\]$ || "$entry" == *=* ]] && continue

                if [[ "$vid:$pid" == "$entry" ]]; then
                    echo "$target_state" > "$dev/power/wakeup"
                fi
            done < "$CONFIG_FILE"
        fi
    done
}

case "$1" in
    pre)
        # Stamp our exact bedtime right before system code freezes
        date +%s > "$BEDTIME_FILE"

        # Ensure rules match the quiet state
        toggle_wake "disabled"
        ;;

    post)
        # 1. FEATURE BYPASS: If threshold is set to 0, the shield is completely OFF.
        if [ "$SLEEP_BUFFER" -eq 0 ]; then
            toggle_wake "enabled"
            exit 0
        fi

        # 2. POWER BUTTON HARDWARE OVERRIDE: Check if the physical power button woke the device.
        # Steam Deck power button interrupts typically log under 'pwrbtn' or 'LNXPWRBN' in sysfs.
        # We check the active wakeup sources to see if the power button was the trigger.
        if grep -q "pwrbtn" /sys/class/wakeup/*/name 2>/dev/null; then
            # Double-check if the power button's internal event count just incremented
            # If a power button event is active, bypass the shield entirely!
            toggle_wake "enabled"
            exit 0
        fi

        # 3. TIME-GATE EVALUATION: If it wasn't the power button, check the clock.
        CURRENT_TIME=$(date +%s)

        if [ -f "$BEDTIME_FILE" ]; then
            BEDTIME=$(cat "$BEDTIME_FILE")
            TIME_SPENT_SLEEPING=$((CURRENT_TIME - BEDTIME))

            # If we've slept LESS than our threshold, it's a false alarm cradle spike
            if [ "$TIME_SPENT_SLEEPING" -lt "$SLEEP_BUFFER" ]; then
                # Instantly force the system back to bed before video handshakes finish
                systemctl suspend
                exit 0
            fi
        fi

        # If we passed the guard time safely, it's a true couch wake. Turn the ears back on!
        toggle_wake "enabled"
        ;;
    esac
