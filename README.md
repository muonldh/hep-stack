# hep-stack

[![install-test](https://github.com/muonldh/hep-stack/actions/workflows/install-test.yml/badge.svg)](https://github.com/muonldh/hep-stack/actions/workflows/install-test.yml)

One command to install a complete high energy physics software environment on Linux or Windows (WSL):
ROOT, Geant4, Pythia 8, LHAPDF, the GENIE neutrino event generator, and the Scikit-HEP Python analysis tools.

No compiling ROOT for an hour, no sudo, no editing paths by hand.

## What you get

| Software | Purpose | How it is installed |
|---|---|---|
| [ROOT](https://root.cern) | Data analysis framework, PyROOT | conda-forge package |
| [Geant4](https://geant4.web.cern.ch) + data sets | Detector simulation | conda-forge package |
| [Pythia 8](https://pythia.org) | Event generation, hadronization | conda-forge package |
| [LHAPDF 6](https://lhapdf.hepforge.org) | Parton distribution functions | conda-forge package |
| [GENIE](https://github.com/GENIE-MC/Generator) (R-3_06_02) | Neutrino event generator | compiled by `scripts/build_genie.sh` |
| [NuCraft](https://arxiv.org/abs/1409.1387) | Atmospheric neutrino oscillation probabilities | bundled in `extern/nucraft`, installed by `scripts/install_nucraft.sh` |
| numpy, scipy, pandas, matplotlib, JupyterLab | General scientific Python | conda-forge packages |
| uproot, awkward, hist, mplhep, iminuit, vector, particle | [Scikit-HEP](https://scikit-hep.org) analysis tools | conda-forge packages |

Everything lives in one conda environment called `hep`, so it cannot interfere with the rest of your system.

## Quick start

```bash
git clone https://github.com/muonldh/hep-stack.git
cd hep-stack
bash install.sh
```

The first run takes about 30 to 45 minutes and needs about 15 GB of disk space.
When it finishes, open a new terminal and run:

```bash
conda activate hep
```

Your prompt now starts with `(hep)` and all the software is available. Type `conda deactivate` to leave.

If you would rather have `hep` active in every new terminal automatically, install with:

```bash
bash install.sh --auto-activate
```

## Never used Linux before? Start here

**On Windows**, you first need WSL, which runs Ubuntu inside Windows:

1. Open **PowerShell as Administrator** and run `wsl --install -d Ubuntu-24.04`
2. Restart your computer when asked.
3. Open **Ubuntu** from the Start menu and choose a username and password.
4. Inside the Ubuntu window, run `sudo apt update && sudo apt install -y git curl`
5. Continue with the Quick start above.

**On Ubuntu or another Linux distribution**, make sure `git` and `curl` are installed, then go straight to the Quick start.

A few terms you will see:

- **Terminal**: the window where you type commands.
- **conda**: a package manager that downloads ready-built scientific software. The installer sets it up for you (through [Miniforge](https://github.com/conda-forge/miniforge)) if you do not have it.
- **Environment**: an isolated set of software. `conda activate hep` switches it on.

## Check that everything works

```bash
conda activate hep
bash scripts/check_install.sh
```

Expected output:

```
  [ok]   ROOT           6.xx.xx
  [ok]   PyROOT         6.xx/xx
  [ok]   Geant4         11.x.x
  ...
8 passed, 0 failed
```

## Using GENIE

After `conda activate hep`, the `GENIE` variable is set and programs such as `gevgen` and `gevgen_atmo` are on your path.
Event generation needs precomputed cross-section splines for your chosen tune. These are distributed by the GENIE
collaboration; see [genie-mc.org](http://genie-mc.org) and the GENIE Physics & User Manual.

To build a different GENIE release or enable extra features:

```bash
conda activate hep
GENIE_VERSION=R-3_06_02 GENIE_EXTRA_FLAGS="--enable-t2k" bash scripts/build_genie.sh --rebuild
```

## Using NuCraft

After `conda activate hep`, NuCraft can be imported from any folder:

```python
from NuCraft import NuCraft, EarthModel
```

NuCraft's `from numpy import *` replaces Python's built-in `bool` with `numpy.bool` under NumPy 2,
which makes its internal `assert type(vacuum) is bool` checks fail. The installer restores the
built-in `bool` directly after that import in the installed copy. Before NumPy 1.24, `numpy.bool`
was the built-in `bool` itself, so this reproduces the behaviour NuCraft was written for.
No physics code is changed and no checks are removed.

## Adding more software

Add the package name to `environment.yml`, then rerun `bash install.sh`. It updates the existing environment instead of starting over.
You can search for available packages at [prefix.dev](https://prefix.dev/channels/conda-forge).

## Updating and uninstalling

Update everything to the latest package versions:

```bash
bash install.sh
```

Remove the environment completely:

```bash
conda deactivate
conda env remove -n hep
```

Miniforge itself lives in `~/miniforge3`. To remove it as well, delete that folder and the `conda initialize` block in `~/.bashrc`.

## How it works

1. **Conda.** `install.sh` finds an existing conda installation or installs Miniforge.
2. **Environment.** It creates the `hep` environment from `environment.yml`, using only the community-maintained [conda-forge](https://conda-forge.org) channel.
3. **GENIE and NuCraft.** GENIE is not available as a conda package, so `scripts/build_genie.sh` compiles it inside the environment with the environment's own compilers and libraries. It then registers conda activation hooks, so `conda activate hep` sets `GENIE`, `PATH` and `LD_LIBRARY_PATH` for you. `scripts/install_nucraft.sh` copies the bundled NuCraft into the environment and applies its NumPy 2 fix.
4. **Test.** `scripts/check_install.sh` verifies each component.

The full installation is tested automatically on a clean Ubuntu 24.04 machine by
[GitHub Actions](.github/workflows/install-test.yml) on every change and once a week.

## Notes

- **Pythia 6 is not available on conda-forge.** GENIE is therefore built with Pythia 8, and its configuration is switched to the Pythia 8 hadronization and decay algorithms. Tunes were originally fitted with Pythia 6, so validate against a reference sample if your analysis is sensitive to hadronization.
- **Versions follow conda-forge.** ROOT, Geant4 and the other packages get the latest compatible release. To freeze an exact working set for a paper or thesis, run `conda env export -n hep > environment.lock.yml` and keep that file.
- **Platform.** Linux and WSL on x86_64. GENIE's build system does not support other architectures.

## Troubleshooting

| Problem | Fix |
|---|---|
| `conda: command not found` | Open a new terminal. The installer only updates `~/.bashrc`, which new terminals read. |
| Installer stops during "Creating environment" | Usually a network drop. Run `bash install.sh` again; it continues from where it stopped. |
| Build is killed or the computer freezes while compiling GENIE | Not enough RAM for parallel builds. Run `JOBS=2 bash install.sh`. |
| `xdg-open: not found` when opening a TBrowser | Run `echo "Browser.Name: TRootBrowser" >> ~/.rootrc` (the installer does this automatically on WSL). |
| Geant4 or ROOT windows do not open on WSL | Graphics need Windows 11 (WSLg). Batch jobs work without it. |

## Reporting problems

If the installer fails or something does not work:

1. Go to the [Issues page](https://github.com/muonldh/hep-stack/issues) and click **New issue**. You need a free GitHub account.
2. Give it a short title, for example "GENIE build fails on Ubuntu 22.04".
3. In the description, include:
   - your system (run `lsb_release -a` and paste the output)
   - whether you use WSL or native Ubuntu
   - the command you ran
   - the last 30 or so lines of the error output

## License

The scripts in this repository are released under the [MIT License](LICENSE).
ROOT, Geant4, Pythia, LHAPDF, GENIE and NuCraft are separate projects under their own licenses.
If you use them in published work, cite them as their authors request.
