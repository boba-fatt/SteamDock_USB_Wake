#!/usr/bin/env bash
# ==============================================================================
# Script Name:  manage_dock.sh
# Description:  Unified Installation & Control Panel for Steam Deck Dock Wake
# Author:       boba-fatt
# Repository:   https://github.com/boba-fatt/SteamDock_USB_Wake
# ==============================================================================
export TARGET_BRANCH="${BRANCH_NAME:-main}"
export REPO_BASE="https://raw.githubusercontent.com/boba-fatt/SteamDock_USB_Wake/${TARGET_BRANCH}"
export CONFIG_FILE="/home/deck/.config/systemd/user-sleep/dock_wake.conf"
export RUNTIME_SCRIPT="/home/deck/.config/systemd/user-sleep/99_dock_wake_delay.sh"
export SERVICE_FILE="/home/deck/.config/systemd/user/dock-wake-shield.service"
export UDEV_PATH="/etc/udev/rules.d/99-dock-hub-wake.rules"

# Mute standard library font warning chatter
zenity() {
    command zenity "$@" 2>/dev/null
}

# ------------------------------------------------------------------------------
# 1. STANDARDIZED REUSABLE HELPER FUNCTIONS
# ------------------------------------------------------------------------------

verify_system_password_exists() {
    # Check if the deck user can escalate or if the account password status is blank/locked
    if ! echo "testing_privileges" | sudo -S -v &>/dev/null; then
        if passwd -S deck 2>/dev/null | grep -E -q "L|NP"; then
            
            # Explicit, beginner-friendly informational warning block
            local message_text="<b>⚠️ Administrator Password Required</b>\n\n"
            message_text="${message_text}It looks like you haven't set up a system password for your Steam Deck yet!\n\n"
            message_text="${message_text}This utility needs one to securely update system hardware rules (udev) and background services (systemd). SteamOS restricts these actions until a password is built.\n\n"
            message_text="${message_text}💡 <b>RECOMMENDATION:</b> The most common and standard password for Steam Deck users is simply <b>deck</b>, but you can use whatever you would like—just make sure you remember it!\n\n"
            message_text="${message_text}🚀 <b>WHAT HAPPENS NEXT:</b> If you choose to proceed, you will be redirected to a standard Konsole window that runs the native Linux <b>'passwd'</b> command.\n\n"
            message_text="${message_text}🔒 <b>SECURITY NOTE:</b> This configuration utility never saves, transmits, or records your password anywhere. It stays completely local and private to your device."

            local setup_choice=$(zenity --question \
                --title="Sudo Password Required" \
                --text="$message_text" \
                --ok-label="Set up Password Now" --cancel-label="Exit Utility" \
                --height=420 --width=520)
            
            if [ $? -eq 0 ]; then
                # Friendly instructional step right before firing off the terminal context window
                zenity --info --text="A terminal window will now pop up to let you create your password.\n\nPlease type your new password twice, pressing Enter after each time.\n\n⚠️ <b>NOTE:</b> The terminal will NOT show characters or asterisks while you are typing for privacy security! Just type it out blindly and hit Enter." --width=450
                
                # Spawn an active Konsole frame running the secure native Linux passwd pipeline
                konsole --noclose -e "passwd"
                
                # Double-check state tracking loops to see if they completed it or just killed the tab
                if passwd -S deck 2>/dev/null | grep -E -q "L|NP"; then
                    zenity --error --text="Password setup was not detected. The utility will now close."
                    exit 1
                fi
            else
                exit 0
            fi
        fi
    fi
}

get_root_credentials() {
    # Run the pre-flight safety check first to protect inexperienced users
    verify_system_password_exists

    # If we are already root, skip the prompt sequence entirely
    if [ "$EUID" -ne 0 ] && [ -z "$PASS" ]; then
        if command -v zenity &> /dev/null; then
            PASS=$(zenity --password --title="Authentication Required" --text="SteamOS Dock Wake Utility needs administrator privileges to update udev rules.")
            
            if [ -z "$PASS" ]; then
                zenity --error --text="Operation cancelled. Administrator privileges are required."
                exit 1
            fi
            
            # Verify the typed credentials against the live sudo engine
            echo "$PASS" | sudo -S -v &>/dev/null
            if [ $? -ne 0 ]; then
                zenity --error --text="Incorrect password. Please run the script again."
                # Clear out the unverified variable cache to avoid stuck loop hooks
                unset PASS
                exit 1
            fi
        else
            sudo -v || exit 1
        fi
    fi
}

unlock_system() {
    get_root_credentials
    echo "$PASS" | sudo -S steamos-readonly disable &>/dev/null
}

lock_system() {
    get_root_credentials
    echo "$PASS" | sudo -S steamos-readonly enable &>/dev/null
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
    cat << 'EOF' > "$desktop_launcher"
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
    if [ ! -f "$CONFIG_FILE" ] && { [ -f "$UDEV_PATH" ] || systemctl --user is-enabled dock-wake-shield.service &>/dev/null; }; then
        fetch_repo_asset "dock_wake.conf" "$CONFIG_FILE"

        if systemctl --user is-enabled dock-wake-shield.service &>/dev/null; then
            set_config_value "user_sleep_service_installed" "true"
        fi

        if [ -f "$UDEV_PATH" ]; then
            if grep -q "#Initialized" "$UDEV_PATH"; then
                set_config_value "udev_rules_installed" "true"
                set_config_value "total_managed_hubs" "0"
            else
                set_config_value "udev_rules_installed" "true"
                local vids=($(grep -oP 'ATTRS{idVendor}=="\K[^" ]+' "$UDEV_PATH" 2>/dev/null))
                local pids=($(grep -oP 'ATTRS{idProduct}=="\K[^" ]+' "$UDEV_PATH" 2>/dev/null))
                local total_hubs=${#vids[@]}

                if [ "$total_hubs" -gt 0 ]; then
                    set_config_value "total_managed_hubs" "$total_hubs"
                    for ((i=0; i<total_hubs; i++)); do
                        if [ -n "${vids[$i]}" ] && [ -n "${pids[$i]}" ]; then
                            sed -i "/\[MANAGED_HUBS\]/a ${vids[$i]}:${pids[$i]}" "$CONFIG_FILE"
                        fi
                    done
                else
                    set_config_value "total_managed_hubs" "0"
                fi
            fi
        fi
    fi

    if [ -f "$CONFIG_FILE" ] && [ ! -f "/home/deck/Desktop/DockWakeManager.desktop" ]; then
        create_desktop_launcher
    fi
}
# ------------------------------------------------------------------------------
# 3. INTERACTIVE GUI PIPELINE (PERSISTENT APPLICATION LOOP)
# ------------------------------------------------------------------------------
show_main_menu() {
    while true; do
        run_diagnostic

        local current_delay=$(get_config_value "sleep_buffer_seconds")
        [ -z "$current_delay" ] && current_delay=10

        local is_installed=false
        if [ -f "$CONFIG_FILE" ] && [ -f "$RUNTIME_SCRIPT" ] && [ -f "$SERVICE_FILE" ]; then
            is_installed=true
        fi

        # Compute Hardware Topology and Device State Readouts
        local total_hubs=0
        local registered_hubs=0
        local hardware_report=""

        while read -r line; do
            local vid=$(echo "$line" | awk '{print $6}' | cut -d':' -f1)
            local pid=$(echo "$line" | awk '{print $6}' | cut -d':' -f2)
            local hw_id="${vid}:${pid}"
            local raw_desc=$(echo "$line" | cut -d' ' -f7-)
            
            # Cleanly truncate description strings to enforce column integrity
            local desc="${raw_desc:0:32}"
            ((total_hubs++))

            if [ "$is_installed" = true ] && [ -f "$CONFIG_FILE" ] && grep -q "$hw_id" "$CONFIG_FILE"; then
                ((registered_hubs++))
                formatted_row=$(printf "%-13s %-34s <span foreground='green'>- Registered</span>" "$hw_id" "$desc")
                hardware_report="${hardware_report}  • ${formatted_row}\n"
            else
                formatted_row=$(printf "%-13s %-34s <span foreground='orange'>- Unregistered</span>" "$hw_id" "$desc")
                hardware_report="${hardware_report}  • ${formatted_row}\n"
            fi
        done < <(lsusb | grep -i "hub" | grep -v "root hub")

        # Fallback profile string if layout survey yields nothing connected
        if [ $total_hubs -eq 0 ]; then
            hardware_report="  No external hardware docks detected via USB system path."
        fi

        # Audit immutable system-level paths to verify update damage (Three-State Evaluation)
        local udev_status="<span foreground='orange'>- missing / needs repaired</span>"
        local sudo_status="<span foreground='orange'>- missing / needs repaired</span>"
        
        [ -f "/etc/sudoers.d/dock-wake-shield" ] && sudo_status="<span foreground='green'>- installed</span>"

        if [ -f "$UDEV_PATH" ]; then
            if grep -q "#Initialized" "$UDEV_PATH"; then
                udev_status="<span foreground='yellow'>- no hubs registered yet</span>"
            else
                udev_status="<span foreground='green'>- installed</span>"
            fi
        fi

        # Dynamically calculate width alignment spacing for paths based on standard Zenity column boundaries
        local path_width=47
        local formatted_udev_path=$(printf "%-${path_width}s" "$UDEV_PATH")
        local formatted_sudo_path=$(printf "%-${path_width}s" "/etc/sudoers.d/dock-wake-shield")

        # Generate Main Interface Readout Block (Using compact Pango Markup font blocks)
        local status_text=""
        status_text="${status_text}<b>🛡️ SYSTEM STATUS PROFILE</b>\n"
        status_text="${status_text}────────────────────────────────────────────────────────────\n"
        status_text="${status_text}  • Guard Time Threshold : ${current_delay} Seconds\n"
        if [ "$is_installed" = true ]; then
            status_text="${status_text}  • Monitored Hardware   : ${registered_hubs}/${total_hubs} USB Hub Targets Registered\n"
        else
            status_text="${status_text}  • Monitored Hardware   : Core Installation Suite Missing\n"
        fi
        status_text="${status_text}────────────────────────────────────────────────────────────\n"
        
        status_text="${status_text}<b>📂 IMMUTABLE SYSTEM OVERLAYS</b>\n"
        status_text="${status_text}  • <span font_family='monospace' font_size='small' foreground='gray'>${formatted_udev_path}</span> ${udev_status}\n"
        status_text="${status_text}  • <span font_family='monospace' font_size='small' foreground='gray'>${formatted_sudo_path}</span> ${sudo_status}\n"
        status_text="${status_text}────────────────────────────────────────────────────────────\n\n"

        status_text="${status_text}<b>🔌 CONNECTED HARDWARE SURVEY</b>\n"
        status_text="${status_text}<span font_family='monospace' font_size='small'>    ID            DEVICE DESCRIPTION                 STATUS</span>\n"
        status_text="${status_text}────────────────────────────────────────────────────────────\n"
        status_text="${status_text}<span font_family='monospace' font_size='small'>${hardware_report}</span>"
        status_text="${status_text}────────────────────────────────────────────────────────────"

        # Create the Dynamic menu options
        local menu_options=()
        if [ "$is_installed" = true ]; then
            if [ "$FRESHLY_INSTALLED" = true ]; then
                menu_options+=("Update / Repair Utilities" "(*) Scan & Register Hubs" "(*) Adjust Sleep Timer" "Completely Uninstall Suite")
            else
                menu_options+=("Update / Repair Utilities" "Scan & Register Hubs" "Adjust Sleep Timer" "Completely Uninstall Suite")
            fi
        else
            menu_options+=("Install Core Utility Suite")
        fi

        CHOICE=$(zenity --list \
            --title="Steam Deck Dock Wake Manager" \
            --text="$status_text" \
            --column="Available Action Routines" "${menu_options[@]}" \
            --height=600 --width=620 \
            --ok-label="Execute" --cancel-label="Exit Application")

        # If user closes window or hits Cancel, cleanly exit the background thread
        [ $? -ne 0 ] && exit 0

        case "$CHOICE" in
            "Install Core Utility Suite" | "Update / Repair Utilities")
                execute_install
                [ "$CHOICE" = "Install Core Utility Suite" ] && export FRESHLY_INSTALLED=true
                if [ "$CHOICE" = "Update / Repair Utilities" ]; then
                    zenity --info --text="Utility suite successfully verified and repaired!" --timeout=2
                fi
                ;;
            *"Scan & Register Hubs")
                execute_hub_wizard
                ;;
            *"Adjust Sleep Timer")
                execute_timer_config
                ;;
            "Completely Uninstall Suite")
                execute_uninstall
                export FRESHLY_INSTALLED=false
                ;;
            *)
                exit 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 4. UNDERLYING EXECUTION ENGINES
# ------------------------------------------------------------------------------
execute_install() {
    if [[ "$XYZ" =~ "sleep_wake_delay" ]] || [[ "$0" =~ "sleep_wake_delay" ]]; then
        export REPO_BASE="https://raw.githubusercontent.com/boba-fatt/SteamDock_USB_Wake/sleep_wake_delay"
    fi

    fetch_repo_asset "dock_wake.conf" "$CONFIG_FILE"
    fetch_repo_asset "99_dock_wake_delay.sh" "$RUNTIME_SCRIPT"
    fetch_repo_asset "dock-wake-shield.service" "$SERVICE_FILE"

    systemctl --user daemon-reload
    systemctl --user disable dock-wake-shield.service &>/dev/null
    systemctl --user enable dock-wake-shield.service
    set_config_value "user_sleep_service_installed" "true"

    get_root_credentials
    unlock_system

    # Create the NOPASSWD privilege exception layer cleanly
    echo "$PASS" | sudo -S tee /etc/sudoers.d/dock-wake-shield > /dev/null <<'EOF'
deck ALL=(ALL) NOPASSWD: /home/deck/.config/systemd/user-sleep/99_dock_wake_delay.sh
EOF

    # Dropping the automated initialization handshake text directly into the system rules path
    echo "#Initialized" | echo "$PASS" | sudo -S tee "$UDEV_PATH" > /dev/null
    set_config_value "udev_rules_installed" "true"

    echo "$PASS" | sudo -S udevadm control --reload-rules && echo "$PASS" | sudo -S udevadm trigger
    lock_system
    create_desktop_launcher
}

execute_timer_config() {
    local current_delay=$(get_config_value "sleep_buffer_seconds")
    [ -z "$current_delay" ] && current_delay=10

    local mode_choice=$(zenity --list --radiolist \
        --title="Configure Guard Threshold" \
        --text="Select your desired configuration method:\n\n💡 <b>NOTE:</b> To completely turn off the shield protection layer, set this value to <b>0</b>." \
        --column="Select" --column="Mode" \
        TRUE "Simple Slider (Recommended)" \
        FALSE "Advanced Manual Input" \
        --height=230 --width=380 --ok-label="Next")

    [ -z "$mode_choice" ] && return

    local final_value=$current_delay

    if [[ "$mode_choice" == "Simple Slider"* ]]; then
        final_value=$(zenity --scale --title="Simple Slider Setup" \
            --text="Adjust shield guard threshold duration (0 to 30 seconds):\n\n(Set to 0 to completely disable the time-gate shield)" \
            --value="$current_delay" --min-value=0 --max-value=30 --step=1)
    else
        local manual_val=$(zenity --entry --title="Advanced Manual Input" \
            --text="Type your custom guard interval in seconds (0 to 120s):\n\n(Type 0 to completely disable the time-gate shield)" \
            --entry-text="$current_delay")

        if [[ "$manual_val" =~ ^[0-9]+$ ]]; then
            if [ "$manual_val" -gt 120 ]; then
                final_value=120
                zenity --warning --text="Value exceeded maximum cap. Automatically bound to 120 seconds." --timeout=3
            elif [ "$manual_val" -lt 0 ]; then
                final_value=0
            else
                final_value=$manual_val
            fi
        fi
    fi

    if [ -n "$final_value" ]; then
        set_config_value "sleep_buffer_seconds" "$final_value"
    fi
}

execute_hub_wizard() {
    local usb_list=()
    local raw_hubs=()
    
    usb_list+=( "FALSE" "ALL_HUBS" "[SELECT ALL DISCOVERED DOCK TARGETS]" )

    while read -r line; do
        local vid=$(echo "$line" | awk '{print $6}' | cut -d':' -f1)
        local pid=$(echo "$line" | awk '{print $6}' | cut -d':' -f2)
        local hw_id="${vid}:${pid}"
        local desc=$(echo "$line" | cut -d' ' -f7-)
        
        raw_hubs+=("$hw_id")

        local default_state="FALSE"
        if [ -f "$CONFIG_FILE" ] && grep -q "$hw_id" "$CONFIG_FILE"; then
            default_state="TRUE"
        fi

        usb_list+=( "$default_state" "$hw_id" "$desc" )
    done < <(lsusb | grep -i "hub" | grep -v "root hub")

    if [ ${#usb_list[@]} -le 3 ]; then
        zenity --error --text="No compatible external USB hubs were discovered attached to the Deck."
        return
    fi

    local chosen_hubs=$(zenity --list --checklist --title="Hardware Discovery Wizard" \
        --text="Manage system targets (Pre-registered items are already checked):" \
        --column="Monitor" --column="Hardware ID" --column="Device Description" \
        "${usb_list[@]}" --height=400 --width=540)

    if [ -n "$chosen_hubs" ]; then
        unlock_system
        echo "$PASS" | sudo -S rm -f "$UDEV_PATH"
        sed -i '/\[MANAGED_HUBS\]/q' "$CONFIG_FILE"

        local IFS='|'
        local count=0
        local udev_buffer=""
        local final_targets=()

        if [[ "$chosen_hubs" == *"ALL_HUBS"* ]]; then
            final_targets=("${raw_hubs[@]}")
        else
            for entry in $chosen_hubs; do
                [ "$entry" != "ALL_HUBS" ] && final_targets+=("$entry")
            done
        fi

        for target in "${final_targets[@]}"; do
            local vid=$(echo "$target" | cut -d':' -f1)
            local pid=$(echo "$target" | cut -d':' -f2)

            udev_buffer="${udev_buffer}SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\", ATTR{power/wakeup}=\"enabled\""$'\n'
            echo "$target" >> "$CONFIG_FILE"
            ((count++))
        done

        # Re-write the rules cleanly. If everything was un-checked, it restores the default #Initialized token state
        if [ "$count" -gt 0 ]; then
            echo "$udev_buffer" | echo "$PASS" | sudo -S tee "$UDEV_PATH" > /dev/null
        else
            echo "#Initialized" | echo "$PASS" | sudo -S tee "$UDEV_PATH" > /dev/null
        fi

        set_config_value "total_managed_hubs" "$count"
        set_config_value "udev_rules_installed" "true"

        echo "$PASS" | sudo -S udevadm control --reload-rules && echo "$PASS" | sudo -S udevadm trigger
        lock_system
        zenity --info --text="Successfully synchronized tracking matrices ($count active targets)!" --timeout=2
    fi
}

execute_uninstall() {
    unlock_system

    echo "$PASS" | sudo -S rm -f "$UDEV_PATH"
    echo "$PASS" | sudo -S udevadm control --reload-rules && echo "$PASS" | sudo -S udevadm trigger
    echo "$PASS" | sudo -S rm -f /etc/sudoers.d/dock-wake-shield

    lock_system

    systemctl --user disable dock-wake-shield.service &>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload

    rm -rf "/home/deck/.config/systemd/user-sleep/"
    rm -f "/home/deck/Desktop/DockWakeManager.desktop"

    zenity --info --text="All components cleanly purged from the system architecture." --timeout=2
}

show_main_menu
