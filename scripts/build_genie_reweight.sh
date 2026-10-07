#!/bin/bash
# Builds GENIE ReWeight (github.com/GENIE-MC/Reweight), the GENIE collaboration's
# companion package for event reweighting, against the GENIE built by build_genie.sh.
# gSeaGen requires it ($GENIE_REWEIGHT).
#
#   bash scripts/build_genie_reweight.sh            build (skips if already built)
#   bash scripts/build_genie_reweight.sh --rebuild  delete and rebuild
#
# Environment variables:
#   GENIE_REWEIGHT_VERSION  git tag (default R-1_04_02, the release for GENIE 3.06)
#   JOBS                    parallel compile jobs (default: number of cores)

set -eo pipefail

GENIE_REWEIGHT_VERSION="${GENIE_REWEIGHT_VERSION:-R-1_04_02}"
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
DIR="$P/opt/genie-reweight"
export GENIE="$P/opt/genie"
export GENIE_REWEIGHT="$DIR"

# Rebuild whenever GENIE was rebuilt after ReWeight (e.g. when APFEL was added).
STAMP="$DIR/.built-$GENIE_REWEIGHT_VERSION"
if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ] && [ "$STAMP" -nt "$GENIE/bin/gevgen" ]; then
    echo "GENIE ReWeight $GENIE_REWEIGHT_VERSION already built in $DIR (use --rebuild to redo it)."
    exit 0
fi

[ -x "$GENIE/bin/gevgen" ] || { echo "GENIE is not built. Run: bash scripts/build_genie.sh"; exit 1; }

CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
CC="${CC:-$P/bin/x86_64-conda-linux-gnu-gcc}"

rm -rf "$DIR"
mkdir -p "$P/opt"
git -c advice.detachedHead=false clone --depth 1 --branch "$GENIE_REWEIGHT_VERSION" \
    https://github.com/GENIE-MC/Reweight.git "$DIR"
cd "$DIR"

# ReWeight reuses GENIE's make system, so the same compiler and RPATH overrides apply.
RPATH="-Wl,--disable-new-dtags -Wl,-rpath,$P/lib -Wl,-rpath,$GENIE/lib -Wl,-rpath,$DIR/lib -L$P/lib"
[ -d "$P/opt/apfel/lib" ] && RPATH="$RPATH -Wl,-rpath,$P/opt/apfel/lib"
MAKE_VARS=(
    CXX="$CXX"
    CC="$CC"
    LD="$CXX"
    LDFLAGS="-g -Wl,--no-as-needed -Wl,--no-undefined $RPATH"
    SOFLAGS="-shared $RPATH"
)

mkdir -p "$DIR/bin" "$DIR/lib"
echo "Compiling GENIE ReWeight with $JOBS jobs..."
make "${MAKE_VARS[@]}" -j"$JOBS" \
  || make "${MAKE_VARS[@]}" -j"$JOBS" \
  || make "${MAKE_VARS[@]}" -j1

compgen -G "$DIR/lib/libGRwFwk*" >/dev/null || { echo "ERROR: ReWeight libraries were not built."; exit 1; }

write_env_hooks genie-reweight GENIE_REWEIGHT lib

touch "$STAMP"
echo "GENIE ReWeight $GENIE_REWEIGHT_VERSION built in $DIR"
