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

if [ ! -d "$script_dir/bootloadHID/commandline" ]; then
    mkdir -p "$script_dir/bootloadHID"
    wget https://www.obdev.at/downloads/vusb/bootloadHID.2012-12-08.tar.gz -O - | tar -xz -C "$script_dir/bootloadHID" --strip-components=1
fi

# Fix include path issues
sudo cp /qmk/x86_64-w64-mingw32/sysroot/usr/x86_64-w64-mingw32/include/hidusage.h /qmk/x86_64-w64-mingw32/sysroot/usr/x86_64-w64-mingw32/include/ddk
sudo cp /qmk/x86_64-w64-mingw32/sysroot/usr/x86_64-w64-mingw32/include/hidpi.h /qmk/x86_64-w64-mingw32/sysroot/usr/x86_64-w64-mingw32/include/ddk

for triple in "${triples[@]}"; do
    echo
    build_dir="$script_dir/.build/$(fn_os_arch_fromtriplet "$triple")/bootloadHID"
    xroot_dir="$script_dir/.xroot/$(fn_os_arch_fromtriplet "$triple")"
    mkdir -p "$build_dir"
    echo "Building bootloadHID for $triple => $build_dir"
    pushd "$script_dir/bootloadHID/commandline" >/dev/null 2>&1
    rm -rf "$build_dir/*"

    CFLAGS=$(pkg-config --with-path="$xroot_dir/lib/pkgconfig" --static --cflags libusb-1.0)
    LDFLAGS=$(pkg-config --with-path="$xroot_dir/lib/pkgconfig" --static --libs libusb-1.0)

    # bootloadHID includes `libusb-1.0` in its paths, so we need the parent.
    CFLAGS="$CFLAGS -I$xroot_dir/include"

    if [ -n "$(fn_os_arch_fromtriplet $triple | grep macos)" ]; then
        echo "MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
        echo "SDK_VERSION=$SDK_VERSION"
    elif [ -n "$(fn_os_arch_fromtriplet $triple | grep windows)" ]; then
        CFLAGS="$CFLAGS -I$script_dir/support/windows-ddk"
        LDFLAGS="$LDFLAGS -lhid -lusb -lsetupapi"
    fi

    rcmd make clean
    rm bootloadHID bootloadHID.exe || true
    rcmd make CC="${triple}-gcc" CXX="${triple}-g++" USBLIBS="-lusb $LDFLAGS" USBFLAGS="$CFLAGS"
    cp bootloadHID* "$xroot_dir/bin"
    rcmd make clean
    popd >/dev/null 2>&1
done
