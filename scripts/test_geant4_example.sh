#!/bin/bash
# Builds and runs Geant4's basic example B1 against the installed Geant4.
# Confirms that you can compile your own Geant4 programs in this environment.
#
#   conda activate hep && bash scripts/test_geant4_example.sh

set -eo pipefail

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

VERSION="$(geant4-config --version)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "Downloading example B1 for Geant4 $VERSION..."
git -c advice.detachedHead=false clone -q --depth 1 --branch "v$VERSION" \
    --filter=blob:none --sparse https://github.com/Geant4/geant4.git g4src
git -C g4src sparse-checkout set examples/basic/B1

echo "Building..."
cmake -S g4src/examples/basic/B1 -B build >/dev/null
cmake --build build -j"$(nproc)" >/dev/null

echo "Running 10000 gammas and 10000 protons (batch mode, about a minute)..."
cd build
./exampleB1 exampleB1.in > b1.log 2>&1

if grep -q "Absorbed dose per run" b1.log; then
    grep -A3 "End of Global Run" b1.log | grep "The run is" || true
    grep "Absorbed dose per run" b1.log | tail -n 1
    echo "Geant4 example B1: OK"
else
    tail -n 30 b1.log
    echo "Geant4 example B1: FAILED"
    exit 1
fi
