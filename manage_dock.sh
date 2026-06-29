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
                echo "This utility needs one to securely update system hardware rules (udev) and background services (systemd)."
                echo ""
                echo "💡 <b>RECOMMENDATION:</b> The most common password for Steam Deck users is simply <b>deck</b>."
                echo ""
                echo "🚀 <b>WHAT HAPPENS NEXT:</b> A Konsole window will run the native Linux <b>'passwd'</b> command."
            )

            local setup_choice=$(zenity --question \
                --title="Sudo Password Required" \
                --text="$message_text" \
                --ok-label="Set up Password Now" --cancel-label="Exit Utility" \
                --height=420 --width=520)
            
            if [ $? -eq 0 ]; then
                zenity --info --text="A terminal window will now pop up to let you create your password.\n\nPlease type your new password twice, pressing Enter after each time.\n\n⚠️ <b>NOTE:</b> The terminal will NOT show characters while you type!" --width=450
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

    # Keep prompting until password is validated or user explicitly cancels
    while [ -z "$PASS" ]; do
        if command -v zenity &> /dev/null; then
            PASS=$(zenity --password --title="Authentication Required" --text="SteamOS Dock Wake Utility needs administrator privileges.")
            [ -z "$PASS" ] && { zenity --error --text="Operation cancelled."; exit 1; }
            
            echo "$PASS" | sudo -S -v &>/dev/null
            if [ $? -ne 0 ]; then
                zenity --error --text="Incorrect password. Please try again."
                unset PASS
            fi
        else
            sudo -v || exit 1
            PASS="cli_mode"
        fi
    done
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
    mkdir -p "$(dirname "$CONFIG_FILE")"
    [ ! -f "$CONFIG_FILE" ] && touch "$CONFIG_FILE"
    
    if grep -q "^${key}=" "$CONFIG_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
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
Exec=konsole -e bash -c "curl -sSL https://raw.githubusercontent.com/boba-fatt/SteamDock_USB_Wake/${TARGET_BRANCH:-main}/manage_dock.sh | bash"
Icon=/home/deck/.config/systemd/user-sleep/dock_wake_small.png
Terminal=false
Type=Application
Categories=Utility;
EOF
    chmod +x "$desktop_launcher"
}

execute_with_log() {
    local window_title="$1"
    local routine_function="$2"
    echo ""
    echo "=================================================================="
    echo " 🛡️  ${window_title^^} "
    echo "=================================================================="
    $routine_function
}

reload_udev_subsystem() {
    echo "🔄 Refreshing active Linux kernel hardware tracking sub-routines..."
    echo "$PASS" | sudo -S udevadm control --reload-rules && echo "$PASS" | sudo -S udevadm trigger --action=add
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
# 2. INTENSE BACKGROUND DIAGNOSTIC ENGINE (DEEP CONTENT INSPECTION)
# ------------------------------------------------------------------------------
run_diagnostic() {
    local launcher_path="/home/deck/Desktop/DockWakeManager.desktop"
    local icon_path="/home/deck/.config/systemd/user-sleep/dock_wake_small.png"
    local system_is_healthy=true
    local needs_launcher_repair=false

    # 1. STRUCTURAL ASSET INTEGITY CHECKS
    [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ] && system_is_healthy=false
    [ ! -f "$RUNTIME_SCRIPT" ] || [ ! -s "$RUNTIME_SCRIPT" ] && system_is_healthy=false
    [ ! -f "$SERVICE_FILE" ] || [ ! -s "$SERVICE_FILE" ] && system_is_healthy=false
    [ ! -f "$SUDO_ERS" ] || [ ! -s "$SUDO_ERS" ] && system_is_healthy=false
    [ ! -f "$UDEV_PATH" ] && system_is_healthy=false

    # 2. THE RULE INTEGRITY DETECTOR (Checks contents for the control rule assignment)
    if [ -f "$UDEV_PATH" ] && [ "$system_is_healthy" = true ]; then
        # If config exists, ensure every hub inside it contains the power/control rule in udev
        if grep -q "\[MANAGED_HUBS\]" "$CONFIG_FILE"; then
            while read -r entry; do
                if [[ -n "$entry" && "$entry" != "#"* ]]; then
                    local target_id=$(echo "$entry" | cut -d'|' -f1)
                    local vid=$(echo "$target_id" | cut -d':' -f1)
                    local pid=$(echo "$target_id" | cut -d':' -f2)
                    
                    if ! grep -q "idVendor}==\"$vid\"" "$UDEV_PATH" || \
                       ! grep -q "idProduct}==\"$pid\"" "$UDEV_PATH" || \
                       ! grep -q "ATTR{power/control}=\"on\"" "$UDEV_PATH"; then
                        echo "⚠️  Diagnostic Alert: Local udev rules are missing required 'power/control' optimization attributes."
                        system_is_healthy=false
                        break
                    fi
                fi
            done < <(sed -n '/\[MANAGED_HUBS\]/,$p' "$CONFIG_FILE" | tail -n +2)
        fi
    fi

    # 3. GRAPHICAL SHORTCUT INTEGRITY DIAGNOSTIC
    if [ ! -f "$launcher_path" ] || [ ! -f "$icon_path" ] || ! grep -q "konsole -e" "$launcher_path"; then
        needs_launcher_repair=true
    fi

    if [ "$needs_launcher_repair" = true ]; then
        mkdir -p "/home/deck/.config/systemd/user-sleep"
        curl -sSL "${REPO_BASE}/assets/dock_wake_small.png" -o "$icon_path" &>/dev/null
        create_desktop_launcher
    fi

    # Return health valuation evaluation parameter
    if [ "$system_is_healthy" = true ]; then
        return 0
    else
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 3. INTERACTIVE GUI PIPELINE (PERSISTENT APPLICATION LOOP)
# ------------------------------------------------------------------------------
show_main_menu() {
    # Run the expensive validation diagnostic EXACTLY ONCE on launch initialization
    local initial_health="PASS"
    if ! run_diagnostic; then
        initial_health="FAIL"
    fi

    while true; do
        local current_delay=$(get_config_value "sleep_buffer_seconds")
        [ -z "$current_delay" ] && current_delay=10

        # Evaluate installation purely based on file presence, NOT health
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

        local udev_status="<span foreground='orange'>- missing / out of date</span>"
        local sudo_status="<span foreground='orange'>- missing / out of date</span>"
        [ -f "$SUDO_ERS" ] && sudo_status="<span foreground='green'>- installed</span>"

        if [ -f "$UDEV_PATH" ] && [ "$initial_health" = "PASS" ]; then
            if grep -q "#Initialized" "$UDEV_PATH"; then
                udev_status="<span foreground='yellow'>- no hubs registered yet</span>"
            else
                udev_status="<span foreground='green'>- installed and optimized</span>"
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
                echo "  • Monitored Hardware   : Core Suite Out of Sync / Update Required"
            fi
            echo "────────────────────────────────────────────────────────────"
            echo "<b>📂 IMMUTABLE SYSTEM OVERLAYS</b>"
            echo "  • <span font_family='monospace' font_size='small' foreground='gray'>${formatted_udev_path}</span> ${udev_status}"
            echo "  • <span font_family='monospace' font_size='small' foreground='gray'>${formatted_sudo_path}</span> ${sudo_status}"
            echo "────────────────────────────────────────────────────────────"
            echo "<b>🔌 ECOSYSTEM HARDWARE MONITOR</b>"
            echo "<span font_family='monospace' font_size='small'>     ID             DEVICE DESCRIPTION                 STATUS</span>"
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

        CHOICE=$(zenity --list \
            --title="Steam Deck Dock Wake Manager" \
            --text="$status_text" \
            --column="Available Action Routines" "${menu_options[@]}" \
            --height=740 --width=650 \
            --ok-label="Execute" --cancel-label="Exit Application")

        [ $? -ne 0 ] && exit 0

        case "$CHOICE" in
            "Install Core Utility Suite" | "Update / Repair Utilities")
                execute_with_log "Core Suite Maintenance Engine" run_maintenance_routine
                initial_health="PASS" # Reset flag back to pass following repair executions
                [ "$CHOICE" = "Install Core Utility Suite" ] && export FRESHLY_INSTALLED=true
                ;;
            *"Scan & Register Hubs")
                execute_hub_wizard
                initial_health="PASS"
                ;;
            *"Adjust Sleep Timer")
                execute_timer_config
                ;;
            "Completely Uninstall Suite")
                execute_with_log "Core Suite Uninstallation Engine" run_uninstall_routine
                export FRESHLY_INSTALLED=false
                initial_health="FAIL"
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
run_maintenance_routine() {
    if [[ "$XYZ" =~ "sleep_wake_delay" ]] || [[ "$0" =~ "sleep_wake_delay" ]]; then
        export REPO_BASE="https://raw.githubusercontent.com/boba-fatt/SteamDock_USB_Wake/sleep_wake_delay"
    fi

    echo "=================================================================="
    echo " 🛡️  SYSTEM REPAIR & MAINTENANCE ENGINE "
    echo "=================================================================="
    
    local preserved_hubs=()
    local preserved_delay="10"

    # 1. EVALUATE APP DATABASE & PRESERVE BASES
    if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then
        echo "💾 Config file discovered and intact. Backing up active profiles..."
        preserved_delay=$(get_config_value "sleep_buffer_seconds")
        [ -z "$preserved_delay" ] && preserved_delay=10

        while read -r entry; do
            if [[ -n "$entry" && "$entry" != "#"* ]]; then
                preserved_hubs+=("$entry")
            fi
        done < <(sed -n '/\[MANAGED_HUBS\]/,$p' "$CONFIG_FILE" | tail -n +2)
        echo "   -> Successfully cached ${#preserved_hubs[@]} registered targets."
    else
        echo "⚠️ Config file is missing or empty! Re-fetching default template..."
        fetch_repo_asset "dock_wake.conf" "$CONFIG_FILE"
    fi

    # 2. RE-FETCH CORE SCRIPTS & TEMPLATES ALWAYS DURING MAINTENANCE
    echo "🔍 Syncing static repository assets and local files..."
    fetch_repo_asset "99_dock_wake_delay.sh" "$RUNTIME_SCRIPT"
    fetch_repo_asset "dock-wake-shield.service" "$SERVICE_FILE"

    local icon_path="/home/deck/.config/systemd/user-sleep/dock_wake_small.png"
    mkdir -p "/home/deck/.config/systemd/user-sleep"
    curl -sSL "${REPO_BASE}/assets/dock_wake_small.png" -o "$icon_path" &>/dev/null

    echo "⚙️ Re-aligning user-space systemd automation profiles..."
    systemctl --user daemon-reload
    systemctl --user disable dock-wake-shield.service &>/dev/null
    systemctl --user enable dock-wake-shield.service

    echo "🔒 Escalating system administration privilege tokens..."
    unlock_system

    echo "📝 Re-compiling administrative NOPASSWD bypass rules..."
    echo "$PASS" | sudo -S tee "$SUDO_ERS" > /dev/null <<'EOF'
deck ALL=(ALL) NOPASSWD: /home/deck/.config/systemd/user-sleep/99_dock_wake_delay.sh
EOF

    echo "🛠️ Re-synthesizing optimized hardware udev configurations..."
    local udev_buffer=""
    local count=0

    if [ "${#preserved_hubs[@]}" -gt 0 ]; then
        for target_line in "${preserved_hubs[@]}"; do
            local target_id=$(echo "$target_line" | cut -d'|' -f1)
            local vid=$(echo "$target_id" | cut -d':' -f1)
            local pid=$(echo "$target_id" | cut -d':' -f2)

            if [ -n "$vid" ] && [ -n "$pid" ]; then
                # Optimized line writing including BOTH wakeup and control attributes
                udev_buffer="${udev_buffer}SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\", ATTR{power/wakeup}=\"enabled\", ATTR{power/control}=\"on\""$'\n'
                ((count++))
            fi
        done
    fi

    if [ "$count" -gt 0 ]; then
        echo "$PASS" | sudo -S sh -c 'printf "%s\n" "$1" > "$2"' _ "$udev_buffer" "$UDEV_PATH"
        echo "   -> Restored $count hardware rules cleanly back to kernel tables."
    else
        echo "$PASS" | sudo -S sh -c 'printf "%s\n" "$1" > "$2"' _ '#Initialized' "$UDEV_PATH"
    fi

    echo "🔄 Re-synchronizing configuration application metadata tables..."
    sed -i '/\[MANAGED_HUBS\]/q' "$CONFIG_FILE"
    set_config_value "sleep_buffer_seconds" "$preserved_delay"
    set_config_value "total_managed_hubs" "$count"
    set_config_value "udev_rules_installed" "true"
    set_config_value "user_sleep_service_installed" "true"

    for verified_entry in "${preserved_hubs[@]}"; do
        echo "$verified_entry" >> "$CONFIG_FILE"
    done

    echo "🔄 Purging kernel hardware memory caching profiles..."
    reload_udev_subsystem
    lock_system
    
    echo "🚀 Re-linking desktop environment application shortcuts..."
    create_desktop_launcher
    echo -e "\n✅ System maintenance successfully completed and healed!"

    local installer_desktop="/home/deck/Desktop/Install_Dock_Wake_Manager.desktop"
    [ -f "$installer_desktop" ] && rm -f "$installer_desktop"
}

run_uninstall_routine() {
    echo "=================================================================="
    echo " 🛡️  CORE SUITE UNINSTALLATION ENGINE "
    echo "=================================================================="
    echo "🔒 Requesting system administration authorization tokens..."
    unlock_system

    echo "🗑️ Scrubbing hardware udev configuration rule targets..."
    echo "$PASS" | sudo -S rm -f "$UDEV_PATH"

    echo "🔄 Purging kernel hardware memory caching profiles..."
    reload_udev_subsystem

    echo "🗑️ Dropping sudoers privilege exception layers..."
    echo "$PASS" | sudo -S rm -f "$SUDO_ERS"

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

    get_root_credentials

    local chosen_hubs=$(zenity --list --checklist --title="Hardware Discovery Wizard" \
        --text="Manage system targets (Pre-registered items are already checked):\n\n🖥️ Monitor the background terminal to view sync operations live!" \
        --column="Monitor" --column="Hardware ID" --column="Device Description" \
        "${usb_list[@]}" --height=400 --width=540)

    if [ $? -eq 0 ]; then
        echo ""
        echo "=================================================================="
        echo " 🔌 SYNCING HARDWARE TRACKING MATRICES..."
        echo "=================================================================="
        
        unlock_system
        
        local final_targets=()
        if [[ "$chosen_hubs" == *"ALL_HUBS"* ]]; then
            final_targets=("${raw_hubs[@]}")
        else
            local OIFS="$IFS"
            IFS='|'
            for entry in $chosen_hubs; do
                if [[ -n "$entry" && "$entry" != "ALL_HUBS" ]]; then
                    final_targets+=("$entry")
                fi
            done
            ifs="$OIFS"
        fi

        local -A selected_map
        for t in "${final_targets[@]}"; do
            selected_map["$t"]=1
        done

        echo "🔍 Auditing profile modifications..."
        if [ -f "$CONFIG_FILE" ]; then
            while read -r entry; do
                if [[ -n "$entry" && "$entry" != "#"* ]]; then
                    local old_id=$(echo "$entry" | cut -d'|' -f1)
                    local old_desc=$(echo "$entry" | cut -d'|' -f2)
                    if [ -z "${selected_map[$old_id]}" ]; then
                        echo "❌ PURGED: ${old_id} (${old_desc})"
                    fi
                fi
            done < <(sed -n '/\[MANAGED_HUBS\]/,$p' "$CONFIG_FILE" | tail -n +2)
        fi

        echo "$PASS" | sudo -S rm -f "$UDEV_PATH" &>/dev/null
        sed -i '/\[MANAGED_HUBS\]/q' "$CONFIG_FILE"

        local count=0
        local udev_buffer=""

        for target in "${final_targets[@]}"; do
            local vid=$(echo "$target" | cut -d':' -f1)
            local pid=$(echo "$target" | cut -d':' -f2)
            local metadata="${label_map[$target]}"

            udev_buffer="${udev_buffer}SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\", ATTR{power/wakeup}=\"enabled\", ATTR{power/control}=\"on\""$'\n'
            echo "${target}|${metadata}" >> "$CONFIG_FILE"
            echo "Base Core Active Target ->: ${target} (${metadata})"
            ((count++))
        done

        if [ "$count" -gt 0 ]; then
            echo "$PASS" | sudo -S sh -c 'printf "%s\n" "$1" > "$2"' _ "$udev_buffer" "$UDEV_PATH"
        else
            echo "⚠️  All targets unselected. Rules file reset to factory defaults."
            echo "$PASS" | sudo -S sh -c 'printf "%s\n" "$1" > "$2"' _ '#Initialized' "$UDEV_PATH"
        fi

        set_config_value "total_managed_hubs" "$count"
        set_config_value "udev_rules_installed" "true"

        reload_udev_subsystem
        lock_system
        
        echo "──────────────────────────────────────────────────────────────────"
        echo " Matrix synchronization successfully locked ($count active targets)!"
        echo "=================================================================="
        echo ""
        
        zenity --info --text="Successfully synchronized tracking matrices ($count active targets)!" --timeout=2
    else
        echo "⚠️ Sync routine aborted by user choice."
    fi
}

show_main_menu
