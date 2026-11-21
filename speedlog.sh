#!/bin/bash
# speedlog.sh — run an Ookla speedtest and append one CSV row that also
# records which connection the test ran over (wired / Wi-Fi / none),
# plus Wi-Fi details: network name, base station (BSSID), signal, noise,
# channel and link rate.
#
# macOS. Run from root's crontab (sudo crontab -e) so that `wdutil`
# can read the Wi-Fi details. Requires Ookla's `speedtest` and `jq`
# (jq ships with macOS 15+; otherwise `brew install jq`).

PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

OWNER="alan"                                  # <- your macOS username
LOG="/Users/$OWNER/Dropbox/speedlog/$(hostname -s).csv"

mkdir -p "$(dirname "$LOG")"
if [ ! -s "$LOG" ]; then
  echo "timestamp,link,iface,ssid,bssid,rssi_dbm,noise_dbm,channel,tx_rate_mbps,ping_ms,jitter_ms,packet_loss_pct,down_mbps,up_mbps,server,isp,result_url" > "$LOG"
fi

TS=$(date +%Y-%m-%dT%H:%M:%S%z)

# Which interface carries the default route right now, and is it Wi-Fi?
IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
WIFI_DEV=$(networksetup -listallhardwareports | awk '/Hardware Port: (Wi-Fi|AirPort)/{getline; print $2}')

SSID= BSSID= RSSI= NOISE= CHAN= TXRATE=
if [ -z "$IFACE" ]; then
  LINK=none
elif [ "$IFACE" = "$WIFI_DEV" ]; then
  LINK=wifi
  # ipconfig getsummary gives unredacted SSID/BSSID on macOS 14.5+
  # (requires: sudo ipconfig setverbose 1  — persists across reboots)
  IPC=$(ipconfig getsummary "$IFACE" 2>/dev/null)
  SSID=$(echo "$IPC"  | awk -F' : ' '/^ +SSID :/{print $2}')
  BSSID=$(echo "$IPC" | awk -F' : ' '/^ +BSSID :/{print $2}')
  # wdutil still provides signal metrics even though it redacts SSID/BSSID
  W=$(wdutil info 2>/dev/null)
  field() { echo "$W" | awk -F' : ' -v k="$1" '{gsub(/^ +| +$/,"",$1)} $1==k{print $2; exit}'; }
  RSSI=$(field "RSSI" | awk '{print $1}')
  NOISE=$(field "Noise" | awk '{print $1}')
  CHAN=$(field "Channel")
  TXRATE=$(field "Tx Rate" | awk '{print $1}')
else
  LINK=wired
fi

# Run the test. Failures are logged too: drop-outs are useful evidence.
if [ "$LINK" = none ]; then
  RES=',,,,,"FAILED",,'
else
  TMPFILE=$(mktemp)
  R=$(librespeed-cli --json --share 2>"$TMPFILE")
  EXIT=$?
  STDERR=$(cat "$TMPFILE"); rm -f "$TMPFILE"
  if [ $EXIT -eq 0 ]; then
    RES=$(echo "$R" | jq -r '[
        .[0].ping, .[0].jitter, "",
        (.[0].download * 100 | round / 100),
        (.[0].upload   * 100 | round / 100),
        .[0].server.name, "", .[0].share
      ] | @csv')
  else
    RES=',,,,,"FAILED",,'
  fi
fi

printf '%s,%s,%s,"%s",%s,%s,%s,"%s",%s,%s\n' \
  "$TS" "$LINK" "$IFACE" "$SSID" "$BSSID" "$RSSI" "$NOISE" "$CHAN" "$TXRATE" "$RES" >> "$LOG"

chown "$OWNER" "$(dirname "$LOG")" "$LOG" 2>/dev/null
