#!/usr/bin/env bash
# =============================================================================
# install_magic.sh — Install Magic VLSI Layout Tool from source
#
# Reference:
#   http://opencircuitdesign.com/magic/install.html
#   https://github.com/RTimothyEdwards/magic
#
# Compatibility:
#   Tested on Ubuntu 22.04 / 24.04, Fedora 40+, Arch Linux, macOS (Homebrew)
#   Automatically handles GCC 14+ incompatibilities with Magic's legacy C code.
#
# Usage:
#   chmod +x install_magic.sh
#   ./install_magic.sh [OPTIONS]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults — override via environment variables or command-line flags
# ---------------------------------------------------------------------------
MAGIC_VERSION="${MAGIC_VERSION:-}"           # Git tag to check out (blank = auto)
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
BUILD_DIR="${BUILD_DIR:-/tmp/magic-build}"
CLONE_URL="https://github.com/RTimothyEdwards/magic.git"

# Stable tag known to work well as a baseline on older compilers.
# On GCC 14+ this tag is combined with source patches (see apply_patches).
STABLE_TAG="magic-8.3.470"

# ---------------------------------------------------------------------------
# Colour output
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; RESET=''
fi

info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }
section() { echo -e "\n${BOLD}${CYAN}>>> $* ${RESET}"; }
die()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || die "'$1' is required but not found. Install it and re-run."
}

# ---------------------------------------------------------------------------
# Package manager detection
# ---------------------------------------------------------------------------
detect_pkg_manager() {
    if   command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf     &>/dev/null; then echo "dnf"
    elif command -v yum     &>/dev/null; then echo "yum"
    elif command -v pacman  &>/dev/null; then echo "pacman"
    elif command -v brew    &>/dev/null; then echo "brew"
    else echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# Install system dependencies
#
# Required packages:
#   git, make, gcc         — build toolchain
#   m4, python3            — Magic build system requirements
#   libx11-dev             — X11 windowing (Xlib.h)
#   tcl-dev, tk-dev        — Tcl/Tk interpreter (strongly recommended;
#                            enables the GUI frontend and scripting)
#   libcairo2-dev          — Cairo graphics backend (magic -d XR)
#   mesa / libgl / libglu  — OpenGL graphics backend (magic -d OGL)
#   zlib                   — compressed GDS/mag file support
#   libncurses-dev         — terminal handling (non-Tcl build only)
# ---------------------------------------------------------------------------
install_dependencies() {
    section "Installing system dependencies"
    local pm
    pm=$(detect_pkg_manager)
    info "Package manager: $pm"

    case "$pm" in
        apt)
            sudo apt-get update -y
            sudo apt-get install -y \
                git build-essential \
                m4 python3 \
                libx11-dev \
                tcl-dev tk-dev \
                libcairo2-dev \
                mesa-common-dev libgl-dev libglu1-mesa-dev \
                zlib1g-dev \
                libncurses-dev
            ;;
        dnf|yum)
            sudo "$pm" groupinstall -y "Development Tools"
            sudo "$pm" install -y \
                git m4 python3 \
                libX11-devel \
                tcl-devel tk-devel \
                cairo-devel \
                mesa-libGL-devel mesa-libGLU-devel \
                zlib-devel \
                ncurses-devel
            ;;
        pacman)
            sudo pacman -Sy --noconfirm \
                git base-devel m4 python \
                libx11 tcl tk cairo \
                mesa glu zlib ncurses
            ;;
        brew)
            brew install git m4 python tcl-tk cairo mesa-glu
            warn "X11 on macOS requires XQuartz — https://www.xquartz.org/"
            ;;
        *)
            warn "Unrecognised package manager. Install these manually and re-run:"
            warn "  git make gcc m4 python3 libx11-dev tcl-dev tk-dev"
            warn "  libcairo2-dev mesa-common-dev libgl-dev libglu1-mesa-dev"
            warn "  zlib1g-dev libncurses-dev"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# GCC version detection and build flag selection
#
# Magic is written in pre-ANSI / K&R-era C and its source is incompatible
# with GCC 14's stricter defaults in two ways:
#
#   Problem 1 — K&R empty parameter lists
#     Header declarations such as  extern void WindMove();  use old-style
#     K&R syntax where () means "unspecified parameters".  GCC 14 changed
#     this to mean (void) — zero parameters — so any call that passes
#     arguments produces: "error: too many arguments to function".
#     Compiling with -std=gnu11 restores the permissive K&R interpretation.
#
#   Problem 2 — 'bool' typedef conflict
#     utils/magic.h contains  typedef unsigned char bool;
#     GCC 14 defaults to -std=gnu17, which adopts the C23 rule that 'bool'
#     is a keyword, making the typedef illegal:
#     "error: 'bool' cannot be defined via 'typedef'"
#     Compiling with -std=gnu11 keeps 'bool' as a plain identifier.
#
# Both problems are resolved together by CFLAGS="-std=gnu11".
# ---------------------------------------------------------------------------
GCC_MAJOR=0
EXTRA_CFLAGS=""

detect_gcc_version() {
    GCC_MAJOR=$(gcc -dumpversion 2>/dev/null | cut -d. -f1)
    info "GCC version: $GCC_MAJOR"
}

select_build_flags() {
    detect_gcc_version
    if [[ "$GCC_MAJOR" -ge 14 ]]; then
        EXTRA_CFLAGS="-std=gnu11"
        info "Applying CFLAGS='$EXTRA_CFLAGS' for GCC $GCC_MAJOR compatibility"
    fi
}

# ---------------------------------------------------------------------------
# Version / tag selection
#
# When no explicit tag is requested and GCC 14+ is detected, the script
# defaults to a known-stable tag rather than the tip of master, which may
# carry additional unreleased issues.  The user can always override this
# with --tag.
# ---------------------------------------------------------------------------
resolve_version() {
    if [[ -n "$MAGIC_VERSION" ]]; then
        info "Using requested version: $MAGIC_VERSION"
        return
    fi

    if [[ "$GCC_MAJOR" -ge 14 ]]; then
        MAGIC_VERSION="$STABLE_TAG"
        info "GCC $GCC_MAJOR detected — defaulting to stable tag: $MAGIC_VERSION"
        info "(Override with: --tag master  or  --tag <other-tag>)"
    else
        info "Using latest master branch"
    fi
}

# ---------------------------------------------------------------------------
# Clone or update the Magic source repository
# ---------------------------------------------------------------------------
fetch_source() {
    section "Fetching Magic source"

    if [[ -d "$BUILD_DIR/.git" ]]; then
        info "Existing clone found — updating …"
        git -C "$BUILD_DIR" fetch --all --tags
        git -C "$BUILD_DIR" checkout master
        git -C "$BUILD_DIR" pull
    else
        info "Cloning from $CLONE_URL into $BUILD_DIR …"
        git clone "$CLONE_URL" "$BUILD_DIR"
    fi

    if [[ -n "$MAGIC_VERSION" ]]; then
        info "Checking out: $MAGIC_VERSION"
        git -C "$BUILD_DIR" checkout "$MAGIC_VERSION"
    fi
}

# ---------------------------------------------------------------------------
# Source patches for modern glibc / GCC 14 compatibility
#
# The SVR3 terminal I/O API (termio.h, struct termio, TCGETA, TCSETAF) was
# removed from modern glibc.  Magic's source uses this API in two places.
# Both are mechanically replaced with their POSIX equivalents (termios.h).
#
#   Patch 1 — utils/magsgtty.h
#     Replaces:  #include <termio.h>
#     With:      #include <termios.h>
#     Rationale: termio.h does not exist on Linux with glibc 2.28+.
#                termios.h is the POSIX standard header and provides all
#                the same types and constants.
#
#   Patch 2 — textio/txInput.c
#     Replaces:  struct termio   →  struct termios
#                TCGETA          →  TCGETS
#                TCSETAF         →  TCSETSF
#     Adds:      #include <termios.h>   — MUST appear before any forward
#                #include <sys/ioctl.h>   declarations that use struct termios.
#
#     Rationale: txInput.c contains forward declarations of functions whose
#                parameter lists use  struct termios *  before <termios.h> is
#                included. GCC sees "struct termios" for the first time inside
#                a parameter list and creates a declaration-scoped incomplete
#                type that is invisible outside that declaration. Every
#                subsequent use of struct termios then fails with:
#                  "invalid use of undefined type 'struct termios'"
#                The only reliable fix is to inject both headers at the very
#                top of the file so the struct is fully defined before any
#                forward declaration is parsed.
#
#                struct termios has the same fields as struct termio
#                (c_iflag, c_oflag, c_cflag, c_lflag, c_cc[]) so no
#                field-level changes are required.
#                TCGETS / TCSETSF are the Linux ioctl equivalents of the
#                SVR3 TCGETA / TCSETAF constants.
#
# All patches are guarded so re-running the script is safe (idempotent).
# ---------------------------------------------------------------------------
apply_patches() {
    section "Applying source compatibility patches"

    # --- Patch 1: utils/magsgtty.h ---
    local magsgtty="$BUILD_DIR/utils/magsgtty.h"
    if [[ -f "$magsgtty" ]]; then
        if grep -q '#include <termio.h>' "$magsgtty"; then
            info "Patch 1: utils/magsgtty.h — <termio.h> → <termios.h>"
            sed -i \
                's|#include <termio.h>|#include <termios.h>  /* patched: termio.h removed from modern glibc */|g' \
                "$magsgtty"
        else
            info "Patch 1: utils/magsgtty.h already patched — skipping"
        fi
    else
        warn "Patch 1: utils/magsgtty.h not found — skipping"
    fi

    # --- Patch 2: textio/txInput.c ---
    local txinput="$BUILD_DIR/textio/txInput.c"
    if [[ -f "$txinput" ]]; then
        local needs_patch=false
        grep -q 'struct termio[^s]' "$txinput" && needs_patch=true
        grep -q '\bTCGETA\b'        "$txinput" && needs_patch=true
        grep -q '\bTCSETAF\b'       "$txinput" && needs_patch=true

        if [[ "$needs_patch" == true ]]; then
            info "Patch 2: textio/txInput.c — SVR3 termio → POSIX termios"

            # struct termio → struct termios (word boundary avoids double-patching)
            sed -i 's/\bstruct termio\b/struct termios/g' "$txinput"

            # TCGETA → TCGETS  (get terminal attributes)
            sed -i 's/\bTCGETA\b/TCGETS/g'   "$txinput"

            # TCSETAF → TCSETSF  (set attributes, flush pending I/O)
            sed -i 's/\bTCSETAF\b/TCSETSF/g' "$txinput"

            # Inject termios.h + sys/ioctl.h at the very top of the file,
            # before any other #include. This is critical: txInput.c has
            # forward declarations with  struct termios *  parameters before
            # any include of termios.h, causing GCC to create a scoped
            # incomplete type that is invisible to the rest of the file.
            # Placing these includes first ensures the struct is fully defined
            # before any forward declaration is parsed.
            if ! grep -q '#include <termios.h>' "$txinput"; then
                info "Patch 2: injecting <termios.h> + <sys/ioctl.h> at top of txInput.c"
                # Prepend both headers before the first line of the file
                sed -i '1s|^|#include <termios.h>\n#include <sys/ioctl.h>\n/* patched: termios headers injected before forward decls for GCC 14+ */\n\n|' \
                    "$txinput"
            fi
        else
            info "Patch 2: textio/txInput.c already patched — skipping"
        fi
    else
        warn "Patch 2: textio/txInput.c not found — skipping"
    fi
}

# ---------------------------------------------------------------------------
# Configure, build, and install
#
# NOTE: Do NOT use make -j (parallel build).  Magic's build scripts generate
# intermediate files that are not thread-safe and will corrupt the build if
# multiple jobs run simultaneously.
# ---------------------------------------------------------------------------
build_and_install() {
    section "Configuring and building Magic"
    cd "$BUILD_DIR"

    local cflags="-g${EXTRA_CFLAGS:+ $EXTRA_CFLAGS}"
    info "CFLAGS: $cflags"
    info "Prefix: $INSTALL_PREFIX"

    ./configure --prefix="$INSTALL_PREFIX" CFLAGS="$cflags"

    info "Building (single-threaded) …"
    make

    section "Installing Magic"
    sudo make install
}

# ---------------------------------------------------------------------------
# Verify the installation
# ---------------------------------------------------------------------------
verify() {
    section "Verifying installation"
    if command -v magic &>/dev/null; then
        info "magic binary: $(command -v magic)"
        magic --version 2>/dev/null || true
        echo ""
        info "Installation successful!"
        info "Launch options:"
        info "  magic              — default X11 graphics"
        info "  magic -d XR        — Cairo graphics (recommended)"
        info "  magic -d OGL       — OpenGL graphics"
    else
        warn "magic not found in PATH."
        warn "Add the following to your shell profile (~/.bashrc or ~/.zshrc):"
        warn "  export PATH=\"$INSTALL_PREFIX/bin:\$PATH\""
    fi
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF

${BOLD}Usage:${RESET} $0 [OPTIONS]

${BOLD}Options:${RESET}
  -p, --prefix DIR     Installation prefix       (default: /usr/local)
  -b, --build-dir DIR  Source / build directory  (default: /tmp/magic-build)
  -t, --tag TAG        Git tag or branch to build
                       (default: '$STABLE_TAG' on GCC 14+, master otherwise)
  --skip-deps          Skip system package installation
  --skip-patches       Skip source compatibility patches
  -h, --help           Show this help message

${BOLD}Environment variables:${RESET}
  INSTALL_PREFIX, BUILD_DIR, MAGIC_VERSION

${BOLD}GCC 14+ compatibility (Ubuntu 24.04, Fedora 40+, etc.):${RESET}
  Magic is written in pre-ANSI C and requires the following adaptations
  when built with GCC 14 or later:

  CFLAGS=-std=gnu11
    Fixes K&R empty parameter list errors (too many arguments to function)
    Fixes 'bool' typedef conflict introduced by C23 keyword rules

  Source Patch 1  utils/magsgtty.h  — <termio.h> → <termios.h>
  Source Patch 2  textio/txInput.c  — struct termio → struct termios
                                      TCGETA → TCGETS, TCSETAF → TCSETSF
                                      + <termios.h> + <sys/ioctl.h> injected
                                        at top of file (before forward decls)

  All of the above are applied automatically when GCC 14+ is detected.

${BOLD}Examples:${RESET}
  $0                            # Recommended — auto-detects GCC, applies patches
  $0 --prefix \$HOME/.local      # Install to home dir (no sudo required)
  $0 --tag magic-8.3.480        # Build a specific release tag
  $0 --tag master               # Build latest master
  $0 --skip-deps --skip-patches # Only rebuild (deps + patches already done)

EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SKIP_DEPS=false
SKIP_PATCHES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--prefix)      INSTALL_PREFIX="$2"; shift 2 ;;
        -b|--build-dir)   BUILD_DIR="$2";      shift 2 ;;
        -t|--tag)         MAGIC_VERSION="$2";  shift 2 ;;
        --skip-deps)      SKIP_DEPS=true;      shift   ;;
        --skip-patches)   SKIP_PATCHES=true;   shift   ;;
        -h|--help)        usage; exit 0 ;;
        *) die "Unknown option: '$1'  (run with --help for usage)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    section "Magic VLSI Layout Tool — Installer"
    info "Install prefix : $INSTALL_PREFIX"
    info "Build directory: $BUILD_DIR"

    require_cmd git
    require_cmd make
    require_cmd gcc

    [[ "$SKIP_DEPS" == false ]] && install_dependencies || info "Skipping dependency installation"

    select_build_flags   # detect GCC version → sets GCC_MAJOR, EXTRA_CFLAGS
    resolve_version      # choose tag/branch  → sets MAGIC_VERSION

    info "Version/tag    : ${MAGIC_VERSION:-latest (master)}"

    mkdir -p "$BUILD_DIR"
    fetch_source

    [[ "$SKIP_PATCHES" == false ]] && apply_patches || info "Skipping source patches"

    build_and_install
    verify
}

main "$@"
