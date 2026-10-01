#!/bin/bash
# Builds OscProb (github.com/joaoabcoelho/OscProb) inside the active conda
# environment, against the environment's ROOT and Eigen.
#
#   bash scripts/build_oscprob.sh            build (skips if already built)
#   bash scripts/build_oscprob.sh --rebuild  delete and rebuild
#
# Environment variables:
#   OSCPROB_VERSION   git tag to build (default v2.4.0)
#   JOBS              parallel compile jobs (default: number of cores)

set -eo pipefail

OSCPROB_VERSION="${OSCPROB_VERSION:-v2.4.0}"
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
DIR="$P/opt/oscprob"          # installed library, headers, PREM tables, tutorials
SRC="$P/opt/oscprob-src"      # source and build tree
STAMP="$DIR/.built-$OSCPROB_VERSION"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "OscProb $OSCPROB_VERSION already built in $DIR (use --rebuild to redo it)."
    exit 0
fi

command -v cmake >/dev/null || { echo "cmake missing in the environment."; exit 1; }

rm -rf "$DIR" "$SRC"
mkdir -p "$P/opt"
git -c advice.detachedHead=false clone --depth 1 --branch "$OSCPROB_VERSION" \
    https://github.com/joaoabcoelho/OscProb.git "$SRC"

# ROOT >= 6.40 rejects the empty MatrixDecomp dictionary in OscProb v2.4.0.
# Apply upstream's fix (OscProb commit f0830e9, "Remove unnecessary LinkDef which
# breaks in ROOT 6.40.02"); it does nothing for later releases that already include it.
sed -i '/add_root_dictionary(MatrixDecomp/d' "$SRC/MatrixDecomp/CMakeLists.txt"

# Eigen comes from the conda environment, so the eigen git submodule is not needed.
   
cmake -S "$SRC" -B "$SRC/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DIR" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_PREFIX_PATH="$P" \
    -DOSCPROB_ENABLE_TESTING=OFF

cmake --build "$SRC/build" --target install -j "$JOBS"

if [ ! -f "$DIR/lib/libOscProb.so" ]; then
    echo "ERROR: libOscProb.so was not installed."
    exit 1
fi

write_env_hooks oscprob OSCPROB_DIR lib include

# Quick check through the PREM Earth model: probabilities must be unitary.
LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
ROOT_INCLUDE_PATH="$DIR/include${ROOT_INCLUDE_PATH:+:$ROOT_INCLUDE_PATH}" \
python - <<'EOF'
import ROOT
assert ROOT.gSystem.Load("libOscProb") >= 0, "could not load libOscProb"
p = ROOT.OscProb.PMNS_Fast()
prem = ROOT.OscProb.PremModel()
prem.FillPath(-1.0)
p.SetPath(prem.GetNuPath())
s = sum(p.Prob(1, j, 5.0) for j in (0, 1, 2))
assert abs(s - 1) < 1e-6, f"unitarity check failed: {s}"
print(f"OscProb check passed (sum of P(numu -> x) = {s:.6f})")
EOF

touch "$STAMP"
echo "OscProb $OSCPROB_VERSION built in $DIR"
