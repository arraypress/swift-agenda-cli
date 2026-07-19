//
//  Agenda.swift
//  SwiftAgenda
//
//  The `Agenda` namespace and its EventKit store / authorization primitives.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// A read/write wrapper over EventKit's calendar and reminder stores.
///
/// `Agenda` is a namespace (a caseless `enum`) — you never instantiate it; call the
/// static methods directly:
///
/// ```swift
/// import AgendaKit
///
/// try await Agenda.requestAccess(to: .event)
/// for event in try Agenda.events(from: .now, to: .now.addingTimeInterval(86_400)) {
///     print(event.title, event.startsAt)
/// }
/// ```
///
/// Every read returns a `Codable` value type (``AgendaEvent``, ``AgendaReminder``)
/// rather than an `EKObject`, so results survive the store going out of scope and
/// serialize without a formatting pass.
///
/// The operations are grouped across the package:
/// - Events: ``events(from:to:calendars:)``, ``event(id:)``
/// - Reminders: ``reminders(matching:)``
/// - Free time: ``freeSlots(ofAtLeast:from:through:within:)``
/// - Writes: ``createEvent(_:)``, ``updateEvent(id:with:)``, ``deleteEvent(id:span:)``
///
/// - Important: Authorization is never implicit. Every read throws
///   ``AgendaError/accessDenied(_:)`` when the relevant entity is not authorized,
///   so a permission failure can never be mistaken for an empty calendar.
public enum Agenda {

    /// The process-wide EventKit store.
    ///
    /// EventKit caches aggressively per-instance and a CLI process is short-lived,
    /// so one shared store is both correct and cheapest. Long-running hosts should
    /// observe `.EKEventStoreChanged` and call ``reset()`` on change.
    public static let store = EKEventStore()

    /// The calendar used for every date calculation in this package.
    ///
    /// Defaults to `Calendar.current`. Point it at a fixed time zone to compute
    /// against somewhere other than where the machine is:
    ///
    /// ```swift
    /// var tokyo = Calendar(identifier: .gregorian)
    /// tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    /// Agenda.calendar = tokyo
    /// ```
    ///
    /// - Important: Day boundaries, working-hour clipping, and all-day handling all
    ///   read this. Setting it mid-run changes what "today" means.
    public nonisolated(unsafe) static var calendar = Calendar.current

    // MARK: - Authorization

    /// The current authorization status for `entity`, without prompting.
    public static func access(to entity: EKEntityType) -> AgendaAccess {
        AgendaAccess(EKEventStore.authorizationStatus(for: entity))
    }

    /// Requests full access to `entity`, prompting the user on first call.
    ///
    /// Presenting the prompt requires the binary to carry the matching usage string
    /// (`NSCalendarsFullAccessUsageDescription` / `NSRemindersFullAccessUsageDescription`).
    /// Without it the system denies silently — which surfaces here as a throw, not a
    /// quiet `false`.
    ///
    /// - Parameter entity: `.event` for calendars, `.reminder` for reminders.
    /// - Throws: ``AgendaError/accessDenied(_:)`` when the user declines or no usage
    ///   string is embedded.
    @discardableResult
    public static func requestAccess(to entity: EKEntityType) async throws -> AgendaAccess {
        let granted: Bool
        switch entity {
        case .event:    granted = (try? await store.requestFullAccessToEvents()) ?? false
        case .reminder: granted = (try? await store.requestFullAccessToReminders()) ?? false
        @unknown default: granted = false
        }
        guard granted else { throw AgendaError.accessDenied(entity) }
        return .authorized
    }

    /// Throws unless `entity` is already authorized. Use to guard a read without prompting.
    public static func requireAccess(to entity: EKEntityType) throws {
        guard access(to: entity) == .authorized else {
            throw AgendaError.accessDenied(entity)
        }
    }

    /// Drops EventKit's cached objects so the next read reflects external edits.
    public static func reset() {
        store.reset()
    }

    // MARK: - Calendars

    /// Every calendar holding `entity`, sorted by title.
    ///
    /// - Throws: ``AgendaError/accessDenied(_:)`` when `entity` is not authorized.
    public static func calendars(for entity: EKEntityType) throws -> [AgendaCalendar] {
        try requireAccess(to: entity)
        let defaultId = (entity == .reminder
            ? store.defaultCalendarForNewReminders()
            : store.defaultCalendarForNewEvents)?.calendarIdentifier

        return store.calendars(for: entity)
            .map { AgendaCalendar($0, isDefault: $0.calendarIdentifier == defaultId) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Resolves `names` to `EKCalendar`s by title or identifier, case-insensitively.
    ///
    /// - Parameters:
    ///   - names: Calendar titles or identifiers. Empty means "all calendars".
    ///   - entity: The entity type the calendars must hold.
    /// - Returns: `nil` when `names` is empty, which EventKit predicates read as
    ///   "search everything".
    /// - Throws: ``AgendaError/unknownCalendar(_:)`` when a name matches nothing —
    ///   a typo'd `--calendar` returning zero events is indistinguishable from a
    ///   genuinely empty range, so it fails loudly instead.
    static func resolveCalendars(_ names: [String], for entity: EKEntityType) throws -> [EKCalendar]? {
        guard !names.isEmpty else { return nil }
        let available = store.calendars(for: entity)
        var resolved: [EKCalendar] = []
        for name in names {
            let match = available.first {
                $0.title.compare(name, options: .caseInsensitive) == .orderedSame
                    || $0.calendarIdentifier == name
            }
            guard let match else { throw AgendaError.unknownCalendar(name) }
            resolved.append(match)
        }
        return resolved
    }
}
