#!/bin/bash
# Build and run the Docker build environment, forwarding arguments to build.sh.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
docker compose -f docker/compose.yml build buildbox
exec docker compose -f docker/compose.yml run --rm buildbox "$@"
