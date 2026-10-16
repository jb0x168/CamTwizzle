import Foundation
import os

/// Tiny logging facade: unified logging for the app, optional stderr echo for the CLI.
public enum TwzLog {
    public static var echoToStderr = false
    public static var verbose = false
    private static let logger = Logger(subsystem: "dev.camtwizzle", category: "core")

    public static func info(_ message: @autoclosure () -> String) {
        let m = message()
        logger.info("\(m, privacy: .public)")
        if echoToStderr && verbose { FileHandle.standardError.write(Data(("· " + m + "\n").utf8)) }
    }

    public static func warn(_ message: @autoclosure () -> String) {
        let m = message()
        logger.warning("\(m, privacy: .public)")
        if echoToStderr { FileHandle.standardError.write(Data(("! " + m + "\n").utf8)) }
    }

    public static func error(_ message: @autoclosure () -> String) {
        let m = message()
        logger.error("\(m, privacy: .public)")
        if echoToStderr { FileHandle.standardError.write(Data(("✗ " + m + "\n").utf8)) }
    }
}
