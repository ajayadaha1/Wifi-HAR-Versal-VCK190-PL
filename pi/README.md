# Raspberry Pi CSI source & Ethernet forwarder (nexmon_csi → VCK190)

Pi-side tooling that turns a Raspberry Pi 4B into the live CSI transmitter for the
`Wifi-HAR-Versal-VCK190-PL` pipeline: it activates `nexmon_csi` and streams the CSI
UDP frames out **eth0** so the VCK190's `csi_udp_parser` receives them.

## Why a forwarder?
`nexmon_csi` injects CSI as UDP:5500 broadcast frames onto **wlan0** (the monitor
interface); they never leave the Pi on their own. `csi_forward.py` captures them at
layer 2 and re-emits the nexmon payload as a fresh UDP datagram on **eth0**. Because
the parser keys off standard offsets (ethertype@12, proto@23, dport@36, nexmon@42,
CSI@60), a fresh UDP send on eth0 reproduces those offsets exactly — the payload is
forwarded byte-for-byte.

## Files
| File | Installs to | Role |
|---|---|---|
| `csi_start.sh` | `/usr/local/bin/` | wlan0 → monitor + `nexutil -s500` extractor config |
| `csi_forward.py` | `/usr/local/bin/` | raw capture on wlan0 → UDP send on eth0 (stdlib only) |
| `csi-activate.service` | `/etc/systemd/system/` | oneshot: runs `csi_start.sh` at boot |
| `csi-forward.service` | `/etc/systemd/system/` | runs `csi_forward.py`; `After=csi-activate` |

## Install
```bash
sudo install -m755 csi_start.sh csi_forward.py /usr/local/bin/
sudo install -m644 csi-activate.service csi-forward.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now csi-activate.service csi-forward.service
```

## Configure
Retarget the stream by overriding env in `csi-forward.service` (then `daemon-reload`
+ `restart`): e.g. `CSI_DST_IP=<versal-ip>` for unicast instead of broadcast, or
`CSI_DST_IF`/`CSI_SRC_IF` for other interfaces. Change the CSI channel by editing the
`csi_start.sh 132/80` argument in `csi-activate.service`.

## Verify
```bash
systemctl status csi-activate csi-forward
# on the receiving host (or the Versal), confirm CSI arrives:
sudo tcpdump -i eth0 -nn udp dst port 5500
```

Requires: `nexmon_csi` firmware already installed (`seemoo-lab/nexmon_csi`), i.e.
`/lib/firmware/.../brcmfmac43455-sdio.bin` = the CSI-patched build, and `nexutil`
built with `USE_VENDOR_CMD=1`.
