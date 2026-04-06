#!/bin/sh
# =============================================================================
#  OhMyCriterion Installer
#
#  One-line install:
#    sh -c "$(curl -fsSL https://raw.githubusercontent.com/pdroalves/OhMyCriterion/main/tools/install.sh)"
#
#  Or with wget:
#    sh -c "$(wget -qO- https://raw.githubusercontent.com/pdroalves/OhMyCriterion/main/tools/install.sh)"
#
#  Custom install directory:
#    OMC_DIR=/custom/path sh -c "$(curl -fsSL ...)"
# =============================================================================

set -e

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
OMC_DIR="${OMC_DIR:-$HOME/.ohmycriterion}"
OMC_REMOTE="https://github.com/pdroalves/OhMyCriterion.git"
OMC_RAW_BASE="https://raw.githubusercontent.com/pdroalves/OhMyCriterion/main"
OMC_BRANCH="main"
OMC_MARKER="# Added by OhMyCriterion installer"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
setup_colors() {
    if [ -n "${NO_COLOR-}" ] || [ ! -t 1 ]; then
        FMT_RESET="" FMT_BOLD="" FMT_DIM=""
        FMT_RED="" FMT_GREEN="" FMT_YELLOW="" FMT_MAGENTA="" FMT_CYAN=""
    else
        FMT_RESET="\033[0m"  FMT_BOLD="\033[1m"  FMT_DIM="\033[2m"
        FMT_RED="\033[31m"   FMT_GREEN="\033[32m" FMT_YELLOW="\033[33m"
        FMT_MAGENTA="\033[35m" FMT_CYAN="\033[36m"
    fi
}

fmt_info()    { printf "${FMT_CYAN}[info]${FMT_RESET}  %s\n" "$1"; }
fmt_success() { printf "${FMT_GREEN}[ok]${FMT_RESET}    %s\n" "$1"; }
fmt_warn()    { printf "${FMT_YELLOW}[warn]${FMT_RESET}  %s\n" "$1"; }
fmt_error()   { printf "${FMT_RED}[error]${FMT_RESET} %s\n" "$1" >&2; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

download() {
    if command_exists curl; then
        curl -fsSL "$1"
    elif command_exists wget; then
        wget -qO- "$1"
    else
        fmt_error "Neither curl nor wget found. Cannot download files."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
print_banner() {
    printf "${FMT_MAGENTA}${FMT_BOLD}"
    cat <<'BANNER'
   ____  _     __  __        ____      _ _            _
  / __ \| |__ |  \/  |_   _ / ___|_ __(_) |_ ___ _ __(_) ___  _ __
 | |  | | '_ \| |\/| | | | | |   | '__| | __/ _ \ '__| |/ _ \| '_ \
 | |__| | | | | |  | | |_| | |___| |  | | ||  __/ |  | | (_) | | | |
  \____/|_| |_|_|  |_|\__, |\____|_|  |_|\__\___|_|  |_|\___/|_| |_|
                       |___/
BANNER
    printf "${FMT_CYAN}  Installer${FMT_RESET}\n\n"
}

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
check_dependencies() {
    if ! command_exists git && ! command_exists curl && ! command_exists wget; then
        fmt_error "Need git, curl, or wget to install OhMyCriterion. Please install one and try again."
        exit 1
    fi

    # Warn about bash 4+ (the tool needs it, the installer doesn't)
    if command_exists bash; then
        bash_version=$(bash -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null || echo "0")
        if [ "$bash_version" -lt 4 ] 2>/dev/null; then
            fmt_warn "Bash 4+ is required to run OhMyCriterion. Found bash $bash_version."
            fmt_warn "On macOS, install bash via: brew install bash"
        fi
    else
        fmt_warn "bash not found. OhMyCriterion requires bash 4+ to run."
    fi
}

# ---------------------------------------------------------------------------
# Install / update
# ---------------------------------------------------------------------------
setup_omc_dir() {
    if [ -d "$OMC_DIR" ]; then
        fmt_info "OhMyCriterion already installed at $OMC_DIR. Updating..."
        if [ -d "$OMC_DIR/.git" ]; then
            git -C "$OMC_DIR" pull --ff-only origin "$OMC_BRANCH" || {
                fmt_warn "git pull failed. Re-cloning..."
                rm -rf "$OMC_DIR"
                git clone --depth=1 --branch "$OMC_BRANCH" "$OMC_REMOTE" "$OMC_DIR"
            }
        else
            # Downloaded install — re-download files
            download "$OMC_RAW_BASE/ohmycriterion.sh" > "$OMC_DIR/ohmycriterion.sh"
            download "$OMC_RAW_BASE/LICENSE"           > "$OMC_DIR/LICENSE"
            mkdir -p "$OMC_DIR/tools"
            download "$OMC_RAW_BASE/tools/uninstall.sh" > "$OMC_DIR/tools/uninstall.sh"
        fi
        fmt_success "Updated to latest version."
    else
        fmt_info "Installing OhMyCriterion to $OMC_DIR..."
        if command_exists git; then
            git clone --depth=1 --branch "$OMC_BRANCH" "$OMC_REMOTE" "$OMC_DIR"
        else
            fmt_info "git not found. Downloading files directly..."
            mkdir -p "$OMC_DIR/tools"
            download "$OMC_RAW_BASE/ohmycriterion.sh"   > "$OMC_DIR/ohmycriterion.sh"
            download "$OMC_RAW_BASE/LICENSE"             > "$OMC_DIR/LICENSE"
            download "$OMC_RAW_BASE/tools/uninstall.sh"  > "$OMC_DIR/tools/uninstall.sh"
        fi
        fmt_success "Installed successfully."
    fi

    chmod +x "$OMC_DIR/ohmycriterion.sh"
    if [ -f "$OMC_DIR/tools/uninstall.sh" ]; then
        chmod +x "$OMC_DIR/tools/uninstall.sh"
    fi
}

# ---------------------------------------------------------------------------
# Shell alias setup
# ---------------------------------------------------------------------------
setup_alias() {
    alias_line="alias omc='$OMC_DIR/ohmycriterion.sh'  $OMC_MARKER"
    added=0

    for rcfile in "$HOME/.zshrc" "$HOME/.bashrc"; do
        if [ -f "$rcfile" ]; then
            if grep -qF "$OMC_MARKER" "$rcfile" 2>/dev/null; then
                fmt_info "Alias already present in $(basename "$rcfile"). Skipping."
            else
                printf '\n%s\n' "$alias_line" >> "$rcfile"
                fmt_success "Added omc alias to $(basename "$rcfile")."
                added=1
            fi
        fi
    done

    # If no shell config existed, create .bashrc
    if [ "$added" = 0 ] && ! grep -rqsF "$OMC_MARKER" "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null; then
        printf '%s\n' "$alias_line" >> "$HOME/.bashrc"
        fmt_success "Created ~/.bashrc with omc alias."
    fi
}

# ---------------------------------------------------------------------------
# Success message
# ---------------------------------------------------------------------------
print_success() {
    printf "\n"
    printf "${FMT_GREEN}${FMT_BOLD}OhMyCriterion is ready!${FMT_RESET}\n"
    printf "\n"
    printf "  Installed to: ${FMT_BOLD}%s${FMT_RESET}\n" "$OMC_DIR"
    printf "\n"
    printf "  To start using it, reload your shell:\n"
    printf "    ${FMT_CYAN}exec \$SHELL${FMT_RESET}\n"
    printf "\n"
    printf "  Then run from any Rust project with Criterion benchmarks:\n"
    printf "    ${FMT_CYAN}omc${FMT_RESET}\n"
    printf "\n"
    printf "  Or run directly:\n"
    printf "    ${FMT_CYAN}%s/ohmycriterion.sh${FMT_RESET}\n" "$OMC_DIR"
    printf "\n"
    printf "  To uninstall:\n"
    printf "    ${FMT_CYAN}%s/tools/uninstall.sh${FMT_RESET}\n" "$OMC_DIR"
    printf "\n"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [ -z "${HOME-}" ]; then
        echo "Error: \$HOME is not set. Cannot determine install directory." >&2
        exit 1
    fi

    setup_colors
    print_banner
    check_dependencies
    setup_omc_dir
    setup_alias
    print_success
}

# Run main at the end so a truncated download does not execute partial code
main "$@"
