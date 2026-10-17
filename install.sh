#!/bin/bash
# One-command installer for the HEP software stack.
#
#   bash install.sh                  install the core stack (see README for the list)
#   bash install.sh --auto-activate  also activate the environment in every new terminal
#                                    (kept on later runs; --no-auto-activate turns it off)
#   bash install.sh --rebuild        force fresh builds of the chosen extras
#   bash install.sh --yes            never ask questions (for automated runs)
#
# Optional extras (can be combined, e.g. --with nuwro --with nucdeex, or --with all):
#   bash install.sh --with genie       GENIE neutrino event generator
#   bash install.sh --with gseagen     gSeaGen with GENIE's ultra-high-energy model (adds GENIE
#                                      and APFEL, and builds GENIE with APFEL)
#   bash install.sh --with corsika8    CORSIKA 8 air showers / atmospheric muons (1-2 hours)
#   bash install.sh --with crmc        CRMC cosmic-ray interaction models
#   bash install.sh --with nuwro       NuWro neutrino event generator
#   bash install.sh --with nucdeex     NucDeEx nuclear de-excitation (with NuWro interface if
#                                      NuWro is installed)
#   bash install.sh --with prometheus  Prometheus, PROPOSAL, LeptonInjector, LeptonWeighter
#   bash install.sh --with garfield    Garfield++ gaseous/semiconductor detector simulation
#   bash install.sh --with oscprob     OscProb neutrino oscillation probabilities
#   bash install.sh --with prob3pp     Prob3++ neutrino oscillation probabilities
#   bash install.sh --with nucraft     NuCraft neutrino oscillation probabilities
#   bash install.sh --with oscillation all three oscillation codes above
#   bash install.sh --with mceq        MCEq atmospheric lepton fluxes (Python)
#   bash install.sh --with chromo      chromo: EPOS, QGSJet, Sibyll, ... from Python
#   bash install.sh --with fennel      Fennel Cherenkov light yields (Python)
#   bash install.sh --with astro       all three Python packages above

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME="${ENV_NAME:-hep}"
MINIFORGE_DIR="${MINIFORGE_DIR:-$HOME/miniforge3}"
AUTO_ACTIVATE=
ASSUME_YES=0
REBUILD_ARGS=()
WITH_CORSIKA8=0
WITH_GSEAGEN=0
WITH_CRMC=0
WITH_NUWRO=0
WITH_NUCDEEX=0
WITH_PROMETHEUS=0
WITH_GARFIELD=0
WITH_OSCPROB=0
WITH_PROB3PP=0
WITH_NUCRAFT=0
WITH_GENIE=0
WITH_MCEQ=0
WITH_CHROMO=0
WITH_FENNEL=0
FENNEL_URL="https://github.com/MeighenBergerS/fennel/archive/refs/tags/v2.1.0.tar.gz"
EXTRAS="genie, gseagen, corsika8, crmc, nuwro, nucdeex, prometheus, garfield, oscprob, prob3pp, nucraft, oscillation, mceq, chromo, fennel, astro or all"

add_extra() {
    case "$1" in
        genie)      WITH_GENIE=1 ;;
        gseagen)    WITH_GSEAGEN=1; add_extra genie ;;
        corsika8)   WITH_CORSIKA8=1 ;;
        crmc)       WITH_CRMC=1 ;;
        nuwro)      WITH_NUWRO=1 ;;
        nucdeex)    WITH_NUCDEEX=1 ;;
        prometheus) WITH_PROMETHEUS=1; add_extra fennel ;;
        garfield)   WITH_GARFIELD=1 ;;
        oscprob)    WITH_OSCPROB=1 ;;
        prob3pp)    WITH_PROB3PP=1 ;;
        nucraft)    WITH_NUCRAFT=1 ;;
        oscillation) for e in oscprob prob3pp nucraft; do add_extra "$e"; done ;;
        mceq)       WITH_MCEQ=1 ;;
        chromo)     WITH_CHROMO=1 ;;
        fennel)     WITH_FENNEL=1 ;;
        astro)      for e in mceq chromo fennel; do add_extra "$e"; done ;;
        all)        for e in genie gseagen corsika8 crmc nuwro nucdeex prometheus garfield oscillation astro; do add_extra "$e"; done ;;
        *) echo "Unknown extra: $1 (choose $EXTRAS)"; exit 1 ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --auto-activate) AUTO_ACTIVATE=1 ;;
        --no-auto-activate) AUTO_ACTIVATE=0 ;;
        --rebuild|--rebuild-genie) REBUILD_ARGS+=(--rebuild) ;;
        --yes|-y)        ASSUME_YES=1 ;;
        --with)          [ -n "${2:-}" ] || { echo "--with needs a name: $EXTRAS"; exit 1; }
                         add_extra "$2"; shift ;;
        --with=*)        add_extra "${1#--with=}" ;;
        -h|--help)       awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
        *) echo "Unknown option: $1 (see: bash install.sh --help)"; exit 1 ;;
    esac
    shift
done

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*"; exit 1; }

confirm() {
    [ "$ASSUME_YES" = 1 ] && return 0
    read -r -p "$1 [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# --- Checks ------------------------------------------------------------------
[ "$EUID" -ne 0 ] || fail "Run this as your normal user, not with sudo."
[ "$(uname -s)" = "Linux" ] || fail "This installer supports Linux and WSL only."
[ "$(uname -m)" = "x86_64" ] || fail "GENIE's build system supports x86_64 only (found $(uname -m))."
# Miniforge is downloaded with curl, or wget if curl is missing (no sudo needed).
# After that, the environment provides its own curl for the build scripts.
command -v curl >/dev/null || command -v wget >/dev/null \
    || fail "Neither curl nor wget is installed. Ask an administrator for: sudo apt install curl"
download() { if command -v curl >/dev/null; then curl -fsSL -o "$1" "$2"; else wget -q -O "$1" "$2"; fi; }

FREE_GB=$(df --output=avail -BG "$HOME" | tail -1 | tr -dc '0-9')
if [ "$FREE_GB" -lt 15 ]; then
    echo "Only ${FREE_GB} GB free in your home folder. About 15 GB is needed."
    confirm "Continue anyway?" || exit 1
fi

# --- 1. Conda ----------------------------------------------------------------
if [ -n "${CONDA_EXE:-}" ] && [ -x "$CONDA_EXE" ]; then
    CONDA_BASE="$("$CONDA_EXE" info --base)"
    say "Using existing conda at $CONDA_BASE"
elif command -v conda >/dev/null; then
    CONDA_BASE="$(conda info --base)"
    say "Using existing conda at $CONDA_BASE"
elif [ -x "$MINIFORGE_DIR/bin/conda" ]; then
    CONDA_BASE="$MINIFORGE_DIR"
    say "Using existing Miniforge at $CONDA_BASE"
else
    say "Installing Miniforge (conda) into $MINIFORGE_DIR"
    INSTALLER="$(mktemp --suffix=.sh)"
    download "$INSTALLER" \
        "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
    bash "$INSTALLER" -b -p "$MINIFORGE_DIR"
    rm -f "$INSTALLER"
    CONDA_BASE="$MINIFORGE_DIR"
    # Make 'conda' available in future terminals.
    "$CONDA_BASE/bin/conda" init bash >/dev/null
fi

# shellcheck disable=SC1091
source "$CONDA_BASE/etc/profile.d/conda.sh"

# --- 2. Environment ----------------------------------------------------------
ENVS="$(conda env list | awk '{print $1}')"
if grep -qx "$ENV_NAME" <<< "$ENVS"; then
    say "Updating environment '$ENV_NAME' (this can take a few minutes)"
    conda env update -n "$ENV_NAME" -f "$REPO_DIR/environment.yml" --prune
else
    say "Creating environment '$ENV_NAME' (downloads a few GB, 5 to 15 minutes)"
    conda env create -n "$ENV_NAME" -f "$REPO_DIR/environment.yml"
fi

conda activate "$ENV_NAME"

# Extras installed by an earlier run stay installed and are kept up to date, so a
# plain 'bash install.sh' after 'git pull' never drops or breaks one of them.
for e in genie gseagen corsika8 crmc nuwro nucdeex prometheus garfield oscprob prob3pp nucraft; do
    if [ -d "$CONDA_PREFIX/opt/$e" ]; then add_extra "$e"; fi
done
for pair in mceq:MCEq chromo:chromo fennel:fennel; do
    if python -c "import importlib.util, sys; sys.exit(importlib.util.find_spec('${pair#*:}') is None)" 2>/dev/null; then
        add_extra "${pair%%:*}"
    fi
done

# If an environment update changed the ROOT version, the packages compiled against
# the old ROOT can no longer load it. Remove their build stamps so they are rebuilt.
ROOT_NOW="$(root-config --version)"
ROOT_FILE="$CONDA_PREFIX/opt/.root-version"
ROOT_CHANGED=0
if [ -f "$ROOT_FILE" ]; then
    [ "$(cat "$ROOT_FILE")" != "$ROOT_NOW" ] && ROOT_CHANGED=1
elif [ -x "$CONDA_PREFIX/opt/genie/bin/gevgen" ] \
     && grep -q 'not found' <<< "$(ldd "$CONDA_PREFIX/opt/genie/bin/gevgen" 2>&1)"; then
    ROOT_CHANGED=1    # installs made before this check existed
fi
if [ "$ROOT_CHANGED" = 1 ]; then
    say "ROOT is now $ROOT_NOW: rebuilding the packages compiled against the old version"
    for pkg in genie oscprob genie-reweight gseagen nuwro nucdeex garfield; do
        rm -f "$CONDA_PREFIX/opt/$pkg"/.built*
    done
fi
mkdir -p "$CONDA_PREFIX/opt"
echo "$ROOT_NOW" > "$ROOT_FILE"

# --- 3. GENIE (optional) -----------------------------------------------------
# For gSeaGen's ultra-high-energy neutrinos GENIE needs APFEL: build it first, so
# GENIE is compiled with it in one go.
if [ "$WITH_GSEAGEN" = 1 ]; then
    say "Building APFEL (needed by GENIE's high-energy model)"
    bash "$REPO_DIR/scripts/build_apfel.sh" "${REBUILD_ARGS[@]}"
fi
if [ "$WITH_GENIE" = 1 ]; then
    say "Building GENIE inside the environment"
    bash "$REPO_DIR/scripts/build_genie.sh" "${REBUILD_ARGS[@]}"
fi

# --- Optional Python packages (PyPI only) ------------------------------------
PIP_PKGS=()
if [ "$WITH_MCEQ" = 1 ]; then PIP_PKGS+=("MCEq"); fi
if [ "$WITH_CHROMO" = 1 ]; then PIP_PKGS+=("chromo"); fi
if [ "$WITH_FENNEL" = 1 ]; then PIP_PKGS+=("fennel_seed @ $FENNEL_URL"); fi
if [ "${#PIP_PKGS[@]}" -gt 0 ]; then
    say "Installing Python packages: ${PIP_PKGS[*]%% @*}"
    python -m pip install -U "${PIP_PKGS[@]}"
fi

# --- 4. Oscillation probability codes (optional) -----------------------------
if [ "$WITH_OSCPROB" = 1 ]; then
    say "Building OscProb"
    bash "$REPO_DIR/scripts/build_oscprob.sh" "${REBUILD_ARGS[@]}"
fi
if [ "$WITH_PROB3PP" = 1 ]; then
    say "Building Prob3++"
    bash "$REPO_DIR/scripts/build_prob3pp.sh" "${REBUILD_ARGS[@]}"
fi

# Geant4's NuDEX model needs an optional dataset that conda-forge does not ship.
say "Installing the Geant4 NuDEX dataset"
bash "$REPO_DIR/scripts/install_g4_nudex.sh"

# --- Optional extras ---------------------------------------------------------
if [ "$WITH_GSEAGEN" = 1 ]; then
    say "Building GENIE ReWeight (needed by gSeaGen)"
    bash "$REPO_DIR/scripts/build_genie_reweight.sh" "${REBUILD_ARGS[@]}"
    say "Building gSeaGen"
    bash "$REPO_DIR/scripts/build_gseagen.sh" "${REBUILD_ARGS[@]}"
    say "Preparing GENIE's ultra-high-energy data (PDF sets, photon and HEDIS tables)"
    bash "$REPO_DIR/scripts/prepare_genie_uhe.sh" "${REBUILD_ARGS[@]}"
fi
if [ "$WITH_CORSIKA8" = 1 ]; then
    say "Building CORSIKA 8 (the first build takes one to two hours)"
    bash "$REPO_DIR/scripts/build_corsika8.sh" "${REBUILD_ARGS[@]}"
fi
if [ "$WITH_CRMC" = 1 ]; then
    say "Building CRMC"
    bash "$REPO_DIR/scripts/build_crmc.sh" "${REBUILD_ARGS[@]}"
fi
# NuWro before NucDeEx, so NucDeEx can build its NuWro interface.
if [ "$WITH_NUWRO" = 1 ]; then
    say "Building NuWro"
    bash "$REPO_DIR/scripts/build_nuwro.sh" "${REBUILD_ARGS[@]}"
fi
if [ "$WITH_NUCDEEX" = 1 ]; then
    say "Building NucDeEx"
    bash "$REPO_DIR/scripts/build_nucdeex.sh" "${REBUILD_ARGS[@]}"
fi
if [ "$WITH_PROMETHEUS" = 1 ]; then
    say "Building Prometheus with PROPOSAL, LeptonInjector and LeptonWeighter"
    bash "$REPO_DIR/scripts/build_prometheus.sh" "${REBUILD_ARGS[@]}"
fi
if [ "$WITH_GARFIELD" = 1 ]; then
    say "Building Garfield++"
    bash "$REPO_DIR/scripts/build_garfield.sh" "${REBUILD_ARGS[@]}"
fi

# Re-activate so the activation hooks written by the build scripts take effect.
conda deactivate
conda activate "$ENV_NAME"

# --- 5. NuCraft (optional) ----------------------------------------------------
if [ "$WITH_NUCRAFT" = 1 ]; then
    say "Installing NuCraft"
    bash "$REPO_DIR/scripts/install_nucraft.sh"
fi

# --- 6. WSL: use ROOT's classic browser --------------------------------------
# ROOT's web-based TBrowser needs a Linux web browser, which WSL does not have.
if grep -qi microsoft /proc/version 2>/dev/null; then
    touch "$HOME/.rootrc"
    if ! grep -q '^Browser.Name:' "$HOME/.rootrc"; then
        echo "Browser.Name: TRootBrowser" >> "$HOME/.rootrc"
        echo "WSL detected: set ROOT to use the classic TBrowser (~/.rootrc)."
    fi
fi

# --- 7. Optional auto-activation ----------------------------------------------
BEGIN="# >>> hep-stack auto-activate >>>"
END="# <<< hep-stack auto-activate <<<"
# Without --auto-activate or --no-auto-activate, keep whatever an earlier run set up.
if [ -z "$AUTO_ACTIVATE" ]; then
    if grep -qF "$BEGIN" "$HOME/.bashrc" 2>/dev/null; then AUTO_ACTIVATE=1; else AUTO_ACTIVATE=0; fi
fi
sed -i "/$BEGIN/,/$END/d" "$HOME/.bashrc"
if [ "$AUTO_ACTIVATE" = 1 ]; then
    printf '%s\nconda activate %s\n%s\n' "$BEGIN" "$ENV_NAME" "$END" >> "$HOME/.bashrc"
fi

# --- 8. Check ----------------------------------------------------------------
say "Checking the installation"
bash "$REPO_DIR/scripts/check_install.sh"

say "Done"
echo "Open a new terminal, then run:   conda activate $ENV_NAME"
[ "$AUTO_ACTIVATE" = 1 ] && echo "(New terminals will activate '$ENV_NAME' automatically.)"
exit 0
