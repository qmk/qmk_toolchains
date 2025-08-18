#!/usr/bin/env bash
# Copyright 2024-2025 Nick Brassel (@tzarc)
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

this_script="$PWD/$(basename ${BASH_SOURCE[0]})"
script_dir=$(dirname "${this_script}")
cd "$script_dir"
source "${script_dir}/common.bashinc"

BUILDER_IMAGE=${BUILDER_IMAGE:-ghcr.io/tzarc/qmk_toolchains:builder}

respawn_docker_if_needed --container-image=${BUILDER_IMAGE} "$@"

declare host_osarch_names=(
    linuxX64
    linuxARM64
    linuxRV64
    macosARM64
    macosX64
    windowsX64
)

declare target_names=(
    baremetalARM
    baremetalAVR
    baremetalRV32
)

# Use gdb as it's the last step in the toolchain
declare -A check_files=(
    [baremetalARM]='arm-none-eabi-gdb'
    [baremetalAVR]='avr-gdb'
    [baremetalRV32]='riscv32-unknown-elf-gdb'
)

for target in "${target_names[@]}"; do
    for host in "${host_osarch_names[@]}"; do
        check_file=${check_files[$target]}
        script="host_${host}-target_${target}.sh"
        if [ ! -x "toolchains/host_${host}-target_${target}/bin/${check_file}" ] && [ ! -x "toolchains/host_${host}-target_${target}/bin/${check_file}.exe" ]; then
            echo "Missing toolchain for ${target} on ${host}, building..."
            ./${script} --container-image=${BUILDER_IMAGE} --no-keep-state "$@"
        fi
    done
done

for target in "${target_names[@]}"; do
    for host in "${host_osarch_names[@]}"; do
        check_file=${check_files[$target]}
        if [ -x "toolchains/host_${host}-target_${target}/bin/${check_file}" ] || [ -x "toolchains/host_${host}-target_${target}/bin/${check_file}.exe" ]; then
            echo "Stripping toolchain for ${target} on ${host}..."
            ./strip_toolchain.sh toolchains/host_${host}-target_${target}
            echo "Creating tarball for ${target} on ${host}..."
            tar acf qmk_toolchain-host_${host}-target_${target}.tar --sort=name -C toolchains host_${host}-target_${target}
            zstdmt -T0 -19 --long --rm --force qmk_toolchain-host_${host}-target_${target}.tar
        fi
    done
done

