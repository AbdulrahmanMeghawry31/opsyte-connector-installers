# Opsyte Camera Connectivity SOP

Version 1.0 — 2 November 2026

For implementation and support teams. Part A covers direct RTSP; Part B covers an existing client NVR; Part C reproduces the mini3/mini4 lab; Part D covers quality, bandwidth and validation. Replace all placeholders. Store account references, not passwords, in handover records or GitHub.

## Evidence and current status

mini4 relay → mini3 was verified using ffprobe. The final Opsyte test through mini3's NVR channel 2 returned H.264, 1920×1080, 15 fps and a camera image. This proves end-to-end test connectivity. The screen states that nothing was saved by the test: the Add camera step remains necessary unless completed separately. No bandwidth measurement has yet been reported. Windows guidance below was not validated on a Windows machine during this lab.

## A. Direct RTSP camera connection

### A1. Mandatory information per site

- Always-on Windows/Linux computer: OS, architecture, administrator access, internet access and camera-network access.
- Camera make/model, local IP, RTSP port, exact stream URL and camera viewing account.
- Confirm RTSP over TCP and codec; H.264 is the tested baseline.
- Camera name and correct Opsyte branch/location.

Reserve the camera/NVR IP in the router's DHCP settings. The device can remain a DHCP client but receives the same address. This is not a requirement for a public static IP. Disable computer sleep and confirm automatic service startup.

### A2. Install and pair the connector

In Opsyte: **Config → Connectors → Add connector**. Choose the location and name. Copy the current platform-generated installation command, exact API value and fresh one-time pairing code. Do not guess whether the API value includes `/api`. Prefer the platform's current installer over an older copy.

Lab platform: https://opsyte1.blockgemini.dev

Lab installer endpoint: https://opsyte1.blockgemini.dev/api/v1/connectors/install.sh

Installer distribution repository: https://github.com/AbdulrahmanMeghawry31/opsyte-connector-installers

A public repository permits unauthenticated download. A private repository needs authorized GitHub access. Keep copied installers matched to the platform release. Downloading an installer does not install the runtime; the installer also downloads a platform bundle.

**Linux: run on the branch computer**

```bash
mkdir -p ~/opsyte-setup
cd ~/opsyte-setup
curl -fL --retry 3 https://raw.githubusercontent.com/AbdulrahmanMeghawry31/opsyte-connector-installers/main/install.sh -o install.sh
sudo bash ./install.sh --api 'API_VALUE_FROM_OPSYTE' --code 'FRESH_PAIRING_CODE'
sudo systemctl status site-connector --no-pager
sudo journalctl -u site-connector -n 50 --no-pager
```

Default runtime `/opt/site-connector`; state `/var/lib/site-connector`; configuration `/etc/site-connector`. Never copy paired state to another client's machine. Confirm Online in Opsyte, then test video. An installation success message alone is insufficient. Resolve dependency conflicts with a supported bundle; do not blindly upgrade global Python packages.

**Windows: Administrator PowerShell**

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\opsyte-setup"
Set-Location "$env:USERPROFILE\opsyte-setup"
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/AbdulrahmanMeghawry31/opsyte-connector-installers/main/install.ps1' -OutFile 'install.ps1'
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Api 'API_VALUE_FROM_OPSYTE' -Code 'FRESH_PAIRING_CODE'
Get-Service SiteConnector
```

Use the current platform-supported Windows bundle/instructions. `install.ps1` is for Windows; `install.sh` is for Linux.

### A3. Validate connectivity

From the connector machine, check the actual device IP and port:

```bash
python3 - <<'PY'
import socket
with socket.create_connection(('CAMERA_OR_NVR_IP', 554), timeout=5):
    print('TCP port reachable')
PY
```

Then test actual authenticated video through Opsyte or this Linux ffprobe command:

```bash
read -rsp 'Authenticated RTSP URL: ' RTSP_URL
printf '\n'
timeout 30s ffprobe -v error -rtsp_transport tcp \
  -show_entries stream=codec_name,width,height,r_frame_rate \
  -of default=noprint_wrappers=1 "$RTSP_URL"
unset RTSP_URL
```

Enter the complete authenticated URL at the prompt. It is not written into shell history, but may appear in errors/process inspection; redact shared output. A reachable TCP port alone does not prove credentials or video.

Tapo example: `rtsp://CAMERA_USER:ENCODED_PASSWORD@CAMERA_IP:554/stream1`. `/stream1` is high quality; `/stream2` is lower quality. Use the Tapo camera account, not the cloud login. Confirm actual resolution using the selected stream.

### A4. Add and save

Open the correct connector → **My camera isn't listed → A camera** → select the available Other/custom RTSP option. Supply name, URL and credentials, test, then **Add camera** and save where required. Discovered cameras can also be tested and added.

The bottom **Test a camera from the site** box tests only: it does not create an entry. Verify the saved camera has a fresh frame and the correct connector.

| Password location | Required format |
|---|---|
| Separate UI password field or YAML `password:` | Original password |
| Password inside RTSP URL | URL-encoded once (`@` becomes `%40`) |

Do not replace shell variable names with passwords; enter values at prompts.

## B. Existing client NVR

```mermaid
flowchart LR
  A[Store cameras] --> B[Client NVR]
  B -->|Selected RTSP channels over TCP| C[On-site Opsyte connector]
  C -->|Outbound HTTPS| D[Opsyte]
```

For Bassam, repeat per branch using its available computer and existing NVR. The cross-site relay in Part C is not required when the connector can reach the local NVR. Hik-Connect is not the RTSP endpoint, and its cloud account is not automatically the NVR viewing account.

1. Obtain NVR make/model, reserved LAN IP, RTSP port, authorized viewing credentials, selected channel numbers/names, RTSP TCP support and codec/stream settings.
2. Install/pair the connector using Part A. Verify access from the computer to the recorder.
3. In that branch's connector choose **My camera isn't listed → A recorder's channels**.
4. Select the actual brand, NVR IP/port and credentials. Choose main/substream and only agreed channel numbers.
5. Test the generated feeds, **Add all ticked**, then save. Ticked numbers are selections, not detected cameras.
6. Verify each channel appears as its own camera with the correct image.

If the preset does not match the model, obtain its exact vendor RTSP URL and use the manual camera form. Typical Hikvision paths are `/Streaming/Channels/101` (channel 1 main), `/102` (channel 1 sub), `/201` (channel 2 main) and `/202` (channel 2 sub), all beneath `/Streaming/Channels/`; verify on the actual recorder. One viewing account can serve multiple authorized channels on the same IP/port.

Local deployment needs outbound HTTPS from the connector; no public RTSP port forwarding is required. If no computer is available, supply one or design an approved site VPN to a remote connector. Management access alone does not establish camera-network routing.

## C. mini3/mini4 software NVR lab

### C1. Design

```mermaid
flowchart TD
  A[Apartment 2203 camera: 192.168.1.238] -->|Local RTSP| D[mini3 software NVR]
  B[Apartment 2501 camera: 192.168.0.113] -->|Local RTSP| C[mini4 relay: 10.8.0.7:18554]
  C -->|RTSP over VPN| D
  D -->|nvr_ch01 and nvr_ch02| E[mini3 Opsyte connector]
  E -->|Outbound HTTPS| F[Opsyte]
```

| Component | Value |
|---|---|
| mini3 LAN / recorder endpoint | `192.168.1.137:18554` |
| mini4 VPN relay | `10.8.0.7:18554/apart2501` |
| Camera users | `mini03` for 2203; `mini04` for 2501 |
| Relay user | `opsyte_relay` |
| NVR viewing user | `opsyte_nvr` |
| Connector serving both final channels | `mini3-apart2203` |
| NVR paths | `/nvr_ch01` and `/nvr_ch02` |

The camera, relay and NVR are separate authentication layers. Opsyte uses the NVR credentials for both final channels. Choosing an NVR label in Opsyte does not install NVR software. The direct mini4 connector is separate from this relay path.

### C2. Install mini4 relay without Docker

Run on Ubuntu amd64 mini4. The official latest-release URL below was used for this cycle; for repeatable rollouts record and pin a reviewed release/version.

```bash
curl -fL --retry 3 https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64 -o /tmp/opsyte-go2rtc
sudo install -m 755 /tmp/opsyte-go2rtc /usr/local/bin/opsyte-go2rtc
sudo install -d -m 700 /opt/opsyte-rtsp-relay
sudo nano /opt/opsyte-rtsp-relay/go2rtc.yaml
```

Insert, replacing placeholders:

```yaml
streams:
  apart2501:
    - "rtsp://mini04:ENCODED_CAMERA_PASSWORD@192.168.0.113:554/stream1#backchannel=0"
rtsp:
  listen: "10.8.0.7:18554"
  username: "opsyte_relay"
  password: "ORIGINAL_RELAY_PASSWORD"
api:
  listen: ""
webrtc:
  listen: ""
```

```bash
sudo chmod 600 /opt/opsyte-rtsp-relay/go2rtc.yaml
sudo tee /etc/systemd/system/opsyte-rtsp-relay.service >/dev/null <<'UNIT'
[Unit]
Description=Opsyte camera RTSP relay
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0
[Service]
Type=simple
DynamicUser=yes
LoadCredential=go2rtc.yaml:/opt/opsyte-rtsp-relay/go2rtc.yaml
ExecStart=/usr/local/bin/opsyte-go2rtc -config %d/go2rtc.yaml
Restart=always
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now opsyte-rtsp-relay
sudo systemctl status opsyte-rtsp-relay --no-pager
```

Permit mini3 → mini4 TCP 18554 in the VPN/firewall. Listening on the VPN IP avoids a public/LAN listener; restrict peer access using VPN/firewall policy. No router RTSP forwarding is needed. First verify mini3 can reach mini4; then run Part A's video test from mini3 with:

```text
rtsp://opsyte_relay:ENCODED_RELAY_PASSWORD@10.8.0.7:18554/apart2501
```

### C3. mini3 recorder setup

mini3 uses Docker/Frigate with integrated go2rtc. Existing container: `opsyte-nvr-lab`; image used: `ghcr.io/blakeblackshear/frigate:0.18.2`. Config: `/opt/opsyte-nvr-lab/config/config.yml`; compose: `/opt/opsyte-nvr-lab/compose.yaml`.

For a **new lab only**, create config/storage directories and this compose file. Docker and the compose plugin must already be installed using their supported OS instructions. Do not replace an existing deployment with this template.

```yaml
name: opsyte-nvr-lab
services:
  frigate:
    image: ghcr.io/blakeblackshear/frigate:0.18.2
    container_name: opsyte-nvr-lab
    restart: unless-stopped
    shm_size: "512mb"
    volumes:
      - ./config:/config
      - ./storage:/media/frigate
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "192.168.1.137:18554:8554/tcp"
      - "127.0.0.1:18971:8971/tcp"
```

Readable configuration representing the lab's two-stream design:

```yaml
mqtt:
  enabled: false
go2rtc:
  rtsp:
    username: opsyte_nvr
    password: "ORIGINAL_NVR_PASSWORD"
  streams:
    nvr_ch01:
      - "rtsp://mini03:ENCODED_CAMERA_1_PASSWORD@192.168.1.238:554/stream1#backchannel=0"
    nvr_ch02:
      - "rtsp://opsyte_relay:ENCODED_RELAY_PASSWORD@10.8.0.7:18554/apart2501#backchannel=0"
detect:
  enabled: false
motion:
  enabled: false
snapshots:
  enabled: false
record:
  enabled: true
  continuous:
    days: 1
  motion:
    days: 0
  alerts:
    retain:
      days: 0
  detections:
    retain:
      days: 0
cameras:
  nvr_ch01:
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/nvr_ch01
          input_args: preset-rtsp-restream
          roles: [record, detect]
    detect:
      enabled: false
      width: 640
      height: 360
      fps: 1
```

This exposes channel 2 for streaming; it does not enable its Frigate recording. Channel 1 retains its recording configuration. Detect dimensions do not resize the RTSP restream.

For an **existing lab**, preserve all settings and add only `nvr_ch02` under `go2rtc.streams`. Back up first:

```bash
sudo cp -a /opt/opsyte-nvr-lab/config/config.yml "/opt/opsyte-nvr-lab/config/config.yml.backup-$(date +%Y%m%d-%H%M%S)"
```

Validate before restarting (YAML parser confirmed available in this container):

```bash
sudo docker exec opsyte-nvr-lab python3 -c '
import yaml
try:
    with open("/config/config.yml") as f:
        c = yaml.safe_load(f)
    assert all(k in c["go2rtc"]["streams"] for k in ("nvr_ch01", "nvr_ch02"))
    print("VALID: YAML parses and both channels exist")
except yaml.YAMLError as e:
    m = getattr(e, "problem_mark", None)
    raise SystemExit(f"Invalid YAML near line {m.line+1}" if m else "Invalid YAML")
except (KeyError, TypeError, AssertionError):
    raise SystemExit("Missing or incorrectly nested channels")
'
```

This validates syntax/placement, not the full application schema or actual video. After it passes:

```bash
sudo docker restart opsyte-nvr-lab
sudo docker ps -a --filter name=opsyte-nvr-lab
sudo docker logs --tail 60 opsyte-nvr-lab
```

For a new lab, start with `sudo docker compose -f /opt/opsyte-nvr-lab/compose.yaml up -d`; inspect startup logs and test both streams. Redact secrets before sharing logs.

Test both channels with NVR credentials, then add each in Opsyte through mini3 using **A camera → Other/custom RTSP**:

```text
rtsp://opsyte_nvr:ENCODED_NVR_PASSWORD@192.168.1.137:18554/nvr_ch01
rtsp://opsyte_nvr:ENCODED_NVR_PASSWORD@192.168.1.137:18554/nvr_ch02
```

Names: `NVR_Test_Channel` and `NVR_Test_Channel_02`. The Hikvision preset does not match these custom paths. Verify Add/Save, correct images and fresh frames for both.

Rollback: restore the specific known-good backup to `config.yml`, restart the container and re-test channel 1. Never overwrite the backup with a broken configuration.

## D. Quality and bandwidth

### D1. Change camera quality

**mini4 camera:** on mini4, back up the relay file, change only `/stream1#backchannel=0` to `/stream2#backchannel=0`, then restart:

```bash
sudo cp -a /opt/opsyte-rtsp-relay/go2rtc.yaml "/opt/opsyte-rtsp-relay/go2rtc.yaml.backup-$(date +%Y%m%d-%H%M%S)"
sudo nano /opt/opsyte-rtsp-relay/go2rtc.yaml
sudo systemctl restart opsyte-rtsp-relay
sudo systemctl status opsyte-rtsp-relay --no-pager
```

Retest final `/nvr_ch02`. Its URL and credentials stay the same. Confirm actual resolution/fps; substream resolution is model-dependent, not necessarily 720p. Reverse the source change to return to main stream.

**mini3 camera:** change its source under `go2rtc.streams.nvr_ch01`, validate YAML, restart the NVR and retest. This also changes the stream recorded locally for channel 1.

**Client NVR:** use its encoder settings for resolution, fps and bitrate, or select main/substream in Opsyte. Review representative frames after changes. Lower bitrate/detail may impair the intended analytics. No transcoding is explicitly configured in this lab; the relay forwards the selected compressed stream. Opsyte sampling at 1 fps does not mean the RTSP connection receives only 1 fps.

### D2. Measure the right traffic

| Segment | Measurement |
|---|---|
| Camera to PC/NVR | Selected full RTSP feed |
| mini4 to mini3 VPN | Full relayed feed plus transport overhead |
| Connector to Opsyte | Actual upload behavior: samples, live viewing, recordings |

Source bitrate is not cloud-upload bitrate. If the direct mini4 camera remains active, it can upload separately; document that during measurements. Do not disable production feeds without planning the interruption.

### D3. Per-stream bitrate (Linux, ffprobe installed)

Run on mini3 against a final authenticated NVR URL. This opens a reader for roughly 30 seconds and estimates audio/video payload bitrate, excluding transport/VPN overhead. Paste the complete URL at the hidden prompt.

```bash
python3 - <<'PY'
import getpass, json, subprocess
url = getpass.getpass('Authenticated RTSP URL: ')
try:
    r = subprocess.run([
        'ffprobe', '-v', 'error', '-rtsp_transport', 'tcp',
        '-read_intervals', '%+30', '-show_packets',
        '-show_entries', 'packet=size,pts_time,dts_time',
        '-of', 'json', url
    ], capture_output=True, text=True, timeout=45)
except subprocess.TimeoutExpired:
    raise SystemExit('Timed out; verify video connectivity.')
if r.returncode:
    raise SystemExit('Probe failed; verify URL and credentials.')
packets = json.loads(r.stdout).get('packets', [])
times = []
for p in packets:
    try:
        times.append(float(p.get('pts_time', p.get('dts_time'))))
    except (TypeError, ValueError):
        pass
if len(times) < 2 or max(times) <= min(times):
    raise SystemExit('Insufficient timestamps for measurement.')
seconds = max(times) - min(times)
rate = sum(int(p.get('size', 0)) for p in packets)*8/seconds/1e6
print(f'Media payload: {rate:.2f} Mbps over {seconds:.1f} seconds')
print(f'Continuous equivalent: {rate*10.8:.2f} GB/day excluding overhead')
PY
```

Compare main and lower streams under similar motion and lighting. Variable bitrate changes with the scene. A reported resolution alone cannot establish bandwidth.

### D4. Actual VPN traffic

Keep channel 2 actively viewed/consumed. On mini4 run `ip -br addr` to identify the VPN interface; it was `wg0` in the observed setup. Substitute if different:

```bash
python3 - <<'PY'
from pathlib import Path
import time
interface = 'wg0'
root = Path('/sys/class/net') / interface / 'statistics'
def counters():
    return [int((root / f'{d}_bytes').read_text()) for d in ('rx', 'tx')]
a = counters()
start = time.monotonic()
time.sleep(30)
b = counters()
elapsed = time.monotonic() - start
for direction, before, after in zip(('RX', 'TX'), a, b):
    print(f'{interface} {direction}: {(after-before)*8/elapsed/1e6:.2f} Mbps average')
PY
```

mini4 VPN TX includes outgoing relay traffic plus any other VPN traffic. These counters exclude outer WireGuard transport overhead. Router/WAN counters measure actual internet-link use; physical-interface counters include unrelated traffic. Do not add VPN and physical totals as independent traffic. A speed test measures available capacity, not camera consumption.

### D5. Acceptance checklist

Record site, connector, models, reserved IP/port, stream path, credential reference, codec, resolution/fps, measured Mbps, test date and saved Opsyte camera name.

- Both authenticated TCP streams show the intended cameras.
- Saved Opsyte entries have fresh frames through the expected connector.
- Quality supports the required visual task.
- Measured traffic fits available upload with operating headroom.
- Services recover after a planned reboot; lab VPN recovery is included.
- Streaming and recording expectations are documented separately.

## E. Diagnostics

| Symptom | Check |
|---|---|
| Connection refused | Correct endpoint, service listener, startup logs |
| Timeout | Route/VPN, firewall, device power/address |
| 401 | Account layer, original vs URL-encoded password, config reload |
| Stream not found | Channel path and selected profile |
| Container Up but unhealthy | Application logs; published port is not proof of working RTSP |
| YAML error | Restore backup or fix syntax; validate before restarting |
| Test works but no camera entry | Add camera / Add all ticked and Save |

## F. References

- Opsyte: https://opsyte1.blockgemini.dev
- Installers: https://github.com/AbdulrahmanMeghawry31/opsyte-connector-installers
- go2rtc: https://github.com/AlexxIT/go2rtc
- Frigate installation: https://docs.frigate.video/frigate/installation/
- Frigate restream: https://docs.frigate.video/configuration/restream/
- Tapo RTSP instructions: https://www.tapo.com/us/faq/34/
- Tapo RTSP questions: https://www.tp-link.com/ae/support/faq/4465/
- ffprobe: https://www.ffmpeg.org/ffprobe.html

This lab validates multiple RTSP feeds behind one recorder endpoint; it does not certify every recorder model or brand-specific discovery behavior. Commission the client's actual channels before handover.
