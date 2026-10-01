#!/bin/bash
# Helper sourced by the build scripts. Not meant to be run directly.
#
# write_env_hooks NAME VAR [LIBDIR] [INCDIR]
#   Writes conda activation and deactivation hooks for a package installed in
#   $CONDA_PREFIX/opt/NAME:
#     - exports VAR pointing at the package directory
#     - prepends LIBDIR (relative to it) to LD_LIBRARY_PATH, if given
#     - prepends INCDIR (relative to it) to ROOT_INCLUDE_PATH, if given, so ROOT
#       and PyROOT can find the headers
#   Use "." for LIBDIR or INCDIR to mean the package directory itself.
#   Deactivation removes exactly those entries again, so the hooks of several
#   packages can be stacked in any order.

write_env_hooks() {
    local name="$1" var="$2" libdir="${3:-}" incdir="${4:-}"
    local libpath="\$$var/$libdir" incpath="\$$var/$incdir"
    [ "$libdir" = "." ] && libpath="\$$var"
    [ "$incdir" = "." ] && incpath="\$$var"
    local act="$CONDA_PREFIX/etc/conda/activate.d/$name.sh"
    local deact="$CONDA_PREFIX/etc/conda/deactivate.d/$name.sh"
    mkdir -p "$(dirname "$act")" "$(dirname "$deact")"

    {
        echo "export $var=\"\$CONDA_PREFIX/opt/$name\""
        if [ -n "$libdir" ]; then
            echo "export LD_LIBRARY_PATH=\"$libpath\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
        fi
        if [ -n "$incdir" ]; then
            echo "export ROOT_INCLUDE_PATH=\"$incpath\${ROOT_INCLUDE_PATH:+:\$ROOT_INCLUDE_PATH}\""
        fi
    } > "$act"

    {
        cat <<'EOF'
_hep_path_remove() {
    eval "_hep_v=\":\${$1-}:\""
    _hep_v="${_hep_v//:$2:/:}"; _hep_v="${_hep_v#:}"; _hep_v="${_hep_v%:}"
    if [ -n "$_hep_v" ]; then export "$1=$_hep_v"; else unset "$1"; fi
    unset _hep_v
}
EOF
        if [ -n "$libdir" ]; then
            echo "_hep_path_remove LD_LIBRARY_PATH \"$libpath\""
        fi
        if [ -n "$incdir" ]; then
            echo "_hep_path_remove ROOT_INCLUDE_PATH \"$incpath\""
        fi
        echo "unset $var"
        echo "unset -f _hep_path_remove"
    } > "$deact"
}

# Registers DIR on the Python path of the active environment (via a .pth file).
add_python_path() {
    local name="$1" dir="$2" site
    site="$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
    echo "$dir" > "$site/$name.pth"
}
