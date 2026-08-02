# Development Work

## Local tools

### `agenda` — Apple Calendar and Reminders

Reads and edits the real local Calendar and Reminders stores. Installed at
`~/.local/bin/agenda`; source in `Swift/Libraries/swift-agenda`.

Use it whenever a task touches the user's schedule or to-dos — checking availability,
adding an event, finding something already booked, ticking off a reminder. The data is
live, so prefer it over asking the user what's on their calendar.

Also registered as an MCP server (`.mcp.json`). If `agenda_query`, `agenda_search`,
`agenda_create`, `agenda_update`, or `agenda_delete` appear in your tools, use those —
they are the same functionality with typed arguments. Otherwise use the CLI below.

```bash
agenda today                              # events + reminders due today
agenda tomorrow
agenda events --next 7d                   # what's coming up
agenda events --from monday --to friday
agenda reminders --overdue
agenda free 90m --within 2w               # gaps long enough to book
agenda search flight                      # text search, events AND reminders
agenda calendars                          # names to pass to --calendar

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
  `done`, and `delete` take. Use `--json` if you'd rather parse.
- **Repeating events need `--span this|future`** to edit or delete, and
  `--occurrence <date>` to target a specific instance. Without `--occurrence`, EventKit
  resolves the id to the series' *first* occurrence — so you will edit the wrong day.
  `--span future` is irreversible across the whole series.
- **`--dry-run`** on `add` and `move` prints a field-level diff without saving. Use it
  before any write the user hasn't explicitly asked for, then confirm.
- **Deletes are irreversible.** Confirm with the user first; there is no undo.
- **Empty output means empty**, never "no permission" — permission failures throw with
  the fix. If something looks wrong, run `agenda doctor`.
- **`--timezone Asia/Tokyo`** computes and displays in that zone, on any command.

Full flags: `agenda help <subcommand>`.
