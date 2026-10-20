#!/usr/bin/env python3
# Copyright 2024-2026 Nick Brassel (@tzarc)
# SPDX-License-Identifier: GPL-2.0-or-later
"""Configure and build QMK toolchains via crosstool-ng."""

import argparse
import dataclasses
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
BUILDER_IMAGE = "ghcr.io/tzarc/qmk_toolchains:builder"
BASE_IMAGE = "ghcr.io/tzarc/qmk_toolchains:base"
BOOTSTRAP_TOOLS_PREFIX = "x86_64-qmk_bootstrap-linux-gnu-"


@dataclasses.dataclass(frozen=True)
class Combo:
    sample_name: str
    canadian_host: str | None = None
    vendor_name: str | None = None
    libc: str | None = None
    multilib_list: str | None = None
    extra_newlib_nano: bool = False
    build_host_compile: bool = False
    dir_suffix: str = ""
    container_image: str = BUILDER_IMAGE
    # Default --tools-prefix to the bootstrap compiler (base/host toolchains
    # must be built with it so they link against the old glibc).
    bootstrap_tools_prefix: bool = False


# Hosts the canadian (baremetal-target) toolchains run on.
_CANADIAN_HOSTS = {
    "linuxX64": "x86_64-qmk-linux-gnu",
    "linuxARM64": "aarch64-unknown-linux-gnu",
    "linuxRV64": "riscv64-unknown-linux-gnu",
    "macosX64": "x86_64-apple-darwin24",
    "macosARM64": "aarch64-apple-darwin24",
    "windowsX64": "x86_64-w64-mingw32",
}

# Per-target settings for the baremetal toolchains.
_BAREMETAL_TARGETS = {
    "baremetalARM": {
        "sample_name": "arm-none-eabi",
        "multilib_list": "rmprofile",
        "libc": "newlib",
        "extra_newlib_nano": True,
    },
    "baremetalAVR": {"sample_name": "avr"},
    "baremetalRV32": {"sample_name": "riscv32-picolibc-elf", "vendor_name": "unknown"},
}

COMBOS: dict[tuple[str, str, str | None], Combo] = {}

# 6 hosts x 3 baremetal targets. Includes host==build combos: intentionally
# built as canadian (even on the same architecture) to ensure libraries in the
# toolchain are compatible with the target.
for _host, _triplet in _CANADIAN_HOSTS.items():
    for _target, _settings in _BAREMETAL_TARGETS.items():
        COMBOS[(_host, _target, None)] = Combo(canadian_host=_triplet, **_settings)

# Base/host toolchains (built inside the `base` container with the bootstrap
# compiler, targeting old glibc for compatibility).
_BASE = {
    "build_host_compile": True,
    "container_image": BASE_IMAGE,
    "bootstrap_tools_prefix": True,
}
COMBOS[("linuxX64", "linuxX64", None)] = Combo(
    sample_name="x86_64-unknown-linux-gnu", vendor_name="qmk", **_BASE
)
COMBOS[("linuxX64", "linuxARM64", None)] = Combo(
    sample_name="aarch64-rpi3-linux-gnu", vendor_name="unknown", **_BASE
)
COMBOS[("linuxX64", "linuxRV64", None)] = Combo(
    sample_name="riscv64-unknown-linux-gnu", vendor_name="unknown", **_BASE
)
COMBOS[("linuxX64", "windowsX64", None)] = Combo(
    sample_name="x86_64-w64-mingw32", **_BASE
)

# Bootstrap compiler (no bootstrap_tools_prefix: it has nothing to bootstrap from).
COMBOS[("linuxX64", "linuxX64", "qmk_bootstrap")] = Combo(
    sample_name="x86_64-unknown-linux-gnu",
    vendor_name="qmk_bootstrap",
    dir_suffix="_qmk_bootstrap",
    build_host_compile=True,
    container_image=BASE_IMAGE,
)


def cpu_count() -> int:
    return os.cpu_count() or 1


def fn_os(os_name: str = "") -> str:
    name = (os_name or platform.system()).lower()
    if any(s in name for s in ("darwin", "macos", "apple")):
        return "macos"
    if any(s in name for s in ("windows", "mingw", "w64")):
        return "windows"
    if "linux" in name:
        return "linux"
    if any(s in name for s in ("none", "unknown", "picolibc", "nano")):
        return "baremetal"
    return "unknown"


def fn_arch(arch_name: str = "") -> str:
    name = (arch_name or platform.machine()).lower()
    if "arm64" in name or "aarch64" in name:
        return "ARM64"
    if "arm" in name:
        return "ARM"
    if "riscv32" in name:
        return "RV32"
    if "riscv64" in name:
        return "RV64"
    if "avr" in name:
        return "AVR"
    if "x86_64" in name or "x64" in name:
        return "X64"
    return "unknown"


def fn_os_arch(os_name: str = "", arch_name: str = "") -> str:
    return fn_os(os_name) + fn_arch(arch_name)


def fn_os_arch_fromtriplet(triplet: str) -> str:
    # AVR is a special snowflake.
    if triplet == "avr":
        return fn_os_arch_fromtriplet("avr-none-none")
    # Remove the qmk vendor from the bootstrapped compiler
    triplet = triplet.replace("qmk-", "")
    parts = triplet.split("-")
    input_arch = parts[0]
    input_os = parts[1] if len(parts) > 1 else ""
    # Try to skip vendor
    if input_os in ("unknown", "multilib", "none", "pc", "rpi3", "w64"):
        input_os = parts[2] if len(parts) > 2 else ""
    # If we're into the ABI stuff, then backtrack
    if input_os in ("eabi", "elf", "mingw32"):
        input_os = parts[1]
    return fn_os_arch(input_os, input_arch)


class KconfigEditor:
    """Surgical edits to a crosstool-ng .config file."""

    def __init__(self, path: Path) -> None:
        self.path = path

    def _read(self) -> list[str]:
        return self.path.read_text().splitlines()

    def _write(self, lines: list[str]) -> None:
        self.path.write_text("\n".join(lines) + "\n")

    def get_value(self, name: str) -> str | None:
        pat = re.compile(rf"^{re.escape(name)}=(.*)$")
        for line in self._read():
            m = pat.match(line)
            if m:
                return m.group(1)
        return None

    def set_value(self, name: str, value: str) -> None:
        """Replace an existing entry in place (set or '# ... is not set'), else append."""
        pat = re.compile(rf"^(# )?{re.escape(name)}(=.*| is not set)$")
        lines = self._read()
        replaced = False
        for i, line in enumerate(lines):
            if pat.match(line):
                lines[i] = f"{name}={value}"
                replaced = True
        if not replaced:
            lines.append(f"{name}={value}")
        self._write(lines)

    def set_choice_value(self, family_regex: str, name: str, value: str) -> None:
        """set_value, but insert next to choice siblings instead of at EOF."""
        # A choice group permits only one selection, so clear any other enabled sibling first.
        clear_pat = re.compile(rf"^({family_regex})=.*$")
        lines = self._read()
        for i, line in enumerate(lines):
            m = clear_pat.match(line)
            if m:
                lines[i] = f"# {m.group(1)} is not set"
        name_pat = re.compile(rf"^(# )?{re.escape(name)}(=.*| is not set)$")
        if any(name_pat.match(line) for line in lines):
            for i, line in enumerate(lines):
                if name_pat.match(line):
                    lines[i] = f"{name}={value}"
        else:
            family_pat = re.compile(rf"^(# )?({family_regex})(=.*| is not set)$")
            last = None
            for i, line in enumerate(lines):
                if family_pat.match(line):
                    last = i
            if last is not None:
                lines.insert(last + 1, f"{name}={value}")
            else:
                lines.append(f"{name}={value}")
        self._write(lines)


def ct_ng_olddefconfig() -> None:
    # Exit status deliberately ignored -- olddefconfig noise is not fatal.
    proc = subprocess.run(
        ["ct-ng", "olddefconfig"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    for line in proc.stdout.splitlines():
        if re.search(r"CONF.*olddefconfig", line):
            continue
        if line.startswith("#"):
            continue
        if re.search(r"warning: override:", line):
            continue
        print(line)


def respawn_docker_if_needed(args: argparse.Namespace, combo: Combo) -> None:
    """If necessary, re-exec with a clean environment inside docker."""
    if not os.environ.get("EXECUTE_UNDER_DOCKER"):
        return
    image = args.container_image or combo.container_image
    # Because I keep forgetting to run with --interactive when running menuconfig:
    interactive = (
        ["-it"]
        if (
            args.interactive or (args.ct_ng_args and args.ct_ng_args[0] == "menuconfig")
        )
        else []
    )
    mem_total_kb = 0
    with open("/proc/meminfo") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                mem_total_kb = int(line.split()[1])
                break
    tc_workdir = os.environ["TC_WORKDIR"]
    cmd = [
        "docker",
        "run",
        "--rm",
        *interactive,
        "-v",
        f"{SCRIPT_DIR}:{tc_workdir}",
        "-w",
        tc_workdir,
        "-e",
        f"TC_WORKDIR={tc_workdir}",
        f"--cpus={cpu_count() * 0.9:.2f}",
        f"--memory={int(mem_total_kb / 1024 * 0.9)}m",
        "--memory-swap=-1",
        image,
        "./build_toolchain.py",
        *sys.argv[1:],
    ]
    print(f"\033[0;36mRunning: \033[1;36m{' '.join(cmd)}\033[0m", file=sys.stderr)
    os.chdir(SCRIPT_DIR)
    os.execvp("docker", cmd)


def build_one(args: argparse.Namespace, combo: Combo) -> None:
    os.umask(0o022)
    if not shutil.which("ct-ng"):
        sys.exit("ct-ng not found in PATH. Please install crosstool-ng first.")

    # Resolve the effective tools prefix: CLI overrides combo default; empty string clears.
    if args.tools_prefix is not None:
        tools_prefix = args.tools_prefix
    elif combo.bootstrap_tools_prefix:
        tools_prefix = BOOTSTRAP_TOOLS_PREFIX
    else:
        tools_prefix = ""

    (SCRIPT_DIR / "tarballs").mkdir(parents=True, exist_ok=True)

    if combo.canadian_host:
        name_host = fn_os_arch_fromtriplet(combo.canadian_host)
    else:
        name_host = fn_os_arch()
    name_target = fn_os_arch_fromtriplet(combo.sample_name)
    target_dir = f"host_{name_host}-target_{name_target}{combo.dir_suffix}"
    build_dir = SCRIPT_DIR / "build" / target_dir
    toolchain_dir = SCRIPT_DIR / "toolchains" / target_dir

    print("============")
    print(f" BUILD TARGET: {target_dir}")
    print(f"    BUILD DIR: {build_dir}")
    print(f"TOOLCHAIN DIR: {toolchain_dir}")
    print("============")
    print()

    build_dir.mkdir(parents=True, exist_ok=True)
    os.chdir(build_dir)

    # Remove any existing configuration
    config = build_dir / ".config"
    if config.exists():
        config.unlink()

    # Load the crosstool-ng sample configuration for the target
    subprocess.run(["ct-ng", combo.sample_name], check=True)
    ed = KconfigEditor(config)

    # Set up the build environment params
    ed.set_value("CT_EXPERIMENTAL", "y")  # required for some features
    ed.set_value("CT_FORCE_EXTRACT", "y")

    # Enable stripping of the toolchain executables
    ed.set_value("CT_STRIP_HOST_TOOLCHAIN_EXECUTABLES", "y")
    ed.set_value("CT_STRIP_TARGET_TOOLCHAIN_EXECUTABLES", "y")

    # Don't go overboard with the parallel jobs
    ed.set_value("CT_PARALLEL_JOBS", str(cpu_count()))

    ct_ng_olddefconfig()

    # Disable the progress bar and other unnecessary features, and zstd support was broken last time it was checked
    ed.set_value("CT_LOCAL_TARBALLS_DIR", f'"{SCRIPT_DIR}/tarballs"')
    ed.set_value("CT_LOG_PROGRESS_BAR", "n")
    ed.set_value("CT_PREFIX_DIR_RO", "n")
    ed.set_value("CT_CC_LANG_CXX", "y")
    ed.set_value("CT_CC_GCC_LTO_ZSTD", "n")
    ed.set_value("CT_COMP_LIBS_ZSTD", "n")
    ed.set_value("CT_ZSTD_NEEDED", "n")
    ed.set_value("CT_ZSTD", "n")
    ed.set_value("CT_DEBUG_GDB", "y")

    # gdb v17 seems to be broken on macOS ARM64, so pin to v16 for now.
    ed.set_choice_value("CT_GDB_V_[A-Za-z0-9_]*", "CT_GDB_V_16", "y")
    ct_ng_olddefconfig()

    # GDB's TUI causes issues with the build, so disable it.
    ed.set_value(
        "CT_GDB_CROSS_EXTRA_CONFIG_ARRAY", '"--disable-tui"'
    )  # see https://github.com/crosstool-ng/crosstool-ng/issues/321

    # For baremetal ARM toolchains, pin binutils at 2.43 due to issues with ARM relocations (ChibiOS-Contrib): https://gcc.gnu.org/pipermail/gcc-help/2025-May/144169.html
    # Fixed in https://github.com/ChibiOS/ChibiOS-Contrib/commit/2fb815dfe05607e65f85083393e1c3aa41cdea3d (2025-06-06)
    # Can remove this override once newer ChibiOS-Contrib submodule revisions are merged into QMK firmware.
    if not combo.build_host_compile and "arm" in combo.sample_name:
        ed.set_choice_value("CT_BINUTILS_V_[A-Za-z0-9_]*", "CT_BINUTILS_V_2_43", "y")

    if "linux" in combo.sample_name:
        # Swap to an older version of glibc to avoid issues with older distros, especially things like older Debian with Raspberry Pi targets.
        # See the glibc version compat list here: https://abi-laboratory.pro/?view=timeline&l=glibc -- 2.28 seems safe enough?
        # NOTE: this must happen before any GCC version override below -- newer glibc versions select
        # GCC_REQUIRE_*_or_later, which makes older CT_GCC_V_* choices invisible and silently reverted
        # by ct-ng olddefconfig.
        if "riscv64-unknown-linux-gnu" in combo.sample_name:
            ed.set_choice_value("CT_GLIBC_V_[A-Za-z0-9_]*", "CT_GLIBC_V_2_36", "y")
            ed.set_value("CT_GLIBC_OLDEST_ABI", '"2.36"')
            ed.set_value("CT_CC_GCC_EXTRA_CONFIG_ARRAY", '"--with-glibc-version=2.36"')
        else:
            ed.set_choice_value("CT_GLIBC_V_[A-Za-z0-9_]*", "CT_GLIBC_V_2_28", "y")
            ed.set_value("CT_GLIBC_OLDEST_ABI", '"2.28"')
            ed.set_value("CT_CC_GCC_EXTRA_CONFIG_ARRAY", '"--with-glibc-version=2.28"')
        ct_ng_olddefconfig()

    # Builder older versions of the toolchain when we're building the base cross-compilers
    if combo.build_host_compile:
        # Don't need gdb for the host builds
        ed.set_value("CT_DEBUG_GDB", "n")

        # Clear the GCC version-constraint selector symbols so older GCC choices stay visible.
        constraint = re.compile(
            r"^(# )?(CT_GCC_[0-9][A-Za-z0-9_]*_or_older"
            r"|CT_GCC_[0-9][A-Za-z0-9_]*_or_later"
            r"|CT_GCC_REQUIRE_[0-9][A-Za-z0-9_]*_or_later"
            r"|CT_GCC_later_than_[A-Za-z0-9_]*"
            r"|CT_GCC_older_than_[A-Za-z0-9_]*)(=.*| is not set)$"
        )
        lines = config.read_text().splitlines()
        lines = [constraint.sub(r"# \2 is not set", line) for line in lines]
        config.write_text("\n".join(lines) + "\n")

        if "riscv64-unknown-linux-gnu" in combo.sample_name:
            ed.set_choice_value("CT_GCC_V_[A-Za-z0-9_]*", "CT_GCC_V_10", "y")
            ed.set_value("CT_GCC_VERSION", '"10.5.0"')
        else:
            ed.set_choice_value("CT_GCC_V_[A-Za-z0-9_]*", "CT_GCC_V_8", "y")
            ed.set_value("CT_GCC_VERSION", '"8.5.0"')

        ct_ng_olddefconfig()

        ed.set_choice_value("CT_MINGW_W64_V_[A-Za-z0-9_]*", "CT_MINGW_W64_V_V10_0", "y")
        ed.set_value("CT_MINGW_W64_VERSION", '"v10.0.0"')

        ct_ng_olddefconfig()

    ct_ng_olddefconfig()

    # Swap to an older version of Linux (LTS) and glibc to avoid execution issues with older distros, especially things like older Debian with Raspberry Pi targets.
    if "riscv64-unknown-linux-gnu" in combo.sample_name:
        # rv64 needs a slightly newer kernel
        ed.set_choice_value("CT_LINUX_V_[A-Za-z0-9_]*", "CT_LINUX_V_5_10", "y")
        ed.set_value("CT_LINUX_VERSION", '"5.10"')
        ed.set_value("CT_GLIBC_MIN_KERNEL", '"5.10"')
        ed.set_choice_value(
            "CT_GLIBC_KERNEL_VERSION_[A-Za-z0-9_]*",
            "CT_GLIBC_KERNEL_VERSION_AS_HEADERS",
            "y",
        )
    else:
        ed.set_choice_value("CT_LINUX_V_[A-Za-z0-9_]*", "CT_LINUX_V_4_19", "y")
        ed.set_value("CT_LINUX_VERSION", '"4.19"')
        ed.set_value("CT_GLIBC_MIN_KERNEL", '"4.19"')
        ed.set_choice_value(
            "CT_GLIBC_KERNEL_VERSION_[A-Za-z0-9_]*",
            "CT_GLIBC_KERNEL_VERSION_AS_HEADERS",
            "y",
        )

    ct_ng_olddefconfig()

    # Disable unnecessary languages
    ed.set_value("CT_CC_LANG_FORTRAN", "n")
    ed.set_value("CT_CC_LANG_JIT", "n")
    ed.set_value("CT_CC_LANG_ADA", "n")
    ed.set_value("CT_CC_LANG_D", "n")
    ed.set_value("CT_CC_LANG_OBJC", "n")
    ed.set_value("CT_CC_LANG_OBJCXX", "n")
    ed.set_value("CT_CC_LANG_GOLANG", "n")

    # Too many concurrent LTO runs breaks RISC-V builds on GHA, which terminate due to being OOM
    # See https://bugs.gentoo.org/946338 for similar issues
    # The following set of options all reduce memory usage during linking of the compiler itself. RISC-V builds will randomly fail on GitHub Actions runs if these aren't present.
    # NOTE: appends to (rather than replaces) any existing CT_CC_GCC_EXTRA_CONFIG_ARRAY (e.g. --with-glibc-version set above) -- it's a plain Kconfig string, so a second set_value would otherwise clobber it.
    existing = ed.get_value("CT_CC_GCC_EXTRA_CONFIG_ARRAY")
    existing = existing.strip('"') if existing else ""
    joined = f"{existing} " if existing else ""
    ed.set_value(
        "CT_CC_GCC_EXTRA_CONFIG_ARRAY",
        f'"{joined}--enable-link-serialization=1 --with-build-config=bootstrap-O1"',
    )
    ed.set_value(
        "CT_CC_GCC_CORE_EXTRA_CONFIG_ARRAY",
        '"--enable-link-serialization=1 --with-build-config=bootstrap-O1"',
    )
    ed.set_value("CT_CC_GCC_DISABLE_PCH", "y")

    # ct-ng feeds these to CXXFLAGS too; there is no CXXFLAGS_FOR_HOST option. Not -Os: it implies -fdeclone-ctor-dtor, which
    # breaks linking C++20 against libstdc++ on targets without symbol aliases: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=125359
    ed.set_value("CT_EXTRA_CFLAGS_FOR_HOST", '"-O2 -g0"')

    if combo.canadian_host and "macos" not in str(toolchain_dir):
        # These only seem to be available with the toolchains built by the base container -- the macOS cross-compilers don't have them.
        # Those don't seem to have an issue with LTO, so safe to skip here.
        ed.set_value(
            "CT_EXTRA_LDFLAGS_FOR_HOST",
            '"-Wl,--no-keep-memory -Wl,--reduce-memory-overheads"',
        )

    ct_ng_olddefconfig()

    # Configure the required C library
    if combo.libc:
        ed.set_value(f"CT_LIBC_{combo.libc.upper()}", "y")
        ed.set_value("CT_LIBC", f'"{combo.libc.lower()}"')
        ed.set_value("CT_COMP_LIBS_NEWLIB_NANO", "n")
        ed.set_value("CT_COMP_LIBS_PICOLIBC", "n")
        ct_ng_olddefconfig()

        if combo.libc == "newlib":
            ed.set_value("CT_LIBC_NEWLIB_DISABLE_SUPPLIED_SYSCALLS", "n")
        ct_ng_olddefconfig()

    # Enable newlib-nano if requested
    if combo.extra_newlib_nano:
        ed.set_value("CT_COMP_LIBS_NEWLIB_NANO", "y")
        ct_ng_olddefconfig()
        ed.set_value("CT_LIBC_NEWLIB_EXTRA_SECTIONS", "y")
        ed.set_value("CT_LIBC_NEWLIB_NANO_MALLOC", "y")
        ed.set_value("CT_NEWLIB_NANO_INSTALL_IN_TARGET", "y")
        ed.set_value("CT_LIBC_NEWLIB_NANO_EXTRA_SECTIONS", "y")
        ct_ng_olddefconfig()

    # Set the list of multilib targets
    if combo.multilib_list:
        ed.set_value("CT_CC_GCC_MULTILIB_LIST", f'"{combo.multilib_list}"')
        ct_ng_olddefconfig()

    # Override the vendor name string
    if combo.vendor_name:
        ed.set_value("CT_TARGET_VENDOR", f'"{combo.vendor_name}"')
        ct_ng_olddefconfig()

    # Disable python for cross-compile GDB
    ed.set_value("CT_GDB_CROSS_PYTHON", "n")
    ct_ng_olddefconfig()

    # Enable canadian builds if requested
    if combo.canadian_host:
        ed.set_value("CT_CROSS", "n")
        ed.set_value("CT_CANADIAN", "y")
        ed.set_value("CT_TOOLCHAIN_TYPE", '"canadian"')

        ed.set_value("CT_HOST", f'"{combo.canadian_host}"')

        if "mingw32" in combo.canadian_host:
            # Fixup Windows builds:
            ed.set_value("CT_LIBC_GLIBC", "n")
            ed.set_value(
                "CT_BINUTILS_PLUGINS", "n"
            )  # need to disable these as builds providing LTO fail on Windows because the DLLs export too many symbols (>65536)

        ct_ng_olddefconfig()

    # Set the toolchain output directory
    ed.set_value("CT_PREFIX_DIR", f'"{toolchain_dir}"')
    ct_ng_olddefconfig()

    # Enable debug options
    ed.set_value("CT_DEBUG_CT", "y")
    ct_ng_olddefconfig()

    if not args.no_keep_state:
        # Save the build steps so that we can save/restore on GHA due to build execution time limits.
        ed.set_value("CT_DEBUG_CT_SAVE_STEPS", "y")
        ed.set_value("CT_DEBUG_CT_SAVE_STEPS_GZIP", "y")
        ed.set_value("CT_DEBUG_CT_SAVE_STEPS_LAST_ONLY", "y")

    # Set the toolchain version string
    describe = subprocess.run(
        ["git", "describe", "--always", "--dirty", "--exclude", "*"],
        capture_output=True,
        text=True,
        cwd=SCRIPT_DIR,
        check=True,
    ).stdout.strip()
    ed.set_value("CT_TOOLCHAIN_PKGVERSION", f'"qmk/qmk_toolchains @ {describe}"')

    if tools_prefix:
        # Set the tools prefix
        ed.set_value("CT_BUILD_PREFIX", f'"{tools_prefix}"')

    ct_ng_olddefconfig()

    # Save a copy of the "cut-down" config for inspection purposes.
    subprocess.run(["ct-ng", "savedefconfig"], check=True)
    bar = "=" * 96
    print(bar)
    print("== begin defconfig " + "=" * 77)
    print(bar)
    print((build_dir / "defconfig").read_text(), end="")
    print(bar)
    print("== end defconfig " + "=" * 79)
    print(bar)
    print()

    # Add the other compilers to the PATH for use in canadian builds
    for bindir in sorted((SCRIPT_DIR / "toolchains").glob(f"host_{fn_os_arch()}*/bin")):
        if bindir.is_dir():
            os.environ["PATH"] = f"{bindir}:{os.environ['PATH']}"

    # Dump out the resulting path
    print("$PATH:")
    print(os.environ["PATH"].replace(":", "\n"))

    positional = list(args.ct_ng_args) or ["build"]

    if positional == ["source"]:
        subprocess.run(
            ["ct-ng", "source"], check=False
        )  # exit status deliberately ignored -- best-effort prefetch
        return

    proc = subprocess.run(
        ["nice", "-n", "10", "ionice", "-c", "3", "ct-ng", *positional], check=False
    )
    if proc.returncode != 0:
        sys.exit(proc.returncode)

    if combo.canadian_host and "macos" in str(toolchain_dir):
        # Patch the `@rpath` of the toolchain binaries so that they look in `@executable_path/../lib` for libraries
        for f in sorted((toolchain_dir / "bin").rglob("*")):
            if f.is_file() and os.access(f, os.X_OK):
                subprocess.run(
                    [
                        f"{combo.canadian_host}-install_name_tool",
                        "-add_rpath",
                        "@executable_path/../lib",
                        str(f),
                    ],
                    check=False,
                )
        # Copy across libstdc++ for gdb
        subprocess.run(
            [
                "cp",
                f"/osxcross/{combo.canadian_host}/lib/libstdc++.6.dylib",
                str(toolchain_dir / "lib"),
            ],
            check=False,
        )
        # Codesign macOS executables
        for f in sorted(toolchain_dir.rglob("*")):
            if f.is_file() and os.access(f, os.X_OK):
                print(f)
                subprocess.run(["rcodesign", "sign", str(f)], check=False)

    # Save identifying information
    (toolchain_dir / "etc").mkdir(parents=True, exist_ok=True)
    commit_iso = subprocess.run(
        ["git", "show", "--no-patch", "--format=%cI", "HEAD"],
        capture_output=True,
        text=True,
        cwd=SCRIPT_DIR,
        check=True,
    ).stdout.strip()
    commit_date = (
        datetime.fromisoformat(commit_iso)
        .astimezone(timezone.utc)
        .strftime("%Y-%m-%dT%H:%M:%SZ")
    )
    release_file = (
        toolchain_dir / "etc" / f"toolchain_release_{name_host}_{name_target}"
    )
    release_file.write_text(
        f"TOOLCHAIN_HOST={name_host}\n"
        f"TOOLCHAIN_TARGET={name_target}\n"
        f"COMMIT_DATE={commit_date}\n"
        f"COMMIT_HASH={describe}\n"
    )


def _sorted_combos() -> list[tuple[str, str, str | None]]:
    return sorted(COMBOS, key=lambda k: (k[0], k[1], k[2] or ""))


def print_combo_table() -> None:
    rows = [
        (
            host,
            target,
            variant or "",
            f"./build_toolchain.py --host {host} --target {target}"
            + (f" --variant {variant}" if variant else ""),
        )
        for host, target, variant in _sorted_combos()
    ]
    headers = ("Host", "Target", "Variant", "Invocation")
    widths = [
        max(len(headers[i]), *(len(r[i]) for r in rows)) for i in range(len(headers))
    ]
    print("  ".join(h.ljust(w) for h, w in zip(headers, widths)).rstrip())
    print("  ".join("-" * w for w in widths))
    for row in rows:
        print("  ".join(c.ljust(w) for c, w in zip(row, widths)).rstrip())


def parse_cli(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Configure and build one QMK toolchain via crosstool-ng.",
        epilog="Remaining arguments are passed to ct-ng (default: build). "
        "Examples: 'build STOP=cc_for_build', '+companion_tools_for_build', 'savedefconfig', 'menuconfig', 'source'.",
    )
    parser.add_argument(
        "--host", help="Host OS/arch the toolchain runs on, e.g. linuxX64"
    )
    parser.add_argument(
        "--target", help="Target the toolchain compiles for, e.g. baremetalARM"
    )
    parser.add_argument(
        "--variant",
        default=None,
        help="Combo variant, e.g. qmk_bootstrap (leading underscore tolerated)",
    )
    parser.add_argument(
        "--list-combos",
        action="store_true",
        help="Print the known combos and exit (a table, or 'host target [variant]' lines with --porcelain)",
    )
    parser.add_argument(
        "--porcelain",
        action="store_true",
        help="Machine-readable --list-combos output for script automation",
    )
    parser.add_argument(
        "--container-image",
        default=None,
        help="Override the docker image used for the build",
    )
    parser.add_argument(
        "--tools-prefix",
        default=None,
        help="Override the build toolchain prefix; empty string clears it",
    )
    parser.add_argument(
        "--no-keep-state",
        action="store_true",
        help="Don't save crosstool-ng step state",
    )
    parser.add_argument(
        "--interactive", action="store_true", help="Add -it to the docker invocation"
    )
    parser.add_argument(
        "ct_ng_args", nargs="*", help="Arguments passed through to ct-ng"
    )
    if not argv:
        parser.print_help()
        print()
        print_combo_table()
        sys.exit(0)
    args = parser.parse_intermixed_args(argv)
    if args.variant is not None:
        args.variant = args.variant.lstrip("_") or None
    return args


def main() -> None:
    # Die quietly when output is piped into `head` etc., like any other CLI tool
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    sys.stdout.reconfigure(line_buffering=True)
    # macOS SDK Version
    os.environ["SDK_VERSION"] = "15.0"
    # macOS Target Version (Monterey)
    os.environ["MACOSX_DEPLOYMENT_TARGET"] = "12.0"
    args = parse_cli(sys.argv[1:])

    if args.list_combos:
        if args.porcelain:
            for host, target, variant in _sorted_combos():
                print(f"{host} {target} {variant}" if variant else f"{host} {target}")
            return
        print_combo_table()
        return

    if not args.host or not args.target:
        sys.exit("error: --host and --target are required (see --list-combos)")
    key = (args.host, args.target, args.variant)
    if key not in COMBOS:
        sys.exit(
            f"error: unknown combo host={args.host} target={args.target} variant={args.variant}"
        )
    combo = COMBOS[key]
    for arg in sys.argv[1:]:
        print(f"\033[0;33m - Arg: \033[1;33m{arg}\033[0m", file=sys.stderr)
    os.environ["PATH"] = f"{Path.home()}/.local/crosstool-ng/bin:{os.environ['PATH']}"
    respawn_docker_if_needed(args, combo)
    build_one(args, combo)


if __name__ == "__main__":
    main()
