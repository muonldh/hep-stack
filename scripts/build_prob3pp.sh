#!/bin/bash
# Builds Prob3++ (Super-Kamiokande's three-flavour oscillation code,
# github.com/rogerwendell/Prob3plusplus) inside the active conda environment.
#
#   bash scripts/build_prob3pp.sh            build (skips if already built)
#   bash scripts/build_prob3pp.sh --rebuild  delete and rebuild
#
# Environment variables:
#   PROB3PP_VERSION   git tag to build (default v3r20)

set -eo pipefail

PROB3PP_VERSION="${PROB3PP_VERSION:-v3r20}"
REBUILD=0
[ "${1:-}" = "--rebuild" ] && REBUILD=1

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

# shellcheck source=scripts/env_hooks.sh
source "$(dirname "${BASH_SOURCE[0]}")/env_hooks.sh"

P="$CONDA_PREFIX"
DIR="$P/opt/prob3pp"
STAMP="$DIR/.built-$PROB3PP_VERSION"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "Prob3++ $PROB3PP_VERSION already built in $DIR (use --rebuild to redo it)."
    exit 0
fi

CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
CC="${CC:-$P/bin/x86_64-conda-linux-gnu-gcc}"

rm -rf "$DIR"
mkdir -p "$P/opt"
git -c advice.detachedHead=false clone --depth 1 --branch "$PROB3PP_VERSION" \
    https://github.com/rogerwendell/Prob3plusplus.git "$DIR"
cd "$DIR"

# 'make shared' builds libThreeProb_<version>.so plus a libThreeProb.so link,
# including the ctypes wrapper used by BargerPropagator.py.
make CC="$CC" CXX="$CXX" shared

if [ ! -e "$DIR/libThreeProb.so" ]; then
    echo "ERROR: libThreeProb.so was not built."
    exit 1
fi

# Library and headers are used in place: $PROB3PP points at this directory.
write_env_hooks prob3pp PROB3PP . .
add_python_path prob3pp "$DIR"

# Quick check: probabilities through the Earth must be unitary.
LD_LIBRARY_PATH="$DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" python - <<'EOF'
from BargerPropagator import BargerPropagator
b = BargerPropagator()
b.SetWarningSuppression(True)
b.SetMNS(0.307, 0.0222, 0.561, 7.49e-5, 2.534e-3, 0.0, 5.0, True, 1)
b.DefinePath(-1.0, 15.0, True)
b.propagate(1)
s = sum(b.GetProb(2, j) for j in (1, 2, 3))
assert abs(s - 1) < 1e-6, f"unitarity check failed: {s}"
print(f"Prob3++ check passed (sum of P(numu -> x) = {s:.6f})")
EOF

touch "$STAMP"
echo "Prob3++ $PROB3PP_VERSION built in $DIR"
