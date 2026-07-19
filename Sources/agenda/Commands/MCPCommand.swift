//
//  MCPCommand.swift
//  agenda
//
//  `agenda mcp` — serve the Model Context Protocol over stdio.
//
//  Created by David Sherlock on 7/19/26.
//

import ArgumentParser
import Foundation

struct MCPCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve calendar and reminder tools over MCP (stdio).",
        discussion: """
            Not run by hand — an MCP client launches it. Register with Claude Code:

              claude mcp add agenda -- agenda mcp

            Or in .mcp.json:

              { "mcpServers": { "agenda": { "command": "agenda", "args": ["mcp"] } } }

            Exposes five tools: agenda_query, agenda_search, agenda_create, \
            agenda_update, agenda_delete. Diagnostics go to stderr; stdout carries \
            protocol frames only.
            """
    )

    func run() async throws {
        await MCPServer.run()
    }
}
