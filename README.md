# Coffee

A tiny macOS menu bar app that keeps your Mac awake. It holds its own power assertion (no `caffeinate` process), and quitting the app releases it.

## Install

Requires macOS 12+ and the Xcode command line tools (`xcode-select --install`).

```sh
./build.sh
```

This builds a universal app into `~/Applications/Coffee.app` and launches it. Run it again after changing the code; it restarts the app.

## Use

A coffee cup icon appears in the menu bar. An outlined cup means off; a filled, steaming cup means the Mac is being kept awake. A small clock on the cup means the schedule is what's keeping it on.

- **Left-click** opens a small menu right under the icon: **Turn Off** when on; when off, **Turn On** (until you turn it off) and **Turn On Schedule** (if the schedule is off or skipped today). Click anywhere else to cancel.
- **Right-click** (or Ctrl-click) opens the menu:
  - **On Indefinitely**, or on for **30 min / 1 / 2 / 4 hours**
  - **Keep Display On**: also stops the screen from sleeping (remembered between launches)
  - **Stay Awake With Lid Closed**: while Coffee is on, closing the lid doesn't sleep the Mac (remembered between launches). This needs a one-time setup, `./setup-lid.sh`, which lets Coffee run `pmset -a disablesleep` without a password; to undo it, turn the option off (or quit Coffee), then run `sudo rm /etc/sudoers.d/coffee`. If the setup is missing, Coffee beeps, shows a note and unchecks the option. It turns the setting back off when Coffee turns off or quits, and leaves alone a `disablesleep` you set yourself. The setting survives restarts, so if Coffee crashes or is force-quit while on, the Mac won't sleep on lid close until Coffee is launched again (it cleans up then) or you run `sudo pmset -a disablesleep 0`. Keep Coffee in Login Items, and turn the option off before deleting the app. Careful: a closed Mac in a bag can get hot and drain its battery.
  - **Ask Before Toggling**: whether left-click asks for confirmation first (on by default); turn it off to toggle in one click
  - **Schedule**: stays on automatically during set hours (default 9:00–17:00, weekdays only) and turns off when they end. Pick the **Start** and **End** hours and toggle **Weekdays Only** in the submenu. If you turn Coffee off during scheduled hours, it skips the rest of that day's window. **Turn On Schedule** in the left-click menu resumes it (or a plain click, with **Ask Before Toggling** off). A manual session picked during scheduled hours (such as **Turn On**) overrides the schedule: the submenu shows it as *overridden* with a dash, and clicking it hands control back to the schedule (click it again to turn the schedule off).
  - **Turn Off** and **Quit Coffee**

To start it at login, add `Coffee.app` in System Settings → General → Login Items.
