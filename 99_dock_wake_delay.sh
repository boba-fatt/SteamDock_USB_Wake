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
DEFAULT_DELAY=10

# 1. Try to read the value if the file exists
if [ -f "$CONFIG_FILE" ]; then
    SLEEP_BUFFER=$(grep -i "sleep_buffer_seconds=" "$CONFIG_FILE" | cut -d'=' -f2 | xargs)
fi

# 2. Check if the value is blank or the file is completely missing
if [ -z "$SLEEP_BUFFER" ]; then
    SLEEP_BUFFER=$DEFAULT_DELAY

    # # NOTE: Instead of printing a raw file locally, we pull the official, fully-structured
    # # boilerplate configuration straight from the GitHub repository to keep things unified.
    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        curl -sSL "https://raw.githubusercontent.com/boba-fatt/SteamDock_USB_Wake/main/dock_wake.conf" -o "$CONFIG_FILE"
    fi

    # Double-check that our key actually exists or is filled out in the freshly pulled file
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

            # Read our config file line-by-line to find a match
            while read -r entry; do
                # Trim whitespace
                entry=$(echo "$entry" | xargs)

                # Skip comments, empty lines, INI section headers, and key-value settings lines
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
        toggle_wake "disabled"
        ;;
    post)
        sleep "$SLEEP_BUFFER"
        toggle_wake "enabled"
        ;;
esac
