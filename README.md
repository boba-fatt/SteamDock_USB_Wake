# SteamOS Dock Wake Manager

A minimal Bash utility for SteamOS to safely enable USB wake-on-suspend for external docks and third-party hubs. 

By default, blanket scripts that enable wakeup states on the Steam Deck's root hubs (`usb1` through `usb4`) trigger immediate wake-up loops due to power-state handshake chatter from internal hardware (like the built-in controller, Bluetooth radio, or Type-C Billboard device).

This script dynamically scans connected USB topologies, isolates third-party vendor hub chips (e.g., VIA Labs, Realtek, Genesys Logic), and generates precise, targeted `udev` rules to allow wake events *only* via external dock ports.

## Features
* **Automated Device Mapping:** Filters out internal Linux Foundation Virtual Root Hubs and isolates external dock bridges.
* **State Verification:** Reads active configurations in real-time, matching explicit hardware ID pairs to prevent duplicate rule compilation.
* **Dynamic Menu Engine:** Automatically handles environment changes, offering context-dependent actions (Create, Wipe/Overwrite, Append, or Purge) based on current hardware scans and file states.
* **Persistent Configuration:** Writes native rules directly to `/etc/udev/rules.d/`, surviving standard SteamOS system updates.

## Layout Overview
The script targets external interface bridges while explicitly avoiding internal hardware lines:

(As found with Steam Deck and Steam Deck Dock)
* **Bus 001/002:** External USB configurations (Dock hubs, external peripherals).
* **Bus 003/004:** Internal hardware layers (Steam Deck integrated controls, display/power subsystems).

## Usage 
  This has to be done in Desktop Mode.  You will need to have your root password already set up in order to create/update/remove the udev script.
  
1. Clone or download the script to your local environment.
2. Mark the script as executable:
   ```
   chmod +x deck_usb_wake_udev_make.sh
   ```
3. Run the script from the terminal:
   ```
   ./deck_usb_wake_udev_make.sh
   ```

## Execution States:

Create/Wipe: Compiles a fresh slate targeting only currently attached physical hubs.

Append: Detects if a new or secondary dock is introduced and appends unmatched entries without modifying existing configurations.

Remove: Completely purges custom rules and commands a live reload of the kernel's udevadm trigger to return the system to stock power-management behavior instantly.
