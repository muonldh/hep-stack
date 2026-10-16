#!/bin/bash
# Builds CORSIKA 8 (open-source particle cascade framework, KIT,
# gitlab.iap.kit.edu/AirShowerPhysics/corsika) inside the active conda environment.
#
# CORSIKA 8 fetches its own C++ dependencies (Boost, Eigen, Arrow, PROPOSAL, ...)
# with the Conan package manager. Conan's cache is kept inside the environment
# ($CONDA_PREFIX/opt/conan2), so nothing is written to your home folder.
# The first build compiles those dependencies too and can take one to two hours.
#
#   bash scripts/build_corsika8.sh            build (skips if already built)
#   bash scripts/build_corsika8.sh --rebuild  delete and rebuild
#
# Environment variables:
#   CORSIKA8_VERSION  git tag or branch to build (default: the repository's default branch)
#   JOBS              parallel compile jobs (default: number of cores)

set -eo pipefail

CORSIKA8_VERSION="${CORSIKA8_VERSION:-}"
JOBS="${JOBS:-$(nproc)}"
REBUILD=0
[ "${1:-}" = "--rebuild" ] && REBUILD=1

if [ -z "${CONDA_PREFIX:-}" ] || [ "${CONDA_DEFAULT_ENV:-base}" = "base" ]; then
    echo "Activate the HEP environment first:  conda activate hep"
    exit 1
fi

P="$CONDA_PREFIX"
SRC="$P/opt/corsika8-src"      # source, including the physics data (CORSIKA_DATA)
BUILD="$P/opt/corsika8-build"  # build tree (kept: the installed CMake files may refer to it)
DIR="$P/opt/corsika8"          # installed framework
STAMP="$DIR/.built"

# Fixes applied after the build (and to existing installs, so a plain
# 'bash install.sh' upgrades older CORSIKA 8 installations too):
#  1. CORSIKA 8 carries its own Pythia 8, whose data files must match it. The env's
#     PYTHIA8DATA points at conda's Pythia 8 (a different version), which makes the
#     shipped programs abort. Each program in bin/ becomes a small wrapper that
#     unsets PYTHIA8DATA before starting the real program (kept in libexec/).
#  2. Projects that use find_package(corsika), such as CORSIKA 8's own examples,
#     cannot see the dependencies Conan built for it. c8_shim.cmake, loaded at the
#     top of corsikaConfig.cmake, points CMake at them (except Conan's Boost 1.85,
#     which lacks 'filesystem' and clashes with conda's Boost) and defines the Boost
#     and BZip2 targets they expect.
c8_postinstall() {
    local dep="$DIR/lib/cmake/dependencies" shim="$DIR/share/hep-stack/c8_shim.cmake"
    local exe name f n cfg

    mkdir -p "$DIR/libexec"
    for exe in "$DIR"/bin/*; do
        [ -f "$exe" ] && [ -x "$exe" ] || continue
        [ "$(head -c 4 "$exe" | tail -c 3)" = "ELF" ] || continue   # already a wrapper
        name="$(basename "$exe")"
        mv "$exe" "$DIR/libexec/$name"
        printf '#!/bin/bash\n# hep-stack wrapper: CORSIKA 8 uses its own Pythia 8, not conda'"'"'s (see PYTHIA8DATA).\nunset PYTHIA8DATA\nexec "%s" "$@"\n' \
            "$DIR/libexec/$name" > "$exe"
        chmod +x "$exe"
    done

    mkdir -p "$(dirname "$shim")"
    {
        echo "# Written by hep-stack (scripts/build_corsika8.sh). Loaded by corsikaConfig.cmake."
        for f in "$dep"/*Config.cmake "$dep"/*-config.cmake; do
            [ -e "$f" ] || continue
            n="$(basename "$f")"; n="${n%Config.cmake}"; n="${n%-config.cmake}"
            case "$n" in Boost*|boost*) continue ;; esac
            printf 'if(NOT DEFINED %s_DIR)\n  set(%s_DIR "%s")\nendif()\n' "$n" "$n" "$dep"
        done
        # shellcheck disable=SC2016
        printf '%s\n' \
            'find_package(Boost REQUIRED COMPONENTS serialization)' \
            'find_package(BZip2 REQUIRED)' \
            'foreach(_c8_target boost::boost Boost::math)' \
            '  if(NOT TARGET ${_c8_target})' \
            '    add_library(${_c8_target} INTERFACE IMPORTED)' \
            '    target_link_libraries(${_c8_target} INTERFACE Boost::headers)' \
            '  endif()' \
            'endforeach()'
    } > "$shim"

    find "$BUILD" "$DIR" -name corsikaConfig.cmake 2>/dev/null | while read -r cfg; do
        grep -q 'c8_shim.cmake' "$cfg" || sed -i "1i include(\"$shim\")" "$cfg"
    done
    echo "CORSIKA 8 fixes applied (Pythia wrappers, $shim)."
}

if [ -f "$STAMP" ] && [ "$REBUILD" = 0 ]; then
    c8_postinstall
    echo "CORSIKA 8 already built in $DIR ($(cat "$STAMP")). Use --rebuild to redo it."
    exit 0
fi

export CC="${CC:-$P/bin/x86_64-conda-linux-gnu-gcc}"
export CXX="${CXX:-$P/bin/x86_64-conda-linux-gnu-c++}"
export FC="${FC:-$P/bin/x86_64-conda-linux-gnu-gfortran}"
export CONAN_HOME="$P/opt/conan2"

for tool in conan cmake git git-lfs "$CC" "$CXX" "$FC"; do
    command -v "$tool" >/dev/null || { echo "Missing $tool. Run 'bash install.sh' to update the environment."; exit 1; }
done

step() { printf '\n--- CORSIKA 8: %s ---\n' "$*"; }

rm -rf "$SRC" "$BUILD" "$DIR"
mkdir -p "$P/opt"

step "downloading source and physics data (several GB)"
BRANCH_ARGS=()
[ -n "$CORSIKA8_VERSION" ] && BRANCH_ARGS=(--branch "$CORSIKA8_VERSION")
# The KIT GitLab server sometimes resets long connections. Retry a few times.
ok=0
for attempt in 1 2 3 4 5; do
    rm -rf "$SRC"
    if git -c advice.detachedHead=false clone --recursive --depth 1 --shallow-submodules \
        "${BRANCH_ARGS[@]}" https://gitlab.iap.kit.edu/AirShowerPhysics/corsika.git "$SRC"; then
        ok=1; break
    fi
    echo "Download attempt $attempt failed; retrying in 30 s..."
    sleep 30
done
[ "$ok" = 1 ] || { echo "ERROR: could not download CORSIKA 8 from gitlab.iap.kit.edu. Check the connection and try again."; exit 1; }
# Large data files may be stored with Git LFS. Fetch them without touching your
# global git configuration (does nothing if the repository does not use LFS).
git -C "$SRC" lfs install --local >/dev/null
git -C "$SRC" lfs pull || true
git -C "$SRC" submodule foreach --recursive 'git lfs install --local >/dev/null && git lfs pull || true'

COMMIT="$(git -C "$SRC" rev-parse --short HEAD)"
echo "Building commit $COMMIT (${CORSIKA8_VERSION:-default branch})"
echo "Most recent release tags:"
git ls-remote --tags --refs https://gitlab.iap.kit.edu/AirShowerPhysics/corsika.git \
    | awk -F/ '{print "  " $3}' | sort -V | tail -n 5 || true

step "Conan profile (compiler: $("$CXX" -dumpfullversion))"
conan profile detect --exist-ok

# GCC 15 compiles C as C23 by default, where an old-style declaration 'f()' means
# "no arguments". Some dependencies Conan builds from source (e.g. termcap 1.3.1)
# rely on the older meaning, so build their C code as C17. This setting lives in
# Conan's global.conf, so it applies to every profile, including CORSIKA's own.
if ! grep -qs 'tools.build:cflags' "$CONAN_HOME/global.conf"; then
    echo 'tools.build:cflags=["-std=gnu17"]' >> "$CONAN_HOME/global.conf"
fi

# Make every package Conan builds use the environment's compilers. Without this,
# Conan's Boost recipe picks the system compiler when one matching the version
# exists (e.g. /usr/bin/g++-15 on Ubuntu 26.04). That compiles against the
# system's newer C library, and linking then fails with "undefined reference to
# statx / __isoc23_sscanf / getrandom".
sed -i '/^tools.build:compiler_executables/d' "$CONAN_HOME/global.conf"
echo "tools.build:compiler_executables={\"c\": \"$CC\", \"cpp\": \"$CXX\", \"fortran\": \"${FC:-$CONDA_PREFIX/bin/x86_64-conda-linux-gnu-gfortran}\"}" \
    >> "$CONAN_HOME/global.conf"

mkdir -p "$BUILD"
cd "$BUILD"

# CORSIKA 8's conan-install.sh needs the source folder passed with
# --source-directory. It runs 'conan install' and writes the generated CMake files
# to <source>/conan_cmake, which the configure step below reads.
CONAN_OUT="$SRC/conan_cmake"

step "installing dependencies with Conan (compiles them the first time)"
"$SRC/conan-install.sh" --source-directory "$SRC" --release

[ -f "$CONAN_OUT/conan_toolchain.cmake" ] || {
    echo "ERROR: Conan did not create $CONAN_OUT/conan_toolchain.cmake."
    exit 1
}

# Same CMake settings as CORSIKA 8's own corsika-cmake.sh helper, plus an install
# location inside the environment. Build type must match the Conan step (Release).
step "configuring"
cmake -S "$SRC" -B "$BUILD" \
    -DCONAN_CMAKE_DIR="$CONAN_OUT" \
    -DCMAKE_TOOLCHAIN_FILE="$CONAN_OUT/conan_toolchain.cmake" \
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DIR"

step "compiling with $JOBS jobs"
cmake --build "$BUILD" -j "$JOBS"
cmake --install "$BUILD"

[ -d "$DIR" ] || { echo "ERROR: nothing was installed in $DIR."; exit 1; }
echo "Installed:"
find "$DIR" -maxdepth 2 -type d | sed "s|$DIR|  \$CORSIKA8_DIR|"

# Activation hooks. corsika_DIR (the build tree, as in CORSIKA 8's own instructions)
# lets your CMake projects find CORSIKA 8; CORSIKA_DATA points at the
# interaction-model tables it reads at run time.
mkdir -p "$P/etc/conda/activate.d" "$P/etc/conda/deactivate.d"
cat > "$P/etc/conda/activate.d/corsika8.sh" <<'EOF'
export CORSIKA8_DIR="$CONDA_PREFIX/opt/corsika8"
export corsika_DIR="$CONDA_PREFIX/opt/corsika8-build"
export CORSIKA_DATA="$CONDA_PREFIX/opt/corsika8-src/modules/data"
export CONAN_HOME="$CONDA_PREFIX/opt/conan2"
export CMAKE_PREFIX_PATH="$CORSIKA8_DIR${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
if [ -d "$CORSIKA8_DIR/bin" ]; then export PATH="$CORSIKA8_DIR/bin:$PATH"; fi
EOF
cat > "$P/etc/conda/deactivate.d/corsika8.sh" <<'EOF'
if [ -n "${CORSIKA8_DIR:-}" ]; then
    PATH=":$PATH:"; PATH="${PATH//:$CORSIKA8_DIR\/bin:/:}"; PATH="${PATH#:}"; export PATH="${PATH%:}"
    _c8=":${CMAKE_PREFIX_PATH-}:"; _c8="${_c8//:$CORSIKA8_DIR:/:}"; _c8="${_c8#:}"; _c8="${_c8%:}"
    if [ -n "$_c8" ]; then export CMAKE_PREFIX_PATH="$_c8"; else unset CMAKE_PREFIX_PATH; fi
    unset _c8
fi
unset CORSIKA8_DIR corsika_DIR CORSIKA_DATA CONAN_HOME
EOF

c8_postinstall
echo "commit $COMMIT, built $(date +%F)" > "$STAMP"
echo "CORSIKA 8 ($COMMIT) installed in $DIR"
