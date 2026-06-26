import Foundation

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

private let contactFrameCallback: MTContactCallbackFunction = { _, touches, count, timestamp, _ in
    activeTrackpadRecognizer?.process(touches: touches, count: Int(count), timestamp: timestamp)
    return 0
}

final class TrackpadTapRecognizer: @unchecked Sendable {
    var fingerCount = 3
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
        if points.count == fingerCount {
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

        if points.count != fingerCount {
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
