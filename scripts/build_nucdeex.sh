#!/bin/bash
# Builds NucDeEx (nuclear de-excitation event generator for neutrino interactions
# and nucleon decays, github.com/SeishoAbe/NucDeEx) inside the active conda
# environment. It needs only ROOT; the TALYS branching ratios are pre-tabulated
# in the repository.
#
# If NuWro is installed (bash install.sh --with nuwro), NucDeEx's NuWro interface
# is built too. Its GENIE interface (bin/genie) reads GENIE output files and is
# always built.
#
#   bash scripts/build_nucdeex.sh            build (skips if already built)
#   bash scripts/build_nucdeex.sh --rebuild  delete and rebuild
#
# Environment variables:
#   NUCDEEX_VERSION   git tag (default v2.2.6)
#   JOBS              parallel compile jobs (default: number of cores)

set -eo pipefail

NUCDEEX_VERSION="${NUCDEEX_VERSION:-v2.2.6}"
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
DIR="$P/opt/nucdeex"
NUWRO_DIR="$P/opt/nuwro"
WITH_NUWRO=0
[ -f "$NUWRO_DIR/bin/event1.so" ] && WITH_NUWRO=1
STAMP="$DIR/.built-$NUCDEEX_VERSION-nuwro$WITH_NUWRO"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "NucDeEx $NUCDEEX_VERSION already built in $DIR (use --rebuild to redo it)."
    exit 0
fi

CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
command -v root-config >/dev/null || { echo "ROOT is missing from the environment."; exit 1; }

rm -rf "$DIR"
mkdir -p "$P/opt"
git -c advice.detachedHead=false clone --depth 1 --branch "$NUCDEEX_VERSION" \
    https://github.com/SeishoAbe/NucDeEx.git "$DIR"
cd "$DIR"
mkdir -p obj bin lib

export ROOTSYS="$P"
export NUCDEEX_ROOT="$DIR"
# NucDeEx's Makefile appends ROOT's flags to LDFLAGS, so set the RPATH here.
export LDFLAGS="-L$P/lib -Wl,-rpath,$P/lib"
if [ "$WITH_NUWRO" = 1 ]; then
    export NUWRO="$NUWRO_DIR"
    export LDFLAGS="$LDFLAGS -Wl,-rpath,$NUWRO_DIR/bin"
    echo "NuWro found: building the NuWro interface too."
else
    unset NUWRO
fi

echo "Compiling NucDeEx with $JOBS jobs..."
make CXX="$CXX" -j"$JOBS" || make CXX="$CXX" -j1

[ -x "$DIR/bin/simulation" ] || { echo "ERROR: bin/simulation was not built."; exit 1; }

write_env_hooks nucdeex NUCDEEX_ROOT lib include
# Also put NucDeEx's programs on the PATH.
# The $ signs are written literally into the hook file, so single quotes are intended.
# shellcheck disable=SC2016
echo 'export PATH="$NUCDEEX_ROOT/bin:$PATH"' >> "$P/etc/conda/activate.d/nucdeex.sh"
# shellcheck disable=SC2016
sed -i '1i if [ -n "${NUCDEEX_ROOT:-}" ]; then PATH=":$PATH:"; PATH="${PATH//:$NUCDEEX_ROOT\\/bin:/:}"; PATH="${PATH#:}"; export PATH="${PATH%:}"; fi' \
    "$P/etc/conda/deactivate.d/nucdeex.sh"

touch "$STAMP"
echo "NucDeEx $NUCDEEX_VERSION built in $DIR"
