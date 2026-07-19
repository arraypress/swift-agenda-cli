//
//  Agenda+MeetingURL.swift
//  SwiftAgenda
//
//  Digging the video-call link out of an event's free-text fields.
//
//  Created by David Sherlock on 7/19/26.
//

import Foundation

extension Agenda {

    /// Video-call URL shapes, most specific first.
    ///
    /// Ordered so a Zoom link inside a body of text wins over the generic fallback,
    /// and so an event carrying both a dial-in note and a real link resolves to the
    /// link.
    private static let meetingPatterns = [
        #"https://[\w.-]*zoom\.us/[\w/?=&.-]+"#,
        #"https://teams\.microsoft\.com/[\w/?=&%.#-]+"#,
        #"https://teams\.live\.com/[\w/?=&%.#-]+"#,
        #"https://meet\.google\.com/[\w-]+"#,
        #"https://[\w.-]*webex\.com/[\w/?=&.-]+"#,
        #"https://[\w.-]*gotomeeting\.com/[\w/?=&.-]+"#,
        #"https://[\w.-]*bluejeans\.com/[\w/?=&.-]+"#,
        #"https://whereby\.com/[\w-]+"#,
        #"https://meet\.jit\.si/[\w-]+"#
    ]

    /// The first video-call link found across an event's text fields.
    ///
    /// Searches notes, location, and the URL field together — organizers put the link
    /// in whichever one their client chose, and there is no reliable convention.
    ///
    /// - Returns: The matched URL, the raw `url` field when nothing matches but a URL
    ///   exists, or `nil` when the event has no link at all.
    public static func meetingURL(notes: String?, location: String?, url: String?) -> String? {
        let haystack = [notes, location, url].compactMap { $0 }.joined(separator: " ")
        guard !haystack.isEmpty else { return nil }

        let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
        for pattern in meetingPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: haystack, options: [], range: range),
                  let matched = Range(match.range, in: haystack) else { continue }
            return String(haystack[matched])
        }
        return url?.nilIfBlank
    }
}
