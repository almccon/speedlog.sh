# Speedtest logging project

## Purpose
Run scheduled internet speed tests and log them with details of the
connection used, to diagnose home broadband vs. Wi-Fi problems. Later
goal: collect logs from several always-on machines at different work
locations and plot them.

## Background and decisions
- Replaced sivel/speedtest-cli (archived 2026; Homebrew disabling it)
  with **librespeed-cli** (`brew tap librespeed/tap && brew install librespeed-cli`).
  Ookla's official CLI was tried first but rate-limited aggressively even at
  20-minute intervals. librespeed-cli has no rate limits and needs no license flags.
- librespeed-cli outputs a JSON array; fields are snake_case (`.ping`, `.download`,
  etc.) and bandwidth is already in **Mbps**. Packet loss, ISP name, and client IP
  are not available; those CSV columns stay empty. The `share` URL field is empty
  unless the server supports it.
- Main machine: a macOS laptop that moves between wired Ethernet and
  several Wi-Fi networks, so every log row records which connection it
  used rather than keeping separate logs.
- Home Wi-Fi is a TP-Link Deco mesh. The BSSID identifies which Deco unit
  (and band) the laptop is on; a BSSID→unit lookup table still needs to be
  built (calibrate by standing next to each unit, or match against unit
  MAC addresses in the Deco app). Slow results on a satellite unit with a
  strong signal may mean weak wireless backhaul to the main unit.

## speedlog.sh
- Runs from **root's crontab** (`sudo crontab -e`), because `wdutil info`
  needs root to report Wi-Fi details. Currently set to `*/5 * * * *`
  (every 5 min); Ookla rate-limits aggressive polling so don't go faster.
- Appends one CSV row per run to `/Users/<OWNER>/speedlog/<hostname>.csv`.
- Columns: timestamp (UTC), link (wired/wifi/none), iface, ssid, bssid,
  rssi_dbm, noise_dbm, channel, tx_rate_mbps, ping_ms, jitter_ms,
  packet_loss_pct, down_mbps, up_mbps, server, isp, result_url.
- Failed tests are logged as rows with server = "FAILED" (network error or no link).
- Requires `jq` (built into macOS 15+, else Homebrew).
- Known caveats: recent macOS may show SSID/BSSID as `<redacted>`; cron
  may need Full Disk Access; no tests run while the laptop sleeps.
- Tested and working on wired and Wi-Fi. On recent macOS, SSID/BSSID show as
  `<redacted>` due to privacy restrictions — all other Wi-Fi fields (RSSI, noise,
  channel, tx rate) are populated correctly.

## Privacy
Never commit log files (`*.csv`, `speedlog/` are in `.gitignore`).
BSSIDs can be geolocated via public Wi-Fi databases.

## Planned next steps
1. Verify Wi-Fi rows and build the Deco BSSID lookup table.
2. Extend `plotscript` (adapted from ansemjo/speedtest-plotter) to split
   lines by link type and BSSID.
3. Later: a hub machine (old Intel Mac Mini running Debian/Ubuntu Server,
   or a small VPS) that receives logs from remote machines via rsync over
   SSH (old OS X machines can't use Dropbox anymore), optionally pushes
   them to Dropbox with rclone, and generates plots.
