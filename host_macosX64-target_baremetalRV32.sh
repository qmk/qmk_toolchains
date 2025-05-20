#!/usr/bin/env bash
# Copyright 2024-2025 Nick Brassel (@tzarc)
# SPDX-License-Identifier: GPL-2.0-or-later

this_script="$PWD/$(basename ${BASH_SOURCE[0]})"
script_dir=$(dirname "${this_script}")
cd "$script_dir"
source "${script_dir}/common.bashinc"

build_one_help "$@"
respawn_docker_if_needed "$@"

build_one \
    --sample-name=riscv32-picolibc-elf \
    --vendor-name=unknown \
    --canadian-host=x86_64-apple-darwin24 \
    --binutils-plugins \
    --no-cross-gdb-python \
    "$@"
