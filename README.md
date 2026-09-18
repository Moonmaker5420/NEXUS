# NEXUS

**Network Access & Control Platform**

NEXUS is a self-hosted captive-portal and network-access management platform built around **openNDS**, **FreeRADIUS**, **MariaDB**, and custom Flask applications.

It provides centralized management for access plans, vouchers, MAC-based access, users, live sessions, bandwidth limits, data quotas, and portal activity.

## Features

- Username/password authentication through FreeRADIUS
- Voucher-based internet access
- MAC-address allow-list access
- Reusable plans with session duration, bandwidth, and quota policies
- Upload and download rate limits
- Upload and download data quotas
- Voucher expiry and usage management
- RADIUS user management
- Live client-session monitoring
- Client deauthentication through `ndsctl`
- Portal authentication and usage reporting
- Banner and advertisement management
- openNDS External Authentication Server (FAS)
- RADIUS accounting integration
- Linux routing, NAT, and traffic-control integration

## Architecture

```text
                         INTERNET
                            |
                     WAN / enp2s0
                    192.168.1.0/24
                            |
                    +----------------+
                    | NEXUS Gateway  |
                    | Linux Server   |
                    +----------------+
                            |
                    LAN / enp3s0
                   192.168.50.0/24
                            |
                 Wi-Fi / Wired Clients
                            |
                         openNDS
                            |
                      NEXUS FAS
                   192.168.50.1:2080
                            |
                       FreeRADIUS
                            |
                         MariaDB
                            |
                    NEXUS Dashboard
                       Port 8090
```

## Authentication Flow

```text
Client connects
      |
      v
openNDS intercepts traffic
      |
      v
NEXUS FAS login page
      |
      +--> Voucher
      +--> Username/password
      +--> MAC allow-list
      |
      v
FreeRADIUS validation
      |
      v
NEXUS applies plan rules
      |
      v
openNDS authorizes the client
      |
      v
Traffic control and quota enforcement
      |
      v
Internet access
```

## Components

| Component | Purpose |
|---|---|
| openNDS | Captive portal gateway and client authorization |
| NEXUS FAS | External Authentication Server and login interface |
| FreeRADIUS | Authentication and policy backend |
| MariaDB | Portal and RADIUS data storage |
| Flask | Dashboard and FAS applications |
| Gunicorn | Production WSGI server |
| dnsmasq | DHCP and DNS services |
| iptables/nftables | Routing, NAT, and firewall integration |
| systemd | Service management |

## Default Endpoints

| Service | Default address |
|---|---|
| Dashboard | `http://<dashboard-ip>:8090` |
| FAS | `http://192.168.50.1:2080/fas/login` |
| openNDS MHD server | `http://192.168.50.1:2050` |
| Client status hostname | `status.client` |

> The administration dashboard should be restricted to the management/WAN-side network and must not be exposed to untrusted captive-portal clients.

## Example Network Configuration

| Setting | Example |
|---|---|
| WAN interface | `enp2s0` |
| WAN address | `192.168.1.44` |
| Upstream gateway | `192.168.1.1` |
| Portal interface | `enp3s0` |
| Portal gateway | `192.168.50.1` |
| Portal network | `192.168.50.0/24` |

Enable IPv4 forwarding:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Add source NAT for the portal network:

```bash
sudo iptables -t nat -A POSTROUTING \
  -s 192.168.50.0/24 \
  -o enp2s0 \
  -j MASQUERADE
```

Persist this rule using the firewall-management method selected for the host.

## Services

```text
mariadb
freeradius
dnsmasq
portal-tc-init
portal-fas
portal-dashboard
opennds
```

Check service status:

```bash
sudo systemctl status portal-fas
sudo systemctl status portal-dashboard
sudo systemctl status opennds
sudo systemctl status freeradius
sudo systemctl status mariadb
sudo systemctl status dnsmasq
```

Check openNDS:

```bash
sudo ndsctl status
sudo ndsctl json
```

Follow logs:

```bash
sudo journalctl -u portal-dashboard -f
sudo journalctl -u portal-fas -f
sudo journalctl -u opennds -f
sudo journalctl -u freeradius -f
```

## Security Considerations

Before production use:

- Replace all development/default secrets.
- Use a strong `DASHBOARD_SECRET_KEY`.
- Protect `/etc/portal/dashboard.env` and `/etc/portal/fas.env`.
- Restrict dashboard access by interface binding and firewall rules.
- Use HTTPS or a trusted reverse proxy for administration.
- Protect FreeRADIUS shared secrets.
- Grant database users only the privileges they require.
- Review `sudoers` permissions for the `portal` account.
- Persist and audit NAT/firewall rules.
- Back up both portal and RADIUS databases.
- Avoid exposing credentials or client information in issue reports.

Recommended permissions:

```bash
sudo chmod 0600 /etc/portal/dashboard.env
sudo chmod 0600 /etc/portal/fas.env
sudo chown root:portal /etc/portal/dashboard.env
sudo chown root:portal /etc/portal/fas.env
```

## Troubleshooting

### Authenticated client has no internet

Check:

```bash
ip route
sudo sysctl net.ipv4.ip_forward
sudo iptables -t nat -L POSTROUTING -n -v
sudo ndsctl status
```

Verify that a MASQUERADE rule exists for the portal subnet:

```bash
sudo iptables -t nat -S POSTROUTING
```

### Database access denied

Verify the dashboard database credentials and privileges for:

```text
portal
radius
```

Inspect the environment file carefully and do not share passwords in logs or screenshots:

```bash
sudo cat /etc/portal/dashboard.env
```

### Gunicorn worker timeouts

Inspect logs and system resources:

```bash
sudo journalctl -u portal-dashboard -n 100 --no-pager
free -h
```

Investigate slow requests, blocked subprocesses, database delays, and memory pressure before increasing Gunicorn timeouts.

## Operational Notes

- The dashboard reads live client data through `ndsctl json`.
- Client deauthentication uses `ndsctl deauth`.
- FreeRADIUS performs authentication.
- Portal-specific business rules are stored in the portal database.
- Bandwidth limits and quotas are passed to openNDS traffic-control mechanisms.
- Portal authentication logs and RADIUS accounting data should be reviewed together.
- NAT and firewall configuration is deployment-specific and must be tested after reboot.

## Roadmap

- Role-based dashboard permissions
- Dashboard audit logs
- Automatic NAT and forwarding validation
- Improved accounting Stop synchronization
- Live bandwidth and quota charts
- Multi-gateway support
- VLAN-aware access policies
- Device and access-point inventory
- API tokens
- Backup and restore
- HTTPS-first deployment
- Service-failure alerting

## Contributing

When reporting an issue, include:

- Operating system and version
- openNDS version
- FreeRADIUS version
- Network interface layout
- Service status
- Sanitized logs
- Reproduction steps

Never include passwords, shared secrets, private keys, database credentials, or unnecessary client-identifying data.

## License

Add the intended open-source license before publishing the repository. Without a license, the code should not be assumed to be freely reusable.
