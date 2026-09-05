#!/usr/bin/env python3
"""Replay synthetic trackpad frames through the production recognizer.

Usage: python3 scripts/benchmark-trackpad.py [path/to/main.swift]
Never registers a device callback, enables the camera, or opens a browser.
"""
import pathlib
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1] / 'Sources/main.swift'
recognizer = source.read_text().split('// MARK: - Raw Trackpad Tap Recognition', 1)[1].split('// MARK: - Menu Bar App', 1)[0]
harness = r'''
func touch(_ id: Int32, x: Float = 0.5, state: Int32 = 4, palm: Bool = false) -> MTTouch {
    MTTouch(frame: 0, timestamp: 0, identifier: id, state: state, fingerID: id, handID: 0,
            normalizedVector: MTVector(position: MTPoint(x: x, y: 0.5), velocity: MTPoint(x: 0, y: 0)),
            total: palm ? 2 : 0, pressure: 0, angle: 0, majorAxis: 0, minorAxis: 0,
            absoluteVector: MTVector(position: MTPoint(x: 0, y: 0), velocity: MTPoint(x: 0, y: 0)),
            unknown14: 0, unknown15: 0, density: 0)
}
func replay(_ recognizer: TrackpadTapRecognizer, _ contacts: [MTTouch], at time: Double) {
    var contacts = contacts
    contacts.withUnsafeMutableBufferPointer { buffer in
        recognizer.process(touches: UnsafeMutableRawPointer(buffer.baseAddress), count: buffer.count, timestamp: time)
    }
}
// Regression: valid taps, palm rejection across frames, released/reused IDs,
// movement, edge contacts, and inactive contacts all take the real process path.
let recognizer = TrackpadTapRecognizer()
var tapCount = 0
recognizer.onTap = { tapCount += 1 }
let fingers = [touch(1, x: 0.4), touch(2), touch(3, x: 0.6)]
let released = [touch(1, state: 7), touch(2, state: 7), touch(3, state: 7)]
replay(recognizer, fingers, at: 2)
replay(recognizer, released, at: 2.1) // valid
replay(recognizer, [touch(1, x: 0.01, palm: true), touch(2), touch(3)], at: 3)
replay(recognizer, fingers, at: 3.05) // rejected ID must stay rejected as palm moves inward
replay(recognizer, released, at: 3.1)
replay(recognizer, fingers, at: 4) // reused ID after release is valid again
replay(recognizer, released, at: 4.1)
replay(recognizer, fingers, at: 5)
replay(recognizer, [touch(1, x: 0.7), touch(2, x: 0.8), touch(3, x: 0.9)], at: 5.05)
replay(recognizer, released, at: 5.1) // movement is not a tap
replay(recognizer, [touch(1, x: 0.1), touch(2), touch(3)], at: 6)
replay(recognizer, released, at: 6.1) // edge-assisted contact is not a tap
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
precondition(tapCount == 2, "Expected two deliberate taps; got \(tapCount)")
print("Gesture regression replay passed: \(tapCount) taps")

// One/two-finger interaction is the common no-palm path, with no tap callbacks.
// Include a rejected-palm workload to detect regressions in the slower path.
for palm in [false, true] {
    let recognizer = TrackpadTapRecognizer()
    var contacts = [touch(1, x: palm ? 0.01 : 0.4, palm: palm), touch(2)]
    var samples: [Double] = []
    contacts.withUnsafeMutableBufferPointer { buffer in
        let pointer = UnsafeMutableRawPointer(buffer.baseAddress)
        for _ in 0..<1000 { recognizer.process(touches: pointer, count: buffer.count, timestamp: 1) }
        for _ in 0..<7 {
            let start = DispatchTime.now().uptimeNanoseconds
            for i in 0..<1_000_000 {
                recognizer.process(touches: pointer, count: buffer.count, timestamp: Double(i))
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
    }
    samples.sort()
    print("1000000 frames palm=\(palm): median_ms=\(samples[3]) min_ms=\(samples[0]) max_ms=\(samples[6])")
}
'''
with tempfile.TemporaryDirectory(prefix='handytab-trackpad-bench-') as directory:
    main = pathlib.Path(directory) / 'main.swift'
    binary = pathlib.Path(directory) / 'benchmark'
    main.write_text('import AppKit\nimport Foundation\n' + recognizer + harness)
    subprocess.run(['swiftc', '-O', str(main), '-F/System/Library/PrivateFrameworks', '-framework', 'MultitouchSupport', '-o', str(binary)], check=True)
    subprocess.run(['/usr/bin/time', '-l', str(binary)], check=True)
