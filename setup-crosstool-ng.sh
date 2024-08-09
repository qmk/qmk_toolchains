#!/usr/bin/env bash

set -eEuo pipefail

if [[ -d "$HOME/crosstool-ng-install" ]]; then
    rm -rf "$HOME/crosstool-ng-install"
fi

git clone https://github.com/crosstool-ng/crosstool-ng.git "$HOME/crosstool-ng-install"

cd "$HOME/crosstool-ng-install"
./bootstrap
./configure --prefix=$HOME/.local/crosstool-ng
make
make install
