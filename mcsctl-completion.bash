#!/usr/bin/env bash

_mcsctl()
{
	local CMD="mcsctl"
	# Commands
	local CMD_HELP="help"
	local CMD_STATUS="status"
	local CMD_START="start"
	local CMD_STOP="stop"
	local CMD_RESTART="restart"
	local CMD_CONSOLE="console"
	local CMD_COMMAND="command"
	local CMD_CREATE="create"
	local CMD_UPDATE="update"
	local CMD_DESTROY="destroy"
	local CMD_PRINT_EXISTS="print-exists"
	local CMD_PRINT_SCREEN="print-screen"
	local CMD_PRINT_ACTIVE="print-active"
	local CMD_PRINT_INACTIVE="print-inactive"
	# /Commands

	if [ "${#COMP_WORDS[@]}" -le "2" ]; then
		COMPREPLY=($(compgen -W "${CMD_HELP} ${CMD_STATUS} ${CMD_START} ${CMD_STOP} ${CMD_RESTART} ${CMD_CONSOLE} ${CMD_COMMAND} ${CMD_CREATE} ${CMD_UPDATE} ${CMD_DESTROY} ${CMD_PRINT_EXISTS} ${CMD_PRINT_SCREEN} ${CMD_PRINT_ACTIVE} ${CMD_PRINT_INACTIVE}" "${COMP_WORDS[1]}"))
	elif [ "${#COMP_WORDS[@]}" -eq "3" ]; then
		case "${COMP_WORDS[1]}" in
			"${CMD_STATUS}")
				COMPREPLY=($(compgen -W "$(${CMD} print-exists all) all" "${COMP_WORDS[2]}"))
				;;
			"${CMD_START}")
				COMPREPLY=($(compgen -W "$(${CMD} print-inactive all) all" "${COMP_WORDS[2]}"))
				;;
			"${CMD_STOP}")
				COMPREPLY=($(compgen -W "$(${CMD} print-active all) all" "${COMP_WORDS[2]}"))
				;;
			"${CMD_RESTART}")
				COMPREPLY=($(compgen -W "$(${CMD} print-active all) all" "${COMP_WORDS[2]}"))
				;;
			"${CMD_CONSOLE}")
				COMPREPLY=($(compgen -W "$(${CMD} print-screen all)" "${COMP_WORDS[2]}"))
				;;
			"${CMD_COMMAND}")
				COMPREPLY=($(compgen -W "$(${CMD} print-active all) all" "${COMP_WORDS[2]}"))
				;;
			"${CMD_UPDATE}")
				COMPREPLY=($(compgen -W "$(${CMD} print-exists all) all" "${COMP_WORDS[2]}"))
				;;
			"${CMD_DESTROY}")
				COMPREPLY=($(compgen -W "$(${CMD} print-inactive all) all" "${COMP_WORDS[2]}"))
				;;
			*)
				# no argument or any argument
				;;
		esac
	fi
}
complete -F _mcsctl mcsctl
