import AppKit
import Foundation

// The self test runs without any UI so that it can be used in CI.
if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
