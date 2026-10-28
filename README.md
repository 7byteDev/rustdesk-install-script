# RustDesk Server OSS — Interactive Docker Installer

A menu-driven Bash installer for deploying a self-hosted RustDesk Server OSS on Linux. Install Docker when needed, deploy the ID and relay services, and display the public key required by your RustDesk clients.

The installer uses the official `rustdesk/rustdesk-server` image and Docker Compose with host networking. All persistent RustDesk data is stored directly on the host under `/rustdesk-server`.

## Features

- Colored ASCII banner and English interactive menus.
- Docker Engine and Compose installation from Docker's official APT repository on Ubuntu and Debian.
- Reuse of an existing Docker installation with a working Compose plugin.
- Interactive public domain or IPv4 address configuration.
- Deployment of `hbbs` (ID/rendezvous) and `hbbr` (relay).
- Automatic key generation by RustDesk on first startup and public key display.
- Persistent bind mounts, automatic container restart, and bounded container logs.
- Status, logs, restart, update, and uninstall actions.
- Optional RustDesk port rules for an already active UFW firewall.
- Preservation of Docker and unrelated containers during uninstall.

## Requirements

| Requirement | Details |
| --- | --- |
| Host | Linux; automatic Docker installation is implemented for Ubuntu and Debian with systemd and APT |
| Privileges | Root or `sudo` |
| Terminal | Interactive Bash session |
| Network | Internet access to the OS repositories, Docker repository, and container registry |
| Address | Reachable public IPv4 or a domain pointing to the server |
| Ports | TCP `21115–21117` and UDP `21116` available on the host |
| Architecture | Must be supported by both Docker and the selected RustDesk image |

If Docker is already installed, the installer does not replace it or automatically install a missing Compose plugin. It stops with an explanation if the plugin is missing. It also refuses to remove conflicting container-runtime packages automatically.

Windows, macOS, rootless Docker, and non-systemd environments are outside the intended deployment scope. IPv6-only server addresses are not accepted by the address prompt.

## Quick start

1. Download `install-rustdesk.sh` from this repository and copy it to your server. Review it before running it as root.
2. Start the installer in an interactive terminal:

   ```bash
   sudo bash install-rustdesk.sh
   ```

3. Select **1 — Install / Update deployment**.
4. Enter the server's public domain or IPv4 address, for example `rustdesk.example.com`. Do not include a URL scheme, path, or port.
5. Confirm the deployment. If UFW is active, choose whether to add the required RustDesk rules.
6. Configure your cloud firewall or router and enter the displayed settings in your RustDesk clients.

You can run the script again at any time to access the management menu.

Confirmation prompts use `[n/Y]`: press Enter to accept **Yes**, or type `n` to decline. Permanent data deletion still requires the additional explicit `DELETE` confirmation.

## Interactive menu

```text
  ____            _   ____            _
 |  _ \ _   _ ___| |_|  _ \  ___  ___| | __
 | |_) | | | / __| __| | | |/ _ \/ __| |/ /
 |  _ <| |_| \__ \ |_| |_| |  __/\__ \   <
 |_| \_\\__,_|___/\__|____/ \___||___/_|\_\
             SERVER OSS | DOCKER

  1) Install / Update deployment
  2) Show status
  3) Show public key and client settings
  4) Show logs
  5) Restart RustDesk
  6) Firewall guidance / UFW rules
  7) Uninstall RustDesk (keep Docker)
  0) Exit

Select an option:
```

The banner and informational messages use cyan, success messages use green, and errors use red. To disable colors:

```bash
sudo env NO_COLOR=1 bash install-rustdesk.sh
```

## Deployment and persistent storage

| Host path | Purpose |
| --- | --- |
| `/rustdesk-server/compose.yml` | Generated Compose configuration |
| `/rustdesk-server/server-address` | Address entered during deployment |
| `/rustdesk-server/hbbs/` | Persistent ID-server data, database, and key files |
| `/rustdesk-server/hbbr/` | Persistent relay-server working directory |
| `/rustdesk-server/compose.yml.backup-*` | Previous Compose files saved before overwriting |

Each data directory is mounted at `/root` in its respective container. Container names are `hbbs` and `hbbr`; the Compose project is `rustdesk-server`.

Both services use `network_mode: host` and `restart: unless-stopped`. The ID server advertises the configured relay as `<server-address>:21117`.

The installer stops if a container named `hbbs` or `hbbr` belongs to another Compose project or was created independently. Resolve that conflict before retrying.

## Firewall and DNS

Allow the following inbound traffic to the RustDesk host:

| Protocol | Port | Service |
| --- | --- | --- |
| TCP | `21115` | NAT type test |
| TCP | `21116` | Connection service and TCP hole punching |
| UDP | `21116` | Registration and heartbeat |
| TCP | `21117` | Relay service |

The installer can add these rules to an **already active UFW firewall** after confirmation. It does not enable UFW, configure other firewall managers, change cloud rules, or configure router port forwarding.

For Google Cloud, create an ingress allow rule in the VM's VPC network and ensure the rule targets the VM through a matching network tag or another applicable target. An unmatched target tag means the rule does not apply to that VM.

If using a domain, point its DNS A record to the server's public IPv4 address. For Cloudflare-managed DNS, use **DNS only** for a direct connection; the standard HTTP proxy is not a proxy for these RustDesk ports.

Ports `21118` and `21119` support WebSocket clients and should remain closed publicly for this deployment. Web clients require a separate reverse proxy configuration. Port `21114` is for the Pro web console; **RustDesk Server OSS does not include that administration console**.

## Configure RustDesk clients

In the RustDesk application, open **Settings → Network → ID/Relay server**:

| Field | Value |
| --- | --- |
| ID server | Your public domain or IPv4 address |
| Relay server | The same public domain or IPv4 address |
| API server | Leave empty |
| Key | The complete public key displayed by the installer |

To display the public key again, select menu option **3**, or run:

```bash
sudo cat /rustdesk-server/hbbs/id_ed25519.pub
```

The public key may be distributed to clients. Keep the private `id_ed25519` file confidential. Retain both key files in your backups to preserve the server identity.

## Updates and backups

Select menu option **1** to pull the current `latest` image and recreate services as needed. Existing data and key files remain in their host directories. An existing Compose file is backed up before being replaced; these configuration copies are **not database backups**.

The installer manages `compose.yml` and rewrites it on deployment. Preserve any manual customizations separately. Updates can briefly interrupt active connections and do not provide automatic rollback.

Before updating, make a consistent backup while the services are stopped:

```bash
sudo docker compose --project-name rustdesk-server -f /rustdesk-server/compose.yml stop
sudo tar -czf "/root/rustdesk-backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C / rustdesk-server
sudo docker compose --project-name rustdesk-server -f /rustdesk-server/compose.yml start
```

Backups contain private keys and should be stored securely. For version-pinned deployments, maintain your own Compose configuration rather than rerunning this installer's deployment action, which uses `latest`.

## Uninstall

Select menu option **7** to remove the RustDesk Compose containers. The script then asks separately whether to delete `/rustdesk-server`, including the database and keys. Permanent deletion requires typing `DELETE`.

Docker, downloaded images, unrelated containers, and previously added firewall rules remain installed or configured. If you retain the data, it can be reused when deploying again.

## Troubleshooting

Show service status:

```bash
sudo docker compose --project-name rustdesk-server -f /rustdesk-server/compose.yml ps -a
```

Show recent logs:

```bash
sudo docker compose --project-name rustdesk-server -f /rustdesk-server/compose.yml logs --tail=100
```

Check host listeners:

```bash
sudo ss -lntup | grep -E ':(21115|21116|21117)\b'
```

If clients cannot connect, check DNS, cloud firewall targets, host firewall rules, router forwarding, and the client key. With host networking, Docker's port-mapping column may be empty; inspect host listeners instead.

If deployment fails, the installer exits with a line number. Inspect the error and logs before retrying: earlier package, configuration, or container changes are not automatically rolled back.

## Validation status

The script has been checked for Bash syntax and its interactive menu has been exercised. A complete Docker installation and live RustDesk client connection have not been tested in the authoring environment. Confirm end-to-end connectivity on your target server after deployment.

## References

- [RustDesk Server OSS Docker documentation](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/)
- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Engine installation on Debian](https://docs.docker.com/engine/install/debian/)

This installer is an independent helper and is not an official RustDesk or Docker project. The RustDesk image and Docker packages retain their respective upstream licenses.
