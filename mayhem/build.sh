#!/usr/bin/env bash
# mayhem/build.sh — build par2cmdline's fuzz harnesses and its own test suite.
# Runs in the commit image as `mayhem` in /mayhem; re-runnable and offline
# (no dependencies beyond the vendored cxxopts in libs/ and pthreads).
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"
B="$SRC/mayhem/build"          # gitignored (mayhem/.gitignore)

# 1) Test suite: the project's normal Release build (par2 tool + unit tests),
#    run by mayhem/test.sh through ctest.
cmake -S . -B "$B/tests" -G Ninja -DCMAKE_BUILD_TYPE=Release -DPAR2_BUILD_TESTS=ON \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS"
cmake --build "$B/tests" -j"$MAYHEM_JOBS"

# 2) The library (libpar2 + libpar2cli) instrumented with the sanitizers and
#    fuzzer coverage, asserts kept. The build type's own flags are emptied so
#    nothing re-adds a plain -g (DWARF 5) after -gdwarf-3.
FUZZ_CXXFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1"
cmake -S . -B "$B/fuzz" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DPAR2_BUILD_TESTS=OFF -DPAR2_BUILD_TOOL=OFF -DPAR2_INSTALL=OFF -DPAR2_KEEP_ASSERTS=ON \
  -DCMAKE_C_FLAGS="$FUZZ_CXXFLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_CXXFLAGS" \
  -DCMAKE_C_FLAGS_RELEASE="" -DCMAKE_CXX_FLAGS_RELEASE=""
cmake --build "$B/fuzz" -j"$MAYHEM_JOBS"

LIBS=("$B/fuzz/libpar2cli.a" "$B/fuzz/libpar2.a" -lpthread)
INC=(-I"$SRC/include" -I"$SRC/src" -I"$B/fuzz" -I"$B/fuzz/include")
HFLAGS=($SANITIZER_FLAGS $DEBUG_FLAGS -O1 -std=c++17)

"$CC" $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"
"$CXX" $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"

for h in fuzz_par2_verify fuzz_par1_verify fuzz_par2_repair fuzz_par1_repair; do
  "$CXX" "${HFLAGS[@]}" "${INC[@]}" -c "$SRC/mayhem/harnesses/$h.cc" -o "$B/$h.o"
  "$CXX" "${HFLAGS[@]}" $LIB_FUZZING_ENGINE "$B/$h.o" "$B/lsan_off.o" "${LIBS[@]}" -o "$SRC/$h"
  # The standalone driver has no LLVMFuzzerMutate; the custom mutator is only
  # referenced by libFuzzer, so stub it out for the reproducer.
  "$CXX" "${HFLAGS[@]}" "$B/$h.o" "$B/standalone_main.o" "$B/lsan_off.o" \
    "$SRC/mayhem/harnesses/no_mutate.cc" "${LIBS[@]}" -o "$SRC/$h-standalone"
done
