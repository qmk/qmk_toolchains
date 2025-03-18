#!/usr/bin/env bash
# Copyright 2024-2025 Nick Brassel (@tzarc)
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

this_script="$PWD/$(basename ${BASH_SOURCE[0]})"
script_dir=$(dirname "${this_script}")
cd "$script_dir"

BASE_IMAGE=${BASE_IMAGE:-qmk_toolchains:base}
BUILDER_IMAGE=${BUILDER_IMAGE:-qmk_toolchains:builder}

declare -A target_scripts=(
    [linuxX64_qmk_bootstrap]='x64linux-native-bootstrap.sh'
    [linuxX64]='x64linux-native.sh'
    [linuxARM64]='aarch64linux-native.sh'
    [linuxRV64]='riscv64linux-native.sh'
    [windowsX64]='win64-native.sh'
)

# Use gdb as it's the last step in the toolchain
declare -A check_files=(
    [linuxX64_qmk_bootstrap]=x86_64-qmk_bootstrap-linux-gnu-gdb
    [linuxX64]=x86_64-qmk-linux-gnu-gdb
    [linuxARM64]=aarch64-unknown-linux-gnu-gdb
    [linuxRV64]=riscv64-unknown-linux-gnu-gdb
    [windowsX64]=x86_64-w64-mingw32-gdb
)

docker build -t qmk_toolchains:base -f Dockerfile.base .

for target in "${!target_scripts[@]}"; do
    script=${target_scripts[$target]}
    check_file=${check_files[$target]}
    if [ ! -x "toolchains/host_linuxX64-target_${target}/bin/${check_file}" ] &&  [ ! -x "toolchains/host_linuxX64-target_${target}/bin/${check_file}.exe" ]; then
        echo "Missing toolchain for ${target}, building..."
        ./${script} --container-image=${BASE_IMAGE}
    fi
    tar acf qmk_toolchain-host_linuxX64-target_${target}.tar -C toolchains host_linuxX64-target_${target}
    zstdmt -T0 -19 --long --rm --force qmk_toolchain-host_linuxX64-target_${target}.tar
done

docker build -t ${BUILDER_IMAGE} -f Dockerfile.builder --build-arg BASE_CONTAINER=${BASE_IMAGE} .
