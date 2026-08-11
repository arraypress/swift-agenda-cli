# Agenda

A command-line tool and Swift library for Apple Calendar and Reminders — query events, find free time, and create or edit items from the terminal. Built for agents as much as for people: dense token-cheap output, `--json` for piping, and errors that name the fix.

## Features

- 📅 **Event queries** — `agenda events --next 7d` lists what's coming, including anything already in progress; `--from`/`--to` for an explicit range, `--calendar` to narrow, `--conflicts` for double-bookings
- ✅ **Reminders** — `agenda reminders --due 7d`, `--overdue`, `--all`; open items first, undated ones kept and sorted last
- 🕳️ **Free-time search** — `agenda free 90m --within 2w` walks the calendar and returns real gaps, merging back-to-back meetings and clipping to working hours (`--any-time` to lift that)
- ↻ **Full recurrence** — daily/weekly/monthly/yearly with `--every N`, `--on MO,WE,FR`, `--on-day 1,15`, `--nth last`, and `--until`/`--times` end conditions. Round-trips through EventKit without loss
- ⏰ **Alarms** — repeatable `--alert 1d --alert 15m`, relative or absolute
- 👥 **Attendees with RSVP state** — accepted/declined/pending per person, plus `awaitingReply` and `isDeclinedByMe`
- 🌍 **Time-zone correct** — `--timezone Asia/Tokyo` computes *and* displays in that zone; DST transitions are handled by calendar arithmetic, not by adding 86,400 seconds
- ✍️ **Writes** — `add`, `move`, `delete`, `done`, with `--dry-run` on the mutating paths and a field-level diff before anything is saved
- 🛟 **Recurring-series guard** — editing or deleting a repeating event *requires* an explicit `--span this|future`, so a weekly standup is never silently rewritten across every future occurrence
- 🎯 **Correct occurrence targeting** — `--occurrence <date>` edits the instance you meant; without it EventKit resolves a series identifier to its *first* occurrence
- 🚦 **Availability-aware** — events marked free, all-day markers, cancelled invitations, and anything you declined don't consume free time
- 🗣️ **Plain-language dates** — `--at "tomorrow 9am"`, `next friday`, `+2d`, `2d ago`, `now`. No date arithmetic required by the caller, which is the thing agents get wrong most
- 📆 **`agenda today` / `agenda tomorrow`** — one whole calendar day, events and reminders together. Distinct from `--next 24h`, which is a rolling window
- 🔎 **Text search** — `agenda search flight` across events *and* reminders, matching title, notes, location, and URL. Case- and diacritic-insensitive, so `zurich` finds `Zürich`
- ✏️ **Full editing** — `agenda edit` for reminders, `agenda move` for events; both cover every field including alerts and recurrence, with `--clear-*` flags so removing a value stays expressible
- 🩺 **`agenda doctor`** — reports permission state per entity with the exact remedy, exits non-zero when something is blocked, and `--fix` triggers the prompts
- 🧾 **Never silently empty** — a permission failure throws with a fix instead of returning zero rows, so "you have nothing on" always means it
- 🪶 **Zero dependencies in the library** — `AgendaKit` is Foundation + EventKit; only the CLI pulls in ArgumentParser
- 🧪 **Fully tested** — 120 tests covering the spoken-date grammar, DST transitions in both hemispheres, recurrence round-trips through `EKRecurrenceRule`, geofenced alarms, working-hours clipping, and free-slot maths. No store or permissions needed to run them

## Requirements

- macOS 15+
- Swift 5.9+

> **Permissions:** Calendars and Reminders are prompted on first use. The binary embeds the required usage strings in its `__TEXT,__info_plist` section — a bare SPM executable has no bundle, so without that the system denies silently.

## Installation

### Homebrew

```bash
brew install arraypress/tap/agenda
```

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-agenda.git", from: "1.0.0")
]
```

### From source

Build the release binary and put it somewhere on your `PATH`:

```bash
swift build -c release
mkdir -p "$HOME/.local/bin"
cp .build/release/agenda "$HOME/.local/bin/agenda"
```

If `~/.local/bin` is not on your `PATH`, add it and reload:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Or system-wide, if you would rather not touch your shell config:

```bash
sudo cp .build/release/agenda /usr/local/bin/agenda
```

Build from the package root. The Info.plist is embedded by a linker flag with a
path relative to it, and that is what makes the permission prompts appear at
all — see the note under **Requirements**.

Check it worked before anything else:

```bash
agenda doctor
```

## Usage

```bash
# What's on
agenda today                              # events + reminders due today
agenda tomorrow
agenda events --next 7d
agenda events --from monday --to friday --calendar Work
agenda events --conflicts                 # double-bookings

# Reminders
agenda reminders --due 7d
agenda reminders --overdue

# Find something
agenda search flight                      # events AND reminders, incl. notes/location
agenda search berlin --within 1y

# When am I free?
agenda free 90m --within 2w
agenda free 30m --first --any-time

# Create
agenda add "Dentist" --at "tomorrow 9am" --for 45m --alert 1d
agenda add "Standup" --at "monday 9:30am" --for 15m --repeat weekly --on MO,TU,WE,TH,FR
agenda add "Retro" --at "2026-07-31T16:00" --repeat monthly --on FR --nth last
agenda add "Pay rent" --remind --at 2026-08-01 --all-day --repeat monthly --on-day 1 --priority 1
agenda add "Buy milk" --remind --alert-at "enter:51.5074,-0.1278,150,Tesco"

# Edit and remove
agenda move <id> --to "next friday 10am" --dry-run
agenda move <id> --by 1h --span this --occurrence 2026-08-10
agenda edit <id> --priority 1 --due "friday 5pm"     # reminders
agenda done <id>
agenda delete <id> --span future

# Setup and plumbing
agenda calendars                          # names, colours, which are read-only
agenda doctor --fix                       # permission state, exits non-zero if blocked

# Everything takes --json and --timezone
agenda events --next 24h --json | jq '.[] | select(.meetingURL != null)'
agenda today --timezone Asia/Tokyo
```

Durations accept `30m`, `4h`, `7d`, `2w`, `6mo`, `1y` — a bare number is minutes, and note `m` is minutes while `mo` is months.

Dates accept plain language or ISO 8601:

| Input | Means |
|---|---|
| `now` | this instant |
| `today`, `tomorrow`, `yesterday` | that day at midnight, unless a time follows |
| `monday`, `fri` | the next such day, today included |
| `next monday` | always a week after the bare form |
| `+2d`, `-1w`, `2d ago` | offset from now |
| `tomorrow 9am`, `monday 14:30` | any day phrase plus a time |
| `2026-07-19T14:00` | exact, in the configured zone |

### Library

```swift
import AgendaKit

try await Agenda.requestAccess(to: .event)

// Next week
let events = try Agenda.upcoming(within: try Agenda.duration("7d"))

// First free 90 minutes in working hours
let slot = try Agenda.nextFreeSlot(
    ofAtLeast: try Agenda.duration("90m"),
    hours: .standard
)

// A repeating event with an alert
try Agenda.createEvent(EventDraft(
    title: "Standup",
    startsAt: start,
    endsAt: start.addingTimeInterval(900),
    recurrence: .everyWeekday,
    alarms: [.before(600)],
    calendar: "Work"
))
```

## For agents

```bash
agenda describe --json          # every command and argument
agenda mcp                      # the same, over MCP on stdio
```

`describe` is built from the parser's own definitions, so it cannot drift from what the tool accepts.

## MCP

`agenda mcp` serves the same functionality over the Model Context Protocol (stdio), so
an agent gets the tools in its list rather than having to be told the CLI exists.

```bash
claude mcp add agenda -- agenda mcp
```

Or in `.mcp.json`:

```json
{ "mcpServers": { "agenda": { "command": "agenda", "args": ["mcp"] } } }
```

Five tools rather than one per subcommand — `agenda_query`, `agenda_search`,
`agenda_create`, `agenda_update`, `agenda_delete`. Every tool definition occupies the
model's context permanently whether called or not, and a model chooses more reliably
among five clear options than thirteen overlapping ones, so the read commands collapse
into a `mode` parameter.

The JSON-RPC layer is hand-rolled against Foundation — no SDK dependency, and the
library target stays dependency-free.

## Design notes

**Permission errors are never empty results.** Every read throws `AgendaError.accessDenied` when the entity isn't authorized. An agent that gets back zero events will report "you have nothing scheduled" — which is a confident lie if the real problem was a missing grant.

**Recurring mutations demand a span.** `EKSpan.futureEvents` on a weekly meeting rewrites every remaining instance and there is no undo. `deleteEvent`/`updateEvent` throw `AgendaError.spanRequired` rather than defaulting.

**Availability is honoured.** A "focus block" you marked free doesn't consume a free slot; neither does an all-day marker or a cancelled invitation.

**Ordering matters in EventKit.** A calendar must be assigned before availability — EventKit validates the value against the target calendar's `supportedEventAvailabilities` and silently discards an unsupported one.

**A series identifier is not an occurrence identifier.** Every occurrence of a repeating event shares one `eventIdentifier`, and `store.event(withIdentifier:)` always returns the first. Editing that with `.thisEvent` rewrites the wrong day. `updateEvent`/`deleteEvent` take an `occurrenceOn:` date and resolve the exact instance by predicate.

**`occurrenceCount` is off by one.** EventKit materialises one fewer event than the count it stores — a stored 4 produces three events. `Recurrence.occurrences` means the total a person intends, and the translation happens at the EventKit boundary.

**A long-lived server must drop EventKit's cache.** `EKEventStore` caches fetched objects, so a process that runs for hours serves stale rows as the calendar changes underneath it — and a write against a stale object can silently no-op. The MCP server calls `Agenda.reset()` before every tool call; the CLI does not need to, being short-lived.

**Dates are computed in `Agenda.calendar`, not the machine's zone.** Set it to compute elsewhere; `--timezone` does this for the CLI. Day iteration uses `date(byAdding:)` rather than adding 86,400 seconds, so DST days of 23 and 25 hours stay correct.

## License

MIT
