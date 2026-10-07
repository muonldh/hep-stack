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

set -eo pipefail

GSEAGEN_VERSION="${GSEAGEN_VERSION:-}"
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
export GENIE_REWEIGHT="$P/opt/genie-reweight"
export GSEAGEN="$DIR"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "gSeaGen already built in $DIR ($(cat "$STAMP")). Use --rebuild to redo it."
    exit 0
fi

[ -x "$GENIE/bin/gevgen" ] || { echo "GENIE is not built. Run: bash scripts/build_genie.sh"; exit 1; }
compgen -G "$GENIE_REWEIGHT/lib/libGRwFwk*" >/dev/null \
    || { echo "GENIE ReWeight is not built. Run: bash scripts/build_genie_reweight.sh"; exit 1; }
if ! ldd "$GENIE/bin/gevgen" 2>/dev/null | grep -q libAPFEL; then
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
# Boost (always required) comes from the conda environment.
# shellcheck disable=SC2086
./configure --with-boost-inc="$P/include" --with-boost-lib="$P/lib" ${GSEAGEN_CONFIGURE_FLAGS:-}

# Same compiler and RPATH overrides as for GENIE, whose make system gSeaGen shares.
RPATH="-Wl,--disable-new-dtags -Wl,-rpath,$P/lib -Wl,-rpath,$GENIE/lib -Wl,-rpath,$GENIE_REWEIGHT/lib -Wl,-rpath,$DIR/lib -L$P/lib"
[ -d "$P/opt/apfel/lib" ] && RPATH="$RPATH -Wl,-rpath,$P/opt/apfel/lib"
MAKE_VARS=(
    CXX="$CXX"
    CC="$CC"
    LD="$CXX"
    LDFLAGS="-g -Wl,--no-as-needed $RPATH"
    SOFLAGS="-shared $RPATH"
)

# Some gSeaGen makefiles (e.g. src/PropaMuon) hard-code -std=c++11, but current ROOT
# headers need at least C++17. Use the same standard ROOT was built with.
ROOT_STD="$(root-config --cflags | grep -o -- '-std=[^ ]*' | head -n 1)"
ROOT_STD="${ROOT_STD:--std=c++17}"
find "$DIR/src" -name 'Makefile*' -print0 | xargs -0 \
    sed -i -E "s/-std=(c|gnu)\+\+(0x|11|14)\b/$ROOT_STD/g"
echo "Using $ROOT_STD for all gSeaGen packages"

# Some gSeaGen files use standard functions without including the header that
# declares them: fabs/sqrt/sin/... need <cmath>, std::replace/std::sort/... need
# <algorithm>. Older compilers pulled these in through other headers; GCC 15 and
# ROOT's dictionary generator (which reads each header on its own) do not.
# Add the missing include to each such header and source file. Files that
# already include it are left unchanged, and no code is modified.
MATHFN='\b(fabs|fmod|sqrt|pow|exp|log|log10|sin|cos|tan|asin|acos|atan|atan2|floor|ceil)[[:space:]]*\('
ALGOFN='std::(replace|replace_if|sort|stable_sort|find|find_if|count|count_if|remove|remove_if|reverse|unique|min_element|max_element|transform|fill|copy_if|any_of|all_of|none_of)[[:space:]]*\('
find "$DIR/src" \( -name '*.h' -o -name '*.hh' -o -name '*.cxx' -o -name '*.cc' -o -name '*.cpp' \) -print0 |
while IFS= read -r -d '' f; do
    if grep -qE "$MATHFN" "$f" && ! grep -qE '#include[[:space:]]*[<"](cmath|math\.h|TMath\.h)[>"]' "$f"; then
        sed -i '1i #include <cmath>' "$f"
        echo "Added #include <cmath> to ${f#"$DIR"/}"
    fi
    if grep -qE "$ALGOFN" "$f" && ! grep -qE '#include[[:space:]]*<algorithm>' "$f"; then
        sed -i '1i #include <algorithm>' "$f"
        echo "Added #include <algorithm> to ${f#"$DIR"/}"
    fi
done

# gSeaGen's makefiles create shared folders without 'mkdir -p', which collides when
# packages are built in parallel ("cannot create directory 'lib': File exists").
# The code base is small, so build it serially.
step "compiling"
make "${MAKE_VARS[@]}" -j1

# gSeaGen builds e.g. bin/gSeaNuEvGenv7.6.1-D and links bin/gSeaNuEvGen to it,
# so accept a symbolic link as long as it points to a working program.
EXE="$(find "$DIR" \( -type f -o -type l \) -name gSeaNuEvGen | head -n 1)"
[ -n "$EXE" ] && [ ! -x "$EXE" ] && EXE=""
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
