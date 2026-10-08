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
# shellcheck disable=SC2016
check "G4 NuDEX"  bash -c 'test -d "$G4NUDEXLIBDATA" && echo "$G4NUDEXLIBDATA"'
check "Pythia 8"  test -f "$CONDA_PREFIX/include/Pythia8/Pythia.h"
check "LHAPDF"    lhapdf-config --version
check "GENIE"     genie_ok
check "OscProb"   python -c "import ROOT; assert ROOT.gSystem.Load('libOscProb') >= 0; p = ROOT.OscProb.PMNS_Fast(); print('P(numu->numu, 1000 km, 5 GeV) = %.4f' % p.Prob(1, 1, 5.0))"
check "Prob3++"   python -c "from BargerPropagator import BargerPropagator; b = BargerPropagator(); print('loaded from', __import__('BargerPropagator').__file__)"
check "Python"    python -c "import numpy, scipy, pandas, matplotlib, uproot, awkward, hist, mplhep, iminuit; print('scientific stack ok')"
check "Data formats" python -c "import pyarrow, h5py, yaml; print('Parquet (pyarrow ' + pyarrow.__version__ + '), HDF5, YAML')"
check "yaml-cpp"  test -f "$CONDA_PREFIX/include/yaml-cpp/yaml.h"
check "ML"        python -c "import sklearn, xgboost, torch, torchvision, torch_geometric; print('scikit-learn', sklearn.__version__, '| xgboost', xgboost.__version__, '| torch', torch.__version__, '| PyG', torch_geometric.__version__)"
check "JAX"       python -c "import jax, optax; print('jax', jax.__version__)"
check "MCEq"      python -c "import MCEq; print(getattr(MCEq, '__version__', 'ok'))"
check "chromo"    python -c "import chromo; print(chromo.__version__)"
check "Fennel"    python -c "import fennel; print('ok')"
if [ -d "$CONDA_PREFIX/opt/corsika8" ]; then
    # shellcheck disable=SC2016
    check "CORSIKA 8"  bash -c 'cat "$CONDA_PREFIX/opt/corsika8/.built" && test -d "$CORSIKA_DATA"'
fi
if [ -d "$CONDA_PREFIX/opt/apfel" ]; then
    # shellcheck disable=SC2016
    check "GENIE+APFEL" bash -c 'ldd "$GENIE/bin/gevgen" | grep -q libAPFEL && echo "HEDIS can use NLO structure functions"'
    check "HERAPDF15"  test -d "$(lhapdf-config --datadir)/HERAPDF15NLO_EIG"
fi
if [ -d "$CONDA_PREFIX/opt/genie-reweight" ]; then
    # shellcheck disable=SC2016
    check "GENIE ReWeight" bash -c 'ls "$GENIE_REWEIGHT"/lib/libGRwFwk*.so | head -n1 | xargs basename'
fi
if [ -d "$CONDA_PREFIX/opt/gseagen" ]; then
    check "gSeaGen"   command -v gSeaNuEvGen
fi
if [ -d "$CONDA_PREFIX/opt/crmc" ]; then
    check "CRMC"      command -v crmc
fi
if [ -d "$CONDA_PREFIX/opt/nuwro" ]; then
    check "NuWro"     command -v nuwro
fi
if [ -d "$CONDA_PREFIX/opt/nucdeex" ]; then
    # shellcheck disable=SC2016
    check "NucDeEx"   bash -c 'test -x "$NUCDEEX_ROOT/bin/simulation" && echo "$NUCDEEX_ROOT"'
fi
if [ -d "$CONDA_PREFIX/opt/prometheus" ]; then
    check "PROPOSAL"  python -c "import proposal; print(getattr(proposal, '__version__', 'ok'))"
    check "LeptonInjector" python -c "import LeptonInjector; print('ok')"
    check "LeptonWeighter" python -c "import LeptonWeighter; print('ok')"
    check "Prometheus" python -c "import prometheus; print(prometheus.__file__)"
fi
if [ -d "$CONDA_PREFIX/opt/nucraft" ]; then
    check "NuCraft"   python -c "import NuCraft; print(NuCraft.__file__)"
fi

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
