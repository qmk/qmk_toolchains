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

if [ ! -d "$script_dir/libusb" ]; then
    git clone https://github.com/libusb/libusb.git "$script_dir/libusb"
else
    git -C "$script_dir/libusb" pull --ff-only
fi

if [ ! -e "$script_dir/libusb/configure" ]; then
    pushd "$script_dir/libusb" >/dev/null 2>&1
    ./bootstrap.sh
    popd >/dev/null 2>&1
fi

for triple in "${triples[@]}"; do
    # macOS container Problems...
    find /gcc /usr/local -path '*'$triple'*include-fixed/dispatch/object.h' -print -exec sudo rm -rf '{}' \; 2>/dev/null || true

    echo
    build_dir="$script_dir/.build/$(fn_os_arch_fromtriplet "$triple")/libusb"
    xroot_dir="$script_dir/.xroot/$(fn_os_arch_fromtriplet "$triple")"
    mkdir -p "$build_dir"
    echo "Building libusb for $triple => $build_dir"
    pushd "$build_dir" >/dev/null 2>&1
    rm -rf "$build_dir/*"
    rcmd "$script_dir/libusb/configure" --prefix="$xroot_dir" --host=$triple --enable-shared=no --enable-static --disable-udev CC="${triple}-gcc" CXX="${triple}-g++" CFLAGS="-fPIC" LDFLAGS="-fPIC"
    make clean
    make -j$(nproc) install
    popd >/dev/null 2>&1
done
