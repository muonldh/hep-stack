#!/bin/bash
# Prepares the data GENIE's ultra-high-energy tune (GHE19_00b_00_000, used by gSeaGen)
# needs before 'gmkspl' can make cross-section splines with it:
#
#   1. the PDF sets for photon-induced processes (NNPDF31_nnlo_as_0118_luxqed and
#      NNPDF31_nnlo_as_0118);
#   2. the photon structure-function tables ($GENIE/data/evgen/photon-sf), made by
#      gmkphotonsf. Without them every GHE19 gmkspl job aborts in PhotonStrucFunc,
#      even after days of running;
#   3. the HEDIS structure-function tables ($GENIE/data/evgen/hedis-sf), made by
#      gmkhedissf. GENIE would otherwise compute them on the first gmkspl run, and
#      several gmkspl jobs started in parallel would all try to write them at once.
#
# install.sh runs this after gSeaGen (bash install.sh --with gseagen). It takes
# roughly 10 to 60 minutes once and is skipped afterwards.
#
#   bash scripts/prepare_genie_uhe.sh            prepare (skips if already done)
#   bash scripts/prepare_genie_uhe.sh --rebuild  redo everything
#
# Environment variables:
#   GENIE_UHE_TUNE   tune to precompute HEDIS tables for (default GHE19_00b_00_000)
#   WITH_GHE19_00D=1 also download the PDF set of the newer GHE19_00d tune

set -eo pipefail

TUNE="${GENIE_UHE_TUNE:-GHE19_00b_00_000}"
REBUILD=0
[ "${1:-}" = "--rebuild" ] && REBUILD=1

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

P="$CONDA_PREFIX"
export GENIE="$P/opt/genie"
STAMP="$GENIE/data/evgen/.uhe-ready-$TUNE"

[ -x "$GENIE/bin/gmkspl" ] || { echo "GENIE is not built. Run: bash install.sh --with gseagen"; exit 1; }
if ! ldd "$GENIE/bin/gmkspl" 2>/dev/null | grep -q libAPFEL; then
    echo "GENIE is built without APFEL; the GHE19 tunes need it. Run: bash install.sh --with gseagen"
    exit 1
fi
if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "GENIE ultra-high-energy data for $TUNE already prepared."
    exit 0
fi

# GENIE's programs read these at run time (the activation hooks may not be loaded yet).
export LD_LIBRARY_PATH="$GENIE/lib:$P/opt/apfel/lib:$P/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
step() { printf '\n--- GENIE high-energy data: %s ---\n' "$*"; }

# --- 1. PDF sets -------------------------------------------------------------
PDFDIR="$(lhapdf-config --datadir)"
SETS=(NNPDF31_nnlo_as_0118_luxqed NNPDF31_nnlo_as_0118)
[ "${WITH_GHE19_00D:-0}" = 1 ] && SETS+=(NNPDF31sx_nlo_as_0118_LHCb_nf_6)
for set in "${SETS[@]}"; do
    if [ -d "$PDFDIR/$set" ]; then
        echo "PDF set $set already installed."
        continue
    fi
    step "downloading PDF set $set"
    ok=0
    for attempt in 1 2 3; do
        if curl -fL --retry 3 "https://lhapdfsets.web.cern.ch/lhapdfsets/current/$set.tar.gz" \
               | tar -xz -C "$PDFDIR"; then ok=1; break; fi
        rm -rf "${PDFDIR:?}/$set"
        echo "Download attempt $attempt failed; retrying in 15 s..."
        sleep 15
    done
    [ "$ok" = 1 ] || { echo "ERROR: could not download PDF set $set."; exit 1; }
done

# --- 2. Photon structure functions -------------------------------------------
mkdir -p "$GENIE/data/evgen/photon-sf"
NSF="$(find "$GENIE/data/evgen/photon-sf" -maxdepth 1 -name '*.dat' | wc -l)"
if [ "$NSF" -ne 12 ] || [ "$REBUILD" = 1 ]; then
    step "photon structure-function tables (gmkphotonsf)"
    (cd "$GENIE/data/evgen/photon-sf" && "$GENIE/bin/gmkphotonsf")
    NSF="$(find "$GENIE/data/evgen/photon-sf" -maxdepth 1 -name '*.dat' | wc -l)"
fi
[ "$NSF" -eq 12 ] || { echo "ERROR: photon structure functions incomplete ($NSF of 12 tables)."; exit 1; }
echo "12 photon structure-function tables present."

# --- 3. HEDIS structure functions --------------------------------------------
if [ ! -d "$GENIE/data/evgen/hedis-sf/$TUNE" ] || [ "$REBUILD" = 1 ]; then
    step "HEDIS structure-function tables for $TUNE (gmkhedissf)"
    "$GENIE/bin/gmkhedissf" --tune "$TUNE"
fi
[ -d "$GENIE/data/evgen/hedis-sf/$TUNE" ] \
    || { echo "ERROR: $GENIE/data/evgen/hedis-sf/$TUNE was not created."; exit 1; }

touch "$STAMP"
echo "GENIE ultra-high-energy data for $TUNE ready."
