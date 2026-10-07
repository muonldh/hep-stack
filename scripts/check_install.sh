#!/bin/bash
# Quick health check of the HEP environment. Run with the environment active:
#   conda activate hep && bash scripts/check_install.sh

PASS=0
FAIL=0

check() {
    local name="$1"; shift
    local out
    if out="$("$@" 2>&1)"; then
        printf '  \033[32m[ok]\033[0m   %-14s %s\n' "$name" "$(head -n1 <<< "$out")"
        PASS=$((PASS+1))
    else
        printf '  \033[31m[fail]\033[0m %-14s %s\n' "$name" "$(tail -n1 <<< "$out")"
        FAIL=$((FAIL+1))
    fi
}

genie_ok() {
    [ -n "${GENIE:-}" ] || { echo "GENIE variable not set"; return 1; }
    [ -x "$GENIE/bin/gevgen" ] || { echo "gevgen not found"; return 1; }
    local missing
    missing="$(ldd "$GENIE/bin/gevgen" | grep 'not found')"
    [ -z "$missing" ] || { echo "missing libraries: $missing"; return 1; }
    echo "$GENIE"
}

echo "Checking HEP environment (${CONDA_DEFAULT_ENV:-none active})"
check "ROOT"      root-config --version
check "PyROOT"    python -c "import ROOT; print(ROOT.gROOT.GetVersion())"
check "Geant4"    geant4-config --version
check "G4 data"   geant4-config --check-datasets
check "Pythia 8"  test -f "$CONDA_PREFIX/include/Pythia8/Pythia.h"
check "LHAPDF"    lhapdf-config --version
check "GENIE"     genie_ok
check "OscProb"   python -c "import ROOT; assert ROOT.gSystem.Load('libOscProb') >= 0; p = ROOT.OscProb.PMNS_Fast(); print('P(numu->numu, 1000 km, 5 GeV) = %.4f' % p.Prob(1, 1, 5.0))"
check "Prob3++"   python -c "from BargerPropagator import BargerPropagator; b = BargerPropagator(); print('loaded from', __import__('BargerPropagator').__file__)"
check "Python"    python -c "import numpy, scipy, pandas, matplotlib, uproot, awkward, hist, mplhep, iminuit; print('scientific stack ok')"
if [ -d "$CONDA_PREFIX/opt/corsika/run" ]; then
    # shellcheck disable=SC2016
    check "CORSIKA"   bash -c 'ls "$CONDA_PREFIX"/opt/corsika/run/corsika7*Linux_* | head -n1 | xargs basename'
fi
if [ -d "$CONDA_PREFIX/opt/corsika8" ]; then
    # shellcheck disable=SC2016
    check "CORSIKA 8"  bash -c 'cat "$CONDA_PREFIX/opt/corsika8/.built" && test -d "$CORSIKA_DATA"'
fi
if [ -d "$CONDA_PREFIX/opt/apfel" ]; then
    # shellcheck disable=SC2016
    check "GENIE+APFEL" bash -c 'ldd "$GENIE"/lib/*.so | grep -q libAPFEL && echo "HEDIS can use NLO structure functions"'
    check "HERAPDF15"  test -d "$(lhapdf-config --datadir)/HERAPDF15NLO_EIG"
fi
if [ -d "$CONDA_PREFIX/opt/gseagen" ]; then
    check "gSeaGen"   command -v gSeaNuEvGen
fi
if [ -d "$CONDA_PREFIX/opt/nucraft" ]; then
    check "NuCraft"   python -c "import NuCraft; print(NuCraft.__file__)"
fi

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
