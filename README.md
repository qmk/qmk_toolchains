# QMK Toolchains

Builds of baremetal cross-compilation `*-gcc` primarily for QMK Firmware use.

Currently provides GCC 14.2.0, for the following baremetal targets:

* `arm-none-eabi`
* `avr`
* `riscv32-unknown-elf`

Two prerequisite container images are created -- `ghcr.io/tzarc/qmk_toolchains:base` and `ghcr.io/tzarc/qmk_toolchains:builder`; the latter includes all the required cross-compilers for:

* `x86_64-qmk-linux-gnu`
* `aarch64-unknown-linux-gnu`
* `riscv64-unknown-linux-gnu`
* `x86_64-w64-mingw32`
* `aarch64-apple-darwin24`
* `x86_64-apple-darwin24`

These containers need a volume mounted on `/t` inside the container -- the user/group permissions inside the container will be updated to match during execution.

Corresponding builds are done on GitHub actions.

