#!/usr/bin/env bash

set -eEuo pipefail

this_script=$(realpath "${BASH_SOURCE[0]}")
script_dir=$(dirname "$this_script")
source "$script_dir/../common.bashinc"
cd "$script_dir"

rcmd() {
    echo "Running: $*"
    "$@"
}

triples=(
    x86_64-qmk-linux-gnu
    aarch64-unknown-linux-gnu
    riscv64-unknown-linux-gnu
    x86_64-w64-mingw32
    aarch64-apple-darwin24
    x86_64-apple-darwin24
)

if [ ! -d "$script_dir/mdloader" ]; then
    git clone https://github.com/massdrop/mdloader.git "$script_dir/mdloader"
else
    git -C "$script_dir/mdloader" pull --ff-only
fi

for triple in "${triples[@]}"; do
    echo
    build_dir="$script_dir/.build/$(fn_os_arch_fromtriplet "$triple")/mdloader"
    xroot_dir="$script_dir/.xroot/$(fn_os_arch_fromtriplet "$triple")"
    mkdir -p "$build_dir"
    echo "Building mdloader for $triple => $build_dir"
    rm -rf "$build_dir/*"
    pushd "$script_dir/mdloader" >/dev/null 2>&1

    if [ -n "$(fn_os_arch_fromtriplet $triple | grep windows)" ]; then
        OS=Windows_NT
        CFLAGS="-static"
        LDFLAGS="-static"
    elif [ -n "$(fn_os_arch_fromtriplet $triple | grep macos)" ]; then
        unset OS
        unset CFLAGS
        unset LDFLAGS
    else
        unset OS
        CFLAGS="-static"
        LDFLAGS="-static"
    fi

    make clean
    make -j$(nproc) OBJDIR="$build_dir" CC="${triple}-gcc" CXX="${triple}-g++" OS=${OS:-} CFLAGS="${CFLAGS:-}" LDFLAGS="${LDFLAGS:-}"
    cp "$build_dir/mdloader"* "$xroot_dir/bin"
    popd >/dev/null 2>&1
done
