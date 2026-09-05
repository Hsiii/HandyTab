# Trackpad frame performance

Run `python3 scripts/benchmark-trackpad.py` to compile the production recognizer
with `swiftc -O`, replay gesture regressions, then measure seven batches of one
million frames for ordinary contacts and rejected palms. Pass an exported base
revision's `Sources/main.swift` as an optional argument to compare the same
workload. The harness never registers trackpad callbacks, starts the camera,
opens a browser, or writes the user's configuration.

The replay checks normal taps, a palm moving inward while its ID remains active,
release and reuse of that ID, movement rejection, edge contact rejection, and
inactive contacts. Both base and updated code must emit exactly two taps.
`/usr/bin/time -l` measures executable CPU time and peak RSS, excluding compilation.
Use `swift build -c release` to verify the complete application still builds.

Measurements and their practical limits are recorded in the pull request.
This is a microbenchmark of frame handling, not camera inference, tap-to-browser
latency, or battery life. Saving a fraction of a microsecond per frame is a small
absolute improvement at real trackpad sampling rates. The optimization avoids
constructing a temporary array and set when there are no rejected IDs; the
existing reconciliation path is retained whenever a rejected palm is present.
