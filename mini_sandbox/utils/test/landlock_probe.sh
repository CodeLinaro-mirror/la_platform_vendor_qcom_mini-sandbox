#!/bin/bash
##
## Copyright (c) 2025 Qualcomm Technologies, Inc. and/or its subsidiaries.
## SPDX-License-Identifier: MIT
##

# Reports the Landlock ABI offered by the running kernel.
#
# Landlock is a property of the kernel, not of the userspace we run in: a
# container inherits the host kernel, so the Ubuntu 24.04 image used for the
# Landlock tests says nothing about the ABI we will actually get. Printing it
# before the tests start lets a Landlock failure be told apart from a kernel
# that is simply too old (ABI 4 needs Linux 6.7, ABI 1 only 5.13).
#
# Informational only: this never fails the test suite.

set -u

PYTHON="${PYTHON:-python3}"

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Read the threshold from the header rather than duplicating the number here,
# so this cannot drift from the value the sandbox actually enforces.
LL_HEADER="$SCRIPT_DIR/../../src/main/tools/ll-isolation.h"
MIN_ABI="$(grep -m1 'define MIN_LL_ABI' "$LL_HEADER" 2>/dev/null | grep -o '[0-9]*$')"
MIN_ABI="${MIN_ABI:-4}"

probe_abi() {
    # landlock_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION) returns
    # the ABI the kernel supports. 444 is the syscall number on every
    # architecture using the generic syscall table, x86_64 and arm64 included.
    "$PYTHON" - <<'EOF' 2>/dev/null
import ctypes
libc = ctypes.CDLL(None, use_errno=True)
abi = libc.syscall(444, None, 0, 1)
print(abi if abi >= 0 else "err:%d" % ctypes.get_errno())
EOF
}

echo "=== Landlock probe ==="
echo "kernel:       $(uname -r)"

if [ -r /sys/kernel/security/lsm ]; then
    echo "active LSMs:  $(cat /sys/kernel/security/lsm)"
else
    # securityfs is not always mounted inside a container.
    echo "active LSMs:  unknown (/sys/kernel/security/lsm not readable)"
fi

if ! command -v "$PYTHON" > /dev/null 2>&1; then
    echo "landlock ABI: not probed ($PYTHON not found)"
    exit 0
fi

ABI="$(probe_abi)"

case "$ABI" in
    "")
        echo "landlock ABI: not probed (the probe itself failed to run)"
        ;;
    err:*)
        echo "landlock ABI: unsupported, landlock_create_ruleset gave errno ${ABI#err:}"
        echo "              the kernel lacks Landlock or it is not in the LSM list"
        ;;
    *)
        echo "landlock ABI: $ABI (the landlock sandbox needs >= $MIN_ABI)"
        if [ "$ABI" -lt "$MIN_ABI" ]; then
            echo "WARNING:      this kernel is too old for the landlock sandbox."
            echo "              Landlock tests will not pass here; ABI $MIN_ABI needs Linux 6.7+."
        fi
        ;;
esac

if [ "${LANDLOCK_TEST:-}" = "1" ]; then
    echo "LANDLOCK_TEST=1, the landlock specific test paths are active"
fi

exit 0
