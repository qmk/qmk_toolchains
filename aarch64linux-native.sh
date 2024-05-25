#!/usr/bin/env bash
# Copyright 2024 Nick Brassel (@tzarc)
# SPDX-License-Identifier: GPL-2.0-or-later

this_script="$PWD/$(basename ${BASH_SOURCE[0]})"
script_dir=$(dirname "${this_script}")
source "${script_dir}/common.bashinc"

build_one_help "$@"

if [[ $(uname -s) == "Linux" ]]; then
    extra_args="--tools-prefix=x86_64-qmk_bootstrap-linux-gnu-"
fi

build_one \
    --sample-name=aarch64-rpi3-linux-gnu \
    --vendor-name=unknown \
    --no-cross-gdb-python \
    --build-host-compile \
    ${extra_args:-} \
    "$@"