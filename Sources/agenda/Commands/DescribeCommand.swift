//
//  DescribeCommand.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//

import ArgumentParser
import Foundation

/// `agenda describe` — the command tree, for an agent to read.
///
/// The rest of this family ships the same command, so a caller that has learnt
/// one tool can discover the next without being told. `mcp` serves the same
/// purpose over a protocol; this is the version you can pipe into `jq`.
struct DescribeCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "describe",
        abstract: "Describe this tool's commands in machine-readable form.",
        discussion: """
              agenda describe --json
              agenda describe --json | jq -r '.commands[].invocation'

            Every command, its arguments, and what they take — built from the \
            parser's own definitions, so it cannot drift from what the tool \
            actually accepts.
            """
    )

    @Flag(name: .long, help: "Force JSON output (the default, and the only form).")
    var json: Bool = false

    func run() throws {
        let dumped = try Self.dumpedTree()
        let root = dumped["command"] as? [String: Any] ?? [:]

        let described = Described(
            tool: "agenda",
            version: AgendaCommand.configuration.version,
            summary: AgendaCommand.configuration.abstract,
            requiresAuth: false,
            commands: Self.walk(root, path: [])
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        FileHandle.standardOutput.write(try encoder.encode(described))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    // MARK: The tree

    /// Flattens ArgumentParser's dump into the shape this family publishes.
    static func walk(_ node: [String: Any], path: [String]) -> [DescribedCommand] {
        let name = node["commandName"] as? String ?? "agenda"
        let here = path + [name]

        var described = [
            DescribedCommand(
                invocation: here.joined(separator: " "),
                path: Array(here.dropFirst()),
                summary: node["abstract"] as? String ?? "",
                details: (node["discussion"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                arguments: arguments(in: node)
            ),
        ]

        for sub in node["subcommands"] as? [[String: Any]] ?? [] {
            // `help` is the parser's own, and describing it says nothing about
            // this tool.
            guard sub["commandName"] as? String != "help" else { continue }
            described += walk(sub, path: here)
        }
        return described
    }

    static func arguments(in node: [String: Any]) -> [DescribedArgument] {
        (node["arguments"] as? [[String: Any]] ?? []).compactMap { item in
            let kind = item["kind"] as? String ?? "option"

            let names = (item["names"] as? [[String: Any]] ?? []).compactMap { name -> String? in
                guard let value = name["name"] as? String else { return nil }
                return (name["kind"] as? String) == "short" ? "-\(value)" : "--\(value)"
            }

            // A positional has no flag names; it is identified by its value name.
            let identifier = names.first { $0.hasPrefix("--") }
                ?? names.first
                ?? (item["valueName"] as? String)
            guard let identifier else { return nil }

            return DescribedArgument(
                kind: kind,
                name: identifier,
                short: names.first { $0.hasPrefix("-") && !$0.hasPrefix("--") },
                summary: (item["abstract"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                valueName: item["valueName"] as? String,
                required: (item["isOptional"] as? Bool).map { !$0 } ?? false,
                repeating: (item["isRepeating"] as? Bool) ?? false
            )
        }
    }

    // MARK: Capture

    /// ArgumentParser's own `--experimental-dump-help`, read from a second
    /// copy of this binary.
    ///
    /// Asking for it in-process does not work: the parser answers that flag by
    /// throwing, so the dump is printed by the top-level handler rather than by
    /// anything this command can capture. Running ourselves costs one fork and
    /// is reliable, and `describe` is not a hot path.
    static func dumpedTree() throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--experimental-dump-help"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ValidationError("Could not describe this tool: \(error.localizedDescription)")
        }

        let captured = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let object = try? JSONSerialization.jsonObject(with: captured) as? [String: Any] else {
            throw ValidationError("Could not read the parser's own help dump.")
        }
        return object
    }
}

// MARK: - Shapes

/// The whole tool, as an agent reads it.
struct Described: Encodable {
    let tool: String
    let version: String
    let summary: String
    let requiresAuth: Bool
    let commands: [DescribedCommand]
}

struct DescribedCommand: Encodable {
    let invocation: String
    let path: [String]
    let summary: String
    let details: String?
    let arguments: [DescribedArgument]
}

struct DescribedArgument: Encodable {
    let kind: String
    let name: String
    let short: String?
    let summary: String?
    let valueName: String?
    let required: Bool
    let repeating: Bool
}
