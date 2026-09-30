#!/bin/bash
# Installs NuCraft (Wallraff & Wiebusch, Comput. Phys. Commun. 197 (2015) 185)
# into the active conda environment from the copy bundled in extern/nucraft/.
#
# NuCraft is pure Python, so it is copied into the environment and registered
# with a .pth file; 'import NuCraft' then works whenever the environment is active.
# The bundled original is never modified; the compatibility fix below is applied
# to the installed copy only.

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_DIR/extern/nucraft"

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

if [ ! -f "$SRC/NuCraft.py" ]; then
    echo "NuCraft is not bundled (extern/nucraft/NuCraft.py not found). Skipping."
    exit 0
fi

DEST="$CONDA_PREFIX/opt/nucraft"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$SRC/." "$DEST/"

# NumPy 2 compatibility fix.
# NuCraft.py does 'from numpy import *'. Since NumPy 2.0 this also imports
# numpy.bool, which replaces Python's built-in bool inside NuCraft, so checks
# like 'assert type(vacuum) is bool' always fail. When NuCraft was written,
# numpy.bool was the built-in bool itself, so restoring the built-in right after
# the import reproduces the original behaviour exactly.
python - "$DEST/NuCraft.py" <<'EOF'
import re, sys
path = sys.argv[1]
src = open(path).read()
marker = "# hep-stack: NumPy 2 compatibility"
if marker not in src:
    fix = ("\nimport builtins as _hep_builtins  " + marker +
           "\nbool = _hep_builtins.bool\n")
    src, n = re.subn(r"^from numpy import \*[ \t]*$", lambda m: m.group(0) + fix,
                     src, count=1, flags=re.M)
    open(path, "w").write(src)
    print("Applied NumPy 2 compatibility fix" if n else
          "No 'from numpy import *' found; no fix needed")
EOF

SITE="$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
echo "$DEST" > "$SITE/nucraft.pth"

python - <<'EOF'
import builtins
import NuCraft
assert getattr(NuCraft, "bool", builtins.bool) is builtins.bool, "bool fix not active"
print("NuCraft installed:", NuCraft.__file__)
EOF
