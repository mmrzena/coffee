# Coffee

A tiny macOS menu bar app that keeps your Mac awake. It holds its own power assertion (no `caffeinate` process), and quitting the app releases it.

## Install

Requires macOS 12+ and the Xcode command line tools (`xcode-select --install`).

```sh
./build.sh
```

This builds a universal app into `~/Applications/Coffee.app` and launches it. Run it again after changing the code; it restarts the app.

## Use

A coffee cup icon appears in the menu bar. An outlined cup means off; a filled, steaming cup means the Mac is being kept awake. A small clock on the cup means the schedule is on and will keep the Mac awake during its hours; it's gone while the schedule is off or skipped for today.

- **Left-click** opens a small menu right under the icon: **Turn Off** when on; when off, **Turn On** (until you turn it off; this switches the schedule off) and **Turn On Schedule (9:00–17:00)**, showing your hours (enables the schedule, or resumes it if skipped today; Coffee comes on now if it's within scheduled hours), or **Turn Off Schedule** instead while the schedule is on and waiting for its hours. Click anywhere else to cancel.
- **Right-click** (or Ctrl-click) opens the menu:
  - **On Indefinitely** (like **Turn On**, this switches the schedule off), or on for **30 min / 1 / 2 / 4 hours**
  - **Keep Display On**: also stops the screen from sleeping (remembered between launches)
  - **Stay Awake With Lid Closed**: while Coffee is on, closing the lid doesn't sleep the Mac (remembered between launches). This needs a one-time setup, `./setup-lid.sh`, which lets Coffee run `pmset -a disablesleep` without a password; to undo it, turn the option off (or quit Coffee), then run `sudo rm /etc/sudoers.d/coffee`. If the setup is missing, Coffee beeps, shows a note and unchecks the option. It turns the setting back off when Coffee turns off or quits, and leaves alone a `disablesleep` you set yourself. The setting survives restarts, so if Coffee crashes or is force-quit while on, the Mac won't sleep on lid close until Coffee is launched again (it cleans up then) or you run `sudo pmset -a disablesleep 0`. Keep Coffee in Login Items, and turn the option off before deleting the app. Careful: a closed Mac in a bag can get hot and drain its battery.
  - **Ask Before Toggling**: whether left-click asks for confirmation first (on by default); turn it off to toggle in one click (turning on this way works like **Turn On**)
  - **Schedule**: stays on automatically during set hours (default 9:00–17:00, every day) and turns off when they end. Pick the **Start** and **End** hours in the submenu. If you turn Coffee off during scheduled hours, it skips the rest of that day's window. **Turn On Schedule** in the left-click menu resumes it. A timed session picked from the right-click menu during scheduled hours (such as **On for 1 hour**) overrides the schedule: the submenu shows it as *overridden* with a dash, and clicking it hands control back to the schedule (click it again to turn the schedule off).
  - **Turn Off** and **Quit Coffee**

To start it at login, add `Coffee.app` in System Settings → General → Login Items.
