#!/bin/bash
# Shader Compilation Script for ZDL
# Compiles GLSL shaders to SPIR-V for Vulkan (Linux/Windows)
# macOS Metal shaders (.metal) are compiled at runtime and don't need pre-compilation

set -e  # Exit on error

SHADER_DIR="assets/shaders"

# Check if glslangValidator is installed
if ! command -v glslangValidator &> /dev/null; then
    echo "Error: glslangValidator not found"
    echo "Please install it:"
    echo "  macOS:   brew install glslang"
    echo "  Ubuntu:  sudo apt-get install glslang-tools"
    echo "  Windows: Download from https://github.com/KhronosGroup/glslang/releases"
    exit 1
fi

echo "=== ZDL Shader Compilation ==="
echo "Using glslangValidator: $(which glslangValidator)"
echo ""

# Function to compile a shader
compile_shader() {
    local shader_file=$1
    local output_file="${shader_file}.spv"

    echo "Compiling: $shader_file -> $output_file"
    glslangValidator -V "$shader_file" -o "$output_file"

    if [ $? -eq 0 ]; then
        echo "  ✓ Success"
    else
        echo "  ✗ Failed"
        exit 1
    fi
}

# Shadow shaders (for cascaded shadow maps)
echo ">>> Shadow Shaders"
compile_shader "$SHADER_DIR/shadow_depth.vert"
compile_shader "$SHADER_DIR/shadow_depth.frag"
echo ""

# PBR shaders (with Forward+ and shadow support)
echo ">>> PBR Shaders"
compile_shader "$SHADER_DIR/pbr.vert"
compile_shader "$SHADER_DIR/pbr_forward_plus.frag"
echo ""

# Light culling compute shader
echo ">>> Forward+ Light Culling"
compile_shader "$SHADER_DIR/light_cull.comp"
echo ""

# Debug rendering shaders
echo ">>> Debug Shaders"
compile_shader "$SHADER_DIR/debug_line.vert"
compile_shader "$SHADER_DIR/debug_line.frag"
echo ""

# UI rendering shaders
echo ">>> UI Shaders"
compile_shader "$SHADER_DIR/ui.vert"
compile_shader "$SHADER_DIR/ui.frag"
echo ""

# Skybox shaders
echo ">>> Skybox Shaders"
compile_shader "$SHADER_DIR/skybox.vert"
compile_shader "$SHADER_DIR/skybox.frag"
echo ""

# BRDF LUT generation shaders
echo ">>> BRDF LUT Shaders"
compile_shader "$SHADER_DIR/brdf_lut.vert"
compile_shader "$SHADER_DIR/brdf_lut.frag"
echo ""

# Skinned mesh shaders (if needed)
if [ -f "$SHADER_DIR/skinned_vertex.vert" ]; then
    echo ">>> Skinned Mesh Shaders"
    compile_shader "$SHADER_DIR/skinned_vertex.vert"
    echo ""
fi

echo "==================================="
echo "✓ All shaders compiled successfully!"
echo ""
echo "Note: Metal shaders (.metal) are compiled at runtime on macOS"
echo "      and do not need pre-compilation."
