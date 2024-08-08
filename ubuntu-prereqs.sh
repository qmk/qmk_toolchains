#!/usr/bin/env bash

unset SUDO
if [[ $EUID != 0 ]]; then
    SUDO=sudo
fi

DEBIAN_FRONTEND=noninteractive $SUDO apt-get update
DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y build-essential git wget curl gperf help2man libtool-bin meson flex bison texinfo gawk libncurses-dev patchelf
