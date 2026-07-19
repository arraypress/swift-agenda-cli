//
//  JSONRPC.swift
//  agenda
//
//  Minimal JSON-RPC 2.0 over stdio — the transport MCP speaks.
//
//  Created by David Sherlock on 7/19/26.
//

import Foundation

/// A loosely-typed JSON value.
///
/// MCP tool arguments are free-form by design — the schema lives in the tool
/// definition, not the wire type — so decoding into a concrete `Codable` per tool
/// would mean a type per tool and a decode failure surfacing as a transport error
/// rather than a helpful message back to the model.
enum JSONValue: Codable, Equatable {

    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:            try container.encodeNil()
        case .bool(let v):     try container.encode(v)
        case .number(let v):   try container.encode(v)
        case .string(let v):   try container.encode(v)
        case .array(let v):    try container.encode(v)
        case .object(let v):   try container.encode(v)
        }
    }

    /// The value as a string, coercing numbers and booleans.
    ///
    /// Models pass `"limit": 5` and `"limit": "5"` interchangeably; refusing one of
    /// them produces a retry loop rather than an answer.
    var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .number(let v): return v == v.rounded() ? String(Int(v)) : String(v)
        case .bool(let v):   return String(v)
        default:             return nil
        }
    }

    /// The value as an integer, accepting a numeric string.
    var intValue: Int? {
        switch self {
        case .number(let v): return Int(v)
        case .string(let v): return Int(v)
        default:             return nil
        }
    }

    /// The value as a boolean, accepting `"true"`/`"false"`.
    var boolValue: Bool? {
        switch self {
        case .bool(let v):   return v
        case .string(let v): return ["true", "yes", "1"].contains(v.lowercased())
        case .number(let v): return v != 0
        default:             return nil
        }
    }

    /// The value as a list of strings, accepting a bare string as a single-item list.
    var stringArray: [String] {
        switch self {
        case .array(let items): return items.compactMap(\.stringValue)
        case .string(let v):    return [v]
        default:                return []
        }
    }

    /// Member lookup for object values.
    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }
}

/// An incoming JSON-RPC request.
///
/// `id` is absent for notifications, which must not be answered — replying to one is
/// a protocol violation that some clients treat as fatal.
struct RPCRequest: Decodable {
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

/// A JSON-RPC error payload.
struct RPCError: Encodable {
    let code: Int
    let message: String

    /// The method is not implemented by this server.
    static func methodNotFound(_ method: String) -> RPCError {
        RPCError(code: -32601, message: "Unknown method \"\(method)\".")
    }

    /// The request was structurally valid but semantically wrong.
    static func invalidParams(_ message: String) -> RPCError {
        RPCError(code: -32602, message: message)
    }
}

/// An outgoing JSON-RPC response.
struct RPCResponse: Encodable {
    let jsonrpc = "2.0"
    let id: JSONValue?
    var result: JSONValue?
    var error: RPCError?
}

/// Reads newline-delimited JSON-RPC from stdin and writes replies to stdout.
///
/// MCP's stdio transport frames messages by newline, not by `Content-Length` headers
/// as LSP does.
///
/// - Important: Nothing else may be written to stdout — a stray `print` corrupts the
///   stream and the client drops the connection. Diagnostics go to stderr.
enum StdioTransport {

    /// Reads requests until stdin closes, passing each to `handle`.
    ///
    /// A handler returning nil means "this was a notification", and nothing is sent.
    static func serve(_ handle: (RPCRequest) async -> RPCResponse?) async {
        let decoder = JSONDecoder()

        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            guard let request = try? decoder.decode(RPCRequest.self, from: data) else {
                // Malformed input is skipped rather than fatal: one bad frame should
                // not take down a long-lived session.
                log("skipped unparseable frame")
                continue
            }
            if let response = await handle(request) { send(response) }
        }
    }

    /// Writes one response frame.
    static func send(_ response: RPCResponse) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(response),
              let text = String(data: data, encoding: .utf8) else {
            log("failed to encode a response")
            return
        }
        print(text)
        fflush(stdout)
    }

    /// Writes a diagnostic to stderr, where it cannot corrupt the protocol stream.
    static func log(_ message: String) {
        FileHandle.standardError.write("[agenda mcp] \(message)\n".data(using: .utf8)!)
    }
}
