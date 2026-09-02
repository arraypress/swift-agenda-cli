//
//  SafeOutput.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  Writing to a pipe that has stopped listening.
//

import Foundation

/// Writes to stdout without dying when the reader has gone.
///
/// `agenda describe | head -1` is a closed stdout, which is how a pipeline
/// says "enough" rather than a failure. Two things go wrong by default:
/// SIGPIPE kills the process at 141, outside any documented exit code; and
/// `FileHandle.write` raises `NSFileHandleOperationException`, which cannot
/// be caught in Swift. This ignores the signal so the write returns `EPIPE`,
/// then exits 0 — the behaviour `head` expects.
///
/// A copy of what CLIKit's `Terminal` does. This package does not depend on
/// CLIKit and is not worth a dependency for fifteen lines.
enum SafeOutput {

    /// Ignores SIGPIPE, once.
    private static let ignoreSignal: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    /// Writes every byte, restarting across interruptions and partial writes.
    static func write(_ data: Data) {
        _ = ignoreSignal
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard var base = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let written = Foundation.write(FileHandle.standardOutput.fileDescriptor, base, remaining)
                if written > 0 {
                    base += written
                    remaining -= written
                    continue
                }
                if errno == EINTR { continue }
                if errno == EPIPE { exit(0) }
                return
            }
        }
    }

    /// Writes text.
    static func write(_ string: String) { write(Data(string.utf8)) }
}
