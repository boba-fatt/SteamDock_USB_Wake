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
export SUDO_ERS="/etc/sudoers.d/dock-wake-shield"

# Mute standard library font warning chatter
zenity() {
    command zenity "$@" 2>/dev/null
}

# ------------------------------------------------------------------------------
# 1. STANDARDIZED REUSABLE HELPER FUNCTIONS
# ------------------------------------------------------------------------------

verify_system_password_exists() {
    if ! echo "testing_privileges" | sudo -S -v &>/dev/null; then
        if passwd -S deck 2>/dev/null | grep -E -q "L|NP"; then
            
            local message_text=$(
                echo "<b>⚠️ Administrator Password Required</b>"
                echo ""
                echo "It looks like you haven't set up a system password for your Steam Deck yet!"
                echo ""
                echo "This utility needs one to securely update system hardware rules (udev) and background services (systemd). SteamOS restricts these actions until a password is built."
                echo ""
                echo "💡 <b>RECOMMENDATION:</b> The most common and standard password for Steam Deck users is simply <b>deck</b>, but you can use whatever you would like—just make sure you remember it!"
                echo ""
                echo "🚀 <b>WHAT HAPPENS NEXT:</b> If you choose to proceed, you will be redirected to a standard Konsole window that runs the native Linux <b>'passwd'</b> command."
                echo ""
                echo "🔒 <b>SECURITY NOTE:</b> This configuration utility never saves, transmits, or records your password anywhere. It stays completely local and private to your device."
            )

            local setup_choice=$(zenity --question \
                --title="Sudo Password Required" \
                --text="$message_text" \
                --ok-label="Set up Password Now" --cancel-label="Exit Utility" \
                --height=420 --width=520)
            
            if [ $? -eq 0 ]; then
                zenity --info --text="A terminal window will now pop up to let you create your password.\n\nPlease type your new password twice, pressing Enter after each time.\n\n⚠️ <b>NOTE:</b> The terminal will NOT show characters or asterisks while you are typing for privacy security! Just type it out blindly and hit Enter." --width=450
                konsole --noclose -e "passwd"
                
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
    verify_system_password_exists

    if [ "$EUID" -ne 0 ] && [ -z "$PASS" ]; then
        if command -v zenity &> /dev/null; then
            PASS=$(zenity --password --title="Authentication Required" --text="SteamOS Dock Wake Utility needs administrator privileges.")
            
            if [ -z "$PASS" ]; then
                zenity --error --text="Operation cancelled. Administrator privileges are required."
                exit 1
            fi
            
            echo "$PASS" | sudo -S -v &>/dev/null
            if [ $? -ne 0 ]; then
                zenity --error --text="Incorrect password. Please run the script again."
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

execute_with_log() {
    local window_title="$1"
    local routine_function="$2"

    # 1. Secure root credentials on the surface loop first
    get_root_credentials

    # 2. Run the routine function cleanly in the primary shell context
    # This captures all standard output into a temporary variable log 
    local log_output
    log_output=$($routine_function 2>&1)

    # 3. Present the compiled log inside your custom monospace display box
    echo "$log_output" | zenity --text-info \
        --title="$window_title" \
        --width=520 --height=300 \
        --font_family="monospace" \
        --auto-scroll
}

reload_udev_subsystem() {
    echo "🔄 Refreshing active Linux kernel hardware tracking sub-routines..."
    echo "$PASS" | sudo -S udevadm control --reload-rules && echo "$PASS" | sudo -S udevadm trigger
}

query_live_hardware() {
    while read -r line; do
        local vid=$(echo "$line" | awk '{print $6}' | cut -d':' -f1)
        local pid=$(echo "$line" | awk '{print $6}' | cut -d':' -f2)
        local raw_desc=$(echo "$line" | cut -d' ' -f7-)
        local desc="${raw_desc:0:32}"
        echo "${vid}:${pid}|${desc}"
    done < <(lsusb | grep -i "hub" | grep -v "root hub")
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

        local local_total=0
        local local_registered=0
        local global_total=0
        local hardware_report=""

        local -A registered_hubs_map
        if [ -f "$CONFIG_FILE" ]; then
            while read -r entry; do
                if [[ -n "$entry" && "$entry" != "#"* ]]; then
                    local reg_id=$(echo "$entry" | cut -d'|' -f1)
                    local reg_desc=$(echo "$entry" | cut -d'|' -f2)
                    registered_hubs_map["$reg_id"]="$reg_desc"
                    ((global_total++))
                fi
            done < <(sed -n '/\[MANAGED_HUBS\]/,$p' "$CONFIG_FILE" | tail -n +2)
        fi

        hardware_report="${hardware_report}<span font_family='monospace' font_size='small'>⚡ LOCAL ACTIVE PLUGS</span>\n"
        while read -r live_hub; do
            [ -z "$live_hub" ] && continue
            local current_id=$(echo "$live_hub" | cut -d'|' -f1)
            local current_desc=$(echo "$live_hub" | cut -d'|' -f2)
            ((local_total++))

            local formatted_row=""
            if [ "$is_installed" = true ] && [ -n "${registered_hubs_map[$current_id]}" ]; then
                ((local_registered++))
                unset registered_hubs_map["$current_id"]
                formatted_row=$(printf "%-13s %-34s <span foreground='green'>- Active</span>" "$current_id" "$current_desc")
                hardware_report="${hardware_report}   • ${formatted_row}\n"
            else
                formatted_row=$(printf "%-13s %-34s <span foreground='orange'>- Unregistered</span>" "$current_id" "$current_desc")
                hardware_report="${hardware_report}   • ${formatted_row}\n"
            fi
        done < <(query_live_hardware)

        if [ $local_total -eq 0 ]; then
            hardware_report="${hardware_report}     No active external USB hubs plugged in.\n"
        fi

        hardware_report="${hardware_report}\n<span font_family='monospace' font_size='small'>🌐 ROAMING GLOBAL REGISTRY</span>\n"
        local offline_count=0
        for offline_id in "${!registered_hubs_map[@]}"; do
            local offline_desc="${registered_hubs_map[$offline_id]}"
            local formatted_row=$(printf "%-13s %-34s <span foreground='blue'>- Disconnected</span>" "$offline_id" "$offline_desc")
            hardware_report="${hardware_report}   • <span foreground='gray'>${formatted_row}</span>\n"
            ((offline_count++))
        done

        if [ $offline_count -eq 0 ] && [ $global_total -eq 0 ]; then
            hardware_report="${hardware_report}     No roaming profiles built into global registry database yet."
        elif [ $offline_count -eq 0 ]; then
            hardware_report="${hardware_report}     All registered global targets are currently online."
        fi

        local udev_status="<span foreground='orange'>- missing / needs repaired</span>"
        local sudo_status="<span foreground='orange'>- missing / needs repaired</span>"
        [ -f "$SUDO_ERS" ] && sudo_status="<span foreground='green'>- installed</span>"

        if [ -f "$UDEV_PATH" ]; then
            if grep -q "#Initialized" "$UDEV_PATH"; then
                udev_status="<span foreground='yellow'>- no hubs registered yet</span>"
            else
                udev_status="<span foreground='green'>- installed</span>"
            fi
        fi

        local path_width=47
        local formatted_udev_path=$(printf "%-${path_width}s" "$UDEV_PATH")
        local formatted_sudo_path=$(printf "%-${path_width}s" "$SUDO_ERS")

        status_text=$(
            echo "<b>🛡️ SYSTEM STATUS PROFILE</b>"
            echo "────────────────────────────────────────────────────────────"
            echo "  • Guard Time Threshold : ${current_delay} Seconds"
            if [ "$is_installed" = true ]; then
                echo "  • Connected Hub Metrics: ${local_registered}/${local_total} Online Targets Guarded"
                echo "  • Roaming Mesh Capacity: ${local_registered}/${global_total} Active Ecosystem Footprint"
            else
                echo "  • Monitored Hardware   : Core Installation Suite Missing"
            fi
            echo "────────────────────────────────────────────────────────────"
            
            echo "<b>📂 IMMUTABLE SYSTEM OVERLAYS</b>"
            echo "  • <span font_family='monospace' font_size='small' foreground='gray'>${formatted_udev_path}</span> ${udev_status}"
            echo "  • <span font_family='monospace' font_size='small' foreground='gray'>${formatted_sudo_path}</span> ${sudo_status}"
            echo "────────────────────────────────────────────────────────────"
            echo "<b>🔌 ECOSYSTEM HARDWARE MONITOR</b>"
            echo "<span font_family='monospace' font_size='small'>    ID            DEVICE DESCRIPTION                 STATUS</span>"
            echo "────────────────────────────────────────────────────────────"
            echo "<span font_family='monospace' font_size='small'>${hardware_report%\n}</span>"
            echo "────────────────────────────────────────────────────────────"
        )
        
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

        # FIX C: Split window initialization patterns so the main window stays anchored in background spaces
        CHOICE=$(zenity --list \
            --title="Steam Deck Dock Wake Manager" \
            --text="$status_text" \
            --column="Available Action Routines" "${menu_options[@]}" \
            --height=740 --width=650 \
            --ok-label="Execute" --cancel-label="Exit Application")

        [ $? -ne 0 ] && exit 0

        case "$CHOICE" in
            "Install Core Utility Suite" | "Update / Repair Utilities")
                execute_with_log "Core Suite Setup Engine" run_install_routine
                [ "$CHOICE" = "Install Core Utility Suite" ] && export FRESHLY_INSTALLED=true
                ;;
            *"Scan & Register Hubs")
                execute_hub_wizard
                ;;
            *"Adjust Sleep Timer")
                execute_timer_config
                ;;
            "Completely Uninstall Suite")
                execute_with_log "Core Suite Uninstallation Engine" run_uninstall_routine
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
run_install_routine() {
    if [[ "$XYZ" =~ "sleep_wake_delay" ]] || [[ "$0" =~ "sleep_wake_delay" ]]; then
        export REPO_BASE="https://raw.githubusercontent.com/boba-fatt/SteamDock_USB_Wake/sleep_wake_delay"
    fi

    echo "📥 Fetching structural application databases from repository..."
    fetch_repo_asset "dock_wake.conf" "$CONFIG_FILE"
    fetch_repo_asset "99_dock_wake_delay.sh" "$RUNTIME_SCRIPT"
    fetch_repo_asset "dock-wake-shield.service" "$SERVICE_FILE"
    
    echo "⚙️ Registering user-space systemd automation profiles..."
    systemctl --user daemon-reload
    systemctl --user disable dock-wake-shield.service &>/dev/null
    systemctl --user enable dock-wake-shield.service
    set_config_value "user_sleep_service_installed" "true"

    echo "🔒 Elevating core security access parameters..."
    unlock_system

    echo "📝 Compiling administrative NOPASSWD bypass exceptions..."
    echo "$PASS" | sudo -S tee "$SUDO_ERS" > /dev/null <<'EOF'
deck ALL=(ALL) NOPASSWD: /home/deck/.config/systemd/user-sleep/99_dock_wake_delay.sh
EOF

    echo "🛠️ Synthesizing clean time-gate hardware structural configurations..."
    sudo -S tee "$UDEV_PATH" > /dev/null <<< "$PASS" << 'EOF'
#Initialized
EOF
    set_config_value "udev_rules_installed" "true"

    echo "🔄 Refreshing active Linux kernel hardware tracking sub-routines..."
    reload_udev_subsystem
    lock_system
    
    echo "🚀 Generating application desktop environment shortcuts..."
    create_desktop_launcher

    local installer_desktop="/home/deck/Desktop/Install_Dock_Wake_Manager.desktop"
    if [ -f "$installer_desktop" ]; then
        echo "🧹 Discovered active setup shortcut on Desktop. Cleaning up installer artifacts..."
        rm -f "$installer_desktop"
    fi    
    echo -e "\n✅ Installation routine successfully completed!"
}

run_uninstall_routine() {
    echo "🔒 Requesting system administration authorization tokens..."
    unlock_system

    echo "🗑️ Scrubbing hardware udev configuration rule targets..."
    echo "$PASS" | sudo -S rm -f "$UDEV_PATH"

    echo "🔄 Purging kernel hardware memory caching profiles..."
    reload_udev_subsystem

    echo "🗑️ Dropping sudoers privilege exception layers..."
    # FIX: Explicit path target ensures the file is vaporized regardless of subshell environment scope
    echo "$PASS" | sudo -S rm -f "/etc/sudoers.d/dock-wake-shield"

    lock_system

    echo "⚙️ De-registering automated background systemd services..."
    systemctl --user disable dock-wake-shield.service &>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload

    echo "🧹 Obliterating configuration folders and local tracking databases..."
    rm -rf "/home/deck/.config/systemd/user-sleep/"
    rm -f "/home/deck/Desktop/DockWakeManager.desktop"
    
    echo -e "\n✅ System environment cleanly restored to factory state!"
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
    local -A label_map
    
    usb_list+=( "FALSE" "ALL_HUBS" "[SELECT ALL DISCOVERED DOCK TARGETS]" )

    while read -r live_hub; do
        [ -z "$live_hub" ] && continue
        local hw_id=$(echo "$live_hub" | cut -d'|' -f1)
        local desc=$(echo "$live_hub" | cut -d'|' -f2)
        
        raw_hubs+=("$hw_id")
        label_map["$hw_id"]="$desc"

        local default_state="FALSE"
        if [ -f "$CONFIG_FILE" ] && grep -q "$hw_id" "$CONFIG_FILE"; then
            default_state="TRUE"
        fi

        usb_list+=( "$default_state" "$hw_id" "$desc" )
    done < <(query_live_hardware)

    if [ ${#usb_list[@]} -le 3 ]; then
        zenity --error --text="No compatible external USB hubs were discovered attached to the Deck."
        return
    fi

    # Fix: Get authentication context in parent thread before spawning the wizard modal box
    get_root_credentials

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
            local metadata="${label_map[$target]}"

            udev_buffer="${udev_buffer}SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\", ATTR{power/wakeup}=\"enabled\""$'\n'
            echo "${target}|${metadata}" >> "$CONFIG_FILE"
            ((count++))
        done

        if [ "$count" -gt 0 ]; then
            echo "$udev_buffer" | echo "$PASS" | sudo -S tee "$UDEV_PATH" > /dev/null
        else
            sudo -S tee "$UDEV_PATH" > /dev/null <<< "$PASS" << 'EOF'
#Initialized
EOF
        fi

        set_config_value "total_managed_hubs" "$count"
        set_config_value "udev_rules_installed" "true"

        reload_udev_subsystem
        lock_system
        zenity --info --text="Successfully synchronized tracking matrices ($count active targets)!" --timeout=2
    fi
}

show_main_menu
