#!/usr/bin/env bash

set -eEuo pipefail

this_script=$(realpath "${BASH_SOURCE[0]}")
script_dir=$(dirname "$this_script")
source "$script_dir/../common.bashinc"
cd "$script_dir"

./build-libusb.sh
./build-libusb-compat.sh
./build-libftdi.sh
./build-libserialport.sh
./build-dfu-programmer.sh
./build-dfu-util.sh
./build-avrdude.sh
./build-mdloader.sh
./build-teensyloader.sh
./build-bootloadHID.sh
./build-hid_bootloader_cli.sh

triples=(
    x86_64-qmk-linux-gnu
    aarch64-unknown-linux-gnu
    riscv64-unknown-linux-gnu
    x86_64-w64-mingw32
    aarch64-apple-darwin24
    x86_64-apple-darwin24
)

for triple in "${triples[@]}"; do
    xroot_dir="$script_dir/.xroot/$(fn_os_arch_fromtriplet "$triple")"

    if [ -n "$(fn_os_arch_fromtriplet $triple | grep macos)" ]; then
        STRIP="${triple}-strip"
    else
        STRIP="${triple}-strip -s"
    fi

    ls -1 "$xroot_dir/bin" | while read -r bin; do
        echo "Stripping $bin"
        ${STRIP} "$xroot_dir/bin/$bin" || true

        if [ -n "$(fn_os_arch_fromtriplet $triple | grep macos)" ]; then
            rcodesign sign --runtime-version 12.0.0 --code-signature-flags runtime "$xroot_dir/bin/$bin" || true
        fi
    done

    tar acf "$script_dir/flashers-$(fn_os_arch_fromtriplet "$triple").tar.zst" -C "$xroot_dir" .
done