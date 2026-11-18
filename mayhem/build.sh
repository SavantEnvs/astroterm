#!/usr/bin/env bash
#
# mayhem/build.sh — build astroterm's fuzz harnesses and its unit-test suite.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image
# (ghcr.io/savantenvs/base) already exports the build contract — use these, don't redefine:
#   CC, CXX             stock clang / clang++
#   LIB_FUZZING_ENGINE  -fsanitize=fuzzer   (link into each harness that has a LLVMFuzzer entry)
#   SANITIZER_FLAGS     -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
#                       (ASan + UBSan, both set to HALT — so Mayhem catches memory AND UB defects)
#   DEBUG_FLAGS         -g -gdwarf-3   (DWARF debug info — always on for fuzz/standalone builds,
#                       independent of the sanitizer off-switch; DWARF version must be < 4)
#   RUST_DEBUG_FLAGS    -C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3
#                       (thread through RUSTFLAGS on every cargo-fuzz build)
#   GO_DEBUG_FLAGS      -gcflags=all=-N -l
#                       (thread through go build / go-fuzz-build so the linked ELF keeps symbols)
#   SRC                 /mayhem (the repo source)
#
# Contract: build EVERYTHING here — one runnable binary per fuzz harness, AND the project's test
# suite (so mayhem/test.sh only has to RUN it, never compile). Keep it ADDITIVE (build upstream as
# upstream documents; don't edit upstream files). IMPORTANT: build the PROJECT ITSELF with
# $SANITIZER_FLAGS and $DEBUG_FLAGS (not just the harness) so the fuzzed code is instrumented
# AND carries DWARF < 4 symbols — otherwise ASan/UBSan only see the harness, not the library
# you're trying to find bugs in, and backtraces won't resolve project source lines. Build the TEST
# suite with the project's NORMAL flags (a clean, independent build) so test.sh stays an honest
# functional oracle and won't false-fail on benign UB. Leave the test binary/runner where test.sh
# expects it.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs come from the ENVIRONMENT (overridable), with sane defaults — no if-statements,
# just parameter-expansion fallbacks. Default sanitizers are the base's ASan+UBSan (halting); override
# per build via the Dockerfile's `--build-arg SANITIZER_FLAGS="..."`.
# NB: SANITIZER_FLAGS uses `=` (no colon) on purpose — `=` only fills when the var is UNSET, so an
# explicit EMPTY value (`--build-arg SANITIZER_FLAGS=`) is honored and builds with NO sanitizers
# (useful when you want the program's natural crash / full backtrace, not an ASan report). The other
# knobs use `:=` (default on empty too). MAYHEM_JOBS sets build parallelism (falls back to nproc).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS carries DWARF debug info INDEPENDENTLY of the sanitizer off-switch (so an empty
# SANITIZER_FLAGS still yields DWARF symbols). DWARF MUST be < 4 (Mayhem triage can't read >=4); clang-19's
# plain `-g` emits DWARF-5, so `-gdwarf-3` is explicit. Apply $DEBUG_FLAGS to the fuzz/harness/standalone
# builds (NOT the test/oracle build). Rust/Go carry the same intent via their language flags below.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3}"
: "${GO_DEBUG_FLAGS:=-gcflags=all=-N -l}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
# COVERAGE_FLAGS: empty by default → no effect on the normal oracle build. Set it via the Dockerfile's
# `--build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping"` to instrument the TEST
# build for source-coverage measurement (how much of the project the test suite actually exercises —
# a quality signal for the oracle; complements the anti-reward-hack sabotage check). APPEND it to the
# test build's compile+link flags in step 3 (NOT the fuzz build); after `test.sh` runs, merge with
# `llvm-profdata` and report with `llvm-cov`. Empty value is honored (`=`, not `:=`).
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS RUST_DEBUG_FLAGS GO_DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# Upstream's meson build expects the Yale Bright Star Catalog at data/bsc5 (gitignored, downloaded by
# upstream's CI). The Dockerfile caches it, sha256-checked, under /opt/toolchains/deps; (re)create it here
# so the build also works on a `git clean -ffdX`-ed tree and offline.
BSC5=/opt/toolchains/deps/bsc5-1991/src/BSC5
[ -f "$BSC5" ] || { echo "missing $BSC5 (cached by mayhem/Dockerfile)" >&2; exit 1; }
cp -f "$BSC5" data/bsc5

# Both meson build dirs must sit directly under the source root (meson.build runs `sh ../scripts/embed.sh`)
# and be gitignored so `git clean -ffdX` removes them: upstream's .gitignore covers `build/` and
# `build_coverage/`. Re-runs start from scratch.
rm -rf build build_coverage

# 1) The project (library + embedded data headers), sanitized, with SanCov on the library so the fuzzed
#    code itself has coverage instrumentation, and DWARF <= 3.
CFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" LDFLAGS="$SANITIZER_FLAGS" \
    meson setup build -Db_lundef=false
ninja -C build -j"$MAYHEM_JOBS" liblib_astroterm.a

# 2) Harnesses, each linked twice: libFuzzer and the standalone run-once reproducer. Leak detection is
#    compiled out of every binary (mayhem/lsan_off.c).
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.c -o build/lsan_off.o
LIBS="build/liblib_astroterm.a $(pkg-config --libs ncursesw 2>/dev/null || echo -lncursesw) -lm"
for h in fuzz_constell fuzz_names fuzz_bsc5 fuzz_city fuzz_datetime; do
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS -D_GNU_SOURCE -Iinclude -Idata -I. -Ibuild \
        $LIB_FUZZING_ENGINE "mayhem/harnesses/$h.c" build/lsan_off.o $LIBS -o "$SRC/$h"
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS -D_GNU_SOURCE -Iinclude -Idata -I. -Ibuild \
        "$STANDALONE_FUZZ_MAIN" "mayhem/harnesses/$h.c" build/lsan_off.o $LIBS -o "$SRC/$h-standalone"
done

# 3) The unit tests (Unity), with the project's NORMAL flags — a separate, unsanitized build.
CFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" meson setup build_coverage -Db_lundef=false
ninja -C build_coverage -j"$MAYHEM_JOBS"
