# hep-stack

[![install-test](https://github.com/muonldh/hep-stack/actions/workflows/install-test.yml/badge.svg)](https://github.com/muonldh/hep-stack/actions/workflows/install-test.yml)
[![extras-test](https://github.com/muonldh/hep-stack/actions/workflows/extras-test.yml/badge.svg)](https://github.com/muonldh/hep-stack/actions/workflows/extras-test.yml)

One command to install a complete high energy physics software environment on Linux or Windows (WSL):
ROOT, Geant4, Pythia 8, LHAPDF, the GENIE neutrino event generator, the OscProb, Prob3++ and NuCraft
oscillation codes, and the Scikit-HEP Python analysis tools.

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
| [CORSIKA 7](https://www.iap.kit.edu/corsika/) (7.8050), optional | Air showers and atmospheric muons | needs your own KIT password; compiled by `scripts/build_corsika.sh` |
| [CORSIKA 8](https://gitlab.iap.kit.edu/AirShowerPhysics/corsika), optional | Open-source air showers and atmospheric muons | `bash install.sh --with corsika8`; compiled by `scripts/build_corsika8.sh` |
| [gSeaGen](https://git.km3net.de/opensource/gseagen), optional | GENIE-based generator for neutrino telescopes, up to ultra-high energies | `bash install.sh --with gseagen`; adds [APFEL](https://github.com/scarrazza/apfel) 3.1.1 and builds GENIE with it |
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
11 passed, 0 failed
```

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

## CORSIKA 7 (optional)

CORSIKA simulates cosmic-ray air showers and gives the muons (and other particles)
arriving at the surface. It is not open source, so `install.sh` does not install it
and this repository does not contain it. Each user needs their own download password:

1. Register as described on the [CORSIKA download page](https://www.iap.kit.edu/corsika/79.php).
   KIT sends you the password by e-mail. Do not share the password or the code;
   KIT asks new users to register themselves.
2. Build it inside the environment (about 10 minutes):

   ```bash
   conda activate hep
   cd ~/hep-stack
   bash scripts/build_corsika.sh
   ```

   It asks for the password, downloads CORSIKA 7.8050, and starts CORSIKA's own
   configuration tool, `coconut`. The script prints suggested answers; for muon
   production SIBYLL 2.3e (high energy) with UrQMD (low energy) is a good default.
   If the download fails, fetch `corsika-78050.tar.gz` in a browser and run
   `bash scripts/build_corsika.sh ~/Downloads/corsika-78050.tar.gz`.

3. Test run: 100 proton showers from 100 GeV to 10 TeV, muons only (no EM cascade):

   ```bash
   conda activate hep
   mkdir -p ~/corsika_test && cd ~/corsika_test
   cat > muons.inp <<EOF
   RUNNR   1
   EVTNR   1
   NSHOW   100
   PRMPAR  14
   ESLOPE  -2.7
   ERANGE  1.E2  1.E4
   THETAP  0.  70.
   PHIP    -180.  180.
   SEED    1  0  0
   SEED    2  0  0
   SEED    3  0  0
   OBSLEV  0.
   ECUTS   0.3  0.3  0.003  0.003
   ELMFLG  F  F
   MUMULT  T
   MAXPRT  0
   DATDIR  $CORSIKA_RUN/
   DIRECT  ./
   EXIT
   EOF
   $CORSIKA_RUN/corsika78050Linux_SIBYLL_urqmd < muons.inp > muons.lst
   tail -n 20 muons.lst
   ```

   The particles at ground level are in the binary file `DAT000001`; `muons.lst` is the run log.
   In Python you can read `DAT000001` with [corsikaio](https://github.com/cta-observatory/pycorsikaio)
   (`pip install corsikaio`). For a real study, set `OBSLEV` (cm) and `MAGNET` (µT) for your
   site and `NSHOW`, `ERANGE` and the primaries for your flux model; all keywords are
   described in Section 4 of `$CORSIKA_DIR/doc/CORSIKA_GUIDE7.8050.pdf`.

CORSIKA gives muons at the surface. Underground detectors such as JUNO still need the muons
transported through the rock overburden with a separate code.

## CORSIKA 8 (optional)

CORSIKA 8 is the open-source successor of CORSIKA 7 (GPLv3, no registration needed).
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
so existing GENIE results are unaffected), downloads `HERAPDF15NLO_EIG`, and builds gSeaGen.
After `conda activate hep`, `gSeaNuEvGen -h` lists all options.

Like any GENIE application, gSeaGen needs cross-section splines for the tune you use.
For ultra-high energies that is `GHE19_00b_00_000`; the first run with it also computes
the structure-function tables with APFEL, which takes a while once.

## How the generators fit together

| Step | Tool | Connection |
|---|---|---|
| Cosmic-ray air showers, atmospheric muons | CORSIKA 7 or 8 | particles at an observation level, written to file |
| Muons reaching the detector | Geant4 | read the CORSIKA muons as primary particles in your Geant4 application |
| Neutrino interactions, GeV scale | GENIE (`gevgen`, `gevgen_atmo`) | atmospheric fluxes as input tables |
| Neutrino interactions in a telescope, up to EeV | gSeaGen | built on the same GENIE |
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
3. **GENIE, OscProb, Prob3++ and NuCraft.** These are not available as conda packages. `scripts/build_genie.sh`, `scripts/build_oscprob.sh` and `scripts/build_prob3pp.sh` compile them inside the environment with the environment's own compilers and libraries, then register conda activation hooks, so `conda activate hep` sets `GENIE`, `OSCPROB_DIR`, `PROB3PP`, `PATH`, `LD_LIBRARY_PATH` and `ROOT_INCLUDE_PATH` for you. `scripts/install_nucraft.sh` copies the bundled NuCraft into the environment and applies its NumPy 2 fix.
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
ROOT, Geant4, Pythia, LHAPDF, GENIE, OscProb, Prob3++, CORSIKA, gSeaGen, APFEL and NuCraft are separate projects under their own licenses.
If you use them in published work, cite them as their authors request.
