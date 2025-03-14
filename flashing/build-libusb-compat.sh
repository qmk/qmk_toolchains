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

if [ ! -d "$script_dir/libusb-compat" ]; then
    git clone https://github.com/libusb/libusb-compat-0.1.git "$script_dir/libusb-compat"
else
    git -C "$script_dir/libusb-compat" pull --ff-only
fi

if [ ! -e "$script_dir/libusb-compat/configure" ]; then
    pushd "$script_dir/libusb-compat" >/dev/null 2>&1
    ./bootstrap.sh
    popd >/dev/null 2>&1
fi

for triple in "${triples[@]}"; do
    echo
    build_dir="$script_dir/.build/$(fn_os_arch_fromtriplet "$triple")/libusb-compat"
    xroot_dir="$script_dir/.xroot/$(fn_os_arch_fromtriplet "$triple")"
    mkdir -p "$build_dir"
    echo "Building libusb-compat for $triple => $build_dir"
    pushd "$build_dir" >/dev/null 2>&1
    rm -rf "$build_dir/*"

    PKG_CONFIG_PATH="$xroot_dir/lib/pkgconfig"
    CFLAGS=$(pkg-config --with-path="$xroot_dir/lib/pkgconfig" --static --cflags libusb-1.0)
    LDFLAGS=$(pkg-config --with-path="$xroot_dir/lib/pkgconfig" --static --libs libusb-1.0)

    # dfu-util includes `libusb-1.0` in its paths, so we need the parent.
    CFLAGS="$CFLAGS -I$xroot_dir/include"


    rcmd "$script_dir/libusb-compat/configure" --prefix="$xroot_dir" --host=$triple --enable-shared=no --enable-static --disable-udev CC="${triple}-gcc" CXX="${triple}-g++" LIBUSB_1_0_CFLAGS="$CFLAGS" LIBUSB_1_0_LIBS="$LDFLAGS"
    make clean
    make -j$(nproc) install
    popd >/dev/null 2>&1
done
