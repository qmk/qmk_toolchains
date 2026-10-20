#!/bin/bash
# Copyright 2026 Nick Brassel (@tzarc)
# SPDX-License-Identifier: GPL-2.0-or-later

set -eEuo pipefail

export PATH="/qmk/bin:/ct-ng/bin:/osxcross/bin:$PATH"

if [ -n "${TC_WORKDIR:-}" ] && [ -e "${TC_WORKDIR:-}" ]; then
    qmk_uid=$(stat --format='%u' "$TC_WORKDIR")
    qmk_gid=$(stat --format='%g' "$TC_WORKDIR")
    groupadd --non-unique -g $qmk_gid qmk
    useradd --non-unique -u $qmk_uid -g $qmk_gid -N qmk
    echo "qmk ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/qmk >/dev/null 2>&1
    cd "$TC_WORKDIR"
    if [[ -n $1 ]]; then
        exec sudo -u qmk -g qmk -H --preserve-env=PATH -- bash -lic 'exec "$@"' bash "$@"
    else
        exec sudo -u qmk -g qmk -H --preserve-env=PATH -- bash -li
    fi
else
    if [[ -n $1 ]]; then
        exec bash -lic 'exec "$@"' bash "$@"
    else
        exec bash -li
    fi
fi
