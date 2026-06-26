import AppKit
import Foundation

// MARK: - Config

final class ConfigStore: @unchecked Sendable {
    static let shared = ConfigStore()
    static let handWaveGesture = "Open_Palm"

    private let configURL: URL
    private let fileManager = FileManager.default

    private init() {
        let home = fileManager.homeDirectoryForCurrentUser
        configURL = home.appendingPathComponent(".handytab_config.json")
    }

    var targetURL: String {
        normalizeURL(string(for: "target_url") ?? "https://hsichen.dev")
    }

    var handWaveWebcamEnabled: Bool {
        bool(for: "hand_wave_webcam_enabled", defaultValue: false)
    }

    func setTargetURL(_ value: String) throws {
        try set("target_url", value: normalizeURL(value))
    }

    func setHandWaveWebcamEnabled(_ value: Bool) throws {
        try set("hand_wave_webcam_enabled", value: value)
    }

    private func string(for key: String) -> String? {
        loadRaw()[key] as? String
    }

    private func bool(for key: String, defaultValue: Bool) -> Bool {
        loadRaw()[key] as? Bool ?? defaultValue
    }

    private func set(_ key: String, value: Any?) throws {
        var raw = loadRaw()
        if let value {
            raw[key] = value
        } else {
            raw.removeValue(forKey: key)
        }
        let data = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
    }

    private func loadRaw() -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return value
    }

    private func normalizeURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "https://hsichen.dev"
        }
        if URLComponents(string: trimmed)?.scheme == nil {
            return "https://\(trimmed)"
        }
        return trimmed
    }
}

// MARK: - Target Opening

final class TargetOpener {
    private var lastOpenTime: TimeInterval = 0
    private let cooldown: TimeInterval = 0.7

    func openTargetURL() {
        let now = Date().timeIntervalSince1970
        guard now - lastOpenTime >= cooldown else {
            return
        }

        let config = ConfigStore.shared
        _ = runProcess("/usr/bin/open", arguments: [config.targetURL], timeout: 1)
        lastOpenTime = now
    }

    @discardableResult
    private func runProcess(_ executable: String, arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Python Gesture Worker

struct WorkerEvent: Decodable {
    let type: String
    let gesture: String?
    let confidence: Double?
    let message: String?
    let targetGesture: String?

    enum CodingKeys: String, CodingKey {
        case type
        case gesture
        case confidence
        case message
        case targetGesture = "target_gesture"
    }
}

final class PythonGestureWorker: @unchecked Sendable {
    var onEvent: ((WorkerEvent) -> Void)?
    var onExit: (() -> Void)?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var outputBuffer = ""
    private let decoder = JSONDecoder()

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start() throws {
        if isRunning {
            return
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pythonPath = root.appendingPathComponent("venv/bin/python3").path
        let fallbackPythonPath = "/usr/bin/python3"
        let executable = FileManager.default.fileExists(atPath: pythonPath) ? pythonPath : fallbackPythonPath

        let process = Process()
        let stdout = Pipe()
        let standardErrorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = root
        process.arguments = [
            "-m",
            "handytab.gesture_worker",
            "--target-gesture",
            ConfigStore.handWaveGesture,
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PYTHONUNBUFFERED": "1"],
            uniquingKeysWith: { _, new in new }
        )
        process.standardOutput = stdout
        process.standardError = standardErrorPipe

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleOutput(handle.availableData)
        }
        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                FileHandle.standardError.write(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopHandlers()
                self?.onExit?()
            }
        }

        try process.run()
        self.process = process
        stdoutPipe = stdout
        stderrPipe = standardErrorPipe
    }

    func stop() {
        guard let process else {
            stopHandlers()
            return
        }
        if process.isRunning {
            process.terminate()
        }
        stopHandlers()
        self.process = nil
    }

    private func handleOutput(_ data: Data) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return
        }
        outputBuffer += text

        while let newline = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)

            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let event = try? decoder.decode(WorkerEvent.self, from: lineData)
            else {
                continue
            }
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(event)
            }
        }
    }

    private func stopHandlers() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }
}

// MARK: - Raw Trackpad Tap Recognition

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallbackFunction = @convention(c) (
    MTDeviceRef?,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32

@_silgen_name("MTDeviceCreateList")
func MTDeviceCreateList() -> CFArray?

@_silgen_name("MTDeviceStart")
func MTDeviceStart(_ device: MTDeviceRef, _ mode: Int32)

@_silgen_name("MTDeviceStop")
func MTDeviceStop(_ device: MTDeviceRef)

@_silgen_name("MTRegisterContactFrameCallback")
func MTRegisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallbackFunction)

@_silgen_name("MTUnregisterContactFrameCallback")
func MTUnregisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallbackFunction?)

struct MTPoint {
    var x: Float
    var y: Float

    func distance(to other: MTPoint) -> Float {
        abs(x - other.x) + abs(y - other.y)
    }
}

struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVector
    var total: Float
    var pressure: Float
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector
    var unknown14: Int32
    var unknown15: Int32
    var density: Float
}

nonisolated(unsafe) private var activeTrackpadRecognizer: TrackpadTapRecognizer?

nonisolated(unsafe) private let contactFrameCallback: MTContactCallbackFunction = { _, touches, count, timestamp, _ in
    activeTrackpadRecognizer?.process(touches: touches, count: Int(count), timestamp: timestamp)
    return 0
}

final class TrackpadTapRecognizer: @unchecked Sendable {
    static let fingerCount = 3
    var onTap: (() -> Void)?

    private enum State {
        case idle
        case possibleTap
    }

    private var state = State.idle
    private var startTime = 0.0
    private var startCentroid: MTPoint?
    private var maxMovement: Float = 0
    private var lastTriggerTime = 0.0
    private var devices = [MTDeviceRef]()

    private let tapDurationLimit = 0.35
    private let movementLimit: Float = 0.08
    private let cooldown = 0.7

    var isRunning: Bool {
        !devices.isEmpty
    }

    func start() -> Bool {
        if isRunning {
            return true
        }
        guard let deviceList = MTDeviceCreateList() else {
            return false
        }

        activeTrackpadRecognizer = self
        for index in 0..<CFArrayGetCount(deviceList) {
            guard let rawDevice = CFArrayGetValueAtIndex(deviceList, index) else {
                continue
            }
            let device = UnsafeMutableRawPointer(mutating: rawDevice)
            MTRegisterContactFrameCallback(device, contactFrameCallback)
            MTDeviceStart(device, 0)
            devices.append(device)
        }

        if devices.isEmpty {
            activeTrackpadRecognizer = nil
            return false
        }
        return true
    }

    func stop() {
        for device in devices {
            MTUnregisterContactFrameCallback(device, contactFrameCallback)
            MTDeviceStop(device)
        }
        devices.removeAll()
        activeTrackpadRecognizer = nil
        reset()
    }

    fileprivate func process(touches rawTouches: UnsafeMutableRawPointer?, count: Int, timestamp: Double) {
        guard let rawTouches, count >= 0 else {
            return
        }

        let touches = UnsafeBufferPointer(
            start: rawTouches.bindMemory(to: MTTouch.self, capacity: count),
            count: count
        )
        let activePoints = touches.compactMap { touch -> MTPoint? in
            guard touch.state == 3 || touch.state == 4 else {
                return nil
            }
            if touch.total > 3.0 {
                return nil
            }
            return touch.normalizedVector.position
        }

        handle(points: activePoints, timestamp: timestamp)
    }

    private func handle(points: [MTPoint], timestamp: Double) {
        if points.count == Self.fingerCount {
            let centroid = centroid(of: points)
            switch state {
            case .idle:
                state = .possibleTap
                startTime = timestamp
                startCentroid = centroid
                maxMovement = 0
            case .possibleTap:
                if let startCentroid {
                    maxMovement = max(maxMovement, centroid.distance(to: startCentroid))
                }
            }
            return
        }

        if points.isEmpty, state == .possibleTap {
            let elapsed = timestamp - startTime
            if elapsed <= tapDurationLimit,
               maxMovement <= movementLimit,
               timestamp - lastTriggerTime >= cooldown {
                lastTriggerTime = timestamp
                DispatchQueue.main.async { [weak self] in
                    self?.onTap?()
                }
            }
        }

        if points.count != Self.fingerCount {
            reset()
        }
    }

    private func centroid(of points: [MTPoint]) -> MTPoint {
        let sum = points.reduce(MTPoint(x: 0, y: 0)) { partial, point in
            MTPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let count = Float(points.count)
        return MTPoint(x: sum.x / count, y: sum.y / count)
    }

    private func reset() {
        state = .idle
        startTime = 0
        startCentroid = nil
        maxMovement = 0
    }
}

// MARK: - Menu Bar App

@MainActor
final class AppController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let config = ConfigStore.shared
    private let targetOpener = TargetOpener()
    private let cameraWorker = PythonGestureWorker()
    private let trackpadRecognizer = TrackpadTapRecognizer()

    private let trackpadStatusItem = NSMenuItem()
    private let cameraItem = NSMenuItem()
    private let targetItem = NSMenuItem()

    func start() {
        configureStatusIcon()
        statusItem.menu = buildMenu()

        cameraWorker.onEvent = { [weak self] event in
            self?.handleWorkerEvent(event)
        }
        cameraWorker.onExit = { [weak self] in
            self?.refreshMenu()
        }
        trackpadRecognizer.onTap = { [weak self] in
            self?.handleTrigger(source: "trackpad")
        }

        refreshMenu()
        startTrackpad()
        if config.handWaveWebcamEnabled {
            startCamera()
        }
    }

    func stop() {
        cameraWorker.stop()
        trackpadRecognizer.stop()
    }

    private func configureStatusIcon() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.imagePosition = .imageOnly

        guard let image = statusIconImage() else {
            button.title = "HT"
            return
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        button.image = image
    }

    private func statusIconImage() -> NSImage? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            root.appendingPathComponent("assets/icon.png"),
            Bundle.main.resourceURL?.appendingPathComponent("icon.png"),
            Bundle.main.resourceURL?.appendingPathComponent("assets/icon.png"),
        ].compactMap { $0 }

        for url in candidates {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        trackpadStatusItem.isEnabled = false
        menu.addItem(trackpadStatusItem)

        targetItem.target = self
        targetItem.action = #selector(editTarget)
        menu.addItem(targetItem)

        menu.addItem(.separator())

        cameraItem.target = self
        cameraItem.action = #selector(toggleHandWaveWebcam)
        menu.addItem(cameraItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit HandyTab", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func refreshMenu() {
        trackpadStatusItem.title = trackpadRecognizer.isRunning
            ? "3-Finger Trackpad Tap: Always On"
            : "3-Finger Trackpad Tap: Not Available"
        targetItem.title = "Open: \(config.targetURL)"
        cameraItem.title = "Hand Wave Webcam"
        cameraItem.state = cameraWorker.isRunning ? .on : .off
    }

    @objc private func toggleHandWaveWebcam() {
        if cameraWorker.isRunning {
            cameraWorker.stop()
            try? config.setHandWaveWebcamEnabled(false)
        } else {
            try? config.setHandWaveWebcamEnabled(true)
            startCamera()
        }
        refreshMenu()
    }

    @objc private func editTarget() {
        prompt(
            title: "Edit Target URL",
            message: "Enter the URL to open from the 3-finger trackpad tap:",
            defaultValue: config.targetURL
        ) { [weak self] value in
            try? self?.config.setTargetURL(value)
            self?.refreshMenu()
        }
    }

    @objc private func quit() {
        stop()
        NSApplication.shared.terminate(nil)
    }

    private func startCamera() {
        do {
            try cameraWorker.start()
        } catch {
            try? config.setHandWaveWebcamEnabled(false)
            showNotification(title: "HandyTab", text: "Hand Wave Webcam failed: \(error.localizedDescription)")
        }
    }

    private func startTrackpad() {
        if !trackpadRecognizer.start() {
            showNotification(title: "HandyTab", text: "No multitouch trackpad was found.")
        }
        refreshMenu()
    }

    private func handleWorkerEvent(_ event: WorkerEvent) {
        switch event.type {
        case "observation":
            break
        case "trigger":
            handleTrigger(source: "camera")
        case "error":
            cameraWorker.stop()
            try? config.setHandWaveWebcamEnabled(false)
            showNotification(title: "HandyTab", text: event.message ?? "Hand Wave Webcam stopped.")
        default:
            break
        }
        refreshMenu()
    }

    private func handleTrigger(source: String) {
        guard source != "camera" || cameraWorker.isRunning else {
            return
        }
        guard source != "trackpad" || trackpadRecognizer.isRunning else {
            return
        }
        targetOpener.openTargetURL()
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

@MainActor
final class HandyTabApp: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = AppController()
        controller?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}

let app = NSApplication.shared
let delegate = HandyTabApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
