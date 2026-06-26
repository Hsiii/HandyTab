import AppKit
import Foundation

final class BrowserActions {
    private var lastOpenTime: TimeInterval = 0
    private var lastCloseTime: TimeInterval = 0
    private let cooldown: TimeInterval = 0.7

    func openTargetURL() {
        let now = Date().timeIntervalSince1970
        guard now - lastOpenTime >= cooldown else {
            return
        }

        let config = ConfigStore.shared
        var arguments = [String]()
        if let browser = config.browser {
            arguments += ["-a", browser]
        }
        arguments.append(config.targetURL)

        _ = runProcess("/usr/bin/open", arguments: arguments, timeout: 1)
        lastOpenTime = now
    }

    func closeCurrentTab() {
        let now = Date().timeIntervalSince1970
        guard now - lastCloseTime >= cooldown else {
            return
        }

        let browser = ConfigStore.shared.browser ?? frontmostAppName()
        guard let script = closeTabScript(for: browser) else {
            return
        }
        _ = runProcess("/usr/bin/osascript", arguments: ["-e", script], timeout: 3)
        lastCloseTime = now
    }

    private func frontmostAppName() -> String? {
        let script = "tell application \"System Events\" to get name of first application process whose frontmost is true"
        return runProcess("/usr/bin/osascript", arguments: ["-e", script], timeout: 3)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func closeTabScript(for browser: String?) -> String? {
        guard let browser else {
            return nil
        }

        let escaped = browser.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let key = browser.lowercased()

        if key == "safari" {
            return """
            tell application "\(escaped)"
            if exists front window then close current tab of front window
            end tell
            """
        }

        let chromiumBrowsers: Set<String> = [
            "arc",
            "brave browser",
            "chromium",
            "dia",
            "google chrome",
            "microsoft edge",
            "opera",
            "vivaldi",
        ]
        if chromiumBrowsers.contains(key) {
            return """
            tell application "\(escaped)"
            if exists front window then close active tab of front window
            end tell
            """
        }

        return nil
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
