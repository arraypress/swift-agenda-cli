//
//  Agenda+Duration.swift
//  SwiftAgenda
//
//  Human duration and date parsing for the command surface.
//
//  Created by David Sherlock on 7/19/26.
//

import Foundation

extension Agenda {

    /// Seconds per unit suffix, longest suffix first so `mo` wins over `m`.
    ///
    /// Months and years are nominal — 30 and 365 days. That is wrong for calendar
    /// arithmetic and right for the search and lookahead windows these feed, where
    /// "roughly a year out" is the whole intent. Anything needing exact month
    /// boundaries should use ``date(_:)`` and a real range.
    private static let durationUnits: [(suffix: String, seconds: TimeInterval)] = [
        ("mo", 2_592_000),
        ("y",  31_536_000),
        ("w",  604_800),
        ("d",  86_400),
        ("h",  3_600),
        ("m",  60)
    ]

    /// Parses a compact duration like `30m`, `4h`, `7d`, `2w`, `6mo`, `1y` into seconds.
    ///
    /// ```swift
    /// try Agenda.duration("90m")   // 5400
    /// try Agenda.duration("2w")    // 1209600
    /// try Agenda.duration("6mo")   // ~6 months
    /// ```
    ///
    /// Relative forms are used rather than absolute timestamps because callers — and
    /// especially agents — reliably get "seven days from now" right and reliably get
    /// date arithmetic wrong.
    ///
    /// - Parameter raw: A positive number followed by `m`, `h`, `d`, `w`, `mo`, or `y`.
    ///   A bare number is read as minutes. Note `m` is minutes and `mo` is months.
    /// - Throws: ``AgendaError/badDuration(_:)`` on anything else.
    public static func duration(_ raw: String) throws -> TimeInterval {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { throw AgendaError.badDuration(raw) }

        // A bare number means minutes.
        if let bare = Double(text) {
            guard bare > 0 else { throw AgendaError.badDuration(raw) }
            return bare * 60
        }

        for (suffix, seconds) in durationUnits where text.hasSuffix(suffix) {
            let digits = String(text.dropLast(suffix.count))
            guard let value = Double(digits), value > 0 else { throw AgendaError.badDuration(raw) }
            return value * seconds
        }
        throw AgendaError.badDuration(raw)
    }

    /// Parses a date, accepting both plain-language and ISO 8601 forms.
    ///
    /// Relative phrases are tried first — `now`, `today`, `tomorrow`, `next friday`,
    /// `+2d`, and any of those with a time (`tomorrow 9am`). See
    /// ``relativeDate(_:)`` for the full grammar.
    ///
    /// Failing that, `2026-07-19` resolves to the start of that day and
    /// `2026-07-19T14:00` to that wall-clock time — both in ``Agenda/calendar``'s
    /// zone, not the machine's. A trailing `Z` or explicit offset overrides that and
    /// is honoured as written.
    ///
    /// ```swift
    /// try Agenda.date("tomorrow 9am")
    /// try Agenda.date("2026-07-19")            // midnight, in Agenda.calendar's zone
    /// try Agenda.date("2026-07-19T12:00:00Z")  // noon UTC, regardless of zone
    /// ```
    ///
    /// - Throws: ``AgendaError/badDate(_:)`` when no format matches.
    public static func date(_ raw: String) throws -> Date {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let zone = calendar.timeZone

        // Relative phrases go first: they are unambiguous, and an ISO date can never
        // look like one.
        if let relative = relativeDate(text) { return relative }

        // Only try the ISO parser on input that actually carries a zone designator.
        // Left to itself it assumes UTC for zone-less input, which would silently
        // shift every bare wall-clock time by the local offset.
        if text.hasSuffix("Z") || text.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let parsed = iso.date(from: text) { return parsed }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.calendar = calendar
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: text) { return parsed }
        }
        throw AgendaError.badDate(raw)
    }
}
