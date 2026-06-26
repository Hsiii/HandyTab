import Foundation

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
    private let decoder = JSONDecoder()

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(targetGesture: String) throws {
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
            targetGesture,
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
        for line in text.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
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
