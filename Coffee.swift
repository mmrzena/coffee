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
	static let askBeforeToggling = "askBeforeToggling"
	static let scheduleEnabled = "scheduleEnabled"
	static let scheduleStartHour = "scheduleStartHour"
	static let scheduleEndHour = "scheduleEndHour"
	static let scheduleWeekdaysOnly = "scheduleWeekdaysOnly"
}

/// Daily keep-awake hours, e.g. 9:00–17:00 on weekdays. Windows start and end on whole hours
/// within one day (startHour < endHour).
private struct Schedule {
	var isEnabled: Bool
	var startHour: Int
	var endHour: Int
	var weekdaysOnly: Bool

	static func load() -> Schedule {
		let defaults = UserDefaults.standard
		return Schedule(
			isEnabled: defaults.bool(forKey: DefaultsKey.scheduleEnabled),
			startHour: defaults.object(forKey: DefaultsKey.scheduleStartHour) as? Int ?? 9,
			endHour: defaults.object(forKey: DefaultsKey.scheduleEndHour) as? Int ?? 17,
			weekdaysOnly: defaults.object(forKey: DefaultsKey.scheduleWeekdaysOnly) as? Bool ?? true)
	}

	func save() {
		let defaults = UserDefaults.standard
		defaults.set(isEnabled, forKey: DefaultsKey.scheduleEnabled)
		defaults.set(startHour, forKey: DefaultsKey.scheduleStartHour)
		defaults.set(endHour, forKey: DefaultsKey.scheduleEndHour)
		defaults.set(weekdaysOnly, forKey: DefaultsKey.scheduleWeekdaysOnly)
	}

	/// The scheduled window on the day containing `date`, or nil if that day isn't scheduled.
	private func window(onDayOf date: Date, calendar: Calendar) -> DateInterval? {
		if weekdaysOnly && calendar.isDateInWeekend(date) { return nil }
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
		for dayOffset in 0...7 {
			if let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
				let window = window(onDayOf: day, calendar: calendar), window.start > now {
				return window.start
			}
		}
		return nil
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

/// The "on" cup with a small clock in the bottom-right corner, shown while the schedule holds
/// Coffee on. A ring around the clock is punched out of the cup so the badge reads at menu-bar size.
private func makeScheduledIcon() -> NSImage? {
	guard let cup = onIcon,
		let clock = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)
	else { return nil }
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
	image.accessibilityDescription = "Coffee on by schedule"
	return image
}

private let scheduledIcon = makeScheduledIcon() ?? onIcon

final class AppDelegate: NSObject, NSApplicationDelegate {
	private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
	private var session: Session?
	private var lastError: String?
	private var keepDisplayOn = UserDefaults.standard.bool(forKey: DefaultsKey.keepDisplayOn)
	private var askBeforeToggling = UserDefaults.standard.object(forKey: DefaultsKey.askBeforeToggling) as? Bool ?? true
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
	private var isSkippingCurrentWindow: Bool {
		guard let end = currentWindow?.end else { return false }
		return end == dismissedWindowEnd
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
			isOn ? userTurnOff() : userTurnOn()
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
			if !schedule.isEnabled || isSkippingCurrentWindow {
				menu.addItem(menuItem("Turn On Schedule", #selector(confirmTurnOnSchedule)))
			}
		}
		return menu
	}

	// Timers keep running while the menu is open, so act on what was offered, not a fresh toggle.
	@objc private func confirmTurnOn() {
		guard !isOn else { return }
		dismissedWindowEnd = nil
		turnOn(until: nil)
	}

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
		menu.addItem(menuItem("On Indefinitely", #selector(turnOnIndefinitely)))
		for option in durationOptions {
			menu.addItem(menuItem(option.label, #selector(turnOnForDuration(_:)), tag: option.minutes))
		}
		menu.addItem(.separator())
		menu.addItem(menuItem("Keep Display On", #selector(toggleKeepDisplayOn), checked: keepDisplayOn))
		menu.addItem(scheduleMenuItem())
		menu.addItem(menuItem("Ask Before Toggling", #selector(toggleAskBeforeToggling), checked: askBeforeToggling))
		menu.addItem(.separator())
		menu.addItem(menuItem("Quit Coffee", #selector(quit)))
		return menu
	}

	private func scheduleMenuItem() -> NSMenuItem {
		let hours = "\(hourLabel(schedule.startHour))–\(hourLabel(schedule.endHour))"
		let title: String
		if !schedule.isEnabled {
			title = "Schedule: Off"
		} else if isSkippingCurrentWindow {
			title = "Schedule: \(hours) (skipped today)"
		} else {
			title = "Schedule: \(hours)"
		}
		let submenu = NSMenu()
		submenu.addItem(menuItem("On \(hours)", #selector(toggleSchedule), checked: schedule.isEnabled))
		submenu.addItem(menuItem("Weekdays Only", #selector(toggleScheduleWeekdaysOnly), checked: schedule.weekdaysOnly))
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

	@objc private func toggleAskBeforeToggling() {
		askBeforeToggling.toggle()
		UserDefaults.standard.set(askBeforeToggling, forKey: DefaultsKey.askBeforeToggling)
	}

	@objc private func toggleSchedule() { updateSchedule { $0.isEnabled.toggle() } }
	@objc private func toggleScheduleWeekdaysOnly() { updateSchedule { $0.weekdaysOnly.toggle() } }
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
		if let until = session?.until, until <= Date() { turnOff() }
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
			lastError = "Couldn't keep the Mac awake (IOKit error \(result))"
			NSSound.beep()
			refresh()
			return
		}

		var timer: Timer?
		if let until {
			timer = oneShotTimer(at: until) { [weak self] in
				self?.turnOff()
				self?.applySchedule() // a short session ending inside scheduled hours hands back to the schedule
			}
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
		guard let session else {
			guard let next = schedule.nextStart(after: Date()) else { return "Off — Mac sleeps normally" }
			return "Off — schedule resumes \(next.formatted(.dateTime.weekday().hour().minute()))"
		}
		guard let until = session.until else { return "On — until turned off" }
		let prefix = isOnBySchedule ? "On by schedule" : "On"
		return "\(prefix) — until \(until.formatted(date: .omitted, time: .shortened))"
	}

	private var currentIcon: NSImage? {
		if isOnBySchedule { return scheduledIcon }
		return isOn ? onIcon : offIcon
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
