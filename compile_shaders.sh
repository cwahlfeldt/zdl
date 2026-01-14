#!/bin/bash
# Shader compilation script for ZDL Engine
# Compiles GLSL shaders to SPIR-V using glslangValidator
# Only needed for non-macOS platforms (macOS uses Metal shaders directly)

set -e

SHADER_SRC_DIR="assets/shaders"
SHADER_BUILD_DIR="build/assets/shaders"

# Create build directory if it doesn't exist
mkdir -p "$SHADER_BUILD_DIR"

# Check if glslangValidator is available
if ! command -v glslangValidator &> /dev/null; then
    echo "Error: glslangValidator not found"
    echo "Please install glslang-tools:"
    echo "  Ubuntu/Debian: sudo apt-get install glslang-tools"
    echo "  macOS: brew install glslang"
    echo "  Arch Linux: sudo pacman -S glslang"
    exit 1
fi

echo "Compiling GLSL shaders to SPIR-V..."

# Compile vertex shaders
for shader in "$SHADER_SRC_DIR"/*.vert; do
    if [ -f "$shader" ]; then
        filename=$(basename "$shader")
        echo "  $filename -> ${filename}.spv"
        glslangValidator -V "$shader" -o "$SHADER_BUILD_DIR/${filename}.spv"
    fi
done

# Compile fragment shaders
for shader in "$SHADER_SRC_DIR"/*.frag; do
    if [ -f "$shader" ]; then
        filename=$(basename "$shader")
        echo "  $filename -> ${filename}.spv"
        glslangValidator -V "$shader" -o "$SHADER_BUILD_DIR/${filename}.spv"
    fi
done

# Compile compute shaders
for shader in "$SHADER_SRC_DIR"/*.comp; do
    if [ -f "$shader" ]; then
        filename=$(basename "$shader")
        echo "  $filename -> ${filename}.spv"
        glslangValidator -V "$shader" -o "$SHADER_BUILD_DIR/${filename}.spv"
    fi
done

echo "Shader compilation complete!"
echo "Compiled shaders are in: $SHADER_BUILD_DIR"
