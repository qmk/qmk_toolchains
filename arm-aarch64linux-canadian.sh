#!/usr/bin/env bash
# Copyright 2024 Nick Brassel (@tzarc)
# SPDX-License-Identifier: GPL-2.0-or-later

this_script=$(realpath "${BASH_SOURCE[0]}")
script_dir=$(dirname "${this_script}")
source "${script_dir}/common.bashinc"

build_one_help "$@"

build_one \
    --canadian-host=aarch64-unknown-linux-gnu \
    --sample-name=arm-none-eabi \
    --multilib-list=rmprofile \
    --libc=newlib \
    --binutils-plugins \
    --extra-newlib-nano \
    --no-cross-gdb-python \
    "$@"