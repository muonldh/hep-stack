#!/bin/bash
# One-command installer for the HEP software stack.
#
#   bash install.sh                  install everything
#   bash install.sh --auto-activate  also activate the environment in every new terminal
#   bash install.sh --rebuild-genie  force a fresh GENIE build
#   bash install.sh --yes            never ask questions (for automated runs)

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME="${ENV_NAME:-hep}"
MINIFORGE_DIR="${MINIFORGE_DIR:-$HOME/miniforge3}"
AUTO_ACTIVATE=0
ASSUME_YES=0
GENIE_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --auto-activate) AUTO_ACTIVATE=1 ;;
        --rebuild-genie) GENIE_ARGS+=(--rebuild) ;;
        --yes|-y)        ASSUME_YES=1 ;;
        -h|--help)       sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (see: bash install.sh --help)"; exit 1 ;;
    esac
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
say "Building GENIE inside the environment"
bash "$REPO_DIR/scripts/build_genie.sh" "${GENIE_ARGS[@]}"

# Re-activate so the GENIE activation hook written by build_genie.sh takes effect.
conda deactivate
conda activate "$ENV_NAME"

# --- 4. NuCraft (only if bundled in extern/nucraft) ---------------------------
say "Installing NuCraft"
bash "$REPO_DIR/scripts/install_nucraft.sh"

# --- 5. WSL: use ROOT's classic browser --------------------------------------
# ROOT's web-based TBrowser needs a Linux web browser, which WSL does not have.
if grep -qi microsoft /proc/version 2>/dev/null; then
    touch "$HOME/.rootrc"
    if ! grep -q '^Browser.Name:' "$HOME/.rootrc"; then
        echo "Browser.Name: TRootBrowser" >> "$HOME/.rootrc"
        echo "WSL detected: set ROOT to use the classic TBrowser (~/.rootrc)."
    fi
fi

# --- 6. Optional auto-activation ----------------------------------------------
BEGIN="# >>> hep-stack auto-activate >>>"
END="# <<< hep-stack auto-activate <<<"
sed -i "/$BEGIN/,/$END/d" "$HOME/.bashrc"
if [ "$AUTO_ACTIVATE" = 1 ]; then
    printf '%s\nconda activate %s\n%s\n' "$BEGIN" "$ENV_NAME" "$END" >> "$HOME/.bashrc"
fi

# --- 7. Check ----------------------------------------------------------------
say "Checking the installation"
bash "$REPO_DIR/scripts/check_install.sh"

say "Done"
echo "Open a new terminal, then run:   conda activate $ENV_NAME"
[ "$AUTO_ACTIVATE" = 1 ] && echo "(New terminals will activate '$ENV_NAME' automatically.)"
exit 0
