#!/usr/bin/env bash

set -eEuo pipefail

this_script="$PWD/$(basename ${BASH_SOURCE[0]})"
script_dir=$(dirname "${this_script}")
cd "$script_dir"
source "${script_dir}/common.bashinc"

if [[ -z "${1}" ]]; then
    echo "Usage: ${this_script} <path-to-toolchain-dir>"
    exit 1
fi

toolchain_dir="${1}"

if [[ ! -d "${toolchain_dir}" ]]; then
    echo "Error: ${toolchain_dir} is not a directory"
    exit 1
fi

# Add the other compilers to the PATH for use
while read bindir; do
    export PATH="$bindir:$PATH"
    echo "Adding $bindir to \$PATH"
done < <(find "$script_dir/toolchains/host_$(fn_os_arch)"* -mindepth 1 -maxdepth 1 -type d -name bin)

echo

# Work out the toolchain prefix
toolchain_prefix=$(find "${toolchain_dir}/bin" -type f -name '*-gcc*' -exec basename '{}' \; 2>/dev/null | head -n1 | sed -e 's@gcc.*$@@g')

echo "Toolchain prefix: ${toolchain_prefix}"
echo

# Strip binaries
find "${toolchain_dir}" -type f \
    -name '*.o' -or -name '*.a' \
    -printf '%P\n' \
    -exec ${toolchain_prefix}strip --strip-debug '{}' \;

find "${toolchain_dir}" -type f \
    -name '*.a' \
    -printf '%P\n' \
    -exec ${toolchain_prefix}ranlib '{}' \;