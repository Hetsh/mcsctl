#!/usr/bin/env bash


# Commands
CMD_HELP="help"
CMD_STATUS="status"
CMD_START="start"
CMD_STOP="stop"
CMD_RESTART="restart"
CMD_CREATE="create"
CMD_UPDATE="update"
CMD_DESTROY="destroy"

# Results
SUCCESS="0"
ERROR_UNKNOWN_COMMAND="1"
ERROR_ID_MISSING="2"
ERROR_INSTALL_DIR_MISSING="3"
ERROR_SERVER_APP_MISSING="4"
ERROR_SCRAPE_FAILED="5"
ERROR_DOWNLOAD_FAILED="6"
ERROR_SERVER_ACTIVE="7"
ERROR_EULA_FILE_MISSING="8"
ERROR_PROPERTIES_FILE_MISSING="9"

# Config
MCS_USER="mcs"
MY_NAME="${0##*/}"
MIN_RAM="1024" # in MB
MAX_RAM="1024" # in MB
TIMEOUT="10" # in seconds
SERVER_ID="$2"
SERVER_NAME="mserver$SERVER_ID"
INSTALL_DIR="$HOME/$SERVER_NAME"
SERVER_APP="$INSTALL_DIR/server.jar"


custom_date() {
	echo "$(date +"%Y")-$(date +"%m")-$(date +"%d")_$(date +"%H")-$(date +"%M"):"
}

screen_active() {
	if [ -n "$(screen -list | grep -o "$SERVER_NAME")" ]; then
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
	local PROCESSES="$(ps -h)"
	if [ -n "$(echo "$PROCESSES" | grep -o "$SERVER_APP")" ]; then
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

status() {
	if screen_active; then
		echo -n "Screen active, "
	else
		echo -n "Screen inactive, "
	fi

	if server_active; then
		echo "Server active"
	else
		echo "Server inactive"
	fi
}

start() {
	echo -n $(custom_date) "Starting server... "

	if [ ! -d "$INSTALL_DIR" ]; then
		echo "INSTALL_DIR nicht vorhanden -> aborted"
		exit $ERROR_INSTALL_DIR_MISSING
	fi

	if [ ! -e "$SERVER_APP" ]; then
		echo "SERVER_APP nicht vorhanden -> aborted"
		exit $ERROR_SERVER_APP_MISSING
	fi

	# start screen session
	if ! screen_active; then
		screen -dmS "$SERVER_NAME"
		wait_screen_start
	fi

	# start server application in working directory
	if ! server_active; then
		screen -S "$SERVER_NAME" -p 0 -X stuff "cd \"$INSTALL_DIR\"; java -Xms${MIN_RAM}M -Xmx${MAX_RAM}M -jar \"$SERVER_APP\" nogui\n"
		wait_server_start
	fi

	echo "done"
}

stop() {
	echo -n $(custom_date) "Stopping server... "

	# stop server application with timeout
	if server_active; then
		screen -S "$SERVER_NAME" -p 0 -X stuff "say ACHTUNG! Server wird in $TIMEOUT Sekunden neu gestartet!\n"
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

download() {
	echo -n $(custom_date) "Downloading latest version... "

	if server_active; then
		echo "server active -> aborted"
		exit $ERROR_SERVER_ACTIVE
	fi

	local SERVER_URL=$(curl -s -L "https://minecraft.net/de-de/download/server" | grep -o -P "https://.*server.jar")

	if [ -z "$SERVER_URL" ]; then
		echo "failed to scrape url -> aborted"
		exit $ERROR_SCRAPE_FAILED
	fi

	mkdir -p "$INSTALL_DIR"
	if ! $(curl -s -L -o "$SERVER_APP" "$SERVER_URL"); then
		echo "failed to download jar -> aborted"
		exit $ERROR_DOWNLOAD_FAILED
	fi

	echo "done"
}

configure() {
	echo -n $(custom_date) "Configuring server... "

	# EULA
	echo "eula=TRUE" > "$INSTALL_DIR/eula.txt"

	# Properties
	echo "server-port=$((25564 + $SERVER_ID))
	motd=Welcome to MC-Server #$SERVER_ID.
	player-idle-timeout=5
	snooper-enabled=false
	view-distance=15" > "$INSTALL_DIR/server.properties"

	echo "done"
}

remove() {
	echo -n $(custom_date) "Removing server... "

	if server_active; then
		echo "server active -> aborted"
		exit $ERROR_SERVER_ACTIVE
	fi

	rm -r "$INSTALL_DIR"

	echo "done"
}


help() {
echo "Usage: $MY_NAME {$CMD_HELP|$CMD_STATUS|$CMD_START|$CMD_STOP|$CMD_RESTART|$CMD_CREATE|$CMD_UPDATE|$CMD_DESTROY}
	$CMD_HELP		Prints this help.
	$CMD_STATUS	<id>	Status of a server and its screen session.
	$CMD_START	<id>	Starts a server inside a screen session.
	$CMD_STOP	<id>	Stops a server and its screen session.
	$CMD_RESTART	<id>	Restarts a server.
	$CMD_CREATE	<id>	Creates a server in \"$INSTALL_DIR\".
	$CMD_UPDATE	<id>	Downloads a new minecraft server executable.
	$CMD_DESTROY	<id>	Removes all files of a server."
}


# All parameters require a server id
if [ -z "$SERVER_ID" ]; then
	echo "Missing server id!"
	exit $ERROR_ID_MISSING
fi

# Enforce mcs user, but allow access by admins
if [ "$USER" != "$MCS_USER" ]; then
	sudo -u "$MCS_USER" -s "/usr/bin/bash" "$0" "$@"
	exit $?
fi

case "$1" in
	"$CMD_HELP")
		help
		;;
	"$CMD_STATUS")
		status
		;;
	"$CMD_START")
		start
		;;
	"$CMD_STOP")
		stop
		;;
	"$CMD_RESTART")
		stop
		start
		;;
	"$CMD_CREATE")
		download
		configure
		;;
	"$CMD_UPDATE")
		download
		;;
	"$CMD_DESTROY")
		remove
		;;
	*)
		help
		exit $ERROR_UNKNOWN_COMMAND
		;;
esac

exit $SUCCESS
