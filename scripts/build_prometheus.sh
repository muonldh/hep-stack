#!/bin/bash
# Builds the Prometheus neutrino-telescope simulation bundle inside the active
# conda environment:
#
#   PROPOSAL        lepton and photon propagation (compiled by pip, uses Conan)
#   LeptonInjector  neutrino event injection (the copy Prometheus ships and tests)
#   LeptonWeighter  event weighting, v1.2.0
#   Prometheus      the simulation framework, including Hyperion and Olympus
#                   (github.com/Harvard-Neutrino/prometheus)
#
# Fennel (light yields) is installed with the environment (environment.yml).
# Photon propagation with IceCube's PPC code is optional in Prometheus and is not
# built here; see the Prometheus documentation if you need it.
#
#   bash scripts/build_prometheus.sh            build (skips if already built)
#   bash scripts/build_prometheus.sh --rebuild  delete and rebuild
#
# Environment variables:
#   PROMETHEUS_VERSION       git branch, tag or commit (default: main)
#   LEPTONWEIGHTER_VERSION   git tag (default v1.2.0)
#   PROPOSAL_VERSION         PyPI version (default 7.6.2)
#   JOBS                     parallel compile jobs (default: number of cores)

set -eo pipefail

PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-main}"
LEPTONWEIGHTER_VERSION="${LEPTONWEIGHTER_VERSION:-v1.2.0}"
PROPOSAL_VERSION="${PROPOSAL_VERSION:-7.6.2}"
JOBS="${JOBS:-$(nproc)}"
REBUILD=0
[ "${1:-}" = "--rebuild" ] && REBUILD=1

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

P="$CONDA_PREFIX"
DIR="$P/opt/prometheus"
STAMP="$DIR/.built"

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    echo "Prometheus already built in $DIR ($(cat "$STAMP")). Use --rebuild to redo it."
    exit 0
fi

export CC="${CC:-$P/bin/x86_64-conda-linux-gnu-gcc}"
export CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
export CMAKE_PREFIX_PATH="$P"
export CMAKE_BUILD_PARALLEL_LEVEL="$JOBS"
for tool in cmake photospline-config "$CC" "$CXX"; do
    command -v "$tool" >/dev/null || { echo "Missing $tool. Run 'bash install.sh' to update the environment."; exit 1; }
done

step() { printf '\n--- Prometheus: %s ---\n' "$*"; }

# --- 1. PROPOSAL --------------------------------------------------------------
# PROPOSAL has no prebuilt wheel: pip compiles it and fetches its C++ dependencies
# with Conan. Keep Conan's cache inside the environment and build old C
# dependencies as C17 (GCC 15 defaults to C23), as for CORSIKA 8.
step "PROPOSAL $PROPOSAL_VERSION (compiles, about 10 to 20 minutes)"
export CONAN_HOME="$P/opt/conan2"
mkdir -p "$CONAN_HOME"
conan profile detect --exist-ok >/dev/null 2>&1 || true
if ! grep -qs 'tools.build:cflags' "$CONAN_HOME/global.conf"; then
    echo 'tools.build:cflags=["-std=gnu17"]' >> "$CONAN_HOME/global.conf"
fi
python -m pip install --no-cache-dir "proposal==$PROPOSAL_VERSION"
python -c "import proposal; print('PROPOSAL', getattr(proposal, '__version__', 'ok'))"

# --- 2. Prometheus source (it also contains the LeptonInjector it is tested with)
step "downloading Prometheus ($PROMETHEUS_VERSION)"
rm -rf "$DIR"
git clone https://github.com/Harvard-Neutrino/prometheus.git "$DIR"
git -C "$DIR" -c advice.detachedHead=false checkout "$PROMETHEUS_VERSION"
COMMIT="$(git -C "$DIR" rev-parse --short HEAD)"
echo "Prometheus commit $COMMIT"

# --- 3. LeptonInjector ----------------------------------------------------------
step "LeptonInjector (Prometheus' vendored copy)"
# Its Python module uses Boost.Python (libboost-python-devel in environment.yml).
# Tell Boost which Python build to use and point CMake at the environment's Python.
PYVER="$(python -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
LI_BUILD="$(mktemp -d)"
cmake -S "$DIR/resources/LeptonInjector" -B "$LI_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$P" \
    -DCMAKE_PREFIX_PATH="$P" \
    -DPython_EXECUTABLE="$P/bin/python" \
    -DPYTHON_EXECUTABLE="$P/bin/python" \
    -DBoost_PYTHON_VERSION="$PYVER" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_INSTALL_RPATH="$P/lib"
cmake --build "$LI_BUILD" -j "$JOBS"
cmake --install "$LI_BUILD"
rm -rf "$LI_BUILD"
python -c "import LeptonInjector; print('LeptonInjector OK')"

# --- 4. LeptonWeighter ----------------------------------------------------------
step "LeptonWeighter $LEPTONWEIGHTER_VERSION"
LW_SRC="$(mktemp -d)"
git -c advice.detachedHead=false clone --depth 1 --branch "$LEPTONWEIGHTER_VERSION" \
    https://github.com/icecube/LeptonWeighter.git "$LW_SRC"
python -m pip install --no-deps --no-build-isolation "$LW_SRC"
rm -rf "$LW_SRC"
python -c "import LeptonWeighter; print('LeptonWeighter OK')"

# --- 5. Prometheus --------------------------------------------------------------
# Installed in editable mode so it finds its resources/ folder (cross sections,
# Earth models, detector geometries) inside $DIR. Its Python dependencies come
# from environment.yml, so pip must not replace them (--no-deps).
step "Prometheus"
python -m pip install --no-deps -e "$DIR"
python -c "import prometheus; print('Prometheus OK')"
python -c "import sys; sys.path.insert(0, sys.argv[1]); import hyperion; print('Hyperion OK')" "$DIR" \
    || echo "Note: Hyperion did not import on its own; it is still available through Prometheus."

echo "commit $COMMIT, built $(date +%F)" > "$STAMP"
echo "Prometheus bundle ($COMMIT) installed."
