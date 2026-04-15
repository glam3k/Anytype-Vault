#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/anytype-vault/env/backup.env}"
DATA_DIR="${DATA_DIR:-/opt/anytype-vault/data}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  echo "Create it from env/backup.env.example and place it at /opt/anytype-vault/env/backup.env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

export B2_ACCOUNT_ID="${B2_ACCOUNT_ID:?missing B2_ACCOUNT_ID}"
export B2_ACCOUNT_KEY="${B2_ACCOUNT_KEY:?missing B2_ACCOUNT_KEY}"
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:?missing RESTIC_REPOSITORY}"
export RESTIC_PASSWORD="${RESTIC_PASSWORD:?missing RESTIC_PASSWORD}"

if [[ ! -d "$DATA_DIR" ]]; then
  echo "Missing data dir: $DATA_DIR" >&2
  exit 1
fi

restic snapshots >/dev/null 2>&1 || {
  echo "Restic repo not reachable/initialized. If this is first run, initialize with:" >&2
  echo "  restic init" >&2
  exit 2
}

HOSTNAME_TAG="$(hostname -s || hostname)"
DATE_TAG="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

restic backup "$DATA_DIR" \
  --tag "anytype-vault" \
  --tag "host:$HOSTNAME_TAG" \
  --tag "run:$DATE_TAG"

restic forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --prune

restic check
