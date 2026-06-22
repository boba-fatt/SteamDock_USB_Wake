#!/usr/bin/env bash
# ==============================================================================
# Script Name:  manage_dock.sh
# Description:  Unified Installation & Control Panel for Steam Deck Dock Wake
# Author:       boba-fatt
# Repository:   https://github.com/boba-fatt/SteamDock_USB_Wake
# ==============================================================================

export CONFIG_FILE="/home/deck/.config/systemd/user-sleep/dock_wake.conf"
export RUNTIME_SCRIPT="/home/deck/.config/systemd/user-sleep/99_dock_wake_delay.sh"
export SERVICE_FILE="/home/deck/.config/systemd/user/dock-wake-shield.service"
export UDEV_PATH="/etc/udev/rules.d/99-dock-hub-wake.rules"
export REPO_BASE="https://raw.githubusercontent.com/boba-fatt/SteamDock_USB_Wake/main"

# ------------------------------------------------------------------------------
# 1. STANDARDIZED REUSABLE HELPER FUNCTIONS
# ------------------------------------------------------------------------------

unlock_system() {
    sudo steamos-readonly disable
}

lock_system() {
    sudo steamos-readonly enable
}

get_config_value() {
    local key="$1"
    if [ -f "$CONFIG_FILE" ]; then
        grep -i "^${key}=" "$CONFIG_FILE" | cut -d'=' -f2 | xargs
    fi
}

set_config_value() {
    local key="$1"
    local value="$2"
    if [ -f "$CONFIG_FILE" ]; then
        if grep -q "^${key}=" "$CONFIG_FILE"; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
        else
            echo "${key}=${value}" >> "$CONFIG_FILE"
        fi
    fi
}

fetch_repo_asset() {
    local filename="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    curl -sSL "${REPO_BASE}/${filename}" -o "$dest"
    if [[ "$dest" == *.sh || "$dest" == *manage_dock.sh ]]; then
        chmod +x "$dest"
    fi
}

create_desktop_launcher() {
    local desktop_launcher="/home/deck/Desktop/DockWakeManager.desktop"
    cat << EOF > "$desktop_launcher"
[Desktop Entry]
Name=Dock Wake Manager
Comment=Manage Steam Deck USB Hub Wake and Sleep Shields
Exec=$HOME/.config/systemd/user-sleep/manage_dock.sh
Icon=preferences-system-power
Terminal=false
Type=Application
Categories=Utility;
EOF
    chmod +x "$desktop_launcher"
}

# ------------------------------------------------------------------------------
# 2. "BRAIN FART" DETECTION ENGINE (SELF-HEALING SYSTEM DIAGNOSTIC)
# ------------------------------------------------------------------------------
run_diagnostic() {
    # If config is missing but assets exist, reverse-engineer and reconstruct it
    if [ ! -f "$CONFIG_FILE" ] && { [ -f "$UDEV_PATH" ] || systemctl --user is-enabled dock-wake-shield.service &>/dev/null; }; then
        fetch_repo_asset "dock_wake.conf" "$CONFIG_FILE"

        # Recover Service Status
        if systemctl --user is-enabled dock-wake-shield.service &>/dev/null; then
            set_config_value "user_sleep_service_installed" "true"
        fi

        # Recover udev Rules Status & Cached Hub Profiles
        if [ -f "$UDEV_PATH" ]; then
            set_config_value "udev_rules_installed" "true"
            local vids=($(grep -oP 'ATTRS{idVendor}=="\K[^" ]+' "$UDEV_PATH"))
            local pids=($(grep -oP 'ATTRS{idProduct}=="\K[^" ]+' "$UDEV_PATH"))
            local total_hubs=${#vids[@]}

            set_config_value "total_managed_hubs" "$total_hubs"
            for ((i=0; i<total_hubs; i++)); do
                sed -i "/\[MANAGED_HUBS\]/a ${vids[$i]}:${pids[$i]}" "$CONFIG_FILE"
            done
        fi
    fi

    # BRAIN FART AUTO-HEAL: Re-verify desktop app launcher existence
    if [ -f "$CONFIG_FILE" ] && [ ! -f "/home/deck/Desktop/DockWakeManager.desktop" ]; then
        create_desktop_launcher
    fi
}

# ------------------------------------------------------------------------------
# 3. INTERACTIVE GUI PIPELINE (DYNAMIC LOOP)
# ------------------------------------------------------------------------------
show_main_menu() {
    run_diagnostic

    # Check if core layout is currently installed
    local is_installed=false
    if [ -f "$CONFIG_FILE" ] && [ -f "$RUNTIME_SCRIPT" ] && [ -f "$SERVICE_FILE" ]; then
        is_installed=true
    fi

    local menu_options=()
    if [ "$is_installed" = true ]; then
        if [ "$FRESHLY_INSTALLED" = true ]; then
            menu_options+=("Update / Repair Utilities" "(*) Scan & Register Hubs" "(*) Adjust Sleep Timer" "Completely Uninstall")
        else
            menu_options+=("Update / Repair Utilities" "Scan & Register Hubs" "Adjust Sleep Timer" "Completely Uninstall")
        fi
    else
        menu_options+=("Install Core Utility Suite")
    fi

    CHOICE=$(zenity --list \
        --title="Steam Deck Dock Wake Manager" \
        --text="Select an operation to perform:" \
        --column="Actions" "${menu_options[@]}" \
        --height=300 --width=400 \
        --ok-label="Select" --cancel-label="Exit")

    case "$CHOICE" in
        "Install Core Utility Suite")
            execute_install
            export FRESHLY_INSTALLED=true
            show_main_menu
            ;;
        "Update / Repair Utilities")
            execute_install
            zenity --info --text="Utility suite successfully verified and repaired!" --timeout=2
            show_main_menu
            ;;
        *"Scan & Register Hubs")
            execute_hub_wizard
            show_main_menu
            ;;
        *"Adjust Sleep Timer")
            execute_timer_config
            show_main_menu
            ;;
        "Completely Uninstall")
            execute_uninstall
            export FRESHLY_INSTALLED=false
            show_main_menu
            ;;
        *)
            exit 0
            ;;
    esac
}

# ------------------------------------------------------------------------------
# 4. UNDERLYING EXECUTION ENGINES
# ------------------------------------------------------------------------------
execute_install() {
    fetch_repo_asset "dock_wake.conf" "$CONFIG_FILE"
    fetch_repo_asset "99_dock_wake_delay.sh" "$RUNTIME_SCRIPT"
    fetch_repo_asset "dock-wake-shield.service" "$SERVICE_FILE"

    systemctl --user daemon-reload
    systemctl --user enable dock-wake-shield.service
    set_config_value "user_sleep_service_installed" "true"

    echo "deck ALL=(ALL) NOPASSWD: $RUNTIME_SCRIPT" | sudo tee /etc/sudoers.d/dock-wake-shield > /dev/null
    create_desktop_launcher
}

execute_timer_config() {
    local current_delay=$(get_config_value "sleep_buffer_seconds")
    [ -z "$current_delay" ] && current_delay=10

    local form_output=$(zenity --forms --title="Configure Sleep Buffer" \
        --text="Select manual mode or simple slider configuration rules:" \
        --add-radio="Use Simple Slider (Recommended)" \
        --add-radio="Use Advanced Manual Input" \
        --add-scale="Simple Slider Adjust (2 to 30s)" --value="$current_delay" --min-value=2 --max-value=30 --step=1 \
        --add-entry="Advanced Manual Entry (Up to 120s)" --entry-text="$current_delay")

    if [ -n "$form_output" ]; then
        local use_simple=$(echo "$form_output" | cut -d'|' -f1)
        local slider_val=$(echo "$form_output" | cut -d'|' -f3)
        local manual_val=$(echo "$form_output" | cut -d'|' -f4 | xargs)

        local final_value=$current_delay
        if [ "$use_simple" = "TRUE" ]; then
            final_value=$slider_val
        else
            if [[ "$manual_val" =~ ^[0-9]+$ ]]; then
                if [ "$manual_val" -gt 120 ]; then
                    final_value=120
                    zenity --warning --text="Value exceeded maximum cap. Automatically bound to 120 seconds." --timeout=3
                elif [ "$manual_val" -lt 2 ]; then
                    final_value=2
                else
                    final_value=$manual_val
                fi
            fi
        fi
        set_config_value "sleep_buffer_seconds" "$final_value"
    fi
}

execute_hub_wizard() {
    local usb_list=()
    while read -r line; do
        local vid=$(echo "$line" | awk '{print $6}' | cut -d':' -f1)
        local pid=$(echo "$line" | awk '{print $6}' | cut -d':' -f2)
        local desc=$(echo "$line" | cut -d' ' -f7-)
        usb_list+=( "FALSE" "$vid:$pid" "$desc" )
    done < <(lsusb | grep -i "hub" | grep -v "root hub")

    if [ ${#usb_list[@]} -eq 0 ]; then
        zenity --error --text="No compatible external USB hubs were discovered attached to the Deck."
        return
    fi

    local chosen_hubs=$(zenity --list --checklist --title="Hardware Discovery Wizard" \
        --text="Check the target desktop dock components to control:" \
        --column="Manage" --column="Hardware ID" --column="Device Description" \
        "${usb_list[@]}" --height=350 --width=500)

    if [ -n "$chosen_hubs" ]; then
        unlock_system
        rm -f "$UDEV_PATH"
        sed -i '/\[MANAGED_HUBS\]/q' "$CONFIG_FILE"

        local IFS='|'
        local count=0
        for entry in $chosen_hubs; do
            local vid=$(echo "$entry" | cut -d':' -f1)
            local pid=$(echo "$entry" | cut -d':' -f2)

            echo "SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\", ATTR{power/wakeup}=\"enabled\"" >> "$UDEV_PATH"
            echo "$entry" >> "$CONFIG_FILE"
            ((count++))
        done

        set_config_value "total_managed_hubs" "$count"
        set_config_value "udev_rules_installed" "true"

        sudo udevadm control --reload-rules && sudo udevadm trigger
        lock_system
        zenity --info --text="Successfully registered $count dock tracking vectors!" --timeout=2
    fi
}

execute_uninstall() {
    unlock_system
    rm -f "$UDEV_PATH"
    sudo udevadm control --reload-rules && sudo udevadm trigger
    lock_system

    systemctl --user disable dock-wake-shield.service &>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload

    sudo rm -f /etc/sudoers.d/dock-wake-shield
    rm -rf "/home/deck/.config/systemd/user-sleep/"
    rm -f "/home/deck/Desktop/DockWakeManager.desktop"

    zenity --info --text="All components cleanly purged from the system architecture." --timeout=2
}

show_main_menu
