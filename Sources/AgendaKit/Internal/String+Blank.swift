//
//  String+Blank.swift
//  SwiftAgenda
//
//  Collapsing EventKit's empty strings into nil.
//
//  Created by David Sherlock on 7/19/26.
//

import Foundation

extension String {

    /// `nil` when this is empty or only whitespace, otherwise the trimmed string.
    ///
    /// EventKit returns `""` rather than nil for untouched text fields, which would
    /// otherwise encode as empty JSON keys on nearly every event.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
