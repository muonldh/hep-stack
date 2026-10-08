#!/bin/bash
# Builds CRMC, the Cosmic Ray Monte Carlo package (R. Ulrich, T. Pierog, C. Baus;
# KIT), inside the active conda environment. CRMC gives one interface to the
# hadronic interaction models used in air-shower physics (EPOS-LHC, QGSJet,
# Sibyll, DPMJET, ...). The source is the release published on Zenodo
# (doi:10.5281/zenodo.5270381).
#
#   bash scripts/build_crmc.sh            build (skips if already built)
#   bash scripts/build_crmc.sh --rebuild  delete and rebuild
#
# Environment variables:
#   CRMC_VERSION   release on Zenodo (default 2.0.1)
#   CRMC_URL       download URL (default: the 2.0.1 archive on Zenodo)
#   JOBS           parallel compile jobs (default: number of cores)

set -eo pipefail

CRMC_VERSION="${CRMC_VERSION:-2.0.1}"
CRMC_URL="${CRMC_URL:-https://zenodo.org/records/5270381/files/crmc-v${CRMC_VERSION}.zip?download=1}"
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
DIR="$P/opt/crmc"
WORK="$P/opt/crmc-src"
STAMP="$DIR/.built-$CRMC_VERSION"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "CRMC $CRMC_VERSION already built in $DIR (use --rebuild to redo it)."
    exit 0
fi

CC="${CC:-$P/bin/x86_64-conda-linux-gnu-gcc}"
CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
FC="${FC:-$P/bin/x86_64-conda-linux-gnu-gfortran}"

rm -rf "$DIR" "$WORK"
mkdir -p "$WORK"

echo "Downloading CRMC $CRMC_VERSION (about 115 MB)..."
curl -fL --retry 3 -o "$WORK/crmc.zip" "$CRMC_URL"
python -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$WORK/crmc.zip" "$WORK"
rm "$WORK/crmc.zip"

SRC="$(dirname "$(find "$WORK" -maxdepth 3 -name CMakeLists.txt | sort | head -n 1)")"
[ -f "$SRC/CMakeLists.txt" ] || { echo "ERROR: no CMakeLists.txt found in the CRMC archive."; exit 1; }
echo "CRMC source: $SRC"

# The interaction models are decades-old Fortran and C. Current compilers are
# stricter by default; these flags restore the older rules without changing the code.
cmake -S "$SRC" -B "$WORK/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DIR" \
    -DCMAKE_PREFIX_PATH="$P" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_Fortran_COMPILER="$FC" \
    -DCMAKE_C_FLAGS="-std=gnu17 -fcommon" \
    -DCMAKE_Fortran_FLAGS="-std=legacy -fallow-argument-mismatch" \
    -DCMAKE_INSTALL_RPATH="$P/lib;$DIR/lib"

echo "CRMC build options (models that will be built):"
cmake -N -LH "$WORK/build" 2>/dev/null | grep -iE -A1 '^// .*(model|crmc|epos|qgs|sibyll|dpmjet|phojet|pythia|urqmd|hijing|hepmc|root)' || true

cmake --build "$WORK/build" --target install -j "$JOBS"

EXE="$(find "$DIR" \( -type f -o -type l \) -name crmc | head -n 1)"
[ -n "$EXE" ] && [ -x "$EXE" ] || { echo "ERROR: the crmc program was not installed."; exit 1; }
echo "crmc installed at $EXE"

write_env_hooks crmc CRMC_DIR lib include
# The $ signs are written literally into the hook file, so single quotes are intended.
# shellcheck disable=SC2016
echo 'export PATH="$CRMC_DIR/bin:$PATH"' >> "$P/etc/conda/activate.d/crmc.sh"
# shellcheck disable=SC2016
sed -i '1i if [ -n "${CRMC_DIR:-}" ]; then PATH=":$PATH:"; PATH="${PATH//:$CRMC_DIR\\/bin:/:}"; PATH="${PATH#:}"; export PATH="${PATH%:}"; fi' \
    "$P/etc/conda/deactivate.d/crmc.sh"

rm -rf "$WORK"
touch "$STAMP"
echo "CRMC $CRMC_VERSION built in $DIR"
