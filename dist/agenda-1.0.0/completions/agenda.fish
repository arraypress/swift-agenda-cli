function __agenda_should_offer_completions_for_flags_or_options -a expected_commands
    set -l non_repeating_flags_or_options $argv[2..]
    set -l non_repeating_flags_or_options_absent 0
    set -l positional_index 0
    set -l commands
    __agenda_parse_tokens
    test "$commands" = "$expected_commands"; and return $non_repeating_flags_or_options_absent
end

function __agenda_should_offer_completions_for_positional -a expected_commands positional_index_comparison expected_positional_index
    set -l non_repeating_flags_or_options
    set -l non_repeating_flags_or_options_absent 0
    set -l positional_index 0
    set -l commands
    __agenda_parse_tokens
    test "$commands" = "$expected_commands" -a \( "$positional_index" "$positional_index_comparison" "$expected_positional_index" \)
end

function __agenda_parse_tokens -S
    set -l unparsed_tokens (__agenda_tokens -pc)
    switch $unparsed_tokens[1]
    case 'agenda'
        __agenda_parse_subcommand 0 'version' 'h/help'
        switch $unparsed_tokens[1]
        case 'events'
            __agenda_parse_subcommand 0 'next=' 'from=' 'to=' 'calendar=+' 'conflicts' 'json' 'timezone=' 'version' 'h/help'
        case 'today'
            __agenda_parse_subcommand 0 'events' 'reminders' 'calendar=+' 'json' 'timezone=' 'version' 'h/help'
        case 'tomorrow'
            __agenda_parse_subcommand 0 'events' 'reminders' 'calendar=+' 'json' 'timezone=' 'version' 'h/help'
        case 'reminders'
            __agenda_parse_subcommand 0 'list=+' 'due=' 'overdue' 'all' 'limit=' 'json' 'timezone=' 'version' 'h/help'
        case 'search'
            __agenda_parse_subcommand 1 'within=' 'past=' 'events' 'reminders' 'calendar=+' 'json' 'timezone=' 'version' 'h/help'
        case 'free'
            __agenda_parse_subcommand 1 'within=' 'start-hour=' 'end-hour=' 'any-time' 'first' 'calendar=+' 'json' 'timezone=' 'version' 'h/help'
        case 'add'
            __agenda_parse_subcommand 1 'at=' 'for=' 'remind' 'all-day' 'calendar=' 'location=' 'notes=' 'alert=+' 'alert-at=+' 'availability=' 'priority=' 'dry-run' 'repeat=' 'every=' 'on=' 'on-day=' 'nth=' 'until=' 'times=' 'json' 'timezone=' 'version' 'h/help'
        case 'done'
            __agenda_parse_subcommand 1 'undo' 'json' 'timezone=' 'version' 'h/help'
        case 'edit'
            __agenda_parse_subcommand 1 'title=' 'due=' 'clear-due' 'start=' 'all-day' 'priority=' 'notes=' 'list=' 'alert=+' 'clear-alerts' 'clear-repeat' 'repeat=' 'every=' 'on=' 'on-day=' 'nth=' 'until=' 'times=' 'json' 'timezone=' 'version' 'h/help'
        case 'move'
            __agenda_parse_subcommand 1 'to=' 'by=' 'title=' 'location=' 'notes=' 'calendar=' 'availability=' 'alert=+' 'clear-alerts' 'clear-repeat' 'repeat=' 'every=' 'on=' 'on-day=' 'nth=' 'until=' 'times=' 'span=' 'occurrence=' 'dry-run' 'json' 'timezone=' 'version' 'h/help'
        case 'delete'
            __agenda_parse_subcommand 1 'remind' 'span=' 'occurrence=' 'yes' 'version' 'h/help'
        case 'calendars'
            __agenda_parse_subcommand 0 'reminders' 'json' 'timezone=' 'version' 'h/help'
        case 'doctor'
            __agenda_parse_subcommand 0 'fix' 'json' 'timezone=' 'version' 'h/help'
        case 'describe'
            __agenda_parse_subcommand 0 'json' 'version' 'h/help'
        case 'mcp'
            __agenda_parse_subcommand 0 'version' 'h/help'
        case 'help'
            __agenda_parse_subcommand -r 1 'version'
        end
    end
end

function __agenda_tokens
    if test (string split -m 1 -f 1 -- . "$FISH_VERSION") -gt 3
        commandline --tokens-raw $argv
    else
        commandline -o $argv
    end
end

function __agenda_parse_subcommand -S -a positional_count
    argparse -s r -- $argv
    set -l option_specs $argv[2..]
    set -l is_repeating_positional $_flag_r
    set -el _flag_r
    set -a commands $unparsed_tokens[1]
    set positional_index 0
    while true
        set -e unparsed_tokens[1]
        argparse -sn "$commands" $option_specs -- $unparsed_tokens 2> /dev/null
        set unparsed_tokens $argv
        set positional_index (math $positional_index + 1)
        for non_repeating_flag_or_option in $non_repeating_flags_or_options
            if set -ql "_flag_$(string replace -a - _ -- $non_repeating_flag_or_option)"
                set non_repeating_flags_or_options_absent 1
                break
            end
        end
        test (count $unparsed_tokens) -eq 0 -o \( -z "$is_repeating_positional" -a "$positional_index" -gt "$positional_count" \) && break
    end
end

function __agenda_complete_directories
    set -l token (commandline -t)
    string match -- '*/' $token
    set -l subdirs $token*/
    printf %s\n $subdirs
end

function __agenda_custom_completion
    set -x SAP_SHELL fish
    set -x SAP_SHELL_VERSION $FISH_VERSION
    set -l tokens (__agenda_tokens -p)
    if test -z "$(__agenda_tokens -t)"
        set -l index (count (__agenda_tokens -pc))
        set tokens $tokens[..$index] \'\' $tokens[(math $index + 1)..]
    end
    command $tokens[1] $argv $tokens
end

complete -c 'agenda' -f
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'events' -d 'List calendar events.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'today' -d 'Everything on today — events, plus reminders due.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'tomorrow' -d 'Everything on tomorrow — events, plus reminders due.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'reminders' -d 'List reminders.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'search' -d 'Find events and reminders matching some text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'free' -d 'Find gaps long enough to schedule something.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'add' -d 'Create an event, or a reminder with --remind.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'done' -d 'Mark a reminder complete.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'edit' -d 'Change an existing reminder.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'move' -d 'Reschedule or edit an existing event.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'delete' -d 'Delete an event or reminder by id.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'calendars' -d 'List calendars, or reminder lists with --reminders.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'doctor' -d 'Check calendar and reminder permissions.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'describe' -d 'Describe this tool\'s commands in machine-readable form.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'mcp' -d 'Serve calendar and reminder tools over MCP (stdio).'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_positional "agenda" -eq 1' -fa 'help' -d 'Show subcommand help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda events" next' -l 'next' -d 'Window forward from now: 4h, 7d, 2w.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda events" from' -l 'from' -d 'Range start: today, monday, 2026-07-19. Overrides --next.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda events" to' -l 'to' -d 'Range end: friday, +2w, 2026-07-26. Overrides --next.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda events"' -l 'calendar' -d 'Restrict to a calendar by title or id. Repeatable.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda events" conflicts' -l 'conflicts' -d 'Only events that overlap another event.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda events" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda events" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda events" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda events" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda today" events' -l 'events' -d 'Events only.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda today" reminders' -l 'reminders' -d 'Reminders only.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda today"' -l 'calendar' -d 'Restrict to a calendar or list. Repeatable.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda today" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda today" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda today" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda today" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda tomorrow" events' -l 'events' -d 'Events only.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda tomorrow" reminders' -l 'reminders' -d 'Reminders only.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda tomorrow"' -l 'calendar' -d 'Restrict to a calendar or list. Repeatable.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda tomorrow" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda tomorrow" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda tomorrow" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda tomorrow" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda reminders"' -l 'list' -d 'Restrict to a list by title or id. Repeatable.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda reminders" due' -l 'due' -d 'Only reminders due within this window: 24h, 7d.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda reminders" overdue' -l 'overdue' -d 'Only reminders past their due date.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda reminders" all' -l 'all' -d 'Include completed reminders.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda reminders" limit' -l 'limit' -d 'Maximum rows to return.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda reminders" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda reminders" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda reminders" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda reminders" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda search" within' -l 'within' -d 'How far ahead to search: 30d, 6m, 1y.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda search" past' -l 'past' -d 'How far back to search.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda search" events' -l 'events' -d 'Search events only.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda search" reminders' -l 'reminders' -d 'Search reminders only.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda search"' -l 'calendar' -d 'Restrict to a calendar or list. Repeatable.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda search" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda search" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda search" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda search" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda free" within' -l 'within' -d 'How far ahead to look: 7d, 2w.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda free" start-hour' -l 'start-hour' -d 'Working day start hour, 0-23.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda free" end-hour' -l 'end-hour' -d 'Working day end hour, 0-23.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda free" any-time' -l 'any-time' -d 'Ignore working hours and weekends.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda free" first' -l 'first' -d 'Return only the first matching slot.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda free"' -l 'calendar' -d 'Restrict to a calendar by title or id. Repeatable.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda free" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda free" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda free" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda free" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" at' -l 'at' -d 'Start: now, tomorrow 9am, next friday, +2d, or ISO 8601. Defaults to now.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" for' -l 'for' -d 'Duration: 30m, 1h. Ignored with --remind.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" remind' -l 'remind' -d 'Create a reminder instead of an event.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" all-day' -l 'all-day' -d 'All-day event.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" calendar list' -l 'calendar' -l 'list' -d 'Target calendar, or reminder list with --remind.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" location' -l 'location' -d 'Location.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" notes' -l 'notes' -d 'Notes.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add"' -l 'alert' -d 'Alert before start: 15m, 1h, 1d. Repeatable. Use 0 for at-start.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add"' -l 'alert-at' -d 'Geofenced alert: enter:LAT,LON[,RADIUS][,TITLE]. Repeatable.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" availability' -l 'availability' -d 'Free/busy marking: busy | free | tentative | unavailable.' -rfka 'busy free tentative unavailable'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" priority' -l 'priority' -d 'Priority for reminders, 1 (highest) to 9.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" dry-run' -l 'dry-run' -d 'Print what would be created without saving.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" repeat' -l 'repeat' -d 'Repeat: daily | weekly | monthly | yearly.' -rfka 'daily weekly monthly yearly'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" every' -l 'every' -d 'Repeat every N periods, e.g. --every 2 with --repeat weekly.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" on' -l 'on' -d 'Weekdays, comma-separated: MO,WE,FR.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" on-day' -l 'on-day' -d 'Days of the month: 1,15 or \'last\'.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" nth' -l 'nth' -d 'Which occurrence in the period: first | second | third | fourth | last.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" until' -l 'until' -d 'Stop repeating after this date (ISO 8601).' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" times' -l 'times' -d 'Stop after this many occurrences.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda add" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda done" undo' -l 'undo' -d 'Reopen the reminder instead of completing it.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda done" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda done" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda done" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda done" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" title' -l 'title' -d 'New title.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" due' -l 'due' -d 'New due date: tomorrow 9am, next friday, +2d, or ISO 8601.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" clear-due' -l 'clear-due' -d 'Remove the due date, leaving it unscheduled.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" start' -l 'start' -d 'New start date — when it becomes actionable.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" all-day' -l 'all-day' -d 'Make the due date all-day, with no time.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" priority' -l 'priority' -d 'New priority, 1 (highest) to 9, or 0 to clear.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" notes' -l 'notes' -d 'New notes.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" list' -l 'list' -d 'Move to this reminder list.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit"' -l 'alert' -d 'Replace alerts: 15m, 1h. Repeatable.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" clear-alerts' -l 'clear-alerts' -d 'Remove all alerts.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" clear-repeat' -l 'clear-repeat' -d 'Stop it repeating.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" repeat' -l 'repeat' -d 'Repeat: daily | weekly | monthly | yearly.' -rfka 'daily weekly monthly yearly'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" every' -l 'every' -d 'Repeat every N periods, e.g. --every 2 with --repeat weekly.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" on' -l 'on' -d 'Weekdays, comma-separated: MO,WE,FR.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" on-day' -l 'on-day' -d 'Days of the month: 1,15 or \'last\'.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" nth' -l 'nth' -d 'Which occurrence in the period: first | second | third | fourth | last.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" until' -l 'until' -d 'Stop repeating after this date (ISO 8601).' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" times' -l 'times' -d 'Stop after this many occurrences.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda edit" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" to' -l 'to' -d 'New start: tomorrow 9am, next friday, +2d, or ISO 8601. Duration is preserved.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" by' -l 'by' -d 'Shift by a duration: 30m, 1h, 1d.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" title' -l 'title' -d 'New title.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" location' -l 'location' -d 'New location.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" notes' -l 'notes' -d 'New notes.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" calendar' -l 'calendar' -d 'Move to this calendar.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" availability' -l 'availability' -d 'Free/busy marking: busy | free | tentative | unavailable.' -rfka 'busy free tentative unavailable'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move"' -l 'alert' -d 'Replace alerts: 15m, 1h, 1d. Repeatable.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" clear-alerts' -l 'clear-alerts' -d 'Remove all alerts.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" clear-repeat' -l 'clear-repeat' -d 'Stop it repeating.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" repeat' -l 'repeat' -d 'Repeat: daily | weekly | monthly | yearly.' -rfka 'daily weekly monthly yearly'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" every' -l 'every' -d 'Repeat every N periods, e.g. --every 2 with --repeat weekly.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" on' -l 'on' -d 'Weekdays, comma-separated: MO,WE,FR.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" on-day' -l 'on-day' -d 'Days of the month: 1,15 or \'last\'.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" nth' -l 'nth' -d 'Which occurrence in the period: first | second | third | fourth | last.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" until' -l 'until' -d 'Stop repeating after this date (ISO 8601).' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" times' -l 'times' -d 'Stop after this many occurrences.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" span' -l 'span' -d 'For repeating events: this | future.' -rfka 'this future'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" occurrence' -l 'occurrence' -d 'Which occurrence of a repeating event, e.g. 2026-08-10 or next friday.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" dry-run' -l 'dry-run' -d 'Print the change without saving.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda move" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda delete" remind' -l 'remind' -d 'The id refers to a reminder.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda delete" span' -l 'span' -d 'For repeating events: this | future.' -rfka 'this future'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda delete" occurrence' -l 'occurrence' -d 'Which occurrence of a repeating event, e.g. 2026-08-10 or next friday.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda delete" yes' -l 'yes' -d 'Skip the confirmation prompt.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda delete" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda delete" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda calendars" reminders' -l 'reminders' -d 'List reminder lists instead of calendars.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda calendars" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda calendars" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda calendars" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda calendars" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda doctor" fix' -l 'fix' -d 'Trigger the permission prompts for anything not yet granted.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda doctor" json' -l 'json' -d 'Emit JSON instead of text.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda doctor" timezone' -l 'timezone' -d 'Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.' -rfka ''
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda doctor" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda doctor" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda describe" json' -l 'json' -d 'Force JSON output (the default, and the only form).'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda describe" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda describe" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda mcp" version' -l 'version' -d 'Show the version.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda mcp" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'agenda' -n '__agenda_should_offer_completions_for_flags_or_options "agenda help" version' -l 'version' -d 'Show the version.'
