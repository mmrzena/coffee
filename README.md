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

- **Left-click** turns it on or off.
- **Right-click** (or Ctrl-click) opens the menu:
  - **On Indefinitely**, or on for **30 min / 1 / 2 / 4 hours**
  - **Keep Display On**: also stops the screen from sleeping (remembered between launches)
  - **Schedule**: stays on automatically during set hours (default 9:00–17:00, weekdays only) and turns off when they end. Pick the **Start** and **End** hours and toggle **Weekdays Only** in the submenu. If you turn Coffee off during scheduled hours, it skips the rest of that day's window. Clicking the cup on again resumes the schedule.
  - **Turn Off** and **Quit Coffee**

To start it at login, add `Coffee.app` in System Settings → General → Login Items.
