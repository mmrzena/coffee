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

/// The menu-bar icon: a cup, plus wisps of steam that rise and fade while Coffee is on.
/// Lives on top of the status-bar button and ignores clicks so the button still gets them.
private final class CoffeeIconView: NSView {
	private let cupView = NSImageView()
	private let wisps = (0..<3).map { _ in CAShapeLayer() }
	private let cupConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
	/// Average seconds for one wisp to rise and fade (each puff varies ±25%).
	private let steamCycle: CFTimeInterval = 4.5
	/// Seconds of no steam between bursts.
	private let quietPause: ClosedRange<Double> = 8...15
	private let wispSpacing: CGFloat = 3
	private var generation = 0

	var isSteaming = false {
		didSet { if isSteaming != oldValue { update() } }
	}

	override init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		cupView.imageScaling = .scaleNone
		addSubview(cupView)
		for wisp in wisps {
			wisp.fillColor = nil
			wisp.lineWidth = 1.2
			wisp.lineCap = .round
			wisp.opacity = 0
			// No implicit 0.25s fades: they made the wisps flash on toggle. Only the explicit
			// puff animations should move them.
			wisp.actions = ["opacity": NSNull(), "path": NSNull(), "position": NSNull(),
				"bounds": NSNull(), "strokeColor": NSNull()]
			layer?.addSublayer(wisp)
		}
		update()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	// Hand-added sublayers stay at 1x unless told otherwise, which blurs the thin strokes on Retina.
	override func viewDidChangeBackingProperties() {
		super.viewDidChangeBackingProperties()
		let scale = window?.backingScaleFactor ?? 2
		for wisp in wisps { wisp.contentsScale = scale }
	}

	override func layout() {
		super.layout()
		let cupSize = cupView.image?.size ?? .zero
		// Nudged 1pt right so the cup looks centred in the menu-bar highlight; sits low so the
		// rising steam stays inside it.
		let offsetX: CGFloat = 1
		cupView.frame = NSRect(x: offsetX, y: 0, width: bounds.width, height: cupSize.height)

		// The cup's opening sits a little left of centre (the handle is on the right).
		let rimY = cupView.frame.maxY + 1
		let height = max(3, min(6, bounds.height - rimY - 1))
		let centerX = bounds.midX - 0.5 + offsetX
		for (index, wisp) in wisps.enumerated() {
			let x = centerX + CGFloat(index - 1) * wispSpacing
			let path = CGMutablePath()
			path.move(to: CGPoint(x: x, y: rimY))
			path.addCurve(to: CGPoint(x: x, y: rimY + height),
				control1: CGPoint(x: x + 1.5, y: rimY + height / 3),
				control2: CGPoint(x: x - 1.5, y: rimY + height * 2 / 3))
			wisp.path = path
			wisp.frame = bounds
		}
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		updateColors()
	}

	private func update() {
		let symbol = isSteaming ? "cup.and.saucer.fill" : "cup.and.saucer"
		cupView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
			.withSymbolConfiguration(cupConfig)
		updateColors()
		needsLayout = true

		generation += 1 // stops any burst loop from the previous state
		let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		for wisp in wisps {
			wisp.removeAllAnimations()
			wisp.opacity = isSteaming && reduceMotion ? 0.7 : 0 // Reduce Motion: static steam
		}
		guard isSteaming, !reduceMotion else { return }
		steamEpisode(generation: generation) // right away, as feedback for the click
	}

	/// A short burst of steam (one random puff per wisp), followed by a quiet pause, then
	/// another burst. Catches the eye now and then without moving constantly.
	private func steamEpisode(generation: Int) {
		guard generation == self.generation else { return } // Coffee was toggled since
		let pause = Double.random(in: quietPause)
		let scheduleNext = { [weak self] in
			DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
				self?.steamEpisode(generation: generation)
			}
		}
		// Skip the burst while nobody can see it (display asleep, menu bar hidden).
		guard window?.occlusionState.contains(.visible) == true else { return scheduleNext() }

		CATransaction.begin()
		CATransaction.setCompletionBlock(scheduleNext)
		for wisp in wisps {
			wisp.add(puff(delay: .random(in: 0...1.5)), forKey: nil)
		}
		CATransaction.commit()
	}

	/// One puff: the wisp drifts up (and a little sideways) while fading in and out, with
	/// random timing, height, drift and strength so the wisps never fall into a fixed sequence.
	private func puff(delay: CFTimeInterval) -> CAAnimation {
		let rise = CABasicAnimation(keyPath: "transform.translation") // up, drifting sideways
		rise.fromValue = NSValue(size: NSSize(width: 0, height: -1))
		rise.toValue = NSValue(size: NSSize(width: .random(in: -0.8...0.8), height: .random(in: 2.5...3.5)))
		let fade = CAKeyframeAnimation(keyPath: "opacity")
		fade.values = [0, Double.random(in: 0.55...0.9), 0]
		fade.keyTimes = [0, NSNumber(value: Double.random(in: 0.25...0.45)), 1]

		let group = CAAnimationGroup()
		group.animations = [rise, fade]
		group.duration = steamCycle * .random(in: 0.75...1.25)
		group.beginTime = CACurrentMediaTime() + delay
		group.timingFunction = CAMediaTimingFunction(name: .easeOut)
		return group
	}

	private func updateColors() {
		effectiveAppearance.performAsCurrentDrawingAppearance {
			let color = NSColor.labelColor.cgColor
			for wisp in wisps { wisp.strokeColor = color }
		}
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
	private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
	private let iconView = CoffeeIconView()
	private var session: Session?
	private var lastError: String?
	private var keepDisplayOn = UserDefaults.standard.bool(forKey: DefaultsKey.keepDisplayOn)

	private var isOn: Bool { session != nil }

	func applicationDidFinishLaunching(_ notification: Notification) {
		if let button = statusItem.button {
			button.target = self
			button.action = #selector(clicked)
			button.sendAction(on: [.leftMouseUp, .rightMouseUp])
			iconView.frame = button.bounds
			iconView.autoresizingMask = [.width, .height]
			button.addSubview(iconView)
		}
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
		statusItem.button?.toolTip = statusText() + "\nClick to toggle · right-click for options"
		statusItem.button?.setAccessibilityLabel(isOn ? "Coffee on" : "Coffee off")
		iconView.isSteaming = isOn
	}
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
