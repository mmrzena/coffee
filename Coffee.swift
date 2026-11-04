// Coffee — a tiny menu-bar toggle that keeps the Mac awake.
// Holds its own IOPMAssertion (no caffeinate process); quitting releases it.
import Cocoa
import IOKit.pwr_mgt

/// One "keep awake" period: the power assertion plus its optional end time.
private struct Session {
	let assertionID: IOPMAssertionID
	let until: Date?
	let timer: Timer?
}

private enum DefaultsKey {
	static let keepDisplayOn = "keepDisplayOn"
}

private let durationOptions: [(label: String, minutes: Int)] = [
	("On for 30 min", 30), ("On for 1 hour", 60), ("On for 2 hours", 120), ("On for 4 hours", 240),
]

final class AppDelegate: NSObject, NSApplicationDelegate {
	private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
	private var session: Session?
	private var lastError: String?
	private var keepDisplayOn = UserDefaults.standard.bool(forKey: DefaultsKey.keepDisplayOn)

	private var isOn: Bool { session != nil }

	func applicationDidFinishLaunching(_ notification: Notification) {
		statusItem.button?.target = self
		statusItem.button?.action = #selector(clicked)
		statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
		// Timers don't count time spent asleep, so re-check the real clock on wake.
		NSWorkspace.shared.notificationCenter.addObserver(
			self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
		refresh()
	}

	func applicationWillTerminate(_ notification: Notification) { turnOff() }

	// Left click toggles; right click (or ctrl-click) opens the menu.
	@objc private func clicked() {
		let event = NSApp.currentEvent
		if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
			statusItem.menu = buildMenu()
			statusItem.button?.performClick(nil)
			statusItem.menu = nil
		} else {
			isOn ? turnOff() : turnOn(until: nil)
		}
	}

	private func buildMenu() -> NSMenu {
		let menu = NSMenu()
		let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
		status.isEnabled = false
		menu.addItem(status)
		menu.addItem(.separator())
		if isOn {
			menu.addItem(menuItem("Turn Off", #selector(turnOff)))
		}
		menu.addItem(menuItem("On Indefinitely", #selector(turnOnIndefinitely)))
		for option in durationOptions {
			let durationItem = menuItem(option.label, #selector(turnOnForDuration(_:)))
			durationItem.tag = option.minutes
			menu.addItem(durationItem)
		}
		menu.addItem(.separator())
		let displayItem = menuItem("Keep Display On", #selector(toggleKeepDisplayOn))
		displayItem.state = keepDisplayOn ? .on : .off
		menu.addItem(displayItem)
		menu.addItem(.separator())
		menu.addItem(menuItem("Quit Coffee", #selector(quit)))
		return menu
	}

	private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = self
		return item
	}

	@objc private func turnOnIndefinitely() { turnOn(until: nil) }
	@objc private func turnOnForDuration(_ sender: NSMenuItem) {
		turnOn(until: Date().addingTimeInterval(TimeInterval(sender.tag * 60)))
	}
	@objc private func quit() { NSApp.terminate(nil) }

	@objc private func toggleKeepDisplayOn() {
		keepDisplayOn.toggle()
		UserDefaults.standard.set(keepDisplayOn, forKey: DefaultsKey.keepDisplayOn)
		if let session { turnOn(until: session.until) } // re-assert with the new type, same end time
	}

	@objc private func didWake() {
		if let until = session?.until, until <= Date() { turnOff() }
	}

	/// Starts (or replaces) a session. `until == nil` means indefinitely; an end time
	/// that has already passed turns Coffee off instead.
	private func turnOn(until: Date?) {
		if let until, until <= Date() { return turnOff() }

		let type = (keepDisplayOn ? kIOPMAssertionTypeNoDisplaySleep : kIOPMAssertionTypeNoIdleSleep) as CFString
		var assertionID: IOPMAssertionID = 0
		let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn),
			"Coffee menu-bar toggle" as CFString, &assertionID)
		guard result == kIOReturnSuccess else {
			lastError = "Couldn't keep the Mac awake (IOKit error \(result))"
			NSSound.beep()
			refresh()
			return
		}

		var timer: Timer?
		if let until {
			let endTimer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in self?.turnOff() }
			RunLoop.main.add(endTimer, forMode: .common) // .common: keeps running while a menu is open
			timer = endTimer
		}

		// New assertion exists before the old one is released, so there's no gap with nothing held.
		endSession()
		session = Session(assertionID: assertionID, until: until, timer: timer)
		lastError = nil
		refresh()
	}

	@objc private func turnOff() {
		endSession()
		lastError = nil
		refresh()
	}

	private func endSession() {
		guard let session else { return }
		session.timer?.invalidate()
		IOPMAssertionRelease(session.assertionID)
		self.session = nil
	}

	private func statusText() -> String {
		if let lastError { return lastError }
		guard let session else { return "Off — Mac sleeps normally" }
		guard let until = session.until else { return "On — until turned off" }
		return "On — until \(until.formatted(date: .omitted, time: .shortened))"
	}

	private func refresh() {
		let symbol = isOn ? "cup.and.saucer.fill" : "cup.and.saucer"
		statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Coffee")
		statusItem.button?.toolTip = statusText() + "\nClick to toggle · right-click for options"
	}
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
