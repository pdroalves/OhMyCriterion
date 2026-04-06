#!/bin/sh
# =============================================================================
#  OhMyCriterion Uninstaller
#
#  Usage:
#    ~/.ohmycriterion/tools/uninstall.sh
#
#  Or remotely:
#    sh -c "$(curl -fsSL https://raw.githubusercontent.com/pdroalves/OhMyCriterion/main/tools/uninstall.sh)"
#
#  Pass --yes to skip confirmation prompt.
# =============================================================================

set -e

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
OMC_DIR="${OMC_DIR:-$HOME/.ohmycriterion}"
OMC_MARKER="# Added by OhMyCriterion installer"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
setup_colors() {
    if [ -n "${NO_COLOR-}" ] || [ ! -t 1 ]; then
        FMT_RESET="" FMT_BOLD=""
        FMT_RED="" FMT_GREEN="" FMT_YELLOW="" FMT_CYAN=""
    else
        FMT_RESET="\033[0m"  FMT_BOLD="\033[1m"
        FMT_RED="\033[31m"   FMT_GREEN="\033[32m"
        FMT_YELLOW="\033[33m" FMT_CYAN="\033[36m"
    fi
}

fmt_info()    { printf "${FMT_CYAN}[info]${FMT_RESET}  %s\n" "$1"; }
fmt_success() { printf "${FMT_GREEN}[ok]${FMT_RESET}    %s\n" "$1"; }
fmt_warn()    { printf "${FMT_YELLOW}[warn]${FMT_RESET}  %s\n" "$1"; }
fmt_error()   { printf "${FMT_RED}[error]${FMT_RESET} %s\n" "$1" >&2; }

# ---------------------------------------------------------------------------
# Confirm
# ---------------------------------------------------------------------------
confirm_uninstall() {
    if [ "$FORCE" = 1 ]; then
        return 0
    fi

    printf "Are you sure you want to uninstall OhMyCriterion? (y/N) "
    read -r reply
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) echo "Aborted."; exit 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# Remove aliases from shell configs
# ---------------------------------------------------------------------------
remove_aliases() {
    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rcfile" ] && grep -qF "$OMC_MARKER" "$rcfile" 2>/dev/null; then
            tmpfile=$(mktemp)
            grep -vF "$OMC_MARKER" "$rcfile" > "$tmpfile"
            mv "$tmpfile" "$rcfile"
            fmt_success "Removed omc alias from $(basename "$rcfile")."
        fi
    done
}

# ---------------------------------------------------------------------------
# Remove install directory
# ---------------------------------------------------------------------------
remove_install_dir() {
    if [ -d "$OMC_DIR" ]; then
        rm -rf "$OMC_DIR"
        fmt_success "Removed $OMC_DIR."
    else
        fmt_warn "$OMC_DIR does not exist. Nothing to remove."
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [ -z "${HOME-}" ]; then
        echo "Error: \$HOME is not set." >&2
        exit 1
    fi

    FORCE=0
    for arg in "$@"; do
        case "$arg" in
            --yes|--force|-y) FORCE=1 ;;
        esac
    done

    setup_colors
    confirm_uninstall
    remove_aliases
    remove_install_dir

    printf "\n"
    printf "${FMT_GREEN}${FMT_BOLD}OhMyCriterion has been uninstalled.${FMT_RESET}\n"
    printf "\n"
    printf "  Restart your shell or run:\n"
    printf "    ${FMT_CYAN}exec \$SHELL${FMT_RESET}\n"
    printf "\n"
}

main "$@"
