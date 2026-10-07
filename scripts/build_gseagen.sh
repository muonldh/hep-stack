#!/bin/bash
# Builds gSeaGen (KM3NeT's GENIE-based event generator for neutrino telescopes,
# git.km3net.de/opensource/gseagen) inside the active conda environment.
#
# gSeaGen is a GENIE application: it links the GENIE built by build_genie.sh and
# uses GENIE for every neutrino interaction. For ultra-high-energy (astrophysical)
# neutrinos it relies on GENIE's HEDIS model, so install.sh builds APFEL and
# rebuilds GENIE with it before running this script (bash install.sh --with gseagen).
#
#   bash scripts/build_gseagen.sh            build (skips if already built)
#   bash scripts/build_gseagen.sh --rebuild  delete and rebuild
#
# Environment variables:
#   GSEAGEN_VERSION          git tag or branch (default: the repository's default branch)
#   GSEAGEN_CONFIGURE_FLAGS  extra ./configure options
#   JOBS                     parallel compile jobs (default: number of cores)

set -eo pipefail

GSEAGEN_VERSION="${GSEAGEN_VERSION:-}"
JOBS="${JOBS:-$(nproc)}"
REBUILD=0
[ "${1:-}" = "--rebuild" ] && REBUILD=1

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

P="$CONDA_PREFIX"
DIR="$P/opt/gseagen"
STAMP="$DIR/.built"
export GENIE="$P/opt/genie"
export GSEAGEN="$DIR"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "gSeaGen already built in $DIR ($(cat "$STAMP")). Use --rebuild to redo it."
    exit 0
fi

[ -x "$GENIE/bin/gevgen" ] || { echo "GENIE is not built. Run: bash scripts/build_genie.sh"; exit 1; }
if ! ldd "$GENIE"/lib/*.so 2>/dev/null | grep -q libAPFEL; then
    echo "Note: GENIE is built without APFEL, so the ultra-high-energy tune GHE19_00b"
    echo "      will not work. Use 'bash install.sh --with gseagen' to set this up."
fi

CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
CC="${CC:-$P/bin/x86_64-conda-linux-gnu-gcc}"

step() { printf '\n--- gSeaGen: %s ---\n' "$*"; }

rm -rf "$DIR"
mkdir -p "$P/opt"

step "downloading"
BRANCH_ARGS=()
[ -n "$GSEAGEN_VERSION" ] && BRANCH_ARGS=(--branch "$GSEAGEN_VERSION")
git -c advice.detachedHead=false clone --depth 1 "${BRANCH_ARGS[@]}" \
    https://git.km3net.de/opensource/gseagen.git "$DIR"
cd "$DIR"
COMMIT="$(git rev-parse --short HEAD)"
echo "Building commit $COMMIT (${GSEAGEN_VERSION:-default branch})"
echo "Most recent release tags:"
git ls-remote --tags --refs https://git.km3net.de/opensource/gseagen.git \
    | awk -F/ '{print "  " $3}' | sort -V | tail -n 5 || true
ls

step "configure options"
./configure --help 2>&1 | head -n 60 || true

step "configuring"
# shellcheck disable=SC2086
./configure ${GSEAGEN_CONFIGURE_FLAGS:-}

# Same compiler and RPATH overrides as for GENIE, whose make system gSeaGen shares.
RPATH="-Wl,--disable-new-dtags -Wl,-rpath,$P/lib -Wl,-rpath,$GENIE/lib -Wl,-rpath,$DIR/lib -L$P/lib"
[ -d "$P/opt/apfel/lib" ] && RPATH="$RPATH -Wl,-rpath,$P/opt/apfel/lib"
MAKE_VARS=(
    CXX="$CXX"
    CC="$CC"
    LD="$CXX"
    LDFLAGS="-g -Wl,--no-as-needed $RPATH"
    SOFLAGS="-shared $RPATH"
)

step "compiling with $JOBS jobs"
make "${MAKE_VARS[@]}" -j"$JOBS" || make "${MAKE_VARS[@]}" -j1

EXE="$(find "$DIR" -type f -name gSeaNuEvGen -perm -u+x | head -n 1)"
if [ -z "$EXE" ]; then
    echo "ERROR: gSeaNuEvGen was not built. Check the output above."
    exit 1
fi
BINDIR="$(dirname "$EXE")"
REL="${BINDIR#"$DIR"}"          # e.g. "/bin", or "" if the program sits at the top level
echo "gSeaNuEvGen built in $BINDIR"

# Activation hooks: GSEAGEN and gSeaNuEvGen on the PATH after 'conda activate hep'.
mkdir -p "$P/etc/conda/activate.d" "$P/etc/conda/deactivate.d"
cat > "$P/etc/conda/activate.d/gseagen.sh" <<EOF
export GSEAGEN="\$CONDA_PREFIX/opt/gseagen"
export PATH="\$GSEAGEN$REL:\$PATH"
EOF
cat > "$P/etc/conda/deactivate.d/gseagen.sh" <<EOF
PATH=":\$PATH:"; PATH="\${PATH//:\$GSEAGEN${REL//\//\\/}:/:}"; PATH="\${PATH#:}"; export PATH="\${PATH%:}"
unset GSEAGEN
EOF

echo "commit $COMMIT, built $(date +%F)" > "$STAMP"
echo "gSeaGen ($COMMIT) built in $DIR"
