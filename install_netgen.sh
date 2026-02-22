#!/bin/bash
# =============================================================================
# Netgen Installation Script - Tag v6.2.2601
# Source: https://github.com/NGSolve/netgen
# =============================================================================

set -e  # Exit immediately on error

# ----------------------------- Configuration ----------------------------------
NETGEN_TAG="v6.2.2601"
INSTALL_PREFIX="/usr/local"       # Change to e.g. $HOME/netgen for local install
BUILD_DIR="$HOME/netgen-build"
SOURCE_DIR="$HOME/netgen-src"
NUM_JOBS=$(nproc)                 # Use all available CPU cores

# Optional flags (set to ON/OFF as needed)
USE_GUI="ON"          # Build with Tcl/Tk GUI
USE_PYTHON="ON"       # Build Python bindings
USE_OCC="OFF"         # Build with OpenCASCADE support (requires OCC installed)
USE_MPI="OFF"         # Build with MPI support
USE_JPEG="OFF"         # JPEG export support
USE_MPEG="OFF"        # MPEG video export (requires ffmpeg)

# ----------------------------- Dependency Install (Ubuntu/Debian) -------------
install_dependencies_ubuntu() {
    echo ">>> Installing dependencies (Ubuntu/Debian)..."
    sudo apt-get update
    sudo apt-get install -y \
        git cmake g++ \
        python3-dev python3-pip \
        libx11-dev libxmu-dev \
        tk-dev tcl-dev \
        libjpeg-dev \
        zlib1g-dev \
        libglu1-mesa-dev \
        libtogl-dev \
        patchelf
    echo ">>> Dependencies installed."
}

# Optional: uncomment if on Ubuntu/Debian
# install_dependencies_ubuntu

# ----------------------------- Clone Repository -------------------------------
echo ">>> Cloning Netgen repository (tag: $NETGEN_TAG)..."
if [ -d "$SOURCE_DIR" ]; then
    echo "    Source directory already exists, skipping clone."
else
    git clone --recursive https://github.com/NGSolve/netgen.git "$SOURCE_DIR"
    cd "$SOURCE_DIR"
    git checkout "$NETGEN_TAG"
    git submodule update --init --recursive
fi

# ----------------------------- Configure with CMake ---------------------------
echo ">>> Configuring build with CMake..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake "$SOURCE_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DUSE_GUI=$USE_GUI \
    -DUSE_PYTHON=$USE_PYTHON \
    -DUSE_OCC=$USE_OCC \
    -DUSE_MPI=$USE_MPI \
    -DUSE_JPEG=$USE_JPEG \
    -DUSE_MPEG=$USE_MPEG \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

# ----------------------------- Build ------------------------------------------
echo ">>> Building Netgen with $NUM_JOBS parallel jobs..."
cmake --build . --config Release --parallel "$NUM_JOBS"

# ----------------------------- Install ----------------------------------------
echo ">>> Installing Netgen to $INSTALL_PREFIX ..."
sudo cmake --install . --config Release

# ----------------------------- Post-install -----------------------------------
echo ""
echo "============================================================"
echo " Netgen $NETGEN_TAG installation complete!"
echo " Install prefix: $INSTALL_PREFIX"
echo ""
echo " To run Netgen GUI:    netgen"
echo " To use Python module: python3 -c 'import netgen; print(netgen.__version__)'"
echo ""
echo " If Python bindings are not found, add to your shell profile:"
echo "   export PYTHONPATH=$INSTALL_PREFIX/lib/python3/dist-packages:\$PYTHONPATH"
echo "   export PATH=$INSTALL_PREFIX/bin:\$PATH"
echo "============================================================"
