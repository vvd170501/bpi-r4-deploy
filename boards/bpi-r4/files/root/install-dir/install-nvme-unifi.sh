#!/bin/sh
# The old UniFi installer uses the former combined-FIT/p3-data layout.
echo "The legacy BPi-R4 UniFi installer is incompatible with the SquashFS NVMe layout." >&2
echo "Install with install-nvme.sh; UniFi data/recording partition support needs porting." >&2
exit 1
