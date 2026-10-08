#!/bin/bash
# Builds the NuWro neutrino event generator (github.com/NuWro/nuwro) inside the
# active conda environment.
#
# NuWro uses Pythia 6 through ROOT's old TPythia6 interface, which current ROOT no
# longer includes. NuWro's own recommended replacement, ROOTEGPythia6
# (github.com/luketpickering/ROOTEGPythia6), provides both and is built first.
#
#   bash scripts/build_nuwro.sh            build (skips if already built)
#   bash scripts/build_nuwro.sh --rebuild  delete and rebuild
#
# Environment variables:
#   NUWRO_VERSION   git tag (default nuwro_25.11)
#   JOBS            parallel compile jobs (default: number of cores)

set -eo pipefail

NUWRO_VERSION="${NUWRO_VERSION:-nuwro_25.11}"
JOBS="${JOBS:-$(nproc)}"
REBUILD=0
[ "${1:-}" = "--rebuild" ] && REBUILD=1

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

P="$CONDA_PREFIX"
EGP="$P/opt/rootegpythia6"     # Pythia 6 + TPythia6 for current ROOT
DIR="$P/opt/nuwro"
STAMP="$DIR/.built-$NUWRO_VERSION"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "NuWro $NUWRO_VERSION already built in $DIR (use --rebuild to redo it)."
    exit 0
fi

CC="${CC:-$P/bin/x86_64-conda-linux-gnu-gcc}"
CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
FC="${FC:-$P/bin/x86_64-conda-linux-gnu-gfortran}"
for tool in root-config cmake "$CC" "$CXX" "$FC"; do
    command -v "$tool" >/dev/null || { echo "Missing $tool. Run 'bash install.sh' to update the environment."; exit 1; }
done

step() { printf '\n--- NuWro: %s ---\n' "$*"; }

# --- 1. ROOTEGPythia6 ---------------------------------------------------------
step "building Pythia 6 and its ROOT interface (ROOTEGPythia6)"
rm -rf "$EGP" "$EGP-src"
git clone --depth 1 https://github.com/luketpickering/ROOTEGPythia6.git "$EGP-src"
echo "ROOTEGPythia6 commit $(git -C "$EGP-src" rev-parse --short HEAD)"

# -march=native would tie the library to the CPU it was built on; drop it.
sed -i 's/ *-march=native//' "$EGP-src/CMakeLists.txt"

# Pythia 6's C helper relies on old C rules: shared COMMON-block symbols (-fcommon,
# the GCC default before version 10) and pre-C23 function declarations (gnu17).
cmake -S "$EGP-src" -B "$EGP-src/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$EGP" \
    -DCMAKE_PREFIX_PATH="$P" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_Fortran_COMPILER="$FC" \
    -DCMAKE_C_FLAGS="-fcommon -std=gnu17" \
    -DCMAKE_Fortran_FLAGS="-std=legacy" \
    -DCMAKE_INSTALL_RPATH="$P/lib;$EGP/lib" \
    -DROOTEGPythia6_Pythia6_BUILTIN=ON
cmake --build "$EGP-src/build" --target install -j "$JOBS"
[ -f "$EGP/lib/libEGPythia6.so" ] || { echo "ERROR: libEGPythia6.so was not installed."; exit 1; }
rm -rf "$EGP-src"

# --- 2. NuWro -----------------------------------------------------------------
step "downloading NuWro $NUWRO_VERSION"
rm -rf "$DIR"
git -c advice.detachedHead=false clone --depth 1 --branch "$NUWRO_VERSION" \
    https://github.com/NuWro/nuwro.git "$DIR"
cd "$DIR"

export ROOTSYS="$P"
export ROOTEGPythia6_ROOT="$EGP"

# Some NuWro sources use TMath:: without including TMath.h. Older ROOT versions
# pulled it in through other headers; current ROOT does not. Add the include.
grep -rlE 'TMath::' src --include='*.cc' --include='*.cxx' --include='*.h' | while read -r f; do
    grep -qE '#include *[<"]TMath.h[>"]' "$f" || sed -i '1i #include "TMath.h"' "$f"
done

# NuWro's Makefile hard-codes g++/gfortran and its link flags. Use the
# environment's compilers and add RPATHs so the programs find ROOT and Pythia 6
# at run time without extra environment variables.
MAKE_VARS=(
    CXX="$CXX" CC="$CXX" LD="$CXX" FC="$FC"
    LDFLAGS="$(root-config --libs) -L$EGP/lib -Wl,-rpath,$EGP/lib -Wl,-rpath-link,$EGP/lib -Wl,-rpath,$P/lib -L$P/lib -lEGPythia6 -lPythia6 -lGeom -lMinuit -lgfortran"
)

step "compiling with $JOBS jobs"
make "${MAKE_VARS[@]}" -j"$JOBS" || make "${MAKE_VARS[@]}" -j1

[ -x "$DIR/bin/nuwro" ] || { echo "ERROR: bin/nuwro was not built. Check the output above."; exit 1; }

# Activation hooks: NUWRO and NuWro's programs on the PATH after 'conda activate hep'.
mkdir -p "$P/etc/conda/activate.d" "$P/etc/conda/deactivate.d"
cat > "$P/etc/conda/activate.d/nuwro.sh" <<'EOF'
export NUWRO="$CONDA_PREFIX/opt/nuwro"
export ROOTEGPythia6_ROOT="$CONDA_PREFIX/opt/rootegpythia6"
export PATH="$NUWRO/bin:$PATH"
EOF
cat > "$P/etc/conda/deactivate.d/nuwro.sh" <<'EOF'
if [ -n "${NUWRO:-}" ]; then
    PATH=":$PATH:"; PATH="${PATH//:$NUWRO\/bin:/:}"; PATH="${PATH#:}"; export PATH="${PATH%:}"
fi
unset NUWRO ROOTEGPythia6_ROOT
EOF

touch "$STAMP"
echo "NuWro $NUWRO_VERSION built in $DIR"
