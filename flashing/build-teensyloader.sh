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

if [ ! -d "$script_dir/teensyloader" ]; then
    git clone https://github.com/PaulStoffregen/teensy_loader_cli.git "$script_dir/teensyloader"
else
    git -C "$script_dir/teensyloader" pull --ff-only
fi

pushd "$script_dir/teensyloader" >/dev/null 2>&1
{ patch -f -s -p1 <"$script_dir/support/teensyloader/mods.patch"; } || true
popd >/dev/null 2>&1

for triple in "${triples[@]}"; do
    echo
    build_dir="$script_dir/.build/$(fn_os_arch_fromtriplet "$triple")/teensyloader"
    xroot_dir="$script_dir/.xroot/$(fn_os_arch_fromtriplet "$triple")"
    mkdir -p "$build_dir"
    echo "Building teensyloader for $triple => $build_dir"
    rm -rf "$build_dir/*"

    CFLAGS="$(pkg-config --with-path="$xroot_dir/lib/pkgconfig" --static --cflags libusb) -I$script_dir/support/teensyloader"
    LDFLAGS="$(pkg-config --with-path="$xroot_dir/lib/pkgconfig" --static --libs libusb) -L$xroot_dir/lib"

    pushd "$script_dir/teensyloader" >/dev/null 2>&1

    if [ -n "$(fn_os_arch_fromtriplet $triple | grep windows)" ]; then
        OS=WINDOWS
        unset SDK
    elif [ -n "$(fn_os_arch_fromtriplet $triple | grep macos)" ]; then
        OS=MACOSX
        SDK=/sdk
    else
        OS=LINUX
        unset SDK
    fi

    make clean
    make -j$(nproc) OBJDIR="$build_dir" CC="${triple}-gcc" OS=${OS:-} SDK=${SDK:-} CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" USE_LIBUSB=YES OUTDIR="$build_dir"
    cp "$build_dir/teensy_loader_cli"* "$xroot_dir/bin"
    popd >/dev/null 2>&1
done
