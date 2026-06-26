import AppKit

@MainActor
final class HandyTabSwiftApp: NSObject, NSApplicationDelegate {
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
let delegate = HandyTabSwiftApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
