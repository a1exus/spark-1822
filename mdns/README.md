# mdns

Host-level systemd template service that publishes subdomain aliases via Avahi mDNS. Lets `netdata.spark-1822.local`, `whatever.spark-1822.local`, etc. resolve on the LAN without DNS or `/etc/hosts` entries on each client.

Unlike the other stacks in this repo, this is **not** a Docker compose stack — Avahi's API is on the host's DBus and aliases must be published by a process the host's `avahi-daemon` trusts.

## Files

```
mdns/
├── sparky-mdns-alias            # bash script — publishes one alias
├── sparky-mdns-alias@.service   # systemd template unit
├── Makefile                     # install / uninstall / list
└── README.md
```

## Install

```bash
cd /opt/mdns
make install
```

This copies:

| Source | Destination |
|---|---|
| `sparky-mdns-alias` | `/usr/local/bin/sparky-mdns-alias` (mode 755) |
| `sparky-mdns-alias@.service` | `/etc/systemd/system/sparky-mdns-alias@.service` (mode 644) |

and runs `systemctl daemon-reload`. Re-run after edits.

`make` with no target prints the available targets:

```
$ make
  help         Show this help.
  install      Install the script + systemd template unit (idempotent).
  uninstall    Disable every active alias instance, remove the script + unit.
  list         Show every currently-active alias instance.
  add          Publish a new mDNS alias. Usage: make add ALIAS=<name>
  remove       Stop and disable an mDNS alias. Usage: make remove ALIAS=<name>
  logs         Tail journal for a given alias. Usage: make logs ALIAS=<name>
  resolve      Resolve an alias via mDNS from this host. Usage: make resolve ALIAS=<name>
```

## Add an alias

```bash
make add ALIAS=netdata
# expands to: sudo systemctl enable --now 'sparky-mdns-alias@netdata.spark-1822.local'
```

`HOST` defaults to `$(hostname).local`. To publish under a different domain, pass it explicitly: `make add ALIAS=netdata HOST=other.local`.

Verify from this host:

```bash
make resolve ALIAS=netdata
# expands to: avahi-resolve -n netdata.spark-1822.local
```

Or from a LAN client:

```bash
dig @224.0.0.251 -p 5353 netdata.spark-1822.local   # raw mDNS query
dscacheutil -q host -a name netdata.spark-1822.local   # macOS
```

If the alias misbehaves, tail its journal:

```bash
make logs ALIAS=netdata
```

## Remove an alias

```bash
make remove ALIAS=netdata
# expands to: sudo systemctl disable --now 'sparky-mdns-alias@netdata.spark-1822.local'
```

## Uninstall everything

Stops + disables every active alias instance, removes the script and unit file, reloads systemd:

```bash
cd /opt/mdns
make uninstall
```

The repo files under `/opt/mdns/` stay in place so a future `make install` brings everything back.

## How it works

The script discovers the host's primary IPv4 (whichever address Linux uses as the source for outbound traffic to a global address) and runs:

```
avahi-publish -a -R <alias> <ip>
```

`avahi-publish` registers the name on the local Avahi daemon for as long as the process runs. systemd keeps it running (with `Restart=always`), so the alias survives across reboots and avahi-daemon restarts.

The unit is a template — `%i` (the part after `@` in the unit name) is passed to the script as the alias to publish, so one unit definition supports any number of aliases.

## Limitations

- Pins to the IP discovered at service start; if the LAN IP changes (DHCP reassignment), restart the unit. A DHCP hook to do this automatically is a possible follow-up.
- mDNS resolution requires the client to support mDNS (Linux with `avahi-daemon` or `systemd-resolved`, macOS, iOS, Windows 10+).

## See also

- Top-level [README](../README.md).
- Avahi manual: `man avahi-publish`.
