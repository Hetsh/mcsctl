# mcsctl

This simple bash script helps you manage minecraft servers on Linux. It is designed to handle multiple servers at once, but works just as fine if you only want to host one. The servers can be automatically started and shut down with the systemd unit template that is also provided.

## Installation

"Prebuilt" packages are currently only provided for Arch Linux. You can just use your aur helper to install it and skip this section.

|[![Foo](https://www.archlinux.org/logos/archlinux-icon-crystal-64.svg)](https://aur.archlinux.org/packages/?K=mcsctl)|
|:---:|
|Arch User Repository|

The following packages must be installed for the script to work properly:
* bash
* grep
* java-runtime-headless>=8
* openbsd-netcat
* jq
* sed
* screen
* sudo

Non-Arch-Linux users can easily install it if you follow these steps as `root`:
```bash
curl -L https://github.com/Hetsh/mcsctl/archive/master.tar.gz | bsdtar -xpf -
install -Dm 644 mcsctl-master/mcs@.service <PATH_TO_UNIT> # usually "/usr/lib/systemd/system/mcs@.service"
install -Dm 755 mcsctl-master/mcsctl.sh <PATH_TO_BIN> # usually /usr/bin/mcsctl
sed -n '/\# Mutable config/,/\# \/Mutable config/p' mcsctl-master/mcsctl.sh | head -n -1 | tail -n +2 > mcsctl-master/mcsctl.conf.bak # strips config from script
install -Dm 644 mcsctl-master/mcsctl.conf.bak /etc/mcsctl.conf.bak
rm -r mcsctl-master
```

Per default, the minecraft servers are run as a different, low privileged user that you need to create:
```bash
useradd --user-group --comment 'Minecraft user' --shell /usr/bin/nologin --create-home mcs
passwd -l mcs
```

## Usage

Servers are assigned unique id's.
These can be specified by the user and must be a positive number.
`mcsctl` will then address each server with its unique id or all servers with the `all` keyword.
```
$ mcsctl help
Usage: mcsctl {help|status|start|stop|restart|console|command|create|update|destroy}
help			Prints this help.
status	<id/all>	Lists status of server(s) and online players.
start	<id/all>	Starts server(s) inside screen session(s).
stop	<id/all>	Stops server(s) and screen session(s).
restart	<id/all>	Restart server(s).
console	<id>		Connect to the screen session of a server.
command	<id/all> <cmd>	Forward <cmd> to specified server(s).
create	<id>		Creates a server in the configured SERVER_ROOT (default: /home/mcs).
update	<id/all>	Downloads a new minecraft server executable for server(s).
destroy	<id/all>	Removes all files of server(s).

$ mcsctl create 1 && mcsctl start 1 # will create a new server with id=1 and start it
$ mcsctl stop all && mcsctl destroy all # will stop and destroy all minecraft servers
```
Similar to this `systemctl enable mcs@1.service` will start and stop the server with id 1 at boot and shutdown respectively. You can also use the `all` keyword here.

## Configuration

`mcsctl` can be configured with a config file `/etc/mcsctl.conf` that is "sourced" on every run.
If no config file is found, the default values are used.
The sample config file that was generated during the installation contains the default values.
```bash
cp /etc/mcsctl.conf.bak /etc/mcsctl.conf
```
This config file is not used to configure your minecraft servers.
