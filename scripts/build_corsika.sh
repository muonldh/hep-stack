#!/bin/bash
# Builds CORSIKA 7 (air shower simulation, KIT) inside the active conda environment.
#
# CORSIKA is not open source: KIT gives out a download password to registered users
# and asks that the code is not passed on. This script therefore never stores the
# code or the password; each user downloads CORSIKA with their own password.
# How to register: see the README section "CORSIKA".
#
#   bash scripts/build_corsika.sh                        download (asks for password) and build
#   bash scripts/build_corsika.sh corsika-78050.tar.gz   build from a tarball you downloaded
#   bash scripts/build_corsika.sh --rebuild              delete the existing build first
#
# Environment variables:
#   CORSIKA_VERSION   version number in the file name (default 78050, i.e. 7.8050)
#   CORSIKA_PW        download password (otherwise you are asked for it)

set -eo pipefail

CORSIKA_VERSION="${CORSIKA_VERSION:-78050}"
SERIES="v${CORSIKA_VERSION:0:2}0"            # 78050 -> v780 (the download subfolder)
TARBALL=""
REBUILD=0
for arg in "$@"; do
    case "$arg" in
        --rebuild) REBUILD=1 ;;
        *.tar.gz)  TARBALL="$(realpath "$arg")" ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

P="$CONDA_PREFIX"
DIR="$P/opt/corsika"

if compgen -G "$DIR/run/corsika${CORSIKA_VERSION}Linux_*" >/dev/null && [ "$REBUILD" = 0 ]; then
    echo "CORSIKA $CORSIKA_VERSION already built in $DIR/run (use --rebuild to redo it)."
    echo "To build another model combination, run:  cd $DIR && ./coconut"
    exit 0
fi

# CORSIKA is Fortran: use the environment's gfortran, like the C/C++ codes use its gcc.
export FC="${FC:-$P/bin/x86_64-conda-linux-gnu-gfortran}"
export F77="${F77:-$FC}"
export CC="${CC:-$P/bin/x86_64-conda-linux-gnu-gcc}"
export CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
command -v "$FC" >/dev/null || { echo "gfortran missing. Run 'bash install.sh' to update the environment."; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -z "$TARBALL" ]; then
    if [ -z "${CORSIKA_PW:-}" ]; then
        read -r -s -p "CORSIKA download password (from the KIT e-mail): " CORSIKA_PW
        echo
    fi
    URL="https://web.iap.kit.edu/corsika/download/corsika-$SERIES/corsika-$CORSIKA_VERSION.tar.gz"
    echo "Downloading corsika-$CORSIKA_VERSION.tar.gz..."
    # The password is passed through a temporary config file, not the command line,
    # so it does not show up in the process list or shell history.
    printf 'user = corsika\npassword = %s\n' "$CORSIKA_PW" > "$WORK/wgetrc"
    if ! WGETRC="$WORK/wgetrc" wget -q --show-progress -O "$WORK/corsika.tar.gz" "$URL"; then
        echo "Download failed. Check the password, or download the file in a browser and run:"
        echo "  bash scripts/build_corsika.sh /path/to/corsika-$CORSIKA_VERSION.tar.gz"
        exit 1
    fi
    TARBALL="$WORK/corsika.tar.gz"
fi

rm -rf "$DIR"
mkdir -p "$DIR"
tar -xzf "$TARBALL" -C "$DIR" --strip-components=1
cd "$DIR"

cat <<EOF

------------------------------------------------------------------------
 CORSIKA is configured with its own interactive tool, coconut.
 Suggested answers for atmospheric muon production:

   32/64 bit ............. 2  (compiler default)
   High-energy model ..... SIBYLL 2.3e   (or EPOS.LHC-R, slower)
   Low-energy model ...... URQMD
   Detector geometry ..... horizontal flat detector (default)
                           or VOLUMEDET for a volume detector such as JUNO
   Additional options .... none needed; press Enter to finish
   Final step ............ f  (compile and remove temporary files)

 Every choice is explained in doc/CORSIKA_GUIDE*.pdf, Section 2.3.
------------------------------------------------------------------------

EOF
./coconut

shopt -s nullglob
BINARIES=("$DIR"/run/corsika"${CORSIKA_VERSION}"Linux_*)
if [ ${#BINARIES[@]} -eq 0 ]; then
    echo "ERROR: no CORSIKA executable was created in $DIR/run."
    exit 1
fi

# Activation hooks: CORSIKA_DIR and CORSIKA_RUN on 'conda activate hep'.
mkdir -p "$P/etc/conda/activate.d" "$P/etc/conda/deactivate.d"
cat > "$P/etc/conda/activate.d/corsika.sh" <<'EOF'
export CORSIKA_DIR="$CONDA_PREFIX/opt/corsika"
export CORSIKA_RUN="$CORSIKA_DIR/run"
EOF
echo 'unset CORSIKA_DIR CORSIKA_RUN' > "$P/etc/conda/deactivate.d/corsika.sh"

echo
echo "CORSIKA built. Executables in $DIR/run:"
for b in "${BINARIES[@]}"; do echo "  $(basename "$b")"; done
echo "Open a new terminal (or run 'conda activate hep' again) to set CORSIKA_RUN."
