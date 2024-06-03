#!/usr/bin/env bash

this_script="$PWD/$(basename ${BASH_SOURCE[0]})"
script_dir=$(dirname "${this_script}")

if [[ -z "${1}" ]]; then
    echo "Usage: ${this_script} <path-to-toolchain-dir>"
    exit 1
fi

toolchain_dir="${1}"

if [[ ! -d "${toolchain_dir}" ]]; then
    echo "Error: ${toolchain_dir} is not a directory"
    exit 1
fi

# Work out the exec prefix
toolchain_prefix=$(find "${toolchain_dir}/bin" -type f -name '*-gcc' -exec basename '{}' \; | head -n1 | sed -e 's@gcc$@@g')

# Strip binaries
find "${toolchain_dir}" -type f \
    -name '*.o' -or -name '*.a' \
    -print \
    -exec ${toolchain_prefix}strip --strip-debug '{}' \;

find "${toolchain_dir}" -type f \
    -name '*.a' \
    -print \
    -exec ${toolchain_prefix}ranlib '{}' \;