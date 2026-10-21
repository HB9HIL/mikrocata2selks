<h1 align="center">Welcome to Mikrocata2SELKS 👋</h1>
<p>
  <img alt="Version" src="https://img.shields.io/badge/version-4.0.0-blue.svg?cacheSeconds=2592000" />
  <a href="https://github.com/angolo40/mikrocata2selks" target="_blank">
    <img alt="License: MIT" src="https://img.shields.io/github/license/angolo40/Mikrocata2SELKS" />
  </a>
</p>


![Selks](Screenshot_20250228_142832.png)

## 📋 Introduction

Mikrocata2SELKS is a streamlined solution for integrating Mikrotik devices with a powerful Network Detection and Response (NDR) system for packet analysis.
It automates the setup process and enables efficient network traffic monitoring and threat detection.

**IMPORTANT UPDATE**: Stamus Networks has removed the SELKS repository (https://github.com/StamusNetworks/SELKS.git). As a result, this project now exclusively supports **Clear NDR** (the evolution of SELKS). SELKS installation is no longer available.

```mermaid
graph LR
    A[Mikrotik Router] -->|TZSP Traffic| B[Mikrocata]
    B -->|Analysis| C[Clear NDR - Suricata on OpenSearch]
    C --> D[Telegram Notifications]
    C --> E[Firewall Rules]
```

**Minimum Requirements:**
- 4 CPU cores
- 10 GB of free RAM
- Minimum 10 GB of free disk space (actual disk usage will mainly depend on the number of rules and the amount of traffic on the network - 200GB+ SSD grade recommended).

## 📚 Documentation
For a comprehensive step-by-step installation guide with detailed explanations, screenshots, and troubleshooting tips, please visit:
[Complete Installation Guide](https://www.sec-ttl.com/mikrocata2selks-integrating-mikrotik-with-suricata-for-network-security/)

## 🚀 Installation

The installation process is now fully interactive!

1. Set up a fresh Debian 12 or 13 installation on a dedicated machine (server or VM).
2. Log in as root.
3. Install Git: `apt install git`.
4. Clone this repository: `git clone https://github.com/angolo40/mikrocata2selks.git`.
5. Navigate to the repository directory: `cd mikrocata2selks`.
6. Run the interactive installer: `./easyinstall.sh`.
7. Follow the on-screen menu:
    - **Install Clear NDR**: The installer will set up Clear NDR with support for one Mikrotik device.
    - **Configure**: The script will prompt you for necessary information, like the installation path.
    - **Wait...**: The script will handle the rest.
8. Once finished, edit the configuration file `/etc/mikrocata/tzsp0.env` with your Mikrotik and Telegram parameters, then restart the service: `systemctl restart mikrocata@tzsp0.service`.
9. Configure your Mikrotik devices as described below.

## 📡 Mikrotik Setup

1. Enable sniffer:
    ```sh
    /tool/sniffer/set filter-stream=yes streaming-enabled=yes streaming-server=[YOURDEBIANIP]:37008
    /tool/sniffer/start
    ```
2. Add firewall rules:
    ```sh
    /ip/firewall/raw/add action=drop chain=prerouting comment="IPS-drop_in_bad_traffic" src-address-list=Suricata
    /ip/firewall/raw/add action=drop chain=prerouting comment="IPS-drop_out_bad_traffic" dst-address-list=Suricata
    /ipv6/firewall/raw/add action=drop chain=prerouting comment="IPS-drop_in_bad_traffic" src-address-list=Suricata
    /ipv6/firewall/raw/add action=drop chain=prerouting comment="IPS-drop_out_bad_traffic" dst-address-list=Suricata
    ```
3. Enable Mikrotik API:
   You have two options:
   - For SSL connection (recommended):
    ```sh
    /ip/service/set api-ssl address=[DEBIANIP]
    ```
   - For non-SSL connection (default settings):
    ```sh
    /ip/service/set api address=[DEBIANIP]
    ```
   
   Then configure the corresponding settings in `/etc/mikrocata/tzsp0.env`:
   ```sh
   USE_SSL=true                   # API port 8729 with SSL, 8728 without
   ALLOW_SELF_SIGNED_CERTS=false  # Set to true only if using self-signed certificates
   ```
4. Add Mikrocata user in Mikrotik:
    ```sh
    /user/add name=mikrocata2selks password=xxxxxxxxxxxxx group=full (change password)
    ```

## ⚙️ Mikrocata Configuration

The configuration lives in `/etc/mikrocata/tzsp0.env`, separate from the code. Updates never overwrite it.
All options are documented in [`mikrocata.env.example`](mikrocata.env.example).

```bash
nano /etc/mikrocata/tzsp0.env
```

### Essential Settings

1. **Mikrotik Connection:**
   ```sh
   ROUTER_IP="192.168.0.1"
   USERNAME="mikrocata2selks"
   PASSWORD="password"
   ```
   The service refuses to start until these are set.

2. **Telegram Notifications (optional):**
   ```sh
   ENABLE_TELEGRAM=true
   TELEGRAM_TOKEN="your_bot_token"
   TELEGRAM_CHATID="your_chat_id"
   ```

3. **Timezone Configuration:**
   ```sh
   # Offset in hours from UTC
   TIMEZONE_OFFSET=1
   ```
   This setting ensures that timestamps in Telegram notifications and MikroTik comments display in your local timezone instead of UTC.
   Examples: `0` UTC, `1` CET, `3` MSK, `-5` EST, `-8` PST, `8` CST.

Quote values containing spaces or special characters with `"..."` and escape the characters `` \ " $ ` `` inside them with a backslash.

After editing the configuration, restart the service:
```bash
systemctl restart mikrocata@tzsp0.service
```

## ⬆️ Update

```bash
cd mikrocata2selks
git pull
./easyinstall.sh update
```

The update installs the new code and systemd units and restarts the services. Your configuration in `/etc/mikrocata` and the saved address lists in `/var/lib/mikrocata` are kept.

**Upgrading from v4.x:** `update` migrates your settings from `/usr/local/bin/mikrocataTZSP0.py` into `/etc/mikrocata/tzsp0.env` and replaces the old `mikrocataTZSP0` / `TZSPreplay37008@tzsp0` services with `mikrocata@tzsp0` / `tzsp-replay@tzsp0`. Review the generated file afterwards.

## 🛠️ Handling Multiple Mikrotik Devices

**Official Support**: The Clear NDR installation officially supports **one Mikrotik device**. The installer will automatically configure a single device setup.

**Manual Multi-Device Configuration**: While SELKS previously supported multiple Mikrotik devices out of the box, it is still possible to configure multiple devices with Clear NDR, but this must be done **manually**. Documentation for manual multi-device setup will be integrated in future updates.

For reference, a multi-device setup would involve:
- Creating additional dummy interfaces (`tzsp1`, `tzsp2`, etc.) on different ports (`37009`, `37010`, etc.)
- Creating a configuration per device (`/etc/mikrocata/tzsp1.env`, ...) with its own `TZSP_PORT`
- Enabling the service instances (`mikrocata@tzsp1`, `tzsp-replay@tzsp1`, ...)
- Configuring each Mikrotik device to send traffic to its dedicated port

If you need to manage multiple Mikrotik devices, please wait for the official documentation or contact the maintainer for assistance.

```mermaid
flowchart TD
    subgraph Mikrotik_Devices
        M0[Mikrotik0 Port:37008]
        M1[Mikrotik1 Port:37009]
        M2[Mikrotik2 Port:37010]
    end

    subgraph Debian_Server ["Debian Server (Clean NDR)"]
        subgraph Interfaces
            I0[Interface:tzsp0 Port:37008]
            I1[Interface:tzsp1 Port:37009]
            I2[Interface:tzsp2 Port:37010]
        end

        subgraph Mikrocata_Services
            S0[mikrocata@tzsp0]
            S1[mikrocata@tzsp1]
            S2[mikrocata@tzsp2]
        end

        subgraph Analysis
            suricata[Suricata IDS/IPS\nDocker Container]
            telegram[Telegram\nNotifications]
        end
    end

    M0 -->|TZSP Traffic| I0
    M1 -->|TZSP Traffic| I1
    M2 -->|TZSP Traffic| I2

    I0 -->|Packet Analysis| S0
    I1 -->|Packet Analysis| S1
    I2 -->|Packet Analysis| S2

    S0 -->|Alerts| suricata
    S1 -->|Alerts| suricata
    S2 -->|Alerts| suricata

    suricata -->|Block Notifications| telegram
    
    style Debian_Server fill:#f5f5f5,stroke:#333,stroke-width:2px
    style Mikrotik_Devices fill:#e1f5fe,stroke:#333,stroke-width:2px
    style Analysis fill:#e8f5e9,stroke:#333,stroke-width:2px
```

## 💡 Features

- Installs Docker and Docker Compose.
- Installs Python dependencies from the Debian repositories.
- Installs **Clear NDR**: The next-generation open-source NDR platform.
  - **Note**: SELKS is no longer supported due to repository removal by Stamus Networks.
- Downloads and installs Mikrocata.
- Installs TZSP interface for packet capture.
- Enables notifications over Telegram when an IP is blocked.
- Updates in place without touching your configuration.
- Includes a complete uninstallation option.

## 🔄 Changelog

- View CHANGELOG.md

## 🔧 Troubleshooting

- Check if packets are arriving at the VM from Mikrotik through the dummy interface:
    ```sh
    tcpdump -i tzsp0
    ```
- Check if mikrocata service and tzsp0 interface are up and running:
    ```sh
    systemctl status mikrocata@tzsp0.service
    systemctl status tzsp-replay@tzsp0.service
    ```
- Check if Suricata Docker container is up and running:
    ```sh
    docker logs -f suricata
    ```
    if suricata shows 'Fatal glibc error: CPU does not support x86-64-v2' and you are under Proxmox Ve, please set CPU processor to HOST


## 📝 Notes
- Access Clear NDR web interface:
    - URL: `https://[YOURDEBIANIP]`
    - Username: clearndr
	- Password: clearndr

## 👤 Author

**Giuseppe Trifilio**

- [Website](https://github.com/angolo40/mikrocata2selks)
- [GitHub](https://github.com/angolo40)

Inspired by [zzbe/mikrocata](https://github.com/zzbe/mikrocata).

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Check the [issues page](https://github.com/angolo40/mikrocata2selks).

## 🌟 Show Your Support

Give a ⭐️ if this project helped you!

- **XMR**: `87LLkcvwm7JUZAVjusKsnwNRPfhegxe73X7X3mWXDPMnTBCb6JDFnspbN8qdKZA6StHXqnJxMp3VgRK7DcS2sgnW3wH7Xhw`
