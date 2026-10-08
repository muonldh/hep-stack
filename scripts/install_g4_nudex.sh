#!/bin/bash
# Installs the optional Geant4 dataset G4NUDEXLIB, which Geant4's NuDEX model
# (neutron-capture gamma cascades, G4NuDEXNeutronCaptureModel) needs. The
# conda-forge Geant4 package ships the standard datasets but not this optional one;
# without it, NuDEX stops with "Environment variable G4NUDEXLIBDATA is not defined".
#
# Version and checksum are those in Geant4's own cmake/Modules/G4DatasetDefinitions.cmake.

set -eo pipefail

NAME="G4NUDEXLIB"
VERSION="1.0"
MD5="09a85f907d2282dbf234d1784f436db3"
URL="https://cern.ch/geant4-data/datasets/${NAME}.${VERSION}.tar.gz"

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

P="$CONDA_PREFIX"
DEST="$P/share/Geant4/data/nudexlib"
STAMP="$DEST/.installed-$VERSION"

if [ -f "$STAMP" ]; then
    echo "$NAME $VERSION already installed in $DEST."
    exit 0
fi

rm -rf "$DEST"
mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $NAME $VERSION..."
curl -fL --retry 3 -o "$TMP/data.tar.gz" "$URL"
echo "$MD5  $TMP/data.tar.gz" | md5sum -c --quiet
tar -xzf "$TMP/data.tar.gz" -C "$DEST"

# The archive contains one top-level folder (e.g. NuDEXLib1.0); point the variable at it.
DATADIR="$(find "$DEST" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$DATADIR" ] || { echo "ERROR: unexpected layout of $NAME archive."; exit 1; }
echo "$NAME data in $DATADIR"

mkdir -p "$P/etc/conda/activate.d" "$P/etc/conda/deactivate.d"
echo "export G4NUDEXLIBDATA=\"\$CONDA_PREFIX/share/Geant4/data/nudexlib/$(basename "$DATADIR")\"" \
    > "$P/etc/conda/activate.d/g4nudex.sh"
echo "unset G4NUDEXLIBDATA" > "$P/etc/conda/deactivate.d/g4nudex.sh"

touch "$STAMP"
