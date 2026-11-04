# Coffee

A tiny macOS menu bar app that keeps your Mac awake. It holds its own power assertion (no `caffeinate` process), and quitting the app releases it.

## Install

Requires macOS 12+ and the Xcode command line tools (`xcode-select --install`).

```sh
./build.sh
```

This builds a universal app into `~/Applications/Coffee.app` and launches it. Run it again after changing the code; it restarts the app.

## Use

A coffee cup icon appears in the menu bar. A filled cup means the Mac is being kept awake.

- **Left-click** turns it on or off.
- **Right-click** (or Ctrl-click) opens the menu:
  - **On Indefinitely**, or on for **30 min / 1 / 2 / 4 hours**
  - **Keep Display On**: also stops the screen from sleeping (remembered between launches)
  - **Turn Off** and **Quit Coffee**

To start it at login, add `Coffee.app` in System Settings → General → Login Items.
