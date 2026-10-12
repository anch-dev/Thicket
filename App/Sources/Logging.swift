import Foundation
import os
import ThicketKit
import UIKit

/// Connects `GameLog` to the system log and to a file the player can share.
///
/// The file lives in the app's Documents folder (visible in the Files app under
/// "On My iPhone › Thicket") and is rewritten every couple of seconds.
enum AppLogging {
    static let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("thicket-log.txt")
    }()

    private static var loggers: [String: Logger] = [:]
    private static let lock = NSLock()
    private static var timer: Timer?

    static func setUp(verbose: Bool) {
        let log = GameLog.shared
        log.verbose = verbose
        log.sink = { level, category, message in
            lock.lock()
            let logger = loggers[category] ?? Logger(subsystem: "dev.anch.thicket", category: category)
            loggers[category] = logger
            lock.unlock()
            switch level {
            case .debug: logger.debug("\(message, privacy: .public)")
            case .info: logger.info("\(message, privacy: .public)")
            case .warning: logger.warning("\(message, privacy: .public)")
            case .error: logger.error("\(message, privacy: .public)")
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in flush() }
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        let device = UIDevice.current
        log.info("app", "Thicket \(version) on \(device.model) iOS \(device.systemVersion), verbose=\(verbose)")
        log.info("app", "log file: \(fileURL.path)")
    }

    static func flush(force: Bool = false) {
        GameLog.shared.flush(to: fileURL, force: force)
    }
}
