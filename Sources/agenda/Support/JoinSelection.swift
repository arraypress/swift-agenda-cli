//
//  JoinSelection.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  Which call `agenda join` means when it is not given an id.
//
//  THE QUESTION BEHIND A BARE `agenda join` IS "WHICH CALL AM I DUE ON", and two windows
//  answer it: a call already running, and one starting within the next quarter of an hour.
//  Anything further out is not something you join, it is something you look up — that is
//  `agenda events`. Fifteen minutes is the default and `--within` moves it.
//
//  WHEN TWO QUALIFY, THE NEAREST START WINS. The common collision is a meeting overrunning
//  into the next one: at 10:52, in a call that began at 10:00, with another at 10:55, the
//  one you mean is the one about to start. At 10:05, with the next at 10:15, it is the one
//  you are in. Distance from the start answers both; a tie goes to the call not yet begun.
//
//  NOT EVERY EVENT WITH A LINK IS A CALL YOU ARE GOING TO. All-day markers, cancelled
//  invitations and anything you declined are skipped — the same events that do not consume
//  free time in `agenda free` — so a declined clash never gets joined in place of the
//  meeting you accepted.
//

import AgendaKit
import Foundation

enum JoinSelection {

    /// How far ahead a bare `agenda join` looks for a call that has not started yet.
    static let defaultLookahead: TimeInterval = 15 * 60

    /// Whether `event` is a call that could be joined at `now`: it has a video call, is
    /// still running, and starts no later than `lookahead` from now.
    static func isJoinable(_ event: AgendaEvent, at now: Date, lookahead: TimeInterval) -> Bool {
        guard event.videoCall != nil, !event.isAllDay,
              event.status != .canceled, !event.isDeclinedByMe else { return false }
        return event.endsAt > now && event.startsAt <= now.addingTimeInterval(lookahead)
    }

    /// The call to join among `events`, or `nil` when none qualifies.
    ///
    /// Of the joinable events, the one whose start is nearest to `now`; on a tie, the one
    /// not yet started, then the earlier start.
    static func pick(from events: [AgendaEvent], at now: Date,
                     lookahead: TimeInterval = defaultLookahead) -> AgendaEvent? {
        events
            .filter { isJoinable($0, at: now, lookahead: lookahead) }
            .min { rank($0, at: now) < rank($1, at: now) }
    }

    /// Sort key: distance from now, then started-or-not, then start.
    private static func rank(_ event: AgendaEvent, at now: Date) -> (TimeInterval, Int, Date) {
        let distance = abs(event.startsAt.timeIntervalSince(now))
        return (distance, event.startsAt >= now ? 0 : 1, event.startsAt)
    }
}
