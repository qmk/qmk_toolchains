#!/usr/bin/env bash
# Copyright 2024-2025 Nick Brassel (@tzarc)
# SPDX-License-Identifier: GPL-2.0-or-later

this_script="$PWD/$(basename ${BASH_SOURCE[0]})"
script_dir=$(dirname "${this_script}")
cd "$script_dir"
source "${script_dir}/common.bashinc"

build_one_help "$@"
respawn_docker_if_needed "$@"

# Intentionally build as canadian (even though we're on the same architecture)
# to ensure libraries in the toolchain are compatible with the target.
build_one \
    --canadian-host=x86_64-qmk-linux-gnu \
    --sample-name=arm-none-eabi \
    --multilib-list=rmprofile \
    --libc=newlib \
    --binutils-plugins \
    --extra-newlib-nano \
    --no-cross-gdb-python \
    "$@"
