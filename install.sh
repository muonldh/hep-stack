#!/bin/bash
# One-command installer for the HEP software stack.
#
#   bash install.sh                  install everything
#   bash install.sh --auto-activate  also activate the environment in every new terminal
#   bash install.sh --rebuild        force fresh builds of GENIE, OscProb and Prob3++
#   bash install.sh --yes            never ask questions (for automated runs)
#
# Optional extras (can be combined, e.g. --with nuwro --with nucdeex, or --with all):
#   bash install.sh --with gseagen     gSeaGen with GENIE's ultra-high-energy model (adds APFEL,
#                                      rebuilds GENIE once with it)
#   bash install.sh --with corsika8    CORSIKA 8 air showers / atmospheric muons (1-2 hours)
#   bash install.sh --with crmc        CRMC cosmic-ray interaction models
#   bash install.sh --with nuwro       NuWro neutrino event generator
#   bash install.sh --with nucdeex     NucDeEx nuclear de-excitation (with NuWro interface if
#                                      NuWro is installed)
#   bash install.sh --with prometheus  Prometheus, PROPOSAL, LeptonInjector, LeptonWeighter

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME="${ENV_NAME:-hep}"
MINIFORGE_DIR="${MINIFORGE_DIR:-$HOME/miniforge3}"
AUTO_ACTIVATE=0
ASSUME_YES=0
REBUILD_ARGS=()
WITH_CORSIKA8=0
WITH_GSEAGEN=0
WITH_CRMC=0
WITH_NUWRO=0
WITH_NUCDEEX=0
WITH_PROMETHEUS=0
EXTRAS="gseagen, corsika8, crmc, nuwro, nucdeex, prometheus or all"

add_extra() {
    case "$1" in
        gseagen)    WITH_GSEAGEN=1 ;;
        corsika8)   WITH_CORSIKA8=1 ;;
        crmc)       WITH_CRMC=1 ;;
        nuwro)      WITH_NUWRO=1 ;;
        nucdeex)    WITH_NUCDEEX=1 ;;
        prometheus) WITH_PROMETHEUS=1 ;;
        all)        for e in gseagen corsika8 crmc nuwro nucdeex prometheus; do add_extra "$e"; done ;;
        *) echo "Unknown extra: $1 (choose $EXTRAS)"; exit 1 ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --auto-activate) AUTO_ACTIVATE=1 ;;
        --rebuild|--rebuild-genie) REBUILD_ARGS+=(--rebuild) ;;
        --yes|-y)        ASSUME_YES=1 ;;
        --with)          [ -n "${2:-}" ] || { echo "--with needs a name: $EXTRAS"; exit 1; }
                         add_extra "$2"; shift ;;
        --with=*)        add_extra "${1#--with=}" ;;
        -h|--help)       sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
command -v curl >/dev/null || fail "curl is missing. Install it with: sudo apt install curl"

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
    curl -fsSL -o "$INSTALLER" \
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

# --- 3. GENIE ----------------------------------------------------------------
# For gSeaGen's ultra-high-energy neutrinos GENIE needs APFEL: build it first, so
# GENIE is compiled with it in one go.
if [ "$WITH_GSEAGEN" = 1 ]; then
    say "Building APFEL (needed by GENIE's high-energy model)"
    bash "$REPO_DIR/scripts/build_apfel.sh" "${REBUILD_ARGS[@]}"
fi
say "Building GENIE inside the environment"
bash "$REPO_DIR/scripts/build_genie.sh" "${REBUILD_ARGS[@]}"

# --- 4. Oscillation probability codes ----------------------------------------
say "Building OscProb"
bash "$REPO_DIR/scripts/build_oscprob.sh" "${REBUILD_ARGS[@]}"
say "Building Prob3++"
bash "$REPO_DIR/scripts/build_prob3pp.sh" "${REBUILD_ARGS[@]}"

# Geant4's NuDEX model needs an optional dataset that conda-forge does not ship.
say "Installing the Geant4 NuDEX dataset"
bash "$REPO_DIR/scripts/install_g4_nudex.sh"

# --- Optional extras ---------------------------------------------------------
if [ "$WITH_GSEAGEN" = 1 ]; then
    say "Building GENIE ReWeight (needed by gSeaGen)"
    bash "$REPO_DIR/scripts/build_genie_reweight.sh" "${REBUILD_ARGS[@]}"
    say "Building gSeaGen"
    bash "$REPO_DIR/scripts/build_gseagen.sh" "${REBUILD_ARGS[@]}"
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

# Re-activate so the activation hooks written by the build scripts take effect.
conda deactivate
conda activate "$ENV_NAME"

# --- 5. NuCraft (only if bundled in extern/nucraft) ---------------------------
say "Installing NuCraft"
bash "$REPO_DIR/scripts/install_nucraft.sh"

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
