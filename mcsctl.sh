#!/usr/bin/env bash


# Commands
CMD_STATUS="help"
CMD_STATUS="status"
CMD_START="start"
CMD_STOP="stop"
CMD_RESTART="restart"
CMD_CREATE="create"
CMD_UPDATE="update"
CMD_DESTROY="destroy"

# Results
SUCCESS="0"
ERROR_ID_MISSING="1"
ERROR_INSTALL_DIR_MISSING="2"
ERROR_SERVER_APP_MISSING="3"
ERROR_SCRAPE_FAILED="4"
ERROR_DOWNLOAD_FAILED="5"
ERROR_SERVER_ACTIVE="6"
ERROR_EULA_FILE_MISSING="7"
ERROR_PROPERTIES_FILE_MISSING="8"

# Config
MCS_USER="mcs"
MCS_SCRIPT="mcsctl"
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
	PROCESSES="$(ps -h)"
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


# All parameters require a server id
if [ -z "$SERVER_ID" ]; then
	echo "Missing server id!"
	exit $ERROR_ID_MISSING
fi

# Enforce mcs user, but allow access by admins
if [ "$USER" != "$MCS_USER" ]; then
	sudo -u "$MCS_USER" -s "/usr/bin/bash" -c "$0 $*"
	exit
fi


case "$1" in
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
		echo "Usage:

		$CMD_START	id
		$CMD_STOP	id
		$CMD_RESTART	id
		$CMD_CREATE	id
		$CMD_UPDATE	id
		$CMD_DESTROY	id"
		;;
esac

exit $SUCCESS
