# Development Work

## Local tools

### `agenda` — Apple Calendar and Reminders

Reads and edits the real local Calendar and Reminders stores. Installed at
`~/.local/bin/agenda`; source in `Swift/Libraries/swift-agenda-cli`.

Use it whenever a task touches the user's schedule or to-dos — checking availability,
adding an event, finding something already booked, ticking off a reminder. The data is
live, so prefer it over asking the user what's on their calendar.

Also registered as an MCP server (`.mcp.json`), one tool per subcommand — `agenda_events`,
`agenda_today`, `agenda_search`, `agenda_join`, `agenda_open`, `agenda_add`, `agenda_move`
and so on. If they appear in your tools, use those — they are the same functionality with
typed arguments. Otherwise use the CLI below.

```bash
agenda today                              # events + reminders due today
agenda tomorrow
agenda events --next 7d                   # what's coming up
agenda events --from monday --to friday
agenda reminders --overdue
agenda free 90m --within 2w               # gaps long enough to book
agenda search flight                      # text search, events AND reminders
agenda calendars                          # names to pass to --calendar

agenda join --print                       # link of the call running now / starting in 15m
agenda join <id>                          # open that event's video call
agenda open <id> --in google              # show it in calendar | google | fantastical | busycal
agenda open "next friday" --view week     # a day or week in Calendar.app

agenda add "Dentist" --at "tomorrow 9am" --for 45m --alert 1d
agenda add "Standup" --at "monday 9:30am" --repeat weekly --on MO,TU,WE,TH,FR
agenda add "Pay rent" --remind --at 2026-08-01 --all-day --repeat monthly --on-day 1

agenda move <id> --to "next friday 10am" --dry-run
agenda edit <id> --priority 1 --due "friday 5pm"    # reminders
agenda done <id>
agenda delete <id> --span future
```

Things that will bite otherwise:

- **Pass date phrases, don't compute dates.** `now`, `today`, `tomorrow 9am`,
  `next friday`, `+2d`, `2d ago` all work, as does ISO 8601. Doing the arithmetic
  yourself is the most common way to get this wrong.
- **Ids print on the second line** of each text result. That's what `move`, `edit`,
  `done`, `delete`, `join`, and `open` take. Use `--json` if you'd rather parse.
- **Repeating events need `--span this|future`** to edit or delete, and
  `--occurrence <date>` to target a specific instance. Without `--occurrence`, EventKit
  resolves the id to the series' *first* occurrence — so you will edit the wrong day.
  `--span future` is irreversible across the whole series.
- **`--dry-run`** on `add` and `move` prints a field-level diff without saving. Use it
  before any write the user hasn't explicitly asked for, then confirm.
- **Deletes are irreversible.** Confirm with the user first; there is no undo.
- **Empty output means empty**, never "no permission" — permission failures throw with
  the fix. If something looks wrong, run `agenda doctor`.
- **Video calls are detected for you.** Events carry `videoCall: {service, url}` in JSON
  (53 services, Safe Links unwrapped) and `📹 Zoom <link>` in text — don't regex the notes.
  `agenda join` with no id picks the call running now or starting within 15m (`--within`
  to widen), nearest start first; none is exit 1. **`join` and `open` launch apps on the
  user's screen** — pass `--print` unless they asked you to open it.
- **`agenda open` on a day in Calendar.app runs AppleScript** and needs Automation
  permission (exit 3 if refused). Google Calendar and Fantastical open an event on its day.
- **`--timezone Asia/Tokyo`** computes and displays in that zone, on any command.

Full flags: `agenda help <subcommand>`.
