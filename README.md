# 🛡️ SteamOS Dock Wake Utility & Delay Shield

Let's be real for a second: out of the box, you can't just slap a button on your wireless controller and wake your Steam Deck up while it's sitting across the room in its dock. 

Now, there are scripts floating around the internet that try to fix this. The problem? They use the "shotgun method." They loop through your entire `lsusb` topology and indiscriminately enable the wake attribute for *every single USB device and root hub* connected to your machine. It works... until you notice your Deck has turned into a total insomniac. Because everything is armed to wake the system, your Deck starts randomly waking up in its case, turning on in the middle of the night, or draining its battery because a background system node blinked. 

This utility is the surgical solution to that problem. 

First, it features a **Hardware Discovery Wizard** that targets *only* the specific, physical third-party desktop dock or USB-C hub you actually use, writing clean, isolated `udev` rules for just those devices. 

Second, it solves the "Charging Cradle Loop." If you've ever put your Deck to bed, set your controller down to charge, and watched in horror as the Deck instantly wakes right back up—you've met the electrical handshake high-five. The dock handles the incoming voltage spike from your charging controller, panics, and blares a phantom connect signal straight up the pipe. This utility creates a temporary "Cone of Silence" for your specific dock hubs the exact millisecond your Deck suspends, keeping them deaf for a few seconds during wake-up so all that initial electrical noise clears out harmlessly before restoring your controller's ability to wake the system normally.
> [!NOTE]
> ### Obligatory Disclaimer: 
>  *I do not work for Valve, nor am I affiliated with them in any official capacity. I am just a developer who deeply respects Lord Gaben, his massive philanthropic contributions to the world, and the glorious hardware innovations he hath gifted mankind. I just wanted my dock to work right.*

> [!WARNING]
> *I am not responsible for you or the decisions you make, so if your Deck, or ROG, or Legion Go, or Microwave, or Tesla implode or stop working properly...*
>
> ![](./assets/itysl_dk-bud.gif)

## 🚀 The One-Liner Control Panel

Whether you're installing this for the very first time, adjusting your timer, or running a repair because a major SteamOS update decided to remodel your system partition, switch to **Desktop Mode**, open up `Konsole`, and fire off this single command:

``` bash
curl -sSL https://raw.githubusercontent.com/boba-fatt/SteamDock_USB_Wake/main/manage_dock.sh -o /tmp/manage_dock.sh && chmod +x /tmp/manage_dock.sh && /tmp/manage_dock.sh
```

---

## 🛠️ The Architecture (How This Whole Thing Actually Works)

Instead of building a messy, hardcoded blob that completely derails your system, this project is split into clean, modular layers. It's built to handle specific, chaotic problems without breaking the rest of the machine.

### 1. The Front-Facing Control Panel (`manage_dock.sh`)
This is the main graphical menu dashboard. It uses native Zenity windows so you don't have to guess at terminal arguments. 
* **Adaptive Interface:** If you are a first-timer, it keeps things dead simple by only showing an "Install" option. Once installed, it expands to unlock the Hub Wizard and Timer options.
* **Brain-Fart Engine:** Look, we've all been there. You run the README one-liner command on a total lapse of memory, completely forgetting to breathe or that you already installed this months ago. The script doesn't get crossed-up, panic, crash, or double-install things. It quietly runs a background diagnostic, realizes everything is already working, reverse-engineers your active hardware rules, and smoothly auto-heals your setup without stepping on its own toes. It’ll even drop a fresh **Application Launcher** right back onto your Desktop so you can find it next time. No more asking "How do we move our bodies ever?"

### 2. The Central Configuration Layer (`dock_wake.conf`)
This is the single source of truth. It's a flat text database that holds your precise hardware profiles and preference metrics. Your background execution scripts read from this directly. That means you can change your sleep timer in the GUI, and the change takes effect instantly without modifying a single line of actual code. It stays out of the way and just holds the data.

### 3. The Pure Chaos Shield (`99_dock_wake_delay.sh`)
This is the muscle. Other scripts on the internet use a heavy-handed shotgun method—indiscriminately enabling wake attributes for every single USB node they can find. It completely ruins the system's peace. You just want your Steam Deck to lay down, be by itself, and read its art books in suspend mode. But because those generic scripts armed every single port on the board, the second a controller drops onto a charging cradle, the resulting voltage spike acts like a pack of rogue contractors running around your system as fast as they can, jumping over your couches and forcing the Deck to wake up constantly. 

To make matters worse, it messes up the handshake chain so badly that when you actually want to wake the system up normally with a peripheral, you're practically yelled at because your controller is suddenly "not part of the Turbo Team." You end up waking up the next day just to discover that the generic code effectively replaced your functional sleep cycle with a joke hole just for farts.

This script fixes that exact nightmare. The exact millisecond your Deck suspends, it applies a temporary "Cone of Silence" to your specific USB hubs. It locks the doors and keeps the ports entirely deaf for a few seconds during the wake-up phase, forcing all that chaotic electrical noise to burn itself out on the outside before letting your registered controller back into the room to handle business normally.

### 4. The Background Service (`dock-wake-shield.service`)
This is the background automation layer that keeps the entire routine running. It's a dedicated user-space `systemd` daemon tied directly to your Deck's power states. Because it registers and loads entirely inside your unprotected user home space (`/home/deck/`), **it completely survives major SteamOS system updates** without requiring you to unlock the root partition. It's stable, reliable, and completely out of sight.

---

## 📐 Customizing Your Delay Buffer

Everyone's desk layout is a little different. Some cheap hubs cycle instantly; some heavy-duty setups take a hot second to stabilize. The manager form gives you two ways to handle this on one screen:
* **The Slider:** A quick visual slider capped from 2 to 30 seconds for standard use cases.
* **Advanced Manual Mode:** Need more time? Pop the radio button over to Advanced and type in your exact threshold. It supports custom intervals up to 120 seconds (2 full minutes) for slow-cycling hardware or accessibility layouts, protected by an internal safety guard so a typo won't crash your boot pipeline like a hotdog-shaped car.
