import AppKit
import Foundation
import ServiceManagement

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

// MARK: - Launch at Login

@MainActor
final class LaunchAtLoginStore {
    private(set) var opensAtLogin = false
    private let swiftRunLoginItem = SwiftRunLoginItem()

    init() {
        refresh()
    }

    func refresh() {
        opensAtLogin = Self.usesServiceManagement
            ? Self.isServiceManagementEnabled
            : swiftRunLoginItem.isEnabled
    }

    func setEnabled(_ enabled: Bool) -> String? {
        do {
            if Self.usesServiceManagement {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } else {
                try swiftRunLoginItem.setEnabled(enabled)
            }

            opensAtLogin = enabled
            return nil
        } catch {
            refresh()
            return Self.message(for: enabled, error: error)
        }
    }

    private static var usesServiceManagement: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private static var isServiceManagementEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private static func message(for enabled: Bool, error: Error) -> String {
        let fallback: String
        if usesServiceManagement {
            fallback = enabled
                ? "HandyTab could not be added to Login Items. Install the app in /Applications and try again."
                : "HandyTab could not be removed from Login Items."
        } else {
            fallback = enabled
                ? "HandyTab could not add its SwiftPM launch agent."
                : "HandyTab could not remove its SwiftPM launch agent."
        }

        let details = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericFailure = details.lowercased().contains("operation")
            && details.lowercased().contains("completed")
        if details.isEmpty || genericFailure {
            return fallback
        }

        return "\(fallback) \(details)"
    }
}

final class SwiftRunLoginItem {
    private let label = "dev.hsichen.handytab"
    private let fileManager = FileManager.default

    var isEnabled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try writePlist()
        } else if isEnabled {
            try fileManager.removeItem(at: plistURL)
        }
    }

    private var plistURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    private var projectRootURL: URL {
        var url = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        while url.path != "/" {
            if fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }

    private func writePlist() throws {
        let root = projectRootURL
        try fileManager.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/usr/bin/swift",
                "run",
                "--package-path",
                root.path,
            ],
            "RunAtLoad": true,
            "WorkingDirectory": root.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }
}

// MARK: - Target Opening

final class TargetOpener {
    private var lastOpenTime: TimeInterval = 0
    private let cooldown: TimeInterval = 0.2

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

        let root = workerRootURL()
        let executable = pythonExecutablePath(workerRootURL: root)

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
        process.environment = workerEnvironment(workerRootURL: root)
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

    private func workerRootURL() -> URL {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let candidates = [
            Bundle.main.resourceURL,
            currentDirectory,
        ].compactMap { $0 }

        for candidate in candidates {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("handytab").path),
               fileManager.fileExists(atPath: candidate.appendingPathComponent("gesture_recognizer.task").path) {
                return candidate
            }
        }

        return currentDirectory
    }

    private func pythonExecutablePath(workerRootURL: URL) -> String {
        let fileManager = FileManager.default
        let candidates = [
            workerRootURL.appendingPathComponent("venv/bin/python3").path,
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("venv/bin/python3").path,
            "/opt/homebrew/opt/python@3.12/bin/python3.12",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]

        return candidates.first { fileManager.fileExists(atPath: $0) } ?? "/usr/bin/python3"
    }

    private func workerEnvironment(workerRootURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let bundledPythonPackages = workerRootURL.appendingPathComponent("python").path
        let pythonPathRoots = [bundledPythonPackages, workerRootURL.path]
            .filter { FileManager.default.fileExists(atPath: $0) }
            .joined(separator: ":")
        let existingPythonPath = environment["PYTHONPATH"]
        if let existingPythonPath, !existingPythonPath.isEmpty {
            environment["PYTHONPATH"] = "\(pythonPathRoots):\(existingPythonPath)"
        } else {
            environment["PYTHONPATH"] = pythonPathRoots
        }
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
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

    private var sawTargetFingerCount = false
    private var startTime = 0.0
    private var startCentroid: MTPoint?
    private var maxMovement: Float = 0
    private var lastTriggerTime = 0.0
    private var rejectedTouchIDs = Set<Int32>()
    private var devices = [MTDeviceRef]()

    private let tapDurationLimit = 0.45
    private let movementLimit: Float = 0.14
    private let cooldown = 0.2
    private let staleTouchClusterLimit = 1.0
    private let palmTotalLimit: Float = 1.5
    private let palmMajorAxisLimit: Float = 10.0
    private let palmMinorAxisLimit: Float = 8.0
    private let palmEdgeMargin: Float = 0.03
    private let palmEdgeTotalLimit: Float = 0.9
    private let typingPalmWindow = 2.0
    private let typingSideMargin: Float = 0.30
    private let typingTopMargin: Float = 0.20

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
        syncRejectedTouchIDs(with: touches)
        let activePoints = touches.compactMap(fingerPoint)

        handle(points: activePoints, timestamp: timestamp)
    }

    private func fingerPoint(from touch: MTTouch) -> MTPoint? {
        guard isActiveTouch(touch) else {
            return nil
        }

        if rejectedTouchIDs.contains(touch.identifier) || isPalmLike(touch) {
            rejectedTouchIDs.insert(touch.identifier)
            return nil
        }

        return touch.normalizedVector.position
    }

    private func syncRejectedTouchIDs(with touches: UnsafeBufferPointer<MTTouch>) {
        let activeTouchIDs = Set(touches.compactMap { touch -> Int32? in
            guard isActiveTouch(touch) else {
                return nil
            }
            return touch.identifier
        })
        rejectedTouchIDs.formIntersection(activeTouchIDs)
    }

    private func isActiveTouch(_ touch: MTTouch) -> Bool {
        touch.state == 3 || touch.state == 4
    }

    private func isPalmLike(_ touch: MTTouch) -> Bool {
        if touch.total > palmTotalLimit ||
            touch.majorAxis > palmMajorAxisLimit ||
            touch.minorAxis > palmMinorAxisLimit {
            return true
        }

        let point = touch.normalizedVector.position
        if hasRecentKeyboardInput && isTypingPalmZone(point) {
            return true
        }

        let isEdgeContact = point.x < palmEdgeMargin ||
            point.x > 1 - palmEdgeMargin ||
            point.y < palmEdgeMargin ||
            point.y > 1 - palmEdgeMargin

        return isEdgeContact && touch.total > palmEdgeTotalLimit
    }

    private var hasRecentKeyboardInput: Bool {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) < typingPalmWindow
    }

    private func isTypingPalmZone(_ point: MTPoint) -> Bool {
        point.x < typingSideMargin ||
            point.x > 1 - typingSideMargin ||
            point.y > 1 - typingTopMargin
    }

    private func handle(points: [MTPoint], timestamp: Double) {
        if points.isEmpty || (sawTargetFingerCount && points.count < Self.fingerCount) {
            finishTouchCluster(timestamp: timestamp)
            return
        }

        if sawTargetFingerCount && timestamp - startTime > staleTouchClusterLimit {
            reset()
        }

        guard points.count == Self.fingerCount else {
            return
        }

        let centroid = centroid(of: points)
        if !sawTargetFingerCount {
            sawTargetFingerCount = true
            startTime = timestamp
            startCentroid = centroid
            maxMovement = 0
        } else if let startCentroid {
            maxMovement = max(maxMovement, centroid.distance(to: startCentroid))
        }
    }

    private func finishTouchCluster(timestamp: Double) {
        defer {
            reset()
        }

        guard sawTargetFingerCount else {
            return
        }

        let elapsed = timestamp - startTime
        guard elapsed <= tapDurationLimit,
              maxMovement <= movementLimit,
              timestamp - lastTriggerTime >= cooldown
        else {
            return
        }

        lastTriggerTime = timestamp
        DispatchQueue.main.async { [weak self] in
            self?.onTap?()
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
        sawTargetFingerCount = false
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
    private let launchAtLoginStore = LaunchAtLoginStore()

    private let trackpadStatusItem = NSMenuItem()
    private let cameraItem = NSMenuItem()
    private let targetItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem()

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

        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleOpenAtLogin)
        menu.addItem(launchAtLoginItem)

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
        launchAtLoginStore.refresh()
        launchAtLoginItem.title = "Open at Login"
        launchAtLoginItem.state = launchAtLoginStore.opensAtLogin ? .on : .off
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

    @objc private func toggleOpenAtLogin() {
        let enabled = !launchAtLoginStore.opensAtLogin
        if let message = launchAtLoginStore.setEnabled(enabled) {
            showAlert(title: "Could Not Update Login Item", text: message)
        }
        refreshMenu()
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

    private func showAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
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
