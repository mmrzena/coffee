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
	static let stayAwakeLidClosed = "stayAwakeLidClosed"
	static let lidSleepDisabledByCoffee = "lidSleepDisabledByCoffee"
	static let askBeforeToggling = "askBeforeToggling"
	static let scheduleEnabled = "scheduleEnabled"
	static let scheduleStartHour = "scheduleStartHour"
	static let scheduleEndHour = "scheduleEndHour"
}

/// Daily keep-awake hours, e.g. 9:00–17:00 every day. Windows start and end on whole hours
/// within one day (startHour < endHour).
private struct Schedule {
	var isEnabled: Bool
	var startHour: Int
	var endHour: Int

	static func load() -> Schedule {
		let defaults = UserDefaults.standard
		defaults.removeObject(forKey: "scheduleWeekdaysOnly") // from the removed Weekdays Only option
		return Schedule(
			isEnabled: defaults.bool(forKey: DefaultsKey.scheduleEnabled),
			startHour: defaults.object(forKey: DefaultsKey.scheduleStartHour) as? Int ?? 9,
			endHour: defaults.object(forKey: DefaultsKey.scheduleEndHour) as? Int ?? 17)
	}

	func save() {
		let defaults = UserDefaults.standard
		defaults.set(isEnabled, forKey: DefaultsKey.scheduleEnabled)
		defaults.set(startHour, forKey: DefaultsKey.scheduleStartHour)
		defaults.set(endHour, forKey: DefaultsKey.scheduleEndHour)
	}

	/// The daily hours as text, e.g. "9:00–17:00".
	var windowLabel: String { "\(hourLabel(startHour))–\(hourLabel(endHour))" }

	/// The scheduled window on the day containing `date`, or nil if the hours don't form a valid window.
	private func window(onDayOf date: Date, calendar: Calendar) -> DateInterval? {
		guard let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: date),
			let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: date),
			start < end
		else { return nil }
		return DateInterval(start: start, end: end)
	}

	/// The window `now` falls inside, if the schedule is on and `now` is within scheduled hours.
	func activeWindow(at now: Date) -> DateInterval? {
		guard isEnabled, let window = window(onDayOf: now, calendar: .current),
			window.start <= now, now < window.end
		else { return nil }
		return window
	}

	func nextStart(after now: Date) -> Date? {
		guard isEnabled else { return nil }
		let calendar = Calendar.current
		// Every day is scheduled, so the next start is today's, or else tomorrow's.
		guard let today = window(onDayOf: now, calendar: calendar) else { return nil }
		if today.start > now { return today.start }
		return calendar.date(byAdding: .day, value: 1, to: today.start)
	}
}

private func hourLabel(_ hour: Int) -> String {
	let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
	return date.formatted(date: .omitted, time: .shortened)
}

private let durationOptions: [(label: String, minutes: Int)] = [
	("On for 30 min", 30), ("On for 1 hour", 60), ("On for 2 hours", 120), ("On for 4 hours", 240),
]

/// The outline steaming cup with the steam removed. SF Symbols has no steam-free version of this
/// cup, so this hides the symbol's steam layer and redraws the stretch of rim that Apple cuts
/// away where the steam crosses it. Rim geometry is measured from the symbol, in points of its
/// 17×16 default size.
private func makeCupWithoutSteam() -> NSImage? {
	guard let cup = NSImage(systemSymbolName: "cup.and.heat.waves", accessibilityDescription: "Coffee off")?
		.withSymbolConfiguration(.init(paletteColors: [.black, .black, .clear])) // layer 3 = steam
	else { return nil }
	let image = NSImage(size: cup.size, flipped: true) { rect in
		cup.draw(in: rect)
		let scale = rect.width / 17
		NSGraphicsContext.saveGraphicsState()
		NSRect(x: 4 * scale, y: 4.5 * scale, width: 7 * scale, height: 2.5 * scale).clip() // top of rim only
		let rimRadius = NSSize(width: 5.075 * scale, height: 1.795 * scale)
		let rim = NSBezierPath(ovalIn: NSRect(x: 7.5 * scale - rimRadius.width, y: 7.56 * scale - rimRadius.height,
			width: 2 * rimRadius.width, height: 2 * rimRadius.height))
		rim.lineWidth = 1.05 * scale
		NSColor.black.setStroke()
		rim.stroke()
		NSGraphicsContext.restoreGraphicsState()
		return true
	}
	image.isTemplate = true
	image.alignmentRect = cup.alignmentRect // sit in the menu bar exactly like the "on" symbol
	image.accessibilityDescription = "Coffee off"
	return image
}

private let offIcon = makeCupWithoutSteam()
	?? NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "Coffee off")

// macOS 14+ has the steaming-cup symbol; older systems fall back to the cup and saucer.
private let onIcon = NSImage(systemSymbolName: "cup.and.heat.waves.fill", accessibilityDescription: "Coffee on")
	?? NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Coffee on")

/// `cup` with a small clock in the bottom-right corner, marking the schedule as enabled. A ring
/// around the clock is punched out of the cup so the badge reads at menu-bar size.
private func withClockBadge(_ cup: NSImage?, description: String) -> NSImage? {
	guard let cup,
		let clock = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)
	else { return cup }
	let image = NSImage(size: cup.size, flipped: false) { rect in
		cup.draw(in: rect)
		let side = rect.height * 0.6
		let badge = NSRect(x: rect.maxX - side, y: rect.minY, width: side, height: side)
		let gap = side * 0.15
		NSGraphicsContext.current?.compositingOperation = .destinationOut
		NSBezierPath(ovalIn: badge.insetBy(dx: -gap, dy: -gap)).fill()
		NSGraphicsContext.current?.compositingOperation = .sourceOver
		clock.draw(in: badge)
		return true
	}
	image.isTemplate = true
	image.alignmentRect = cup.alignmentRect
	image.accessibilityDescription = description
	return image
}

private let onScheduleArmedIcon = withClockBadge(onIcon, description: "Coffee on, schedule on")
private let offScheduleArmedIcon = withClockBadge(offIcon, description: "Coffee off, schedule on")

final class AppDelegate: NSObject, NSApplicationDelegate {
	private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
	private var session: Session?
	private var lastError: String?
	private var keepDisplayOn = UserDefaults.standard.bool(forKey: DefaultsKey.keepDisplayOn) {
		didSet { UserDefaults.standard.set(keepDisplayOn, forKey: DefaultsKey.keepDisplayOn) }
	}
	private var stayAwakeLidClosed = UserDefaults.standard.bool(forKey: DefaultsKey.stayAwakeLidClosed) {
		didSet { UserDefaults.standard.set(stayAwakeLidClosed, forKey: DefaultsKey.stayAwakeLidClosed) }
	}
	/// Whether Coffee turned on the system-wide `pmset disablesleep`; persisted so a crash gets
	/// cleaned up on next launch, and so Coffee never undoes a setting someone else made.
	private var lidSleepDisabledByCoffee = UserDefaults.standard.bool(forKey: DefaultsKey.lidSleepDisabledByCoffee) {
		didSet { UserDefaults.standard.set(lidSleepDisabledByCoffee, forKey: DefaultsKey.lidSleepDisabledByCoffee) }
	}
	private var lidRestoreFailureReported = false
	private var askBeforeToggling = UserDefaults.standard.object(forKey: DefaultsKey.askBeforeToggling) as? Bool ?? true {
		didSet { UserDefaults.standard.set(askBeforeToggling, forKey: DefaultsKey.askBeforeToggling) }
	}
	private var schedule = Schedule.load()
	private var scheduleTimer: Timer?
	/// End of the scheduled window the user turned off by hand; the schedule leaves that window alone.
	private var dismissedWindowEnd: Date?

	private var isOn: Bool { session != nil }
	/// On, and ending exactly when the current scheduled window does — i.e. the schedule's session.
	private var isOnBySchedule: Bool {
		guard let until = session?.until else { return false }
		return until == currentWindow?.end
	}
	private var currentWindow: DateInterval? { schedule.activeWindow(at: Date()) }
	/// Enabled and not skipping today: the schedule will keep Coffee on through its next hours.
	private var isScheduleArmed: Bool { schedule.isEnabled && !isSkippingCurrentWindow }
	private var isSkippingCurrentWindow: Bool {
		guard let end = currentWindow?.end else { return false }
		return end == dismissedWindowEnd
	}
	/// Within scheduled hours, but the schedule isn't what's in charge: the user skipped this
	/// window, or picked a timed session (e.g. "On for 1 hour") that overrides it. Shown as a mixed checkmark.
	private var isScheduleSidelined: Bool {
		guard currentWindow != nil else { return false }
		return isSkippingCurrentWindow || (isOn && !isOnBySchedule)
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		if let button = statusItem.button {
			button.target = self
			button.action = #selector(clicked)
			button.sendAction(on: [.leftMouseUp, .rightMouseUp])
		}
		// Timers don't count time spent asleep, so re-check the real clock on wake and clock changes.
		NSWorkspace.shared.notificationCenter.addObserver(
			self, selector: #selector(recheckClock), name: NSWorkspace.didWakeNotification, object: nil)
		for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
			NotificationCenter.default.addObserver(self, selector: #selector(recheckClock), name: name, object: nil)
		}
		applySchedule()
		syncLidSleep() // clears a setting a crashed run left on, unless the schedule just turned Coffee on
		refresh()
	}

	func applicationWillTerminate(_ notification: Notification) { turnOff() }

	// Left click toggles or asks first; right click (or ctrl-click) opens the menu.
	@objc private func clicked() {
		let event = NSApp.currentEvent
		if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
			showMenu(buildMenu())
		} else if askBeforeToggling {
			showMenu(buildConfirmMenu())
		} else {
			isOn ? userTurnOff() : turnOnManually()
		}
	}

	/// Pops `menu` up directly under the icon.
	private func showMenu(_ menu: NSMenu) {
		statusItem.menu = menu
		statusItem.button?.performClick(nil)
		statusItem.menu = nil
	}

	/// A short menu under the icon, so confirming is a click just below where you clicked.
	private func buildConfirmMenu() -> NSMenu {
		let menu = NSMenu()
		if isOn {
			menu.addItem(menuItem("Turn Off", #selector(userTurnOff)))
		} else {
			menu.addItem(menuItem("Turn On", #selector(confirmTurnOn)))
			// Off while the schedule waits for its hours: turning it "on" would do nothing.
			if isScheduleArmed {
				menu.addItem(menuItem("Turn Off Schedule", #selector(confirmTurnOffSchedule)))
			} else {
				menu.addItem(menuItem("Turn On Schedule (\(schedule.windowLabel))", #selector(confirmTurnOnSchedule)))
			}
		}
		return menu
	}

	// Timers keep running while the menu is open, so the confirm handlers act on what was
	// offered, not a fresh toggle.

	@objc private func confirmTurnOn() {
		guard !isOn else { return }
		turnOnManually()
	}

	@objc private func confirmTurnOffSchedule() { updateSchedule { $0.isEnabled = false } }

	/// Enables the schedule, or stops skipping today's window; Coffee comes on now if it's within hours.
	@objc private func confirmTurnOnSchedule() {
		dismissedWindowEnd = nil
		updateSchedule { $0.isEnabled = true }
	}

	private func buildMenu() -> NSMenu {
		let menu = NSMenu()
		let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
		status.isEnabled = false
		menu.addItem(status)
		menu.addItem(.separator())
		if isOn {
			menu.addItem(menuItem("Turn Off", #selector(userTurnOff)))
		}
		menu.addItem(menuItem("On Indefinitely", #selector(turnOnManually)))
		for option in durationOptions {
			menu.addItem(menuItem(option.label, #selector(turnOnForDuration(_:)), tag: option.minutes))
		}
		menu.addItem(.separator())
		menu.addItem(menuItem("Keep Display On", #selector(toggleKeepDisplayOn), checked: keepDisplayOn))
		menu.addItem(menuItem("Stay Awake With Lid Closed", #selector(toggleStayAwakeLidClosed), checked: stayAwakeLidClosed))
		menu.addItem(scheduleMenuItem())
		menu.addItem(menuItem("Ask Before Toggling", #selector(toggleAskBeforeToggling), checked: askBeforeToggling))
		menu.addItem(.separator())
		menu.addItem(menuItem("Quit Coffee", #selector(quit)))
		return menu
	}

	private func scheduleMenuItem() -> NSMenuItem {
		let hours = schedule.windowLabel
		let sidelined = isScheduleSidelined
		let title: String
		if !schedule.isEnabled {
			title = "Schedule: Off"
		} else if isSkippingCurrentWindow {
			title = "Schedule: \(hours) (skipped today)"
		} else if sidelined {
			title = "Schedule: \(hours) (overridden)"
		} else {
			title = "Schedule: \(hours)"
		}
		let submenu = NSMenu()
		let toggle = menuItem("On \(hours)", #selector(toggleSchedule))
		toggle.state = sidelined ? .mixed : schedule.isEnabled ? .on : .off
		submenu.addItem(toggle)
		submenu.addItem(.separator())
		submenu.addItem(hourPicker("Start", selected: schedule.startHour,
			enabled: 0...(schedule.endHour - 1), action: #selector(setScheduleStart(_:))))
		submenu.addItem(hourPicker("End", selected: schedule.endHour,
			enabled: (schedule.startHour + 1)...23, action: #selector(setScheduleEnd(_:))))
		return submenuItem(title, submenu)
	}

	private func hourPicker(_ title: String, selected: Int, enabled: ClosedRange<Int>, action: Selector) -> NSMenuItem {
		let submenu = NSMenu()
		submenu.autoenablesItems = false // so hours that would make an empty window can be greyed out
		for hour in 0...23 {
			let hourItem = menuItem(hourLabel(hour), action, tag: hour, checked: hour == selected)
			hourItem.isEnabled = enabled.contains(hour)
			submenu.addItem(hourItem)
		}
		return submenuItem("\(title): \(hourLabel(selected))", submenu)
	}

	private func menuItem(_ title: String, _ action: Selector, tag: Int = 0, checked: Bool = false) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = self
		item.tag = tag
		item.state = checked ? .on : .off
		return item
	}

	private func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
		item.submenu = submenu
		return item
	}

	/// A one-shot timer in `.common` mode, so it still fires while a menu is open.
	private func oneShotTimer(at date: Date, _ block: @escaping () -> Void) -> Timer {
		let timer = Timer(fire: date, interval: 0, repeats: false) { _ in block() }
		RunLoop.main.add(timer, forMode: .common)
		return timer
	}

	/// "On until turned off" (Turn On, a plain click, On Indefinitely) is manual mode: it switches
	/// the schedule off so it can't take over. Turning on first, so `updateSchedule` doesn't end a
	/// session the schedule started and leave a gap with nothing held.
	@objc private func turnOnManually() {
		turnOn(until: nil)
		updateSchedule { $0.isEnabled = false }
	}
	@objc private func turnOnForDuration(_ sender: NSMenuItem) {
		turnOn(until: Date().addingTimeInterval(TimeInterval(sender.tag * 60)))
	}
	@objc private func quit() { NSApp.terminate(nil) }

	@objc private func toggleKeepDisplayOn() {
		keepDisplayOn.toggle()
		if let session { turnOn(until: session.until) } // re-assert with the new type, same end time
	}

	@objc private func toggleStayAwakeLidClosed() {
		stayAwakeLidClosed.toggle()
		lastError = nil
		syncLidSleep()
		refresh()
	}

	/// Power assertions don't stop lid-close sleep; only the system-wide `pmset disablesleep` does,
	/// and it needs root (via the sudoers rule from setup-lid.sh). Held only while Coffee is on.
	private func syncLidSleep() {
		let want = isOn && stayAwakeLidClosed
		guard want != lidSleepDisabledByCoffee else { return }
		switch (want, systemSleepDisabled()) {
		case (true, .some(true)): return // already set by someone else; leave it theirs to undo
		case (false, .some(false)): lidSleepDisabledByCoffee = false; return // someone already cleared it
		default: break
		}
		if setSystemSleepDisabled(want) {
			lidSleepDisabledByCoffee = want
			lidRestoreFailureReported = false
		} else if want {
			stayAwakeLidClosed = false // so later turn-ons, e.g. the schedule's, don't retry and beep
			fail("Lid-closed mode needs setup: run setup-lid.sh")
		} else {
			// Retried on every turn-off and launch until it works, but only beeps the first time.
			lastError = "Couldn't restore lid sleep: run sudo pmset -a disablesleep 0"
			if !lidRestoreFailureReported { NSSound.beep() }
			lidRestoreFailureReported = true
		}
	}

	/// The live `disablesleep` value from the power manager, or nil if it can't be read.
	private func systemSleepDisabled() -> Bool? {
		let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
		guard rootDomain != 0 else { return nil }
		defer { IOObjectRelease(rootDomain) }
		return IORegistryEntryCreateCFProperty(rootDomain, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
			.takeRetainedValue() as? Bool
	}

	/// The arguments must match the sudoers rule in setup-lid.sh exactly, or sudo wants a password.
	private func setSystemSleepDisabled(_ disabled: Bool) -> Bool {
		let sudo = Process()
		sudo.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
		sudo.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"]
		sudo.standardError = FileHandle.nullDevice
		let exited = DispatchSemaphore(value: 0)
		sudo.terminationHandler = { _ in exited.signal() }
		do { try sudo.run() } catch { return false }
		// A semaphore, not waitUntilExit(): that spins the run loop, letting timers re-enter
		// turnOn/turnOff mid-call. The timeout keeps a stalled sudo from freezing the menu bar.
		guard exited.wait(timeout: .now() + 5) == .success else {
			sudo.terminate()
			return false
		}
		return sudo.terminationStatus == 0
	}

	private func fail(_ message: String) {
		lastError = message
		NSSound.beep()
		refresh()
	}

	@objc private func toggleAskBeforeToggling() { askBeforeToggling.toggle() }

	/// When the schedule is set but sidelined, clicking it hands control back to it instead of
	/// disabling it; otherwise it switches the schedule on or off.
	@objc private func toggleSchedule() {
		if isScheduleSidelined { userTurnOn() } else { updateSchedule { $0.isEnabled.toggle() } }
	}
	@objc private func setScheduleStart(_ sender: NSMenuItem) { updateSchedule { $0.startHour = sender.tag } }
	@objc private func setScheduleEnd(_ sender: NSMenuItem) { updateSchedule { $0.endHour = sender.tag } }

	private func updateSchedule(_ change: (inout Schedule) -> Void) {
		let wasSkipping = isSkippingCurrentWindow
		let oldWindowEnd = currentWindow?.end
		change(&schedule)
		schedule.save()
		let newWindowEnd = currentWindow?.end
		// Skipping today survives a settings edit: carry the skip over to the edited window.
		dismissedWindowEnd = wasSkipping ? newWindowEnd : nil
		// A session the old schedule started follows the new one: moved end, or off if outside it.
		if let oldWindowEnd, session?.until == oldWindowEnd, newWindowEnd != oldWindowEnd {
			if let newWindowEnd { turnOn(until: newWindowEnd) } else { turnOff() }
		}
		applySchedule()
		refresh()
	}

	/// During scheduled hours, keeps Coffee on until the window ends (an indefinite or longer
	/// session is left alone), then arms a timer for the next window's start.
	private func applySchedule() {
		scheduleTimer?.invalidate()
		scheduleTimer = nil
		let now = Date()
		if let window = schedule.activeWindow(at: now), !isSkippingCurrentWindow {
			let sessionEnd = session.map { $0.until ?? .distantFuture } ?? .distantPast
			if sessionEnd < window.end { turnOn(until: window.end) }
		}
		if let next = schedule.nextStart(after: now) {
			scheduleTimer = oneShotTimer(at: next) { [weak self] in self?.applySchedule() }
		}
	}

	/// Clicking on during scheduled hours hands back to the schedule (on until the window ends);
	/// outside them it's on until turned off.
	private func userTurnOn() {
		dismissedWindowEnd = nil
		turnOn(until: currentWindow?.end)
	}

	/// Turning off by hand during scheduled hours skips the rest of that window.
	@objc private func userTurnOff() {
		guard isOn else { return } // a timer may have turned it off while a menu was open
		dismissedWindowEnd = currentWindow?.end
		turnOff()
	}

	@objc private func recheckClock() {
		if let until = session?.until, until <= Date() { sessionEnded() } else { applySchedule() }
	}

	/// A session that ran out hands straight over to the schedule when within its hours, rather
	/// than turning off first, which would briefly re-enable lid sleep with the lid maybe closed.
	private func sessionEnded() {
		if let window = currentWindow, !isSkippingCurrentWindow { turnOn(until: window.end) } else { turnOff() }
		applySchedule()
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
			return fail("Couldn't keep the Mac awake (IOKit error \(result))")
		}

		var timer: Timer?
		if let until {
			timer = oneShotTimer(at: until) { [weak self] in self?.sessionEnded() }
		}

		// New assertion exists before the old one is released, so there's no gap with nothing held.
		endSession()
		session = Session(assertionID: assertionID, until: until, timer: timer)
		lastError = nil
		syncLidSleep()
		refresh()
	}

	@objc private func turnOff() {
		endSession()
		lastError = nil
		syncLidSleep()
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
		guard let session else {
			guard let next = schedule.nextStart(after: Date()) else { return "Off — Mac sleeps normally" }
			return "Off — schedule resumes \(next.formatted(.dateTime.weekday().hour().minute()))"
		}
		guard let until = session.until else { return "On — until turned off" }
		let prefix = isOnBySchedule ? "On by schedule" : "On"
		return "\(prefix) — until \(until.formatted(date: .omitted, time: .shortened))"
	}

	private var currentIcon: NSImage? {
		// The cup says whether Coffee is on; the clock says the schedule will keep it on in its hours.
		if isOn { return isScheduleArmed ? onScheduleArmedIcon : onIcon }
		return isScheduleArmed ? offScheduleArmedIcon : offIcon
	}

	private func refresh() {
		statusItem.button?.image = currentIcon
		let click = askBeforeToggling ? "Click for on/off" : "Click to toggle"
		statusItem.button?.toolTip = statusText() + "\n\(click) · right-click for options"
	}
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
