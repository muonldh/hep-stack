#!/bin/bash
# Builds Garfield++ (CERN toolkit for simulating gaseous and semiconductor detectors:
# ionisation with Heed, electron transport with Magboltz, signal induction;
# gitlab.cern.ch/garfield/garfieldpp) inside the active conda environment.
#
# Its dependencies (ROOT, GSL, CMake, C++ and Fortran compilers) all come from
# environment.yml. Garfield++ has no regular releases; the developers recommend
# the master branch, so that is the default. The commit that was built is printed
# and stored in $CONDA_PREFIX/opt/garfield/.built.
#
#   bash scripts/build_garfield.sh            build (skips if already built)
#   bash scripts/build_garfield.sh --rebuild  delete and rebuild
#
# Environment variables:
#   GARFIELD_VERSION  git branch, tag or commit (default: master)
#   JOBS              parallel compile jobs (default: number of cores)

set -eo pipefail

GARFIELD_VERSION="${GARFIELD_VERSION:-master}"
JOBS="${JOBS:-$(nproc)}"
REBUILD=0
[ "${1:-}" = "--rebuild" ] && REBUILD=1

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

P="$CONDA_PREFIX"
DIR="$P/opt/garfield"          # installed Garfield++ (GARFIELD_INSTALL)
SRC="$P/opt/garfield-src"      # source (also holds the Examples folder)
STAMP="$DIR/.built"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "Garfield++ already built in $DIR ($(cat "$STAMP")). Use --rebuild to redo it."
    exit 0
fi

CC="${CC:-$P/bin/x86_64-conda-linux-gnu-gcc}"
CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
FC="${FC:-$P/bin/x86_64-conda-linux-gnu-gfortran}"
for tool in root-config gsl-config cmake git "$CC" "$CXX" "$FC"; do
    command -v "$tool" >/dev/null || { echo "Missing $tool. Run 'bash install.sh' to update the environment."; exit 1; }
done

step() { printf '\n--- Garfield++: %s ---\n' "$*"; }

rm -rf "$DIR" "$SRC"
mkdir -p "$P/opt"

step "downloading source ($GARFIELD_VERSION)"
ok=0
for attempt in 1 2 3; do
    rm -rf "$SRC"
    if git clone https://gitlab.cern.ch/garfield/garfieldpp.git "$SRC"; then ok=1; break; fi
    echo "Download attempt $attempt failed; retrying in 30 s..."
    sleep 30
done
[ "$ok" = 1 ] || { echo "ERROR: could not download Garfield++ from gitlab.cern.ch."; exit 1; }
git -C "$SRC" -c advice.detachedHead=false checkout "$GARFIELD_VERSION"
COMMIT="$(git -C "$SRC" rev-parse --short HEAD)"
echo "Building Garfield++ commit $COMMIT"

# Magboltz and Degrade are Fortran 77; current gfortran rejects some of their
# old constructs unless told to accept them. The C flags match the other builds.
step "configuring"
cmake -S "$SRC" -B "$SRC/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DIR" \
    -DCMAKE_PREFIX_PATH="$P" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_Fortran_COMPILER="$FC" \
    -DCMAKE_C_FLAGS="-std=gnu17" \
    -DCMAKE_Fortran_FLAGS="-std=legacy -fallow-argument-mismatch" \
    -DCMAKE_INSTALL_RPATH="$P/lib;$DIR/lib" \
    -DWITH_EXAMPLES=OFF

step "compiling with $JOBS jobs"
cmake --build "$SRC/build" -j "$JOBS"
cmake --install "$SRC/build"
rm -rf "$SRC/build"

SETUP="$DIR/share/Garfield/setupGarfield.sh"
[ -f "$SETUP" ] || { echo "ERROR: $SETUP was not installed."; exit 1; }
HEED_DB="$(find "$DIR/share" -type d -path '*Heed*' -name database | head -n 1)"
[ -n "$HEED_DB" ] || { echo "ERROR: the Heed database was not installed."; exit 1; }
LIBDIR="$(dirname "$(find "$DIR" -name 'libGarfield.so*' | head -n 1)")"
[ -d "$LIBDIR" ] || { echo "ERROR: libGarfield was not installed."; exit 1; }
# Folder holding the Python module ('import Garfield'), if this version installs one.
PYDIR=""
PYFILE="$(find "$DIR" -name 'Garfield.py' | head -n 1)"
PYPKG="$(find "$DIR" -path '*/Garfield/__init__.py' | head -n 1)"
if [ -n "$PYFILE" ]; then PYDIR="$(dirname "$PYFILE")"
elif [ -n "$PYPKG" ]; then PYDIR="$(dirname "$(dirname "$PYPKG")")"
fi

# Activation hooks: the same variables as Garfield's setupGarfield.sh, plus the
# library and include paths PyROOT needs to load Garfield.
mkdir -p "$P/etc/conda/activate.d" "$P/etc/conda/deactivate.d"
{
    echo "export GARFIELD_INSTALL=\"$DIR\""
    echo "export GARFIELD_HOME=\"$SRC\""
    echo "export HEED_DATABASE=\"$HEED_DB\""
    echo "export CMAKE_PREFIX_PATH=\"$DIR\${CMAKE_PREFIX_PATH:+:\$CMAKE_PREFIX_PATH}\""
    echo "export LD_LIBRARY_PATH=\"$LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
    echo "export ROOT_INCLUDE_PATH=\"$DIR/include\${ROOT_INCLUDE_PATH:+:\$ROOT_INCLUDE_PATH}\""
    if [ -n "$PYDIR" ] && [ -d "$PYDIR" ]; then
        echo "export PYTHONPATH=\"$PYDIR\${PYTHONPATH:+:\$PYTHONPATH}\""
    fi
} > "$P/etc/conda/activate.d/garfield.sh"
cat > "$P/etc/conda/deactivate.d/garfield.sh" <<EOF
_strip() { local v=":\$1:"; v="\${v//:\$2:/:}"; v="\${v#:}"; printf '%s' "\${v%:}"; }
export CMAKE_PREFIX_PATH="\$(_strip "\${CMAKE_PREFIX_PATH-}" "$DIR")"
export LD_LIBRARY_PATH="\$(_strip "\${LD_LIBRARY_PATH-}" "$LIBDIR")"
export ROOT_INCLUDE_PATH="\$(_strip "\${ROOT_INCLUDE_PATH-}" "$DIR/include")"
[ -n "$PYDIR" ] && export PYTHONPATH="\$(_strip "\${PYTHONPATH-}" "$PYDIR")"
unset -f _strip
unset GARFIELD_INSTALL GARFIELD_HOME HEED_DATABASE
EOF

# Quick test: load Garfield in ROOT and set up an Ar/CO2 gas.
step "testing"
# shellcheck disable=SC1091
source "$P/etc/conda/activate.d/garfield.sh"
python -c "
import ROOT
assert ROOT.gSystem.Load('libGarfield') >= 0, 'libGarfield did not load'
gas = ROOT.Garfield.MediumMagboltz('ar', 90., 'co2', 10.)
print('Garfield++ gas:', gas.GetName())"

echo "commit $COMMIT, built $(date +%F)" > "$STAMP"
echo "Garfield++ ($COMMIT) installed in $DIR. Examples are in $SRC/Examples."
