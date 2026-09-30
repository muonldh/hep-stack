#!/bin/bash
# Builds the GENIE neutrino event generator inside the active conda environment.
# GENIE is not packaged on conda-forge, so it is compiled against the environment's
# ROOT, Pythia 8, LHAPDF 6, libxml2, log4cpp and GSL, using the environment's compilers.
#
#   bash scripts/build_genie.sh            build (skips if already built)
#   bash scripts/build_genie.sh --rebuild  delete and rebuild
#
# Environment variables:
#   GENIE_VERSION      git tag to build (default R-3_06_02)
#   GENIE_EXTRA_FLAGS  extra ./configure flags, e.g. "--enable-geant4"
#   JOBS               parallel compile jobs (default: number of cores)

set -eo pipefail

GENIE_VERSION="${GENIE_VERSION:-R-3_06_02}"
JOBS="${JOBS:-$(nproc)}"
REBUILD=0
[ "${1:-}" = "--rebuild" ] && REBUILD=1

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

P="$CONDA_PREFIX"
GENIE_DIR="$P/opt/genie"
STAMP="$GENIE_DIR/.built-$GENIE_VERSION"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "GENIE $GENIE_VERSION already built in $GENIE_DIR (use --rebuild to redo it)."
    exit 0
fi

for tool in root-config gsl-config lhapdf-config "$CXX"; do
    command -v "$tool" >/dev/null || { echo "Missing $tool in the environment."; exit 1; }
done

rm -rf "$GENIE_DIR"
mkdir -p "$P/opt"
git clone --depth 1 --branch "$GENIE_VERSION" \
    https://github.com/GENIE-MC/Generator.git "$GENIE_DIR"
cd "$GENIE_DIR"

# GENIE is used in place (no 'make install'): $GENIE points at this directory.
export GENIE="$GENIE_DIR"

# shellcheck disable=SC2086
./configure \
    --disable-pythia6 \
    --enable-pythia8 \
    --with-pythia8-inc="$P/include" \
    --with-pythia8-lib="$P/lib" \
    --disable-lhapdf5 \
    --enable-lhapdf6 \
    --with-lhapdf6-inc="$P/include" \
    --with-lhapdf6-lib="$P/lib" \
    --with-libxml2-inc="$P/include/libxml2" \
    --with-libxml2-lib="$P/lib" \
    --with-log4cpp-inc="$P/include" \
    --with-log4cpp-lib="$P/lib" \
    --enable-flux-drivers \
    --enable-geom-drivers \
    --enable-atmo \
    --enable-nucleon-decay \
    --enable-nnbar-oscillation \
    --enable-boosted-dark-matter \
    --enable-heavy-neutral-lepton \
    --enable-dark-neutrino \
    ${GENIE_EXTRA_FLAGS:-}

# GENIE's makefiles hard-code g++ and their own link flags. Override them on the
# command line so the conda compilers are used and every library and program gets
# an RPATH to the environment. Without the RPATH, GENIE could pick up the system's
# copies of libraries like libxml2 at run time instead of the environment's.
RPATH="-Wl,--disable-new-dtags -Wl,-rpath,$P/lib -Wl,-rpath,$GENIE_DIR/lib -L$P/lib"
MAKE_VARS=(
    CXX="$CXX"
    CC="$CC"
    LD="$CXX"
    LDFLAGS="-g -Wl,--no-as-needed -Wl,--no-undefined $RPATH"
    SOFLAGS="-shared $RPATH"
)

mkdir -p "$GENIE_DIR/bin" "$GENIE_DIR/lib"

# GENIE's parallel build has a known race condition: retry, then fall back to serial.
echo "Compiling GENIE with $JOBS jobs..."
make "${MAKE_VARS[@]}" -j"$JOBS" \
  || make "${MAKE_VARS[@]}" -j"$JOBS" \
  || make "${MAKE_VARS[@]}" -j1

if [ ! -x "$GENIE_DIR/bin/gevgen" ]; then
    echo "ERROR: gevgen was not built. Check the output above."
    exit 1
fi

# Pythia 6 is not available on conda-forge, so point the physics configuration at
# the Pythia 8 implementations. Only algorithm choices (<param type="alg">) are
# changed; the algorithm registry in master_config.xml and the message stream
# names are left alone, since both Pythia 6 and Pythia 8 entries already exist there.
find "$GENIE_DIR/config" -name '*.xml' -print0 | xargs -0 \
    sed -i -E '/<param[^>]*type="alg"/ s/(genie::[A-Za-z0-9]*)Pythia6/\1Pythia8/g'

# Conda activation hooks: set GENIE's variables on 'conda activate hep' and
# remove them again on 'conda deactivate'.
mkdir -p "$P/etc/conda/activate.d" "$P/etc/conda/deactivate.d"

cat > "$P/etc/conda/activate.d/genie.sh" <<'EOF'
export GENIE="$CONDA_PREFIX/opt/genie"
export _GENIE_OLD_LD_LIBRARY_PATH="${LD_LIBRARY_PATH-__unset__}"
export PATH="$GENIE/bin:$PATH"
export LD_LIBRARY_PATH="$GENIE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
EOF

cat > "$P/etc/conda/deactivate.d/genie.sh" <<'EOF'
if [ -n "${GENIE:-}" ]; then
    PATH=":$PATH:"; PATH="${PATH//:$GENIE\/bin:/:}"; PATH="${PATH#:}"; export PATH="${PATH%:}"
fi
if [ "${_GENIE_OLD_LD_LIBRARY_PATH-}" = "__unset__" ]; then
    unset LD_LIBRARY_PATH
else
    export LD_LIBRARY_PATH="$_GENIE_OLD_LD_LIBRARY_PATH"
fi
unset GENIE _GENIE_OLD_LD_LIBRARY_PATH
EOF

touch "$STAMP"
echo "GENIE $GENIE_VERSION built in $GENIE_DIR"
