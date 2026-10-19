//
//  StoreTests.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  Tags, sections, subtasks and smart lists on the way out — and tag writes,
//  with Shortcuts and the store both faked.
//
//  NOTHING HERE TOUCHES REMINDERS. The store contents are built by hand, a
//  "missing" store is a folder that does not exist, and the tag writer runs a
//  closure that edits a dictionary instead of a shortcut.
//

import AgendaKit
import AppleShortcuts
import CLIKit
import Foundation
import XCTest
@testable import agenda

private let token = "0123456789abcdef"
private let on = UntrustedPolicy(isEnabled: true, token: token)
private let off = UntrustedPolicy(isEnabled: false, token: token)

private func capture(_ body: () throws -> Void) rethrows -> String {
    let pipe = Pipe()
    let saved = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    try body()
    fflush(stdout)
    dup2(saved, STDOUT_FILENO)
    close(saved)
    try? pipe.fileHandleForWriting.close()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

private func reminder(_ id: String, _ title: String = "Task") -> AgendaReminder {
    AgendaReminder(id: id, title: title, list: "Home")
}

/// Parent P with child C, grandchild G; S in Produce; T in Dairy; L loose; O's parent absent.
private func contents() -> ReminderStoreContents {
    let details = [
        ReminderStoreDetails(id: "P", tags: ["Errands", "home"], section: "Produce", sectionID: "S1"),
        ReminderStoreDetails(id: "C", tags: [], parentID: "P"),
        ReminderStoreDetails(id: "G", tags: ["Café"], parentID: "C"),
        ReminderStoreDetails(id: "S", tags: ["work"], section: "Produce", sectionID: "S1"),
        ReminderStoreDetails(id: "T", tags: [], section: "Dairy", sectionID: "S2"),
        ReminderStoreDetails(id: "L"),
        ReminderStoreDetails(id: "O", parentID: "ABSENT"),
    ]
    return ReminderStoreContents(
        reminders: Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) }),
        sections: [ReminderSection(id: "S2", name: "Dairy", listID: "Home"),
                   ReminderSection(id: "S1", name: "Produce", listID: "Home")],
        smartLists: [SmartList(id: "X", name: "Focus <|im_start|>", kind: "custom", rules: ["hashtags.hashtags: work"])],
        modelVersion: "v2026_A", isKnownVersion: true, storeCount: 1)
}

final class ReminderTreeTests: XCTestCase {

    func testTagFiltersMatchAnyIgnoringCaseAccentsAndHash() {
        let all = ["P", "C", "G", "S", "T", "L"].map { reminder($0) }
        XCTAssertEqual(ReminderTree.filter(all, tags: ["#errands"], sections: [], store: contents()).map(\.id), ["P"])
        XCTAssertEqual(ReminderTree.filter(all, tags: ["cafe", "WORK"], sections: [], store: contents()).map(\.id), ["G", "S"])
        XCTAssertEqual(ReminderTree.filter(all, tags: [], sections: ["produce"], store: contents()).map(\.id), ["P", "S"])
        XCTAssertEqual(ReminderTree.filter(all, tags: ["work"], sections: ["Dairy"], store: contents()).map(\.id), [])
        XCTAssertEqual(ReminderTree.filter(all, tags: [], sections: [], store: nil).count, 6, "no filter, no store needed")
        XCTAssertEqual(ReminderTree.filter(all, tags: ["work"], sections: [], store: nil), [], "unknown tags match nothing")
    }

    func testSubtasksPrintUnderTheirParent() {
        let order = ["G", "S", "C", "P", "O", "L"].map { reminder($0) }
        let placed = ReminderTree.nest(order, store: contents())
        XCTAssertEqual(placed.map(\.reminder.id), ["S", "P", "C", "G", "O", "L"])
        XCTAssertEqual(placed.map(\.depth), [0, 0, 1, 2, 0, 0])
        XCTAssertEqual(ReminderTree.nest(order, store: nil).map(\.depth), [0, 0, 0, 0, 0, 0])
    }

    func testACycleLosesNothing() {
        let store = ReminderStoreContents(
            reminders: ["A": ReminderStoreDetails(id: "A", parentID: "B"), "B": ReminderStoreDetails(id: "B", parentID: "A")],
            sections: [], smartLists: [], modelVersion: nil, isKnownVersion: true, storeCount: 1)
        XCTAssertEqual(Set(ReminderTree.nest([reminder("A"), reminder("B")], store: store).map(\.reminder.id)), ["A", "B"])
    }

    func testGroupsPutLooseFirstThenSectionsInStoreOrder() {
        let placed = ReminderTree.nest(["S", "P", "C", "T", "L"].map { reminder($0) }, store: contents())
        let groups = ReminderTree.group(placed, store: contents())
        XCTAssertEqual(groups.map(\.section), [nil, "Dairy", "Produce"])
        XCTAssertEqual(groups.map { $0.reminders.map(\.reminder.id) }, [["L"], ["T"], ["S", "P", "C"]],
                       "a subtask goes with its parent's section")
    }
}

final class StorePayloadTests: XCTestCase {

    func testJSONCarriesFencedTagsSectionAndParent() throws {
        let store = contents()
        let child = try capture {
            try Emitter(format: .json, untrusted: on).emit(ReminderPayload(reminder("G"), details: store.details(for: "G")))
        }
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(child.utf8)) as? [String: Any])
        XCTAssertEqual(object["tags"] as? [String], [Untrusted.wrap("Café", token: token)])
        XCTAssertEqual(object["parentID"] as? String, "C", "an id is handed back, never fenced")
        XCTAssertNil(object["section"])

        let parent = try capture {
            try Emitter(format: .json, untrusted: on).emit(ReminderPayload(reminder("P"), details: store.details(for: "P")))
        }
        XCTAssertTrue(parent.contains("\"section\":\"\(Untrusted.wrap("Produce", token: token))\""), parent)
    }

    func testWithoutTheStoreTheKeysAreAbsentNotEmpty() throws {
        let output = try capture { try Emitter(format: .json, untrusted: off).emit(ReminderPayload(reminder("P"))) }
        XCTAssertFalse(output.contains("\"tags\""), output)
        let known = try capture {
            try Emitter(format: .json, untrusted: off).emit(ReminderPayload(reminder("L"), details: contents().details(for: "L")))
        }
        XCTAssertTrue(known.contains("\"tags\":[]"), "read, and none: an empty list")
    }

    func testTextShowsTagsSectionAndIndentsSubtasks() throws {
        let store = contents()
        let text = try capture {
            try Emitter(format: .text, untrusted: off).emitAll([
                ReminderPayload(reminder("P", "Shop"), details: store.details(for: "P")),
                ReminderPayload(reminder("C", "Fruit"), details: store.details(for: "C"), depth: 1),
            ])
        }
        XCTAssertTrue(text.contains("[ ]  Shop  #Errands #home  § Produce  [Home]"), text)
        XCTAssertTrue(text.contains("\n  ↳ [ ]  Fruit  [Home]\n        C"), text)

        let fenced = try capture {
            try Emitter(format: .text, untrusted: on).emit(ReminderPayload(reminder("P", "Shop"), details: store.details(for: "P")))
        }
        XCTAssertTrue(fenced.contains(Untrusted.wrap("#Errands #home", token: token)), fenced)
        XCTAssertTrue(fenced.contains("§ \(Untrusted.wrap("Produce", token: token))"), fenced)
    }

    func testSearchHitsCarryTheStoreToo() throws {
        let output = try capture {
            try Emitter(format: .json, untrusted: off).emitAll([SearchPayload(.reminder(reminder("S")), store: contents())])
        }
        XCTAssertTrue(output.contains("\"tags\":[\"work\"]"), output)
    }

    func testSmartListsAreFencedWholeNameAndRules() throws {
        let output = try capture {
            try Emitter(format: .json, untrusted: on).emitAll(contents().smartLists.map(SmartListPayload.init))
        }
        XCTAssertFalse(output.contains("<|im_start|>"), output)
        XCTAssertTrue(output.contains(Untrusted.wrap("hashtags.hashtags: work", token: token)), output)
        XCTAssertTrue(output.contains("\"id\":\"X\""), output)
    }

    func testTagCountsFoldSpellingsAndSortByUse() {
        var store = contents().reminders
        store["L"] = ReminderStoreDetails(id: "L", tags: ["WORK"])
        let contents = ReminderStoreContents(reminders: store, sections: [], smartLists: [], modelVersion: nil,
                                             isKnownVersion: true, storeCount: 1)
        let counts = TagCount.tally(["P", "S", "L", "G", "NOT-IN-STORE"].map { reminder($0) }, store: contents)
        XCTAssertEqual(counts.first, TagCount(tag: "work", reminders: 2))
        XCTAssertEqual(counts.dropFirst().map(\.tag), ["Café", "Errands", "home"])
    }
}

final class StoreDegradeTests: XCTestCase {

    func testAMissingStoreIsANoteNotAFailure() throws {
        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent("agenda-none-\(UUID().uuidString)")
        let store = StoreDetails.load(from: nowhere)
        XCTAssertNil(store.contents)
        XCTAssertTrue(store.note?.contains("without tags, sections or subtasks") ?? false, store.note ?? "")
        XCTAssertThrowsError(try store.require(for: "--tag")) {
            XCTAssertEqual(($0 as? CLIError)?.code.exitCode.rawValue, 5)
        }
    }

    func testRefusedAccessIsExitThreeWithTheFix() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agenda-shut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let store = StoreDetails.load(from: folder)
        XCTAssertTrue(store.note?.contains("Full Disk Access") ?? false, store.note ?? "")
        XCTAssertThrowsError(try store.require(for: "--tag")) {
            let error = $0 as? CLIError
            XCTAssertEqual(error?.code.exitCode.rawValue, 3)
            XCTAssertTrue(error?.hint?.contains("Full Disk Access") ?? false)
        }
    }

    func testAnUnverifiedVersionIsSaidButRead() {
        let newer = StoreDetails.read(ReminderStoreContents(reminders: [:], sections: [], smartLists: [],
                                                            modelVersion: "v2027_A", isKnownVersion: false, storeCount: 1))
        XCTAssertTrue(newer.note?.contains("v2027_A") ?? false)
        XCTAssertNoThrow(try newer.require(for: "--tag"))
        XCTAssertNil(StoreDetails.read(contents()).note)
    }
}

final class TagWriteTests: XCTestCase {

    func testTheTargetIsCurrentPlusAddMinusRemove() {
        let plan = TagPlan.make(current: ["Work", "home"], add: ["#work", "errands", " errands ", "", "Errands"],
                                remove: ["HOME", "absent"])
        XCTAssertEqual(plan.before, ["Work", "home"])
        XCTAssertEqual(plan.target, ["Work", "errands"], "existing spelling kept, repeats folded, removals dropped")
        XCTAssertTrue(TagPlan.make(current: ["a"], add: ["A"], remove: ["b"]).isEmpty)
        XCTAssertEqual(TagPlan.make(current: [], add: ["x", "#y"], remove: []).target, ["x", "y"], "a new reminder: just the given tags")
        XCTAssertEqual(TagPlan.make(current: ["only"], add: [], remove: ["only"]).target, [])
    }

    func testSameMeansExactlyTheseTags() {
        XCTAssertTrue(TagPlan.same(["B", "a"], ["A", "b"]))
        XCTAssertFalse(TagPlan.same(["a", "b", "c"], ["a", "b"]), "one more is not the same")
        XCTAssertFalse(TagPlan.same(["a"], ["a", "b"]), "one fewer is not the same")
        XCTAssertFalse(TagPlan.same(["a", "a"], ["a"]))
    }

    /// A fake helper over a fake store. By default it does what a SET does.
    private final class Fake: @unchecked Sendable {
        var tags: [String: [String]] = ["R": ["Hello", "David", "It", "works"]]
        var inputs: [[String: Any]] = []
        var effect: ([String], inout [String]) throws -> Void = { given, tags in tags = given }

        var found: [String] = ["Call Bob"]
        func writer() -> TagWriter {
            var writer = TagWriter()
            writer.check = { [self] _ in found }
            writer.run = { [self] given in
                // The input as the helper would get it: through its JSON.
                let data = try JSONEncoder().encode(given)
                let input = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                inputs.append(input)
                var current = tags["R"] ?? []
                defer { tags["R"] = current }     // what a failing shortcut did still stands
                try effect(input["tags"] as? [String] ?? [], &current)
            }
            writer.readTags = { [self] id in tags[id] }
            writer.attempts = 4
            writer.interval = 0.001
            return writer
        }
    }

    func testOneSetCarriesTheWholeListAndIsReadBack() throws {
        let fake = Fake()
        let plan = TagPlan.make(current: fake.tags["R"]!, add: ["tested"], remove: [])
        XCTAssertEqual(try fake.writer().apply(plan, id: "R", title: "Hello Claude"), ["Hello", "David", "It", "works", "tested"])
        XCTAssertEqual(fake.inputs.count, 1)
        XCTAssertEqual(fake.inputs.first?["title"] as? String, "Hello Claude")
        XCTAssertEqual(fake.inputs.first?["tags"] as? [String], ["Hello", "David", "It", "works", "tested"])
    }

    func testAnAddThatReplacesIsCaught() {
        // What "Edit Reminder" in Add mode did live: the given tags replaced the rest.
        let fake = Fake()
        fake.effect = { _, tags in tags = ["tested"] }
        let plan = TagPlan.make(current: fake.tags["R"]!, add: ["tested"], remove: [])
        XCTAssertThrowsError(try fake.writer().apply(plan, id: "R", title: "x")) {
            let error = $0 as? CLIError
            XCTAssertEqual(error?.code.exitCode.rawValue, 5)
            XCTAssertEqual(error?.retry, .mayHaveCompleted)
            XCTAssertTrue(error?.message.contains("expected #Hello #David #It #works #tested, the store shows #tested") ?? false,
                          error?.message ?? "")
        }
    }

    func testOneTagTooManyIsNotSuccess() {
        let fake = Fake()
        fake.effect = { given, tags in tags = given + ["extra"] }
        XCTAssertThrowsError(try fake.writer().apply(TagPlan.make(current: ["a"], add: ["b"], remove: []), id: "R", title: "x"))
    }

    func testNothingLandingIsSafeToRetry() {
        let fake = Fake()
        fake.effect = { _, _ in }
        XCTAssertThrowsError(try fake.writer().apply(TagPlan.make(current: fake.tags["R"]!, add: ["new"], remove: []), id: "R", title: "x")) {
            let error = $0 as? CLIError
            XCTAssertEqual(error?.code.exitCode.rawValue, 5)
            XCTAssertEqual(error?.retry, .notStarted)
            XCTAssertTrue(error?.message.contains("Nothing changed") ?? false, error?.message ?? "")
        }
    }

    func testATimedOutRunMayHaveCompletedEvenIfNothingShows() {
        let fake = Fake()
        fake.effect = { _, _ in throw ShortcutsError.timedOut("agenda set tags", seconds: 30) }
        XCTAssertThrowsError(try fake.writer().apply(TagPlan.make(current: fake.tags["R"]!, add: ["new"], remove: []), id: "R", title: "x")) {
            XCTAssertEqual(($0 as? CLIError)?.retry, .mayHaveCompleted)
        }
    }

    func testAFailedRunThatLandedAnywayIsBelieved() throws {
        let fake = Fake()
        fake.effect = { given, tags in tags = given; throw ShortcutsError.runFailed("exit 1") }
        XCTAssertEqual(try fake.writer().apply(TagPlan.make(current: ["old"], add: ["new"], remove: []), id: "R", title: "x"),
                       ["old", "new"])
    }

    func testASharedTitleIsRefusedBeforeAnythingRuns() {
        let mine = AgendaReminder(id: "R", title: "Call Bob", list: "Home")
        let twin = AgendaReminder(id: "Q", title: " call bob", list: "Work", isCompleted: true)
        XCTAssertNoThrow(try TitleMatch.requireUnique("Call Bob", id: "R", in: [mine]))
        XCTAssertThrowsError(try TitleMatch.requireUnique("Call Bob", id: "R", in: [mine, twin])) {
            let error = $0 as? CLIError
            XCTAssertEqual(error?.code.exitCode.rawValue, 2)
            XCTAssertEqual(error?.retry, .notStarted)
        }
        XCTAssertThrowsError(try TitleMatch.requireUnique("Call Bob", id: nil, in: [mine]), "a new one would share it")
        XCTAssertNoThrow(try TitleMatch.requireUnique("Call Alice", id: nil, in: [mine]))
    }

    func testTheHelperSetsAndNeverAdds() throws {
        let helper = try TagShortcuts.helper
        let recipe = helper.recipe
        XCTAssertEqual(recipe.name, "agenda · Set Tags")
        XCTAssertEqual(helper.version, 1)
        XCTAssertEqual(recipe.actions.first?.action, "is.workflow.actions.comment", "the marker comes first")
        XCTAssertEqual(recipe.actions.last?.action, "is.workflow.actions.nothing", "no output, so no output prompt")
        XCTAssertFalse(recipe.actions.contains { $0.action == "com.apple.reminders.AddOrRemoveTagsAppIntent" },
                       "refused on import on the Mac")
        let edit = try XCTUnwrap(recipe.actions.first { $0.action == "is.workflow.actions.setters.reminders" })
        XCTAssertEqual(edit.parameters["Mode"], .string("Set"), "Add mode replaces, measured")
        XCTAssertEqual(edit.parameters["WFContentItemPropertyName"], .string("Tags"))
        guard case .dictionary(let tags)? = edit.parameters["WFReminderContentItemTags"],
              case .dictionary(let value)? = tags["Value"] else { return XCTFail("tags are not the variable") }
        XCTAssertEqual(value["VariableName"], .string("agendaTags"))
        let find = try XCTUnwrap(recipe.actions.first { $0.action == "is.workflow.actions.filter.reminders" })
        guard case .dictionary(let filter)? = find.parameters["WFContentItemFilter"],
              case .dictionary(let predicate)? = filter["Value"],
              case .array(let templates)? = predicate["WFActionParameterFilterTemplates"],
              case .dictionary(let only)? = templates.first else { return XCTFail("no title filter") }
        XCTAssertEqual(only["Property"], .string("Title"))
        XCTAssertEqual(only["Operator"], .integer(4))
        XCTAssertEqual(TagShortcuts.input(title: "Call \"Bob\"", tags: ["a", "b"]),
                       ["title": .string("Call \"Bob\""), "tags": .array([.string("a"), .string("b")])])
        XCTAssertEqual(Set(helper.replaces), ["agenda add tags", "agenda remove tags", "agenda set tags"])
    }

    /// A Shortcuts that answers from a list.
    final class Library: HelperHost, @unchecked Sendable {
        var entries: [InstalledShortcut]
        init(_ entries: [InstalledShortcut]) { self.entries = entries }
        func installed() throws -> [InstalledShortcut] { entries }
        func write(_ recipe: Recipe, to folder: URL) throws -> URL { folder }
        func offer(_ file: URL) throws {}
        func run(_ name: String, input: Data?, patience: Double, timeout: Double, onWaiting: (@Sendable () -> Void)?) throws -> RunResult {
            RunResult(output: Data(), duration: 0)
        }
    }

    func testObsoleteHelpersAreNamedAndTheNewOneMustBeCurrent() throws {
        let helper = try TagShortcuts.helper
        let old = Library([InstalledShortcut(id: "1", name: "agenda add tags"), InstalledShortcut(id: "2", name: "agenda set tags"),
                           InstalledShortcut(id: "3", name: "Other")])
        let before = try TagShortcuts.status(host: old)
        XCTAssertFalse(before.installed)
        XCTAssertEqual(Set(before.obsolete), ["agenda add tags", "agenda set tags"])
        XCTAssertTrue(before.obsoleteNote?.contains("can be deleted") ?? false)
        let clean = try TagShortcuts.status(host: Library([InstalledShortcut(id: "9", name: helper.name, marker: helper.marker)]))
        XCTAssertTrue(clean.installed)
        XCTAssertNil(clean.obsoleteNote)
    }

    func testTheHelperBuildsStrictlyAgainstThisMacsCatalogue() throws {
        guard let builder = try? ShortcutBuilder() else { throw XCTSkip("no Shortcuts action catalogue here") }
        XCTAssertNoThrow(try builder.build(try TagShortcuts.helper.recipe))
    }
}
