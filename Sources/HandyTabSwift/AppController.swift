import AppKit
import Foundation

@MainActor
final class AppController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let config = ConfigStore.shared
    private let browserActions = BrowserActions()
    private let cameraWorker = PythonGestureWorker()
    private let trackpadRecognizer = TrackpadTapRecognizer()

    private let cameraItem = NSMenuItem()
    private let trackpadItem = NSMenuItem()
    private let trackpadFingersItem = NSMenuItem()
    private let targetItem = NSMenuItem()
    private let browserItem = NSMenuItem()

    func start() {
        statusItem.button?.title = "HT"
        statusItem.menu = buildMenu()

        cameraWorker.onEvent = { [weak self] event in
            self?.handleWorkerEvent(event)
        }
        cameraWorker.onExit = { [weak self] in
            self?.refreshMenu()
        }
        trackpadRecognizer.onTap = { [weak self] in
            self?.handleTrigger(source: "trackpad", name: "Trackpad_\(self?.trackpadRecognizer.fingerCount ?? 0)_Finger_Tap")
        }

        refreshMenu()
        if config.trackpadEnabled {
            startTrackpad()
        }
        if config.cameraEnabled {
            startCamera()
        }
    }

    func stop() {
        cameraWorker.stop()
        trackpadRecognizer.stop()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        cameraItem.target = self
        cameraItem.action = #selector(toggleCamera)
        menu.addItem(cameraItem)

        trackpadItem.target = self
        trackpadItem.action = #selector(toggleTrackpad)
        menu.addItem(trackpadItem)

        trackpadFingersItem.target = self
        trackpadFingersItem.action = #selector(cycleTrackpadFingers)
        menu.addItem(trackpadFingersItem)

        menu.addItem(.separator())

        targetItem.target = self
        targetItem.action = #selector(editTarget)
        menu.addItem(targetItem)

        browserItem.target = self
        browserItem.action = #selector(editBrowser)
        menu.addItem(browserItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit HandyTab", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func refreshMenu() {
        cameraItem.title = "Camera Gesture: \(cameraWorker.isRunning ? "On" : "Off")"
        trackpadItem.title = "Trackpad Tap: \(trackpadRecognizer.isRunning ? "On" : "Off")"
        trackpadFingersItem.title = "Trackpad Fingers: \(config.trackpadFingerCount)"
        targetItem.title = "Target: \(config.targetURL)"
        browserItem.title = "Browser: \(config.browser ?? "System Default")"
    }

    @objc private func toggleCamera() {
        if cameraWorker.isRunning {
            cameraWorker.stop()
            try? config.setCameraEnabled(false)
        } else {
            try? config.setCameraEnabled(true)
            startCamera()
        }
        refreshMenu()
    }

    @objc private func toggleTrackpad() {
        if trackpadRecognizer.isRunning {
            trackpadRecognizer.stop()
            try? config.setTrackpadEnabled(false)
        } else {
            try? config.setTrackpadEnabled(true)
            startTrackpad()
        }
        refreshMenu()
    }

    @objc private func cycleTrackpadFingers() {
        let options = ConfigStore.trackpadFingerOptions
        let current = config.trackpadFingerCount
        let index = options.firstIndex(of: current) ?? -1
        let next = options[(index + 1) % options.count]
        try? config.setTrackpadFingerCount(next)
        trackpadRecognizer.fingerCount = next
        refreshMenu()
    }

    @objc private func editTarget() {
        prompt(
            title: "Edit Target URL",
            message: "Enter the URL to open when a gesture is detected:",
            defaultValue: config.targetURL
        ) { [weak self] value in
            try? self?.config.setTargetURL(value)
            self?.refreshMenu()
        }
    }

    @objc private func editBrowser() {
        prompt(
            title: "Set Browser",
            message: "Enter a browser app name, or leave empty for the system default:",
            defaultValue: config.browser ?? ""
        ) { [weak self] value in
            try? self?.config.setBrowser(value)
            self?.refreshMenu()
        }
    }

    @objc private func quit() {
        stop()
        NSApplication.shared.terminate(nil)
    }

    private func startCamera() {
        do {
            try cameraWorker.start(targetGesture: config.targetGesture)
        } catch {
            try? config.setCameraEnabled(false)
            showNotification(title: "HandyTab", text: "Camera worker failed: \(error.localizedDescription)")
        }
    }

    private func startTrackpad() {
        trackpadRecognizer.fingerCount = config.trackpadFingerCount
        if !trackpadRecognizer.start() {
            try? config.setTrackpadEnabled(false)
            showNotification(title: "HandyTab", text: "No multitouch trackpad was found.")
        }
    }

    private func handleWorkerEvent(_ event: WorkerEvent) {
        switch event.type {
        case "observation":
            if let gesture = event.gesture, let confidence = event.confidence {
                statusItem.button?.title = "\(gesture.replacingOccurrences(of: "_", with: " ")) \(Int(confidence * 100))%"
            }
        case "trigger":
            handleTrigger(source: "camera", name: event.gesture ?? "")
        case "error":
            cameraWorker.stop()
            try? config.setCameraEnabled(false)
            showNotification(title: "HandyTab", text: event.message ?? "Camera detection stopped.")
        default:
            break
        }
        refreshMenu()
    }

    private func handleTrigger(source: String, name: String) {
        guard source != "camera" || cameraWorker.isRunning else {
            return
        }
        guard source != "trackpad" || trackpadRecognizer.isRunning else {
            return
        }
        if name == "Thumb_Down" {
            browserActions.closeCurrentTab()
        } else {
            browserActions.openTargetURL()
        }
    }

    private func prompt(
        title: String,
        message: String,
        defaultValue: String,
        onSave: (String) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.stringValue = defaultValue
        alert.accessoryView = input

        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            onSave(input.stringValue)
        }
    }

    private func showNotification(title: String, text: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = text
        NSUserNotificationCenter.default.deliver(notification)
    }
}
