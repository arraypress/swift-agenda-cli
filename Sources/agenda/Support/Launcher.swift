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
    /// - Throws: ``CLIError`` (upstream, retry `not_started`) when nothing on this Mac
    ///   handles the link.
    static func open(_ url: URL, app: String) throws {
        let (status, message) = run("/usr/bin/open", [url.absoluteString])
        guard status == 0 else {
            throw CLIError(
                code: .upstream,
                message: "Could not open \(url.scheme.map { "\($0):" } ?? "the") link: \(message ?? "open exited \(status)")",
                hint: "Is \(app) installed? Pass --print to get the link instead.",
                service: "agenda",
                retry: .notStarted
            )
        }
    }

    /// Opens `url`, trying `preferred` first — a native-app form such as `zoommtg://` that
    /// skips the browser, but only works when that app is installed.
    static func open(_ url: URL, preferring preferred: URL?, app: String) throws {
        if let preferred, run("/usr/bin/open", [preferred.absoluteString]).status == 0 { return }
        try open(url, app: app)
    }

    /// Runs AppleScript source through CLIKit's `OSAScript`.
    ///
    /// - Throws: `OSAScriptError`, which leaves as exit 3 with the Automation hint when
    ///   driving Calendar is refused (-1743), exit 5 for anything else — each with a retry
    ///   verdict, and a timeout that kills a Calendar.app stuck behind a dialog.
    static func run(script: String, timeout: Double? = nil) throws {
        try OSAScript.run(script, timeout: timeout)
    }

    /// Runs `tool` and returns its exit status and trimmed stderr.
    ///
    /// Through `ChildProcess`, with a limit: `open` returns as soon as the link is handed
    /// over, so fifteen seconds is a hang, not a slow app.
    private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, message: String?) {
        do {
            let output = try ChildProcess.runBlocking(tool, arguments, timeout: 15, stdout: .none)
            if output.timedOut { return (-1, "\(tool) did not return within 15 s") }
            return (output.status, output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
        } catch {
            return (-1, error.reason)
        }
    }
}
