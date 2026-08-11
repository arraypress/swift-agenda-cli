#!/bin/bash

__agenda_cursor_index_in_current_word() {
    local remaining="${COMP_LINE}"

    local word
    for word in "${COMP_WORDS[@]::COMP_CWORD}"; do
        remaining="${remaining##*([[:space:]])"${word}"*([[:space:]])}"
    done

    local -ir index="$((COMP_POINT - ${#COMP_LINE} + ${#remaining}))"
    if [[ "${index}" -le 0 ]]; then
        printf 0
    else
        printf %s "${index}"
    fi
}

# positional arguments:
#
# - 1: the current (sub)command's count of positional arguments
#
# required variables:
#
# - repeating_flags: the repeating flags that the current (sub)command can accept
# - non_repeating_flags: the non-repeating flags that the current (sub)command can accept
# - repeating_options: the repeating options that the current (sub)command can accept
# - non_repeating_options: the non-repeating options that the current (sub)command can accept
# - positional_number: value ignored
# - unparsed_words: unparsed words from the current command line
#
# modified variables:
#
# - non_repeating_flags: remove flags for this (sub)command that are already on the command line
# - non_repeating_options: remove options for this (sub)command that are already on the command line
# - positional_number: set to the current positional number
# - unparsed_words: remove all flags, options, and option values for this (sub)command
__agenda_offer_flags_options() {
    local -ir positional_count="${1}"
    positional_number=0

    local was_flag_option_terminator_seen=false
    local is_parsing_option_value=false

    local -ar unparsed_word_indices=("${!unparsed_words[@]}")
    local -i word_index
    for word_index in "${unparsed_word_indices[@]}"; do
        if "${is_parsing_option_value}"; then
            # This word is an option value:
            # Reset marker for next word iff not currently the last word
            [[ "${word_index}" -ne "${unparsed_word_indices[${#unparsed_word_indices[@]} - 1]}" ]] && is_parsing_option_value=false
            unset "unparsed_words[${word_index}]"
            # Do not process this word as a flag or an option
            continue
        fi

        local word="${unparsed_words["${word_index}"]}"
        if ! "${was_flag_option_terminator_seen}"; then
            case "${word}" in
            --)
                unset "unparsed_words[${word_index}]"
                # by itself -- is a flag/option terminator, but if it is the last word, it is the start of a completion
                if [[ "${word_index}" -ne "${unparsed_word_indices[${#unparsed_word_indices[@]} - 1]}" ]]; then
                    was_flag_option_terminator_seen=true
                fi
                continue
                ;;
            -*)
                # ${word} is a flag or an option
                # If ${word} is an option, mark that the next word to be parsed is an option value
                local option
                for option in "${repeating_options[@]}" "${non_repeating_options[@]}"; do
                    [[ "${word}" = "${option}" ]] && is_parsing_option_value=true && break
                done

                # Remove ${word} from ${non_repeating_flags} or ${non_repeating_options} so it isn't offered again
                local not_found=true
                local -i index
                for index in "${!non_repeating_flags[@]}"; do
                    if [[ "${non_repeating_flags[${index}]}" = "${word}" ]]; then
                        unset "non_repeating_flags[${index}]"
                        non_repeating_flags=("${non_repeating_flags[@]}")
                        not_found=false
                        break
                    fi
                done
                if "${not_found}"; then
                    for index in "${!non_repeating_flags[@]}"; do
                        if [[ "${non_repeating_flags[${index}]}" = "${word}" ]]; then
                            unset "non_repeating_flags[${index}]"
                            non_repeating_flags=("${non_repeating_flags[@]}")
                            break
                        fi
                    done
                fi
                unset "unparsed_words[${word_index}]"
                continue
                ;;
            esac
        fi

        # ${word} is neither a flag, nor an option, nor an option value
        if [[ "${positional_number}" -lt "${positional_count}" || "${positional_count}" -lt 0 ]]; then
            # ${word} is a positional
            ((positional_number++))
            unset "unparsed_words[${word_index}]"
        else
            if [[ -z "${word}" ]]; then
                # Could be completing a flag, option, or subcommand
                positional_number=-1
            else
                # ${word} is a subcommand or invalid, so stop processing this (sub)command
                positional_number=-2
            fi
            break
        fi
    done

    unparsed_words=("${unparsed_words[@]}")

    if\
        ! "${was_flag_option_terminator_seen}"\
        && ! "${is_parsing_option_value}"\
        && [[ ("${cur}" = -* && "${positional_number}" -ge 0) || "${positional_number}" -eq -1 ]]
    then
        COMPREPLY+=($(compgen -W "${repeating_flags[*]} ${non_repeating_flags[*]} ${repeating_options[*]} ${non_repeating_options[*]}" -- "${cur}"))
    fi
}

__agenda_add_completions() {
    local completion
    while IFS='' read -r completion; do
        COMPREPLY+=("${completion}")
    done < <(IFS=$'\n' compgen "${@}" -- "${cur}")
}

__agenda_custom_complete() {
    if [[ -n "${cur}" || -z ${COMP_WORDS[${COMP_CWORD}]} || "${COMP_LINE:${COMP_POINT}:1}" != ' ' ]]; then
        local -ar words=("${COMP_WORDS[@]}")
    else
        local -ar words=("${COMP_WORDS[@]::${COMP_CWORD}}" '' "${COMP_WORDS[@]:${COMP_CWORD}}")
    fi

    "${COMP_WORDS[0]}" "${@}" "${words[@]}"
}

_agenda() {
    local state
    state="$(shopt -p;shopt -po)"
    trap "${state//$'\n'/;}" RETURN
    shopt -s extglob
    set +o history +o posix

    local -xr SAP_SHELL=bash
    local -x SAP_SHELL_VERSION
    SAP_SHELL_VERSION="$(IFS='.';printf %s "${BASH_VERSINFO[*]}")"
    local -r SAP_SHELL_VERSION

    local -r cur="${2}"
    local -r prev="${3}"

    local -i positional_number
    local -a unparsed_words=("${COMP_WORDS[@]:1:${COMP_CWORD}}")

    local -a repeating_flags=()
    local -a non_repeating_flags=(--version -h --help)
    local -a repeating_options=()
    local -a non_repeating_options=()
    __agenda_offer_flags_options 0

    # Offer subcommand / subcommand argument completions
    local -r subcommand="${unparsed_words[0]}"
    unset 'unparsed_words[0]'
    unparsed_words=("${unparsed_words[@]}")
    case "${subcommand}" in
    events|today|tomorrow|reminders|search|free|add|done|edit|move|delete|calendars|doctor|describe|mcp|help)
        # Offer subcommand argument completions
        "_agenda_${subcommand}"
        ;;
    *)
        # Offer subcommand completions
        COMPREPLY+=($(compgen -W 'events today tomorrow reminders search free add done edit move delete calendars doctor describe mcp help' -- "${cur}"))
        ;;
    esac
}

_agenda_events() {
    repeating_flags=()
    non_repeating_flags=(--conflicts --json --version -h --help)
    repeating_options=(--calendar)
    non_repeating_options=(--next --from --to --timezone)
    __agenda_offer_flags_options 0

    # Offer option value completions
    case "${prev}" in
    '--next')
        return
        ;;
    '--from')
        return
        ;;
    '--to')
        return
        ;;
    '--calendar')
        return
        ;;
    '--timezone')
        return
        ;;
    esac
}

_agenda_today() {
    repeating_flags=()
    non_repeating_flags=(--events --reminders --json --version -h --help)
    repeating_options=(--calendar)
    non_repeating_options=(--timezone)
    __agenda_offer_flags_options 0

    # Offer option value completions
    case "${prev}" in
    '--calendar')
        return
        ;;
    '--timezone')
        return
        ;;
    esac
}

_agenda_tomorrow() {
    repeating_flags=()
    non_repeating_flags=(--events --reminders --json --version -h --help)
    repeating_options=(--calendar)
    non_repeating_options=(--timezone)
    __agenda_offer_flags_options 0

    # Offer option value completions
    case "${prev}" in
    '--calendar')
        return
        ;;
    '--timezone')
        return
        ;;
    esac
}

_agenda_reminders() {
    repeating_flags=()
    non_repeating_flags=(--overdue --all --json --version -h --help)
    repeating_options=(--list)
    non_repeating_options=(--due --limit --timezone)
    __agenda_offer_flags_options 0

    # Offer option value completions
    case "${prev}" in
    '--list')
        return
        ;;
    '--due')
        return
        ;;
    '--limit')
        return
        ;;
    '--timezone')
        return
        ;;
    esac
}

_agenda_search() {
    repeating_flags=()
    non_repeating_flags=(--events --reminders --json --version -h --help)
    repeating_options=(--calendar)
    non_repeating_options=(--within --past --timezone)
    __agenda_offer_flags_options 1

    # Offer option value completions
    case "${prev}" in
    '--within')
        return
        ;;
    '--past')
        return
        ;;
    '--calendar')
        return
        ;;
    '--timezone')
        return
        ;;
    esac
}

_agenda_free() {
    repeating_flags=()
    non_repeating_flags=(--any-time --first --json --version -h --help)
    repeating_options=(--calendar)
    non_repeating_options=(--within --start-hour --end-hour --timezone)
    __agenda_offer_flags_options 1

    # Offer option value completions
    case "${prev}" in
    '--within')
        return
        ;;
    '--start-hour')
        return
        ;;
    '--end-hour')
        return
        ;;
    '--calendar')
        return
        ;;
    '--timezone')
        return
        ;;
    esac
}

_agenda_add() {
    repeating_flags=()
    non_repeating_flags=(--remind --all-day --dry-run --json --version -h --help)
    repeating_options=(--alert --alert-at)
    non_repeating_options=(--at --for --calendar --list --location --notes --availability --priority --repeat --every --on --on-day --nth --until --times --timezone)
    __agenda_offer_flags_options 1

    # Offer option value completions
    case "${prev}" in
    '--at')
        return
        ;;
    '--for')
        return
        ;;
    '--calendar'|'--list')
        return
        ;;
    '--location')
        return
        ;;
    '--notes')
        return
        ;;
    '--alert')
        return
        ;;
    '--alert-at')
        return
        ;;
    '--availability')
        __agenda_add_completions -W 'busy'$'\n''free'$'\n''tentative'$'\n''unavailable'
        return
        ;;
    '--priority')
        return
        ;;
    '--repeat')
        __agenda_add_completions -W 'daily'$'\n''weekly'$'\n''monthly'$'\n''yearly'
        return
        ;;
    '--every')
        return
        ;;
    '--on')
        return
        ;;
    '--on-day')
        return
        ;;
    '--nth')
        return
        ;;
    '--until')
        return
        ;;
    '--times')
        return
        ;;
    '--timezone')
        return
        ;;
    esac
}

_agenda_done() {
    repeating_flags=()
    non_repeating_flags=(--undo --json --version -h --help)
    repeating_options=()
    non_repeating_options=(--timezone)
    __agenda_offer_flags_options 1

    # Offer option value completions
    case "${prev}" in
    '--timezone')
        return
        ;;
    esac
}

_agenda_edit() {
    repeating_flags=()
    non_repeating_flags=(--clear-due --all-day --clear-alerts --clear-repeat --json --version -h --help)
    repeating_options=(--alert)
    non_repeating_options=(--title --due --start --priority --notes --list --repeat --every --on --on-day --nth --until --times --timezone)
    __agenda_offer_flags_options 1

    # Offer option value completions
    case "${prev}" in
    '--title')
        return
        ;;
    '--due')
        return
        ;;
    '--start')
        return
        ;;
    '--priority')
        return
        ;;
    '--notes')
        return
        ;;
    '--list')
        return
        ;;
    '--alert')
        return
        ;;
    '--repeat')
        __agenda_add_completions -W 'daily'$'\n''weekly'$'\n''monthly'$'\n''yearly'
        return
        ;;
    '--every')
        return
        ;;
    '--on')
        return
        ;;
    '--on-day')
        return
        ;;
    '--nth')
        return
        ;;
    '--until')
        return
        ;;
    '--times')
        return
        ;;
    '--timezone')
        return
        ;;
    esac
}

_agenda_move() {
    repeating_flags=()
    non_repeating_flags=(--clear-alerts --clear-repeat --dry-run --json --version -h --help)
    repeating_options=(--alert)
    non_repeating_options=(--to --by --title --location --notes --calendar --availability --repeat --every --on --on-day --nth --until --times --span --occurrence --timezone)
    __agenda_offer_flags_options 1

    # Offer option value completions
    case "${prev}" in
    '--to')
        return
        ;;
    '--by')
        return
        ;;
    '--title')
        return
        ;;
    '--location')
        return
        ;;
    '--notes')
        return
        ;;
    '--calendar')
        return
        ;;
    '--availability')
        __agenda_add_completions -W 'busy'$'\n''free'$'\n''tentative'$'\n''unavailable'
        return
        ;;
    '--alert')
        return
        ;;
    '--repeat')
        __agenda_add_completions -W 'daily'$'\n''weekly'$'\n''monthly'$'\n''yearly'
        return
        ;;
    '--every')
        return
        ;;
    '--on')
        return
        ;;
    '--on-day')
        return
        ;;
    '--nth')
        return
        ;;
    '--until')
        return
        ;;
    '--times')
        return
        ;;
    '--span')
        __agenda_add_completions -W 'this'$'\n''future'
        return
        ;;
    '--occurrence')
        return
        ;;
    '--timezone')
        return
        ;;
    esac
}

_agenda_delete() {
    repeating_flags=()
    non_repeating_flags=(--remind --yes --version -h --help)
    repeating_options=()
    non_repeating_options=(--span --occurrence)
    __agenda_offer_flags_options 1

    # Offer option value completions
    case "${prev}" in
    '--span')
        __agenda_add_completions -W 'this'$'\n''future'
        return
        ;;
    '--occurrence')
        return
        ;;
    esac
}

_agenda_calendars() {
    repeating_flags=()
    non_repeating_flags=(--reminders --json --version -h --help)
    repeating_options=()
    non_repeating_options=(--timezone)
    __agenda_offer_flags_options 0

    # Offer option value completions
    case "${prev}" in
    '--timezone')
        return
        ;;
    esac
}

_agenda_doctor() {
    repeating_flags=()
    non_repeating_flags=(--fix --json --version -h --help)
    repeating_options=()
    non_repeating_options=(--timezone)
    __agenda_offer_flags_options 0

    # Offer option value completions
    case "${prev}" in
    '--timezone')
        return
        ;;
    esac
}

_agenda_describe() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __agenda_offer_flags_options 0
}

_agenda_mcp() {
    repeating_flags=()
    non_repeating_flags=(--version -h --help)
    repeating_options=()
    non_repeating_options=()
    __agenda_offer_flags_options 0
}

_agenda_help() {
    repeating_flags=()
    non_repeating_flags=(--version)
    repeating_options=()
    non_repeating_options=()
    __agenda_offer_flags_options -1
}

complete -o filenames -F _agenda agenda
