#!/usr/bin/env bash

# Path to our custom udev rule
RULE_PATH="/etc/udev/rules.d/99-dock-hub-wake.rules"

# ANSI Escape Codes for Colors
GREEN='\033[1;36m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo "===================================================="
echo "         STEAM DECK DOCK WAKEUP MANAGER             "
echo "===================================================="
echo ""

# 1. System Status
echo "🔍 System Status:"
if [ -f "$RULE_PATH" ]; then
    echo -e "   [ FOUND ] Existing rule file found at: $RULE_PATH"
else
    echo "   [ EMPTY ] No custom dock wakeup rules are currently active."
fi
echo ""

# 2. Scan for physical hubs, excluding Linux Foundation (1d6b)
hub_devices=$(lsusb | grep -i "hub" | grep -v "1d6b:")

if [ -z "$hub_devices" ]; then
    echo "❌ No third-party USB hubs detected."
    echo "   Make sure your external dock is securely plugged into the Deck."
    echo ""
fi

# Trackers to see if any new/unmapped hubs exist
total_hubs=0
already_in_udev_count=0

# 3. Display the discovered hubs and check them against the existing udev file
if [ -n "$hub_devices" ]; then
    echo "✨ Currently Found External Hubs:"
    echo "----------------------------------------------------"

    while read -r line; do
        ((total_hubs++))
        id_pair=$(echo "$line" | awk '{print $6}')
        vid=$(echo "$id_pair" | cut -d':' -f1)
        pid=$(echo "$id_pair" | cut -d':' -f2)
        desc=$(echo "$line" | cut -d' ' -f7-)

        # BULLETPROOF MATCH: Just look for both the specific Vendor and Product hex strings on one line
        if [ -f "$RULE_PATH" ] && grep -i "idVendor.*$vid" "$RULE_PATH" | grep -qi "idProduct.*$pid"; then
            echo -e "   📍 ID [ $id_pair ] -> $desc\t${YELLOW}- in existing udev script${RESET}"
            ((already_in_udev_count++))
        else
            echo "   📍 ID [ $id_pair ] -> $desc"
        fi
    done <<< "$hub_devices"

    echo "----------------------------------------------------"
    echo ""
fi

# Helper function to generate udev lines from the scanned hubs
generate_udev_content() {
    echo "$hub_devices" | while read -r line; do
        id_pair=$(echo "$line" | awk '{print $6}')
        vid=$(echo "$id_pair" | cut -d':' -f1)
        pid=$(echo "$id_pair" | cut -d':' -f2)
        desc=$(echo "$line" | cut -d' ' -f7-)

        echo "# $desc"
        echo "SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\", ATTR{power/wakeup}=\"enabled\""
    done
}

# Helper function to safely reload udev engine
reload_udev() {
    echo "⏳ Reloading system udev engine..."
    sudo udevadm control --reload-rules && sudo udevadm trigger
    echo "✅ Done!"
}

# 4. Dynamically Build Interactive Menu Options
options=()
if [ -n "$hub_devices" ]; then
    if [ -f "$RULE_PATH" ]; then
        options+=("Wipe old rules and write ONLY newly found hubs")

        # Only show Append option if there's actually a connected hub missing from the file
        if [ "$already_in_udev_count" -lt "$total_hubs" ]; then
            options+=("Append (Add) newly found hubs to the existing rules")
        fi
    else
        options+=("Create new udev rule for found hubs")
    fi
fi

if [ -f "$RULE_PATH" ]; then
    options+=("Remove existing udev rule completely")
fi
options+=("Exit")

# 5. The Dynamic Menu Engine
while true; do
    echo "Select an action:"
    echo "--------------------------------"

    for i in "${!options[@]}"; do
        printf "  %b) %s\n" "${GREEN}$((i+1))${RESET}" "${options[$i]}"
    done

    echo ""
    printf "Type a number %b " "${BLUE}#?${RESET}"
    read -r choice
    echo ""

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        opt="${options[$((choice-1))]}"
        break
    else
        echo "❌ Invalid choice. Please enter a number between 1 and ${#options[@]}."
        echo ""
    fi
done

# 6. Choose your destructor...
case "$opt" in
    "Create new udev rule for found hubs" | "Wipe old rules and write ONLY newly found hubs")
        echo "Writing new rules..."
        generate_udev_content | sudo tee "$RULE_PATH" > /dev/null
        echo "📝 Updated: $RULE_PATH"
        reload_udev
        ;;

    "Append (Add) newly found hubs to the existing rules")
        echo "Appending new entries..."
        echo "" | sudo tee -a "$RULE_PATH" > /dev/null
        echo "# Added via management script on $(date)" | sudo tee -a "$RULE_PATH" > /dev/null

        echo "$hub_devices" | while read -r line; do
            id_pair=$(echo "$line" | awk '{print $6}')
            vid=$(echo "$id_pair" | cut -d':' -f1)
            pid=$(echo "$id_pair" | cut -d':' -f2)
            desc=$(echo "$line" | cut -d' ' -f7-)

            # Double check to prevent appending duplicate entries (fixed missing '=')
            if ! (grep -i "idVendor.*$vid" "$RULE_PATH" | grep -qi "idProduct.*$pid"); then
                echo "# $desc" | sudo tee -a "$RULE_PATH" > /dev/null
                echo "SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\", ATTR{power/wakeup}=\"enabled\"" | sudo tee -a "$RULE_PATH" > /dev/null
            fi
        done

        echo "📝 Appended entries to: $RULE_PATH"
        reload_udev
        ;;

    "Remove existing udev rule completely")
        echo "🗑️ Removing $RULE_PATH..."
        sudo rm -f "$RULE_PATH"
        reload_udev
        ;;

    "Exit")
        echo "Exiting."
        ;;
esac
