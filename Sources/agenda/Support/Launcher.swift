//
//  Launcher.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  Handing a link or a script to macOS, for `join` and `open`.
//
//  `/usr/bin/open` AND `/usr/bin/osascript`, NOT NSWorkspace. The tool already talks to
//  Calendar.app through `osascript` (see `HiddenCalendars`), it links no AppKit, and `open`
//  answers the one question worth asking — did anything handle this link — with an exit
//  status and a sentence on stderr.
//
//  A FAILURE IS SAID, NOT SWALLOWED. Fantastical's links do nothing on a Mac without
//  Fantastical, and Calendar.app refuses a script until Automation is granted; both arrive
//  here as a non-zero exit, and both become an error that names the fix.
//

import AgendaKit
import CLIKit
import Foundation

enum Launcher {

    /// Opens `url` with whatever app handles its scheme.
    ///
    /// - Throws: ``CLIError`` (upstream) when nothing on this Mac handles the link.
    static func open(_ url: URL, app: String) throws {
        let (status, message) = run("/usr/bin/open", [url.absoluteString])
        guard status == 0 else {
            throw CLIError.upstream(
                "Could not open \(url.scheme.map { "\($0):" } ?? "the") link: \(message ?? "open exited \(status)")",
                service: "agenda",
                hint: "Is \(app) installed? Pass --print to get the link instead."
            )
        }
    }

    /// Opens `url`, trying `preferred` first — a native-app form such as `zoommtg://` that
    /// skips the browser, but only works when that app is installed.
    static func open(_ url: URL, preferring preferred: URL?, app: String) throws {
        if let preferred, run("/usr/bin/open", [preferred.absoluteString]).status == 0 { return }
        try open(url, app: app)
    }

    /// Runs AppleScript source.
    ///
    /// - Throws: ``CLIError`` (auth) when Automation over the target app is refused, and
    ///   (upstream) for any other failure.
    static func run(script: String) throws {
        let (status, message) = run("/usr/bin/osascript", ["-e", script])
        guard status == 0 else {
            // -1743 is errAEEventNotPermitted: the user has not allowed this process to
            // drive Calendar. That is a grant, like the calendar permission itself.
            if message?.contains("-1743") == true {
                throw CLIError.authRequired(
                    "Not allowed to control Calendar.",
                    service: "agenda",
                    hint: "System Settings ▸ Privacy & Security ▸ Automation"
                )
            }
            throw CLIError.upstream("Calendar did not run the script: \(message ?? "osascript exited \(status)")",
                                    service: "agenda")
        }
    }

    /// Runs `tool` and returns its exit status and trimmed stderr.
    private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, message: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, message.isEmpty ? nil : message)
    }
}
