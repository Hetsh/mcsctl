#!/usr/bin/env bash

# CLI args
readonly CMD="$1"
readonly SERVER_ID="$2"
readonly SERVER_COMMAND="${@:3}"
# /CLI args

# Commands
readonly CMD_HELP="help"
readonly CMD_STATUS="status"
readonly CMD_START="start"
readonly CMD_STOP="stop"
readonly CMD_RESTART="restart"
readonly CMD_CONSOLE="console"
readonly CMD_COMMAND="command"
readonly CMD_CREATE="create"
readonly CMD_UPDATE="update"
readonly CMD_DESTROY="destroy"
readonly CMD_PRINT_EXISTS="print-exists"
readonly CMD_PRINT_SCREEN="print-screen"
readonly CMD_PRINT_ACTIVE="print-active"
readonly CMD_PRINT_INACTIVE="print-inactive"
# /Commands

# Results
readonly SUCCESS="0"
readonly ERROR_UNKNOWN_COMMAND="1"
readonly ERROR_ID_MISSING="2"
readonly ERROR_COMMAND_MISSING="3"
readonly ERROR_SERVER_MISSING="4"
readonly ERROR_SERVER_EXISTS="5"
readonly ERROR_SERVER_APP_MISSING="6"
readonly ERROR_SCRAPE_FAILED="7"
readonly ERROR_SERVER_LATEST="8"
readonly ERROR_DOWNLOAD_FAILED="9"
readonly ERROR_SERVER_ACTIVE="10"
readonly ERROR_SERVER_INACTIVE="11"
readonly ERROR_EULA_FILE_MISSING="12"
readonly ERROR_PROPERTIES_FILE_MISSING="13"
readonly ERROR_MULTI_CONSOLE="14"
readonly ERROR_MULTI_CREATE="15"
readonly ERROR_NO_SERVERS="16"
readonly ERROR_JAVA_OLD="17"
# /Results

# Enforce mcs user (except for help command)
readonly MCS_USER="mcs"
if [ -n "$CMD" ] && [ "$CMD" != "$CMD_HELP" ] && [ "$USER" != "$MCS_USER" ]; then
	sudo -u "$MCS_USER" -s "/usr/bin/bash" "$0" "$@"
	exit $?
fi

# Mutable config
# mcsctl configuration
TIMEOUT="10"
SERVER_ROOT="$HOME"
DATE_FORMAT="%Y_%m_%d-%H_%M_%S"

# initial server configuration
MIN_RAM="1024"
MAX_RAM="1024"
if [ -n "$SERVER_ID" ] && [ "$SERVER_ID" != "all" ]; then
	INITIAL_SERVER_PROPERTIES="server-port=$((25564 + $SERVER_ID))
	\rmotd=Welcome to MC-Server #$SERVER_ID.
	\rplayer-idle-timeout=5
	\rsnooper-enabled=false
	\rview-distance=15"
fi
# /Mutable config
source "/etc/mcsctl.conf" &> /dev/null

# Immutable config
readonly SERVER_NAME="mcserver$SERVER_ID"
readonly SERVER_DIR="$SERVER_ROOT/$SERVER_NAME"
readonly SERVER_APP_NAME="server.jar"
readonly SERVER_APP="$SERVER_DIR/$SERVER_APP_NAME"
readonly SERVER_SCRIPT_NAME="launch.sh"
readonly SERVER_SCRIPT="$SERVER_DIR/$SERVER_SCRIPT_NAME"
readonly SERVER_VERSION="$SERVER_DIR/server.version"
# /Immutable config

screen_active() {
	# look for tab indicating the end of the name to avoid prefix issues
	if screen -list | grep "$SERVER_NAME"$'\t' > /dev/null; then
		return $(true)
	else
		return $(false)
	fi
}

wait_screen_start() {
	while ! screen_active; do
		sleep 0.1
	done
}

wait_screen_stop() {
	while screen_active; do
		sleep 0.1
	done
}

server_active() {
	# uses unique path to server application or launch script to find process
	if pgrep -f -u "$MCS_USER" "$SERVER_SCRIPT|$SERVER_APP" > /dev/null; then
		return $(true)
	else
		return $(false)
	fi
}

server_exists() {
	if [ -d "$SERVER_DIR" ]; then
		return $(true)
	else
		return $(false)
	fi
}

wait_server_start() {
	while ! server_active; do
		sleep 0.1
	done
}

wait_server_stop() {
	while server_active; do
		sleep 0.1
	done
}

version_lower() {
	local VERSION_A="$1"
	local VERSION_B="$2"

	echo -e "$VERSION_A\n$VERSION_B" | sort --version-sort --check=quiet
}

download() {
	local LATEST_VERSION=$(curl -s -L "https://launchermeta.mojang.com/mc/game/version_manifest.json" | jq -r ".latest.release")
	if [ -z "$LATEST_VERSION" ]; then
		echo "failed to scrape version -> aborted"
		exit $ERROR_SCRAPE_FAILED
	fi

	local CURRENT_VERSION="$(cat "$SERVER_VERSION" 2> /dev/null)"
	if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
		echo "already on latest release."
		exit $ERROR_SERVER_LATEST
	fi

	local METADATA_URL=$(curl -s -L "https://launchermeta.mojang.com/mc/game/version_manifest.json" | jq -r ".versions[] | select(.id==\"$LATEST_VERSION\") | .url")
	local SERVER_URL=$(curl -s -L "$METADATA_URL" | jq -r ".downloads.server.url")
	if [ -z "$SERVER_URL" ]; then
		echo "failed to scrape url -> aborted"
		exit $ERROR_SCRAPE_FAILED
	fi

	mkdir -p "$SERVER_DIR"
	if ! $(curl -s -L -o "$SERVER_APP" "$SERVER_URL"); then
		echo "failed to download jar -> aborted"
		exit $ERROR_DOWNLOAD_FAILED
	fi
	echo "$LATEST_VERSION" > "$SERVER_VERSION"
}

create_launch_script() {
	cat <<-EOF > "$SERVER_SCRIPT"
	#!/bin/sh
	java -Xms${MIN_RAM}M -Xmx${MAX_RAM}M -jar "$SERVER_APP" nogui
	EOF
	chmod +x "$SERVER_SCRIPT"
}

status() {
	echo -n $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Server "
	if server_active; then
		local SERVER_PORT=$(grep -s server-port "$SERVER_DIR/server.properties" | tail -n1 | cut -d'=' -f2)
		if [ -n "$SERVER_PORT" ]; then
			# Send server list ping https://wiki.vg/Server_List_Ping to query online players and remove binary part of the response
			local RESPONSE=$(echo -n -e '\x0f\x00\x2f\x09\x6c\x6f\x63\x61\x6c\x68\x6f\x73\x74\x63\xdd\x01\x01\x00' | nc -q 0 127.0.0.1 "$SERVER_PORT" | jq -Rr 'sub("^[^{]*"; "")')
			local PLAYERS_ACTIVE=$(echo "$RESPONSE" | jq -r .players.online)
			local PLAYERS_MAX=$(echo "$RESPONSE" | jq -r .players.max)
			echo "active ($PLAYERS_ACTIVE/$PLAYERS_MAX)"
		else
			echo "active (players unknown)"
		fi
	elif screen_active; then
		echo "inactive, screen running"
	else
		echo "inactive"
	fi
}

start() {
	echo -n $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Starting server... "

	# starting with minecraft 1.17, java 16 the is minimum version
	local MC_VERSION="$(cat "$SERVER_VERSION" 2> /dev/null)"
	local JAVA_VERSION="$(java --version | head -n 1 | cut -d ' ' -f 2)"
	if version_lower "1.17" "$MC_VERSION" && version_lower "$JAVA_VERSION" "16"; then
		echo "java version incompatible -> aborted"
		exit $ERROR_JAVA_INCOMPATIBLE
	fi

	# start screen session
	if ! screen_active; then
		screen -dmS "$SERVER_NAME"
		wait_screen_start
	fi

	# start server application in working directory
	if ! server_active; then
		if [ ! -x "$SERVER_SCRIPT" ]; then
			create_launch_script
		fi
		screen -S "$SERVER_NAME" -p 0 -X stuff "cd \"$SERVER_DIR\"; \"$SERVER_SCRIPT\"\n"
		wait_server_start
	fi

	echo "done"
}

stop() {
	echo -n $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Stopping server... "

	# stop server application with timeout
	if screen_active && server_active; then
		screen -S "$SERVER_NAME" -p 0 -X stuff "say ATTENTION! Server will be shut down in $TIMEOUT seconds!\n"
		sleep "$TIMEOUT"
		screen -S "$SERVER_NAME" -p 0 -X stuff "stop\n"
		wait_server_stop
	fi

	# stop screen session
	if screen_active; then
		screen -S "$SERVER_NAME" -p 0 -X stuff "exit\n"
		wait_screen_stop
	fi

	echo "done"
}

console() {
	echo -n $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Connecting to screen session... "

	screen -r "$SERVER_NAME"

	echo "done"
}

forward_command() {
	echo -n $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Forwarding command... "

	screen -S "$SERVER_NAME" -p 0 -X stuff "$SERVER_COMMAND\n"
	local KEYWORD="/\[$(date +%H:%M:%S)\]/p"
	echo "done"

	sleep 0.5
	sed -n "$KEYWORD" "$SERVER_DIR/logs/latest.log"
}

create() {
	echo -n $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Creating server... "

	download

	# Just accept the EULA, you wouldn't read it anyway :P
	echo "eula=TRUE" > "$SERVER_DIR/eula.txt"

	# Properties
	echo -e "$INITIAL_SERVER_PROPERTIES" > "$SERVER_DIR/server.properties"

	# Launch script
	create_launch_script

	echo "done"
}

update() {
	echo -n $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Updating server... "

	download

	echo "done"
}

remove() {
	echo -n $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Removing server... "

	rm -r -f "$SERVER_DIR"

	echo "done"
}

print_exists() {
	if server_exists; then
		echo $SERVER_ID
	fi
}

print_screen() {
	if screen_active; then
		echo $SERVER_ID
	fi
}

print_active() {
	if server_active; then
		echo $SERVER_ID
	fi
}

print_inactive() {
	if ! server_active; then
		echo $SERVER_ID
	fi
}

help() {
	local MY_NAME="${0##*/}"
	echo -e "Usage: $MY_NAME {$CMD_HELP|$CMD_STATUS|$CMD_START|$CMD_STOP|$CMD_RESTART|$CMD_CONSOLE|$CMD_COMMAND|$CMD_CREATE|$CMD_UPDATE|$CMD_DESTROY|$CMD_PRINT_EXISTS|$CMD_PRINT_SCREEN|$CMD_PRINT_ACTIVE|$CMD_PRINT_INACTIVE}
		\r$CMD_HELP                          Prints this help.
		\r$CMD_STATUS         <id/all>       Lists status of server(s) and online players.
		\r$CMD_START          <id/all>       Starts server(s) inside screen session(s).
		\r$CMD_STOP           <id/all>       Stops server(s) and screen session(s).
		\r$CMD_RESTART        <id/all>       Restarts server(s).
		\r$CMD_CONSOLE        <id>           Connects to the screen session of a server.
		\r$CMD_COMMAND        <id/all> <cmd> Forwards <cmd> to specified server(s).
		\r$CMD_CREATE         <id>           Creates a server in the configured SERVER_ROOT (default: /home/$MCS_USER).
		\r$CMD_UPDATE         <id/all>       Downloads a new minecraft server executable for server(s).
		\r$CMD_DESTROY        <id/all>       Removes all files of server(s).
		\r$CMD_PRINT_EXISTS   <id/all>       Prints IDs of given server(s) if they exist.
		\r$CMD_PRINT_SCREEN   <id/all>       Prints IDs of given server(s) if they have screen sessions.
		\r$CMD_PRINT_ACTIVE   <id/all>       Prints IDs of given server(s) if they are active.
		\r$CMD_PRINT_INACTIVE <id/all>       Prints IDs of given server(s) if they are inactive."
}

require_server_id() {
	if [ -z "$SERVER_ID" ]; then
		echo $(date "+$DATE_FORMAT:") "Missing server id!"
		exit $ERROR_ID_MISSING
	fi
}

require_command() {
	if [ -z "$SERVER_COMMAND" ]; then
		echo $(date "+$DATE_FORMAT:") "Missing command!"
		exit $ERROR_COMMAND_MISSING
	fi
}

require_server_exists() {
	require_server_id

	if ! server_exists; then
		echo $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Server does not exist!"
		exit $ERROR_SERVER_MISSING
	fi
}

require_server_active() {
	require_server_exists

	if ! server_active; then
		echo $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Server is not running!"
		exit $ERROR_SERVER_ACTIVE
	elif ! screen_active; then
		echo $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Server is running outside of screen!"
		exit $ERROR_SERVER_ACTIVE
	fi
}

require_server_inactive() {
	require_server_exists

	if server_active; then
		echo $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Server is running!"
		exit $ERROR_SERVER_INACTIVE
	fi
}

require_screen_active() {
	require_server_exists

	if ! screen_active; then
		echo $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Screen session is not running!"
		exit $ERROR_SERVER_ACTIVE
	fi
}

if [ "$SERVER_ID" == "all" ]; then
	case "$CMD" in
		"$CMD_CONSOLE")
			echo $(date "+$DATE_FORMAT:") "Cannot connect to multiple consoles!"
			exit $ERROR_MULTI_CONSOLE
			;;
		"$CMD_CREATE")
			echo $(date "+$DATE_FORMAT:") "Cannot create multiple servers!"
			exit $ERROR_MULTI_CREATE
			;;
	esac

	ID_LIST=$(find "$SERVER_ROOT" -type f -name "$SERVER_APP_NAME" -o -name "$SERVER_SCRIPT_NAME" 2>/dev/null | sed "s|${SERVER_ROOT}/\?mcserver||; s|/.*||" | sort -n -u)
	if [ -z "$ID_LIST" ]; then
		echo $(date "+$DATE_FORMAT:") "No servers exist!"
		exit $ERROR_NO_SERVERS
	fi

	for NEXT_ID in $ID_LIST; do
		"$0" "$CMD" "$NEXT_ID" "$SERVER_COMMAND"
	done
	exit $SUCCESS
else
	case "$CMD" in
		"$CMD_HELP")
			help
			;;
		"$CMD_STATUS")
			require_server_exists
			status
			;;
		"$CMD_START")
			require_server_inactive
			start
			;;
		"$CMD_STOP")
			require_server_active
			stop
			;;
		"$CMD_RESTART")
			require_server_active
			stop
			start
			;;
		"$CMD_CONSOLE")
			require_screen_active
			console
			;;
		"$CMD_COMMAND")
			require_server_active
			require_command
			forward_command
			;;
		"$CMD_CREATE")
			require_server_id
			if ! server_exists; then
				create
			else
				echo $(date "+$DATE_FORMAT:") "MCServer #$SERVER_ID: Server already exists!"
				exit $ERROR_SERVER_EXISTS
			fi
			;;
		"$CMD_UPDATE")
			require_server_exists
			update
			;;
		"$CMD_DESTROY")
			require_server_inactive
			read -p "Delete world data and configuration of server #$SERVER_ID? [y/n]" -n 1 -r; echo ""
			if [[ $REPLY =~ ^[Yy]$ ]]; then
				remove
			fi
			;;
		"$CMD_PRINT_EXISTS")
			require_server_id
			print_exists
			;;
		"$CMD_PRINT_SCREEN")
			require_server_id
			print_screen
			;;
		"$CMD_PRINT_ACTIVE")
			require_server_id
			print_active
			;;
		"$CMD_PRINT_INACTIVE")
			require_server_id
			print_inactive
			;;
		*)
			help
			exit $ERROR_UNKNOWN_COMMAND
			;;
	esac
fi

exit $SUCCESS
