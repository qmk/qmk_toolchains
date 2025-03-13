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

if [ ! -d "$script_dir/dfu-util" ]; then
    git clone https://git.code.sf.net/p/dfu-util/dfu-util "$script_dir/dfu-util"
else
    git -C "$script_dir/dfu-util" pull --ff-only
fi

if [ ! -e "$script_dir/dfu-util/configure" ]; then
    pushd "$script_dir/dfu-util" >/dev/null 2>&1
    { patch -f -s -p1 < "$script_dir/support/dfu-util/configure.patch"; } || true
    ./autogen.sh
    popd >/dev/null 2>&1
fi

for triple in "${triples[@]}"; do
    echo
    build_dir="$script_dir/.build/$(fn_os_arch_fromtriplet "$triple")/dfu-util"
    xroot_dir="$script_dir/.xroot/$(fn_os_arch_fromtriplet "$triple")"
    mkdir -p "$build_dir"
    echo "Building dfu-util for $triple => $build_dir"
    pushd "$build_dir" >/dev/null 2>&1
    rm -rf "$build_dir/*"

    CFLAGS=$(pkg-config --with-path="$xroot_dir/lib/pkgconfig" --static --cflags libusb-1.0)
    LDFLAGS=$(pkg-config --with-path="$xroot_dir/lib/pkgconfig" --static --libs libusb-1.0)

    # dfu-util includes `libusb-1.0` in its paths, so we need the parent.
    CFLAGS="$CFLAGS -I$xroot_dir/include"

    if [ -z "$(fn_os_arch_fromtriplet $triple | grep macos)" ]; then
        CFLAGS="$CFLAGS -static"
        LDFLAGS="$LDFLAGS -static -pthread"
    else
        echo "MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
        echo "SDK_VERSION=$SDK_VERSION"
    fi

    rcmd "$script_dir/dfu-util/configure" --prefix="$xroot_dir" --host=$triple CC="${triple}-gcc" CXX="${triple}-g++" LDFLAGS="$LDFLAGS" CFLAGS="$CFLAGS" CXXFLAGS="$CFLAGS"
    make clean
    make -j$(nproc) install || true # Makefile fails to deal with the bash completion files so we `|| true` to ignore the error
    popd >/dev/null 2>&1
done
