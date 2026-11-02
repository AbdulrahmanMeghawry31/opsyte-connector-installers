#!/usr/bin/env bash
# Installs the site connector on a Linux machine at a customer's site (R15j) as a systemd service.
#
#   sudo bash install.sh --api https://<api host> --code XXXX-XXXX            # a bundle install (updates itself)
#   sudo bash install.sh --api https://<api host> --code XXXX-XXXX --docker --image <registry>/site-connector:1.0.0
#
# The pairing code comes from the app (Config → Connectors → Add connector) and works once. The connector keeps its
# own token in /var/lib/site-connector (readable by its user only). Everything it says to the platform goes over
# HTTPS to the API host; nothing listens on this machine.
#
# Options:
#   --api URL          the platform's API address (https://…)
#   --code CODE        the one-time pairing code
#   --docker           run the docker image instead of a bundle (needs docker); a daily timer pulls updates
#   --image IMAGE      the docker image (default: the one the platform names)
#   --bundle FILE      install this bundle (site-connector-<version>-linux.tar.gz) instead of downloading it
#   --name NAME        service and folder name (default: site-connector)
#   --uninstall        stop and remove the service (keeps /var/lib/<name> unless --purge)
#   --purge            with --uninstall: remove the token and buffered recordings too
set -euo pipefail

NAME=site-connector
API=""
CODE=""
MODE=bundle
IMAGE=""
BUNDLE=""
UNINSTALL=0
PURGE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --api) API="${2%/}"; shift 2 ;;
    --code) CODE="$2"; shift 2 ;;
    --docker) MODE=docker; shift ;;
    --image) IMAGE="$2"; shift 2 ;;
    --bundle) BUNDLE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --purge) PURGE=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$NAME" in *[!a-z0-9-]*|"") echo "--name: lower-case letters, digits and dashes only" >&2; exit 2 ;; esac
CODE=$(printf '%s' "$CODE" | tr -cd 'A-Za-z0-9-')

ROOT=/opt/$NAME
DATA=/var/lib/$NAME
CONF=/etc/$NAME
UNIT=/etc/systemd/system/$NAME.service

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root (sudo bash install.sh …)"
command -v systemctl >/dev/null || die "this installer needs systemd"

if [ "$UNINSTALL" -eq 1 ]; then
  say "Removing $NAME"
  systemctl disable --now "$NAME.service" "$NAME-update.timer" 2>/dev/null || true
  rm -f "$UNIT" "/etc/systemd/system/$NAME-update.service" "/etc/systemd/system/$NAME-update.timer"
  systemctl daemon-reload
  rm -rf "$ROOT"
  if [ "$PURGE" -eq 1 ]; then rm -rf "$DATA" "$CONF"; fi
  say "Removed. Revoke or remove the connector in the app too."
  exit 0
fi

[ -n "$API" ] || die "give the API address: --api https://<api host>"
case "$API" in https://*) ;; *) die "the API address must start with https://" ;; esac
command -v curl >/dev/null || die "curl is needed"

json_field() { # json_field <field> — reads JSON on stdin, prints .data.<field> or .<field>
  python3 -c 'import json,sys; b=json.load(sys.stdin); d=b.get("data",b) if isinstance(b,dict) else b; v=d.get(sys.argv[1]) if isinstance(d,dict) else None; print("" if v is None else (json.dumps(v) if isinstance(v,(dict,list)) else v))' "$1"
}

install -d -m 0755 "$ROOT" "$CONF"
id -u "$NAME" >/dev/null 2>&1 || useradd --system --home "$DATA" --shell /usr/sbin/nologin "$NAME"
install -d -m 0700 -o "$NAME" -g "$NAME" "$DATA" "$DATA/edge"

# ── Pair (once): the code for the connector's own token ──────────────────────────────────────────
STATE="$DATA/edge/connector.json"
if [ -s "$STATE" ] && grep -q '"token"' "$STATE"; then
  say "Already paired (keeping $STATE)"
else
  [ -n "$CODE" ] || die "give the pairing code from the app: --code XXXX-XXXX"
  command -v python3 >/dev/null || die "python3 is needed"
  say "Pairing with $API"
  REPLY=$(curl -fsS -X POST "$API/api/v1/connectors/pair" -H 'Content-Type: application/json' \
    -d "{\"code\":\"$CODE\",\"host\":{\"os\":\"linux\",\"install\":\"$MODE\",\"hostname\":\"$(hostname | cut -c1-60)\"}}") \
    || die "the code was not accepted (it works once and expires after a day): issue a new one in the app"
  TOKEN=$(printf '%s' "$REPLY" | json_field token)
  [ -n "$TOKEN" ] || die "pairing gave no token"
  CONNECTOR_ID=$(printf '%s' "$REPLY" | json_field connectorId)
  RELEASE_KEY=$(printf '%s' "$REPLY" | json_field releasePublicKey)
  umask 077
  python3 - "$STATE" "$TOKEN" "$CONNECTOR_ID" "$RELEASE_KEY" "$API" <<'PY'
import json, sys
path, token, cid, key, api = sys.argv[1:6]
json.dump({"token": token, "connectorId": cid, "releasePublicKey": key or None, "apiUrl": api}, open(path, "w"), indent=2)
PY
  chown "$NAME:$NAME" "$STATE"
  chmod 0600 "$STATE"
  say "Paired as connector $CONNECTOR_ID"
fi
TOKEN=$(json_field token < "$STATE")
auth=(-H "Authorization: Bearer $TOKEN")

cat > "$CONF/env" <<EOF
EDGE_MODE=true
EDGE_API_URL=$API
EDGE_DATA_DIR=$DATA/edge
EDGE_INSTALL_KIND=$MODE
EDGE_INSTALL_ROOT=$ROOT
DEMO_PAUSE_ENABLED=false
# Cameras on this machine itself (e.g. a local RTSP server): their ports
CAMERA_LOCAL_PORTS=
EOF
chmod 0644 "$CONF/env"

if [ "$MODE" = docker ]; then
  # ── Docker: the image runs as the service; a daily timer pulls updates ───────────────────────
  command -v docker >/dev/null || die "docker is needed for --docker"
  if [ -z "$IMAGE" ]; then
    IMAGE=$(curl -fsS "${auth[@]}" "$API/api/v1/edge/releases/latest" | python3 -c 'import json,sys; b=json.load(sys.stdin); d=b.get("data",b); m=json.loads(d.get("manifest") or "{}"); print((m.get("docker") or {}).get("image") or "")')
    [ -n "$IMAGE" ] || die "the platform names no docker image: give one with --image"
  fi
  echo "IMAGE=$IMAGE" > "$CONF/image"
  docker pull "$IMAGE"
  cat > "$UNIT" <<EOF
[Unit]
Description=Site connector ($NAME, docker)
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
EnvironmentFile=$CONF/image
ExecStartPre=-/usr/bin/docker rm -f $NAME
ExecStart=/usr/bin/docker run --rm --name $NAME --network host --env-file $CONF/env -e EDGE_DATA_DIR=/data/edge -e EDGE_INSTALL_KIND=docker -v $DATA:/data \${IMAGE}
ExecStop=/usr/bin/docker stop -t 30 $NAME
Restart=always
RestartSec=10
# 78: not paired, or the code was refused — waiting for a person, not a restart
RestartPreventExitStatus=78

[Install]
WantedBy=multi-user.target
EOF
  cat > "/etc/systemd/system/$NAME-update.service" <<EOF
[Unit]
Description=Pull the site connector's newest image and restart it when it changed

[Service]
Type=oneshot
EnvironmentFile=$CONF/image
ExecStart=/bin/sh -c 'before=\$(docker image inspect -f "{{.Id}}" "\$IMAGE" 2>/dev/null); docker pull -q "\$IMAGE" >/dev/null && after=\$(docker image inspect -f "{{.Id}}" "\$IMAGE") && [ "\$before" != "\$after" ] && systemctl restart $NAME.service || true'
EOF
  chown -R 10001:10001 "$DATA"  # the image's user
else
  # ── Bundle: python + ffmpeg on this machine; the program updates itself ──────────────────────
  command -v python3 >/dev/null || die "python3 (3.10 or newer) is needed"
  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' || die "python 3.10 or newer is needed"
  python3 -c 'import venv' 2>/dev/null || die "python3-venv is needed (apt install python3-venv)"
  command -v ffmpeg >/dev/null || die "ffmpeg is needed (apt install ffmpeg)"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  if [ -z "$BUNDLE" ]; then
    say "Downloading the newest release"
    curl -fsS "${auth[@]}" "$API/api/v1/edge/releases/latest" -o "$TMP/release.json"
    read -r FILE URL SHA < <(python3 - "$TMP/release.json" <<'PY'
import json, sys
b = json.load(open(sys.argv[1])); d = b.get("data", b)
if not d.get("configured"): sys.exit("the platform publishes no release yet: " + str(d.get("reason")))
m = json.loads(d["manifest"])
a = next((a for a in m.get("artifacts", []) if a.get("platform") == "linux" and a["name"].endswith(".tar.gz")), None)
if not a: sys.exit("the release has no Linux bundle")
print(a["name"], a["url"], a["sha256"])
PY
)
    curl -fsS "${auth[@]}" "$API$URL" -o "$TMP/$FILE"
    echo "$SHA  $TMP/$FILE" | sha256sum -c - >/dev/null || die "the download does not match the release manifest"
    BUNDLE="$TMP/$FILE"
  fi
  VERSION=$(tar -xzOf "$BUNDLE" VERSION 2>/dev/null | tr -cd 'A-Za-z0-9.+-') || true
  [ -n "$VERSION" ] || die "not a connector bundle: $BUNDLE"
  install -d -m 0755 "$ROOT/versions/$VERSION" "$ROOT/bin"
  tar -xzf "$BUNDLE" -C "$ROOT/versions/$VERSION" --no-same-owner
  ln -sfn "versions/$VERSION" "$ROOT/current"
  [ -x "$ROOT/venv/bin/python" ] || python3 -m venv "$ROOT/venv"
  cat > "$ROOT/bin/prepare.sh" <<'EOF'
#!/bin/sh
# Before each start: the python packages the current version needs (a self-update may have changed them)
set -e
ROOT=$(dirname "$(dirname "$(readlink -f "$0")")")
LOCK="$ROOT/current/requirements.lock"
STAMP="$ROOT/venv/.installed"
want=$(cat "$LOCK" "$ROOT/current/VERSION" | sha256sum | cut -d' ' -f1)
[ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$want" ] && exit 0
"$ROOT/venv/bin/pip" install --quiet --disable-pip-version-check "$ROOT/current/ml-common"
"$ROOT/venv/bin/pip" install --quiet --disable-pip-version-check -r "$LOCK"
echo "$want" > "$STAMP"
EOF
  chmod 0755 "$ROOT/bin/prepare.sh"
  "$ROOT/bin/prepare.sh"
  chown -R "$NAME:$NAME" "$ROOT"
  cat > "$UNIT" <<EOF
[Unit]
Description=Site connector ($NAME)
After=network-online.target
Wants=network-online.target

[Service]
User=$NAME
Group=$NAME
EnvironmentFile=$CONF/env
WorkingDirectory=$ROOT/current
ExecStartPre=$ROOT/bin/prepare.sh
ExecStart=$ROOT/venv/bin/python -m src.main
Restart=always
RestartSec=10
RestartPreventExitStatus=78
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths=$DATA $ROOT

[Install]
WantedBy=multi-user.target
EOF
  # The program installs updates itself; the timer only restarts it if it stopped for an update and stayed down
  cat > "/etc/systemd/system/$NAME-update.service" <<EOF
[Unit]
Description=Make sure the site connector runs (after a self-update)

[Service]
Type=oneshot
ExecStart=/bin/systemctl start $NAME.service
EOF
fi

cat > "/etc/systemd/system/$NAME-update.timer" <<EOF
[Unit]
Description=Site connector updates

[Timer]
OnBootSec=15min
OnUnitActiveSec=1d
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "$NAME.service" "$NAME-update.timer"
say "Installed. It shows as Online in the app within a minute: journalctl -u $NAME -f"
