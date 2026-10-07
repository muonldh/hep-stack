#!/bin/bash
# Builds APFEL (PDF evolution and structure functions, github.com/scarrazza/apfel)
# inside the active conda environment, linked to the environment's LHAPDF.
#
# GENIE needs APFEL for its high-energy DIS model (HEDIS), which the ultra-high-energy
# tune GHE19_00b uses: the NLO structure-function tables are computed with APFEL the
# first time they are needed. build_genie.sh enables APFEL automatically when it is
# installed, and also downloads the PDF set that tune uses (HERAPDF15NLO_EIG).
#
#   bash scripts/build_apfel.sh            build (skips if already built)
#   bash scripts/build_apfel.sh --rebuild  delete and rebuild
#
# Environment variables:
#   APFEL_VERSION   git tag to build (default 3.1.1)
#   JOBS            parallel compile jobs (default: number of cores)

set -eo pipefail

APFEL_VERSION="${APFEL_VERSION:-3.1.1}"
JOBS="${JOBS:-$(nproc)}"
REBUILD=0
[ "${1:-}" = "--rebuild" ] && REBUILD=1

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

# shellcheck source=scripts/env_hooks.sh
source "$(dirname "${BASH_SOURCE[0]}")/env_hooks.sh"

P="$CONDA_PREFIX"
DIR="$P/opt/apfel"
SRC="$P/opt/apfel-src"
STAMP="$DIR/.built-$APFEL_VERSION"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "APFEL $APFEL_VERSION already built in $DIR (use --rebuild to redo it)."
    exit 0
fi

export CC="${CC:-$P/bin/x86_64-conda-linux-gnu-gcc}"
export CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
export FC="${FC:-$P/bin/x86_64-conda-linux-gnu-gfortran}"
for tool in cmake lhapdf-config "$CC" "$CXX" "$FC"; do
    command -v "$tool" >/dev/null || { echo "Missing $tool. Run 'bash install.sh' to update the environment."; exit 1; }
done

rm -rf "$DIR" "$SRC"
mkdir -p "$P/opt"
git -c advice.detachedHead=false clone --depth 1 --branch "$APFEL_VERSION" \
    https://github.com/scarrazza/apfel.git "$SRC"

cmake -S "$SRC" -B "$SRC/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DIR" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_RPATH="$P/lib;$DIR/lib" \
    -DAPFEL_ENABLE_LHAPDF=ON \
    -DAPFEL_ENABLE_PYTHON=OFF \
    -DAPFEL_ENABLE_TESTS=OFF \
    -DAPFEL_DOWNLOAD_PDFS=OFF

cmake --build "$SRC/build" --target install -j "$JOBS"

[ -f "$DIR/lib/libAPFEL.so" ] || { echo "ERROR: libAPFEL.so was not installed."; exit 1; }
[ -f "$DIR/include/APFEL/APFEL.h" ] || { echo "ERROR: APFEL headers were not installed."; exit 1; }

write_env_hooks apfel APFEL_DIR lib

rm -rf "$SRC"
touch "$STAMP"
echo "APFEL $APFEL_VERSION built in $DIR"
