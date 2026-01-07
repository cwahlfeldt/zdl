const std = @import("std");
const types = @import("types.zig");
const GLTFError = types.GLTFError;
const GLTFAsset = types.GLTFAsset;
const TextureData = types.TextureData;
const ImageData = types.ImageData;
const Texture = @import("../../resources/texture.zig").Texture;
const sdl = @import("sdl3");

/// Import all textures from a glTF asset and upload to GPU
pub fn importTextures(asset: *GLTFAsset, device: *sdl.gpu.Device) !void {
    for (asset.textures, 0..) |tex_data, tex_idx| {
        const source_idx = tex_data.source orelse continue;
        if (source_idx >= asset.images.len) continue;

        const image = asset.images[source_idx];
        const texture = try importImage(asset, image, device);
        errdefer {
            texture.deinit(device);
            asset.allocator.destroy(texture);
        }

        // Store in asset
        const gpu_idx = asset.gpu_textures.items.len;
        try asset.gpu_textures.append(asset.allocator, texture);

        // Map glTF texture index to GPU texture index
        try asset.texture_map.put(tex_idx, gpu_idx);
    }
}

/// Import a single image as a ZDL Texture
fn importImage(
    asset: *const GLTFAsset,
    image: ImageData,
    device: *sdl.gpu.Device,
) !*Texture {
    const texture = try asset.allocator.create(Texture);
    errdefer asset.allocator.destroy(texture);

    if (image.buffer_view) |bv_idx| {
        // Embedded image - load from buffer
        if (bv_idx >= asset.buffer_views.len) {
            return GLTFError.InvalidBufferView;
        }

        const buffer_view = asset.buffer_views[bv_idx];
        if (buffer_view.buffer >= asset.buffers.len) {
            return GLTFError.BufferOutOfBounds;
        }

        const buffer = asset.buffers[buffer_view.buffer];
        const start = buffer_view.byte_offset;
        const end = start + buffer_view.byte_length;

        if (end > buffer.len) {
            return GLTFError.BufferOutOfBounds;
        }

        const image_data = buffer[start..end];
        texture.* = try Texture.loadFromMemory(device, image_data);
    } else if (image.uri) |uri| {
        // External image or data URI
        if (std.mem.startsWith(u8, uri, "data:")) {
            // Base64 data URI
            const decoded = try decodeDataURI(asset.allocator, uri);
            defer asset.allocator.free(decoded);
            texture.* = try Texture.loadFromMemory(device, decoded);
        } else {
            // External file - resolve relative to glTF base path
            const full_path = try std.fs.path.join(asset.allocator, &.{ asset.base_path, uri });
            defer asset.allocator.free(full_path);
            texture.* = try Texture.loadFromFile(device, full_path);
        }
    } else {
        return GLTFError.InvalidImageSource;
    }

    return texture;
}

/// Decode a base64 data URI
fn decodeDataURI(allocator: std.mem.Allocator, uri: []const u8) ![]u8 {
    // Format: data:[<mediatype>][;base64],<data>
    const comma_pos = std.mem.indexOf(u8, uri, ",") orelse return GLTFError.InvalidImageSource;
    const header = uri[0..comma_pos];
    const data = uri[comma_pos + 1 ..];

    // Check if it's base64 encoded
    if (!std.mem.containsAtLeast(u8, header, 1, "base64")) {
        return GLTFError.UnsupportedImageFormat;
    }

    // Decode base64
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(data) catch {
        return GLTFError.InvalidImageSource;
    };
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);

    std.base64.standard.Decoder.decode(decoded, data) catch {
        allocator.free(decoded);
        return GLTFError.InvalidImageSource;
    };

    return decoded;
}

/// Get the GPU texture for a glTF texture index
pub fn getGPUTexture(asset: *const GLTFAsset, texture_index: usize) ?*Texture {
    if (asset.texture_map.get(texture_index)) |gpu_idx| {
        return asset.gpu_textures.items[gpu_idx];
    }
    return null;
}

/// Get the base color texture for a material (if any)
pub fn getMaterialBaseColorTexture(asset: *const GLTFAsset, material_index: usize) ?*Texture {
    if (material_index >= asset.materials.len) return null;

    const material = asset.materials[material_index];
    const tex_info = material.base_color_texture orelse return null;

    return getGPUTexture(asset, tex_info.index);
}

/// Get the metallic-roughness texture for a material (if any)
pub fn getMaterialMetallicRoughnessTexture(asset: *const GLTFAsset, material_index: usize) ?*Texture {
    if (material_index >= asset.materials.len) return null;

    const material = asset.materials[material_index];
    const tex_info = material.metallic_roughness_texture orelse return null;

    return getGPUTexture(asset, tex_info.index);
}

/// Get the normal texture for a material (if any)
pub fn getMaterialNormalTexture(asset: *const GLTFAsset, material_index: usize) ?*Texture {
    if (material_index >= asset.materials.len) return null;

    const material = asset.materials[material_index];
    const tex_info = material.normal_texture orelse return null;

    return getGPUTexture(asset, tex_info.index);
}

/// Get the occlusion texture for a material (if any)
pub fn getMaterialOcclusionTexture(asset: *const GLTFAsset, material_index: usize) ?*Texture {
    if (material_index >= asset.materials.len) return null;

    const material = asset.materials[material_index];
    const tex_info = material.occlusion_texture orelse return null;

    return getGPUTexture(asset, tex_info.index);
}

/// Get the emissive texture for a material (if any)
pub fn getMaterialEmissiveTexture(asset: *const GLTFAsset, material_index: usize) ?*Texture {
    if (material_index >= asset.materials.len) return null;

    const material = asset.materials[material_index];
    const tex_info = material.emissive_texture orelse return null;

    return getGPUTexture(asset, tex_info.index);
}
