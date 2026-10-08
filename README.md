# hep-stack

[![install-test](https://github.com/muonldh/hep-stack/actions/workflows/install-test.yml/badge.svg)](https://github.com/muonldh/hep-stack/actions/workflows/install-test.yml)
[![extras-test](https://github.com/muonldh/hep-stack/actions/workflows/extras-test.yml/badge.svg)](https://github.com/muonldh/hep-stack/actions/workflows/extras-test.yml)

One command to install a complete high energy physics software environment on Linux or Windows (WSL):
ROOT, Geant4, Pythia 8, LHAPDF, the GENIE neutrino event generator, the OscProb, Prob3++ and NuCraft
oscillation codes, MCEq, chromo, the Scikit-HEP Python analysis tools and a machine-learning stack,
plus optional extras such as CORSIKA 8, gSeaGen, NuWro, NucDeEx, CRMC and Prometheus.

No compiling ROOT for an hour, no sudo, no editing paths by hand.

## What you get

| Software | Purpose | How it is installed |
|---|---|---|
| [ROOT](https://root.cern) | Data analysis framework, PyROOT | conda-forge package |
| [Geant4](https://geant4.web.cern.ch) + data sets | Detector simulation | conda-forge package |
| [Pythia 8](https://pythia.org) | Event generation, hadronization | conda-forge package |
| [LHAPDF 6](https://lhapdf.hepforge.org) | Parton distribution functions | conda-forge package |
| [GENIE](https://github.com/GENIE-MC/Generator) (R-3_06_02) | Neutrino event generator | compiled by `scripts/build_genie.sh` |
| [OscProb](https://github.com/joaoabcoelho/OscProb) (v2.4.0) | Oscillation probabilities with PREM, NSI, sterile, decoherence | compiled by `scripts/build_oscprob.sh` |
| [Prob3++](https://github.com/rogerwendell/Prob3plusplus) (v3r20) | Super-Kamiokande's oscillation probability code | compiled by `scripts/build_prob3pp.sh` |
| [CORSIKA 8](https://gitlab.iap.kit.edu/AirShowerPhysics/corsika), optional | Open-source air showers and atmospheric muons | `bash install.sh --with corsika8`; compiled by `scripts/build_corsika8.sh` |
| [gSeaGen](https://git.km3net.de/opensource/gseagen), optional | GENIE-based generator for neutrino telescopes, up to ultra-high energies | `bash install.sh --with gseagen`; adds [APFEL](https://github.com/scarrazza/apfel) 3.1.1 and builds GENIE with it |
| [NuCraft](https://arxiv.org/abs/1409.1387) | Atmospheric neutrino oscillation probabilities | bundled in `extern/nucraft`, installed by `scripts/install_nucraft.sh` |
| [CRMC](https://doi.org/10.5281/zenodo.5270381) (2.0.1), optional | Cosmic-ray interaction models (EPOS, QGSJet, Sibyll, ...) | `bash install.sh --with crmc`; compiled by `scripts/build_crmc.sh` |
| [NuWro](https://github.com/NuWro/nuwro) (25.11), optional | Neutrino event generator | `bash install.sh --with nuwro`; compiled with [ROOTEGPythia6](https://github.com/luketpickering/ROOTEGPythia6) by `scripts/build_nuwro.sh` |
| [NucDeEx](https://github.com/SeishoAbe/NucDeEx) (v2.2.6), optional | Nuclear de-excitation after neutrino interactions and nucleon decay | `bash install.sh --with nucdeex`; compiled by `scripts/build_nucdeex.sh` |
| [Prometheus](https://github.com/Harvard-Neutrino/prometheus), optional | Neutrino telescope simulation (includes Hyperion and Olympus) | `bash install.sh --with prometheus`, together with [PROPOSAL](https://github.com/tudo-astroparticlephysics/PROPOSAL) 7.6.2, [LeptonInjector](https://github.com/icecube/LeptonInjector) and [LeptonWeighter](https://github.com/icecube/LeptonWeighter) 1.2.0 |
| [MCEq](https://github.com/afedynitch/MCEq) | Atmospheric lepton fluxes (Matrix Cascade Equations) | PyPI package |
| [chromo](https://github.com/impy-project/chromo) | EPOS, QGSJet, Sibyll, DPMJET, Pythia and UrQMD from Python | PyPI package |
| [Fennel](https://github.com/MeighenBergerS/fennel) (2.1.0) | Cherenkov light yields of particles and showers | installed from GitHub with the environment |
| Apache Parquet (pyarrow), yaml-cpp, HDF5 (h5py), HepMC3 | Data formats | conda-forge packages |
| scikit-learn, XGBoost, PyTorch, torchvision, PyTorch Geometric, JAX | Machine learning (see below) | conda-forge packages |
| numpy, scipy, pandas, matplotlib, JupyterLab | General scientific Python | conda-forge packages |
| uproot, awkward, hist, mplhep, iminuit, vector, particle | [Scikit-HEP](https://scikit-hep.org) analysis tools | conda-forge packages |

Geant4 also includes **Geant4-DNA** (track-structure physics in water) and **NuDEX**
(neutron-capture gamma cascades). Both are part of the conda-forge Geant4 package; NuDEX's
optional data library (`G4NUDEXLIB`), which conda-forge does not ship, is downloaded by the
installer and found through `G4NUDEXLIBDATA`.

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
19 passed, 0 failed
```

Optional extras add their own checks: with `--with all` the result is `31 passed, 0 failed`.

If a later `bash install.sh` updates ROOT to a new version, the installer rebuilds GENIE, OscProb and the other packages compiled against ROOT automatically.

To confirm you can compile your own Geant4 programs, build and run Geant4's example B1:

```bash
bash scripts/test_geant4_example.sh
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

## Using OscProb and Prob3++

Both are available from Python (and C++) after `conda activate hep`.

OscProb, through PyROOT:

```python
import ROOT
ROOT.gSystem.Load("libOscProb")

p = ROOT.OscProb.PMNS_Fast()          # standard 3-flavour; also PMNS_NSI, PMNS_Sterile, ...
prem = ROOT.OscProb.PremModel()       # PREM Earth model
prem.FillPath(-1.0)                   # cos(zenith) = -1: straight up through the core
p.SetPath(prem.GetNuPath())
print(p.Prob(1, 1, 5.0))              # P(numu -> numu) at 5 GeV
```

Prob3++, through its Python wrapper:

```python
from BargerPropagator import BargerPropagator

b = BargerPropagator()
# sin^2(th12), sin^2(th13), sin^2(th23), dm21, dm_atm [eV^2], delta_cp [rad], E [GeV], sin^2 inputs, nu/anti-nu
b.SetMNS(0.307, 0.0222, 0.561, 7.49e-5, 2.534e-3, 3.8, 5.0, True, 1)
b.DefinePath(-1.0, 15.0, True)        # cos(zenith), production height [km], use PREM
b.propagate(1)
print(b.GetProb(2, 2))                # P(numu -> numu)
```

The codes use different conventions. Check these before comparing results:

| | OscProb | Prob3++ |
|---|---|---|
| Flavour index | 0 = e, 1 = mu, 2 = tau | 1 = e, 2 = mu, 3 = tau |
| Antineutrinos | `p.SetIsNuBar(True)` | negative type, e.g. `-1`, in `SetMNS` and `propagate` |
| Inverted ordering | negative `SetDm(3, ...)` | negative atmospheric splitting (see the Prob3++ README) |

To rebuild a different release: `OSCPROB_VERSION=v2.3.0 bash scripts/build_oscprob.sh --rebuild`
(the same works with `PROB3PP_VERSION` and `scripts/build_prob3pp.sh`).

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

## CORSIKA 8 (optional)

CORSIKA 8 is the open-source successor of CORSIKA 7 (GPLv3, no registration needed).
It simulates cosmic-ray air showers and gives the muons and other particles arriving at an
observation level.
Install it with:

```bash
cd ~/hep-stack
bash install.sh --with corsika8
```

The first build downloads several GB (source plus interaction-model tables) and compiles
CORSIKA 8's own dependencies with Conan, so it takes one to two hours. Later runs of
`install.sh` skip it. After `conda activate hep`:

| Variable | Meaning |
|---|---|
| `CORSIKA8_DIR` | installed framework |
| `corsika_DIR` | lets your own CMake projects find CORSIKA 8 |
| `CORSIKA_DATA` | interaction-model tables read at run time |

CORSIKA 8 is a C++ framework: you write a small program that sets up the atmosphere,
primary, interaction models and observation level. The examples in
`$CONDA_PREFIX/opt/corsika8-src/examples` are the starting point:

```bash
conda activate hep
cmake -S $CONDA_PREFIX/opt/corsika8-src/examples -B ~/c8-examples
cmake --build ~/c8-examples -j4
ls ~/c8-examples/bin
```

To build a specific release instead of the latest development version:
`CORSIKA8_VERSION=<tag> bash scripts/build_corsika8.sh --rebuild` (the build log lists recent tags).

## gSeaGen (optional)

gSeaGen is KM3NeT's event generator for neutrino telescopes. It is a GENIE application:
it links the GENIE built here and uses GENIE for every interaction. For astrophysical
neutrinos above about 100 TeV it uses GENIE's high-energy model (HEDIS, tune
`GHE19_00b_00_000`), which needs NLO structure functions from APFEL and the
`HERAPDF15NLO_EIG` PDF set. `--with gseagen` sets all of this up:

```bash
cd ~/hep-stack
bash install.sh --with gseagen
```

It builds APFEL, rebuilds GENIE once with APFEL enabled (same version and tunes as before,
so existing GENIE results are unaffected), downloads `HERAPDF15NLO_EIG`, builds GENIE
ReWeight (R-1_04_02, which gSeaGen requires), and then builds gSeaGen.
After `conda activate hep`, `gSeaNuEvGen -h` lists all options.

Like any GENIE application, gSeaGen needs cross-section splines for the tune you use.
For ultra-high energies that is `GHE19_00b_00_000`; the first run with it also computes
the structure-function tables with APFEL, which takes a while once.

## Machine learning

| Model | Package | Example |
|---|---|---|
| Logistic regression | scikit-learn | `from sklearn.linear_model import LogisticRegression` |
| Multilayer perceptron (MLP) | scikit-learn or PyTorch | `from sklearn.neural_network import MLPClassifier` |
| Gradient-boosted trees | XGBoost | `from xgboost import XGBClassifier` |
| Convolutional neural network (CNN) | PyTorch (+ torchvision) | `torch.nn.Conv2d`, `torchvision.models` |
| Graph neural network (GNN) | PyTorch Geometric | `from torch_geometric.nn import GCNConv, EdgeConv` |

PyTorch is installed as the CPU build, which works on every machine. With an NVIDIA GPU,
conda-forge can install a CUDA build instead (`conda install -n hep "pytorch=*=cuda*"`).

## CRMC and chromo

Both give access to the hadronic interaction models used in air-shower physics.

- **chromo** is installed by default: `import chromo` in Python, or the `chromo` command.
- **CRMC** is the classic C++/Fortran package (`bash install.sh --with crmc`). After
  `conda activate hep`, run `crmc --help`.

## NuWro and NucDeEx (optional)

```bash
cd ~/hep-stack
bash install.sh --with nuwro --with nucdeex
```

**NuWro** is built against current ROOT using ROOTEGPythia6, the Pythia 6 interface NuWro
itself recommends. After `conda activate hep`, `nuwro` is on your path; copy
`$NUWRO/data/params.txt` to your working folder and edit it to set up a run (see the
[NuWro user guide](https://nuwro.github.io/user-guide/)).

**NucDeEx** simulates the gamma rays, neutrons and protons emitted when the residual
nucleus de-excites after a neutrino interaction or nucleon decay (12C and 16O targets,
TALYS-based). `NUCDEEX_ROOT` is set on activation. Its programs include:

- `simulation`: stand-alone de-excitation events, e.g. `simulation 11B 2 1 1`
- `genie`: adds de-excitation to GENIE output files
- `nuwro`: adds de-excitation to NuWro output files (built when NuWro is installed first,
  as with the command above)

## Prometheus (optional)

```bash
cd ~/hep-stack
bash install.sh --with prometheus
```

Installs the Prometheus neutrino-telescope simulation with everything it is built on:
PROPOSAL (lepton propagation, compiled during the install), LeptonInjector, LeptonWeighter
and Fennel. Prometheus' own photon-propagation models, Hyperion and Olympus, come with it.
Photon propagation with IceCube's `ppc` code is optional in Prometheus and is not installed;
see the [Prometheus documentation](https://github.com/Harvard-Neutrino/prometheus) if you need it.

## How the generators fit together

| Step | Tool | Connection |
|---|---|---|
| Cosmic-ray air showers, atmospheric muons | CORSIKA 8, CRMC, chromo, MCEq | CORSIKA 8 writes particles at an observation level; CRMC and chromo give single interactions; MCEq gives inclusive fluxes |
| Muons reaching the detector | Geant4 | read the CORSIKA muons as primary particles in your Geant4 application |
| Neutrino interactions, GeV scale | GENIE (`gevgen`, `gevgen_atmo`), NuWro | atmospheric fluxes as input tables (MCEq can produce them) |
| Nuclear de-excitation | NucDeEx | added to GENIE or NuWro output files |
| Neutrino interactions in a telescope, up to EeV | gSeaGen, Prometheus (LeptonInjector) | gSeaGen is built on the same GENIE |
| Lepton propagation and light in water or ice | PROPOSAL, Fennel, Hyperion | used inside Prometheus; PROPOSAL also on its own |
| Oscillation weights | OscProb, Prob3++, NuCraft | applied to GENIE or gSeaGen events afterwards |

The codes are joined through their output files rather than linked into one program,
which is how large experiments run them too.

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
3. **GENIE, OscProb, Prob3++ and NuCraft.** These are not available as conda packages (the optional extras are built the same way, by their own scripts in `scripts/`). `scripts/build_genie.sh`, `scripts/build_oscprob.sh` and `scripts/build_prob3pp.sh` compile them inside the environment with the environment's own compilers and libraries, then register conda activation hooks, so `conda activate hep` sets `GENIE`, `OSCPROB_DIR`, `PROB3PP`, `PATH`, `LD_LIBRARY_PATH` and `ROOT_INCLUDE_PATH` for you. `scripts/install_nucraft.sh` copies the bundled NuCraft into the environment and applies its NumPy 2 fix.
4. **Test.** `scripts/check_install.sh` verifies each component.

The full installation is tested automatically on a clean Ubuntu 24.04 machine by
[GitHub Actions](.github/workflows/install-test.yml) on every change and once a week.
The optional extras are tested separately by [extras-test](.github/workflows/extras-test.yml).

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

## License

The scripts in this repository are released under the [MIT License](LICENSE).
ROOT, Geant4, Pythia, LHAPDF, GENIE, OscProb, Prob3++, CORSIKA 8, gSeaGen, APFEL, CRMC, chromo, MCEq, NuWro, NucDeEx, Prometheus, PROPOSAL, LeptonInjector, LeptonWeighter, Fennel and NuCraft are separate projects under their own licenses.
If you use them in published work, cite them as their authors request.
