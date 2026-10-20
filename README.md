# QMK Toolchains

Builds of baremetal cross-compilation `*-gcc` primarily for QMK Firmware use.

Currently provides GCC 16.2.0, for the following baremetal targets:

* `arm-none-eabi`
* `avr`
* `riscv32-unknown-elf`

Toolchain host machines supported:

* Linux/x86_64
* Linux/aarch64
* Linux/riscv64
* macOS/aarch64
* macOS/x86_64
* Windows/x86_64

All builds for the above toolchain variants are done on GitHub actions -- the [latest release](https://github.com/tzarc/qmk_toolchains/releases/tag/latest) provides tarballs for each of the target+host combinations.

Repacked toolchain downloads can be found on [qmk/qmk_toolchains releases](https://github.com/qmk/qmk_toolchains/releases); these offer merged distributions for all baremetal targets for each host type.

# Containers

Two prerequisite container images are created through GitHub actions -- `ghcr.io/tzarc/qmk_toolchains:base` and `ghcr.io/tzarc/qmk_toolchains:builder`; the latter includes all the required cross-compilers for:

* `x86_64-qmk-linux-gnu`
* `aarch64-unknown-linux-gnu`
* `riscv64-unknown-linux-gnu`
* `x86_64-w64-mingw32`
* `aarch64-apple-darwin24`
* `x86_64-apple-darwin24`

These containers need an environment variable -- `$TC_WORKDIR` -- with a corresponding volume mounted to that location inside the container as the user/group permissions will be updated to match during execution.

# Building a toolchain locally

`build_toolchain.py` re-executes itself inside the builder container with the repository mounted at `$TC_WORKDIR`. The tracked `.envrc` sets `TC_WORKDIR` and `EXECUTE_UNDER_DOCKER` for `direnv` users; export them yourself otherwise.

```sh
./build_toolchain.py --host macosARM64 --target baremetalAVR
```

Run it without arguments to list every host/target pair with the command that builds it.

The result lands in `toolchains/host_<host>-target_<target>/`, with crosstool-ng's working tree, logs and saved step state under `build/`, and source tarballs cached in `tarballs/`.
