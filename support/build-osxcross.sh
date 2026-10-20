#!/bin/bash
# Copyright 2026 Nick Brassel (@tzarc)
# SPDX-License-Identifier: GPL-2.0-or-later

# Builds the macOS host compilers for the canadian builds: cctools/ld64/SDK via osxcross, then the Darwin GCC fork for both arches.
# Usage: build-osxcross.sh <osxcross source dir> <install prefix> -- the SDK tarball must already be in <source dir>/tarballs

set -eEuo pipefail

src_dir=$1
prefix=$2

export UNATTENDED=1
export TARGET_DIR=$prefix
export OSX_VERSION_MIN=11.0
export ENABLE_ARCHS="arm64 x86_64"
export MACOSX_DEPLOYMENT_TARGET=$OSX_VERSION_MIN                 # GCC ignores OSX_VERSION_MIN when building libstdc++, this is what it reads instead
export PATH="$prefix/bin:$PATH"                                  # build_gcc.sh finds the install via osxcross-conf on $PATH, and silently exits 0 if it can't
export CFLAGS_FOR_TARGET="-O2 -g0" CXXFLAGS_FOR_TARGET="-O2 -g0" # no debug info in libstdc++.a et al.

cd "$src_dir"
BUILD_FLAVOR=latest ./build.sh
./build_gcc_with_arm64_support.sh

eval "$(osxcross-conf)"
for arch in aarch64 x86_64; do
    test -x "$prefix/bin/$arch-apple-$OSXCROSS_TARGET-gcc"
    test -x "$prefix/bin/$arch-apple-$OSXCROSS_TARGET-g++"
    # ct-ng refuses to start without host objcopy/objdump; cctools has neither, LLVM's handle Mach-O
    ln -s "$(command -v llvm-objcopy)" "$prefix/bin/$arch-apple-$OSXCROSS_TARGET-objcopy"
    ln -s "$(command -v llvm-objdump)" "$prefix/bin/$arch-apple-$OSXCROSS_TARGET-objdump"
done

# GCC installs cc1 et al. unstripped at ~400MB each; only strip the ELF side, the Mach-O target libs stay as-is
find "$prefix/bin" "$prefix/libexec" -type f -perm -u+x -exec file {} + |
    grep -E "ELF .*not stripped" | cut -d: -f1 | xargs -r strip --strip-unneeded

# Trim what nothing here uses: ObjC frontends, lto-dump, docs, and the SDK's private frameworks, Swift modules and manpages
rm -rf "$prefix"/libexec/gcc/*/*/cc1obj "$prefix"/libexec/gcc/*/*/cc1objplus "$prefix"/libexec/gcc/*/*/install-tools \
    "$prefix"/bin/*-lto-dump "$prefix"/share/man "$prefix"/share/info "$prefix"/share/locale
sdk=$(echo "$prefix"/SDK/MacOSX*.sdk)
rm -rf "$sdk"/System/Library/PrivateFrameworks "$sdk"/System/Library/Perl "$sdk"/usr/share "$sdk"/usr/lib/swift
find "$sdk" \( -name "*.swiftmodule" -o -name "*.swiftinterface" -o -name "*.swiftdoc" -o -name "*.swiftsourceinfo" \) -prune -exec rm -rf {} +
