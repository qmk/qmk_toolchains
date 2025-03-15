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

if [ ! -d "$script_dir/libftdi" ]; then
    git clone git://developer.intra2net.com/libftdi "$script_dir/libftdi"
else
    git -C "$script_dir/libftdi" pull --ff-only
fi

for triple in "${triples[@]}"; do
    echo
    build_dir="$script_dir/.build/$(fn_os_arch_fromtriplet "$triple")/libftdi"
    xroot_dir="$script_dir/.xroot/$(fn_os_arch_fromtriplet "$triple")"
    mkdir -p "$build_dir"
    echo "Building libftdi for $triple => $build_dir"
    pushd "$build_dir" >/dev/null 2>&1
    rm -rf "$build_dir/*"

    CFLAGS="-fPIC $(pkg-config --with-path="$xroot_dir/lib/pkgconfig" --static --cflags libusb-1.0)"
    LDFLAGS="-fPIC $(pkg-config --with-path="$xroot_dir/lib/pkgconfig" --static --libs libusb-1.0)"

    if [ -z "$(fn_os_arch_fromtriplet $triple | grep macos)" ]; then
        CFLAGS="$CFLAGS"
        LDFLAGS="$LDFLAGS -pthread"
    else
        echo "MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
        echo "SDK_VERSION=$SDK_VERSION"
    fi

    rcmd cmake "$script_dir/libftdi" -DCMAKE_BUILD_TYPE=Release -G Ninja -DCMAKE_TOOLCHAIN_FILE="$script_dir/support/$(fn_os_arch_fromtriplet "$triple")-toolchain.cmake" -DCMAKE_PREFIX_PATH="$xroot_dir" -DCMAKE_INSTALL_PREFIX="$xroot_dir" -DCMAKE_INSTALL_LIBDIR="$xroot_dir/lib" -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" -DSTATICLIBS=ON -DDOCUMENTATION=OFF -DBUILD_TESTS=OFF -DFTDIPP=OFF -DPYTHON_BINDINGS=OFF -DFTDI_EEPROM=OFF -DEXAMPLES=OFF
    rcmd cmake --build . --target ftdi1-static -- -j$(nproc)
    rcmd cmake --install . --component staticlibs
    rcmd cmake --install . --component headers
    popd >/dev/null 2>&1
done
