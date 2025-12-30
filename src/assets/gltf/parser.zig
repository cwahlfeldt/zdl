const std = @import("std");
const types = @import("types.zig");
const GLTFError = types.GLTFError;
const GLTFAsset = types.GLTFAsset;
const NodeData = types.NodeData;
const SceneData = types.SceneData;
const MeshData = types.MeshData;
const PrimitiveData = types.PrimitiveData;
const MaterialData = types.MaterialData;
const TextureData = types.TextureData;
const ImageData = types.ImageData;
const SamplerData = types.SamplerData;
const CameraData = types.CameraData;
const BufferViewData = types.BufferViewData;
const AccessorData = types.AccessorData;
const ComponentType = types.ComponentType;
const ElementType = types.ElementType;
const PrimitiveMode = types.PrimitiveMode;
const BufferTarget = types.BufferTarget;
const AlphaMode = types.AlphaMode;
const TextureInfo = types.TextureInfo;
const CameraType = types.CameraType;
const AnimationData = types.AnimationData;
const AnimationChannelData = types.AnimationChannelData;
const AnimationChannelTarget = types.AnimationChannelTarget;
const AnimationSamplerData = types.AnimationSamplerData;
const AnimationInterpolation = types.AnimationInterpolation;
const AnimationTargetPath = types.AnimationTargetPath;
const SkinData = types.SkinData;

/// Parse glTF JSON and populate asset structure
/// Does not load external buffers - call loadBuffers() separately
pub fn parseJSON(allocator: std.mem.Allocator, json_data: []const u8, asset: *GLTFAsset) !void {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_data, .{}) catch {
        return GLTFError.InvalidJSON;
    };
    defer parsed.deinit();

    const root = parsed.value;

    if (root != .object) {
        return GLTFError.InvalidJSON;
    }

    // Validate asset version
    if (root.object.get("asset")) |asset_obj| {
        if (asset_obj.object.get("version")) |version| {
            const ver_str = version.string;
            // Accept 2.x versions
            if (!std.mem.startsWith(u8, ver_str, "2.")) {
                return GLTFError.UnsupportedVersion;
            }
        } else {
            return GLTFError.MissingRequiredProperty;
        }
    } else {
        return GLTFError.MissingRequiredProperty;
    }

    // Parse buffer views
    if (root.object.get("bufferViews")) |bv_array| {
        asset.buffer_views = try parseBufferViews(allocator, bv_array);
    }

    // Parse accessors
    if (root.object.get("accessors")) |acc_array| {
        asset.accessors = try parseAccessors(allocator, acc_array);
    }

    // Parse meshes
    if (root.object.get("meshes")) |meshes_array| {
        asset.meshes = try parseMeshes(allocator, meshes_array);
    }

    // Parse materials
    if (root.object.get("materials")) |materials_array| {
        asset.materials = try parseMaterials(allocator, materials_array);
    }

    // Parse textures
    if (root.object.get("textures")) |textures_array| {
        asset.textures = try parseTextures(allocator, textures_array);
    }

    // Parse images
    if (root.object.get("images")) |images_array| {
        asset.images = try parseImages(allocator, images_array);
    }

    // Parse samplers
    if (root.object.get("samplers")) |samplers_array| {
        asset.samplers = try parseSamplers(allocator, samplers_array);
    }

    // Parse cameras
    if (root.object.get("cameras")) |cameras_array| {
        asset.cameras = try parseCameras(allocator, cameras_array);
    }

    // Parse nodes
    if (root.object.get("nodes")) |nodes_array| {
        asset.nodes = try parseNodes(allocator, nodes_array);
    }

    // Parse scenes
    if (root.object.get("scenes")) |scenes_array| {
        asset.scenes = try parseScenes(allocator, scenes_array);
    }

    // Parse animations
    if (root.object.get("animations")) |animations_array| {
        asset.animations = try parseAnimations(allocator, animations_array);
    }

    // Parse skins
    if (root.object.get("skins")) |skins_array| {
        asset.skins = try parseSkins(allocator, skins_array);
    }

    // Parse default scene
    if (root.object.get("scene")) |scene_val| {
        asset.default_scene = @intCast(scene_val.integer);
    }

    // Parse buffer URIs for later loading
    if (root.object.get("buffers")) |buffers_array| {
        const buffer_count = buffers_array.array.items.len;
        asset.buffers = try allocator.alloc([]const u8, buffer_count);
        asset.owns_buffers = try allocator.alloc(bool, buffer_count);
        for (asset.buffers, asset.owns_buffers) |*buf, *owns| {
            buf.* = &.{};
            owns.* = false;
        }
    }
}

fn parseBufferViews(allocator: std.mem.Allocator, array: std.json.Value) ![]BufferViewData {
    const items = array.array.items;
    var result = try allocator.alloc(BufferViewData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;
        result[i] = .{
            .buffer = @intCast(obj.get("buffer").?.integer),
            .byte_offset = if (obj.get("byteOffset")) |v| @intCast(v.integer) else 0,
            .byte_length = @intCast(obj.get("byteLength").?.integer),
            .byte_stride = if (obj.get("byteStride")) |v| @intCast(v.integer) else null,
            .target = if (obj.get("target")) |v| @enumFromInt(@as(u32, @intCast(v.integer))) else null,
        };
    }

    return result;
}

fn parseAccessors(allocator: std.mem.Allocator, array: std.json.Value) ![]AccessorData {
    const items = array.array.items;
    var result = try allocator.alloc(AccessorData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;

        const type_str = obj.get("type").?.string;
        const element_type = ElementType.fromString(type_str) orelse return GLTFError.InvalidAccessor;

        result[i] = .{
            .buffer_view = if (obj.get("bufferView")) |v| @intCast(v.integer) else null,
            .byte_offset = if (obj.get("byteOffset")) |v| @intCast(v.integer) else 0,
            .component_type = @enumFromInt(@as(u32, @intCast(obj.get("componentType").?.integer))),
            .normalized = if (obj.get("normalized")) |v| v.bool else false,
            .count = @intCast(obj.get("count").?.integer),
            .element_type = element_type,
            .min = null, // Could parse if needed
            .max = null,
        };
    }

    return result;
}

fn parseMeshes(allocator: std.mem.Allocator, array: std.json.Value) ![]MeshData {
    const items = array.array.items;
    var result = try allocator.alloc(MeshData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;
        const prims = obj.get("primitives").?.array.items;

        var primitives = try allocator.alloc(PrimitiveData, prims.len);
        for (prims, 0..) |prim, j| {
            const prim_obj = prim.object;
            const attrs = prim_obj.get("attributes").?.object;

            primitives[j] = .{
                .attributes = .{
                    .position = if (attrs.get("POSITION")) |v| @intCast(v.integer) else null,
                    .normal = if (attrs.get("NORMAL")) |v| @intCast(v.integer) else null,
                    .tangent = if (attrs.get("TANGENT")) |v| @intCast(v.integer) else null,
                    .texcoord_0 = if (attrs.get("TEXCOORD_0")) |v| @intCast(v.integer) else null,
                    .texcoord_1 = if (attrs.get("TEXCOORD_1")) |v| @intCast(v.integer) else null,
                    .color_0 = if (attrs.get("COLOR_0")) |v| @intCast(v.integer) else null,
                    .joints_0 = if (attrs.get("JOINTS_0")) |v| @intCast(v.integer) else null,
                    .weights_0 = if (attrs.get("WEIGHTS_0")) |v| @intCast(v.integer) else null,
                },
                .indices = if (prim_obj.get("indices")) |v| @intCast(v.integer) else null,
                .material = if (prim_obj.get("material")) |v| @intCast(v.integer) else null,
                .mode = if (prim_obj.get("mode")) |v| @enumFromInt(@as(u32, @intCast(v.integer))) else .triangles,
            };
        }

        result[i] = .{
            .name = if (obj.get("name")) |v| v.string else null,
            .primitives = primitives,
        };
    }

    return result;
}

fn parseMaterials(allocator: std.mem.Allocator, array: std.json.Value) ![]MaterialData {
    const items = array.array.items;
    var result = try allocator.alloc(MaterialData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;
        var mat = MaterialData.default();

        mat.name = if (obj.get("name")) |v| v.string else null;

        // Parse PBR metallic-roughness
        if (obj.get("pbrMetallicRoughness")) |pbr| {
            const pbr_obj = pbr.object;

            if (pbr_obj.get("baseColorFactor")) |bcf| {
                const arr = bcf.array.items;
                mat.base_color_factor = .{
                    parseFloat(arr[0]),
                    parseFloat(arr[1]),
                    parseFloat(arr[2]),
                    parseFloat(arr[3]),
                };
            }

            if (pbr_obj.get("baseColorTexture")) |bct| {
                mat.base_color_texture = parseTextureInfo(bct);
            }

            if (pbr_obj.get("metallicFactor")) |mf| {
                mat.metallic_factor = parseFloat(mf);
            }

            if (pbr_obj.get("roughnessFactor")) |rf| {
                mat.roughness_factor = parseFloat(rf);
            }

            if (pbr_obj.get("metallicRoughnessTexture")) |mrt| {
                mat.metallic_roughness_texture = parseTextureInfo(mrt);
            }
        }

        // Parse normal texture
        if (obj.get("normalTexture")) |nt| {
            mat.normal_texture = parseTextureInfo(nt);
            if (nt.object.get("scale")) |s| {
                mat.normal_scale = parseFloat(s);
            }
        }

        // Parse occlusion texture
        if (obj.get("occlusionTexture")) |ot| {
            mat.occlusion_texture = parseTextureInfo(ot);
            if (ot.object.get("strength")) |s| {
                mat.occlusion_strength = parseFloat(s);
            }
        }

        // Parse emissive
        if (obj.get("emissiveFactor")) |ef| {
            const arr = ef.array.items;
            mat.emissive_factor = .{
                parseFloat(arr[0]),
                parseFloat(arr[1]),
                parseFloat(arr[2]),
            };
        }

        if (obj.get("emissiveTexture")) |et| {
            mat.emissive_texture = parseTextureInfo(et);
        }

        // Parse alpha mode
        if (obj.get("alphaMode")) |am| {
            mat.alpha_mode = if (std.mem.eql(u8, am.string, "MASK"))
                .mask
            else if (std.mem.eql(u8, am.string, "BLEND"))
                .blend
            else
                .@"opaque";
        }

        if (obj.get("alphaCutoff")) |ac| {
            mat.alpha_cutoff = parseFloat(ac);
        }

        if (obj.get("doubleSided")) |ds| {
            mat.double_sided = ds.bool;
        }

        result[i] = mat;
    }

    return result;
}

fn parseTextureInfo(value: std.json.Value) TextureInfo {
    const obj = value.object;
    return .{
        .index = @intCast(obj.get("index").?.integer),
        .tex_coord = if (obj.get("texCoord")) |tc| @intCast(tc.integer) else 0,
    };
}

fn parseTextures(allocator: std.mem.Allocator, array: std.json.Value) ![]TextureData {
    const items = array.array.items;
    var result = try allocator.alloc(TextureData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;
        result[i] = .{
            .sampler = if (obj.get("sampler")) |v| @intCast(v.integer) else null,
            .source = if (obj.get("source")) |v| @intCast(v.integer) else null,
        };
    }

    return result;
}

fn parseImages(allocator: std.mem.Allocator, array: std.json.Value) ![]ImageData {
    const items = array.array.items;
    var result = try allocator.alloc(ImageData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;
        result[i] = .{
            .name = if (obj.get("name")) |v| v.string else null,
            .uri = if (obj.get("uri")) |v| v.string else null,
            .buffer_view = if (obj.get("bufferView")) |v| @intCast(v.integer) else null,
            .mime_type = if (obj.get("mimeType")) |v| v.string else null,
        };
    }

    return result;
}

fn parseSamplers(allocator: std.mem.Allocator, array: std.json.Value) ![]SamplerData {
    const items = array.array.items;
    var result = try allocator.alloc(SamplerData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;
        var sampler = SamplerData.default();

        if (obj.get("magFilter")) |v| sampler.mag_filter = @intCast(v.integer);
        if (obj.get("minFilter")) |v| sampler.min_filter = @intCast(v.integer);
        if (obj.get("wrapS")) |v| sampler.wrap_s = @intCast(v.integer);
        if (obj.get("wrapT")) |v| sampler.wrap_t = @intCast(v.integer);

        result[i] = sampler;
    }

    return result;
}

fn parseCameras(allocator: std.mem.Allocator, array: std.json.Value) ![]CameraData {
    const items = array.array.items;
    var result = try allocator.alloc(CameraData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;
        const cam_type_str = obj.get("type").?.string;

        if (std.mem.eql(u8, cam_type_str, "perspective")) {
            const persp = obj.get("perspective").?.object;
            result[i] = .{
                .name = if (obj.get("name")) |v| v.string else null,
                .camera_type = .perspective,
                .aspect_ratio = if (persp.get("aspectRatio")) |v| parseFloat(v) else null,
                .yfov = parseFloat(persp.get("yfov").?),
                .znear = parseFloat(persp.get("znear").?),
                .zfar = if (persp.get("zfar")) |v| parseFloat(v) else null,
                .xmag = 0,
                .ymag = 0,
            };
        } else {
            const ortho = obj.get("orthographic").?.object;
            result[i] = .{
                .name = if (obj.get("name")) |v| v.string else null,
                .camera_type = .orthographic,
                .aspect_ratio = null,
                .yfov = 0,
                .znear = parseFloat(ortho.get("znear").?),
                .zfar = parseFloat(ortho.get("zfar").?),
                .xmag = parseFloat(ortho.get("xmag").?),
                .ymag = parseFloat(ortho.get("ymag").?),
            };
        }
    }

    return result;
}

fn parseNodes(allocator: std.mem.Allocator, array: std.json.Value) ![]NodeData {
    const items = array.array.items;
    var result = try allocator.alloc(NodeData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;

        // Parse children
        var children: []usize = &.{};
        if (obj.get("children")) |c| {
            children = try allocator.alloc(usize, c.array.items.len);
            for (c.array.items, 0..) |child, j| {
                children[j] = @intCast(child.integer);
            }
        }

        // Parse matrix
        var matrix: ?[16]f32 = null;
        if (obj.get("matrix")) |m| {
            matrix = .{
                parseFloat(m.array.items[0]),  parseFloat(m.array.items[1]),
                parseFloat(m.array.items[2]),  parseFloat(m.array.items[3]),
                parseFloat(m.array.items[4]),  parseFloat(m.array.items[5]),
                parseFloat(m.array.items[6]),  parseFloat(m.array.items[7]),
                parseFloat(m.array.items[8]),  parseFloat(m.array.items[9]),
                parseFloat(m.array.items[10]), parseFloat(m.array.items[11]),
                parseFloat(m.array.items[12]), parseFloat(m.array.items[13]),
                parseFloat(m.array.items[14]), parseFloat(m.array.items[15]),
            };
        }

        // Parse TRS
        var translation: ?[3]f32 = null;
        if (obj.get("translation")) |t| {
            translation = .{
                parseFloat(t.array.items[0]),
                parseFloat(t.array.items[1]),
                parseFloat(t.array.items[2]),
            };
        }

        var rotation: ?[4]f32 = null;
        if (obj.get("rotation")) |r| {
            rotation = .{
                parseFloat(r.array.items[0]),
                parseFloat(r.array.items[1]),
                parseFloat(r.array.items[2]),
                parseFloat(r.array.items[3]),
            };
        }

        var scale: ?[3]f32 = null;
        if (obj.get("scale")) |s| {
            scale = .{
                parseFloat(s.array.items[0]),
                parseFloat(s.array.items[1]),
                parseFloat(s.array.items[2]),
            };
        }

        result[i] = .{
            .name = if (obj.get("name")) |v| v.string else null,
            .children = children,
            .mesh_index = if (obj.get("mesh")) |v| @intCast(v.integer) else null,
            .camera_index = if (obj.get("camera")) |v| @intCast(v.integer) else null,
            .skin_index = if (obj.get("skin")) |v| @intCast(v.integer) else null,
            .matrix = matrix,
            .translation = translation,
            .rotation = rotation,
            .scale = scale,
        };
    }

    return result;
}

fn parseScenes(allocator: std.mem.Allocator, array: std.json.Value) ![]SceneData {
    const items = array.array.items;
    var result = try allocator.alloc(SceneData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;

        var nodes: []usize = &.{};
        if (obj.get("nodes")) |n| {
            nodes = try allocator.alloc(usize, n.array.items.len);
            for (n.array.items, 0..) |node, j| {
                nodes[j] = @intCast(node.integer);
            }
        }

        result[i] = .{
            .name = if (obj.get("name")) |v| v.string else null,
            .nodes = nodes,
        };
    }

    return result;
}

fn parseAnimations(allocator: std.mem.Allocator, array: std.json.Value) ![]AnimationData {
    const items = array.array.items;
    var result = try allocator.alloc(AnimationData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;

        // Parse samplers
        var samplers: []AnimationSamplerData = &.{};
        if (obj.get("samplers")) |s| {
            samplers = try allocator.alloc(AnimationSamplerData, s.array.items.len);
            for (s.array.items, 0..) |sampler, j| {
                const sampler_obj = sampler.object;
                samplers[j] = .{
                    .input = @intCast(sampler_obj.get("input").?.integer),
                    .output = @intCast(sampler_obj.get("output").?.integer),
                    .interpolation = if (sampler_obj.get("interpolation")) |interp|
                        AnimationInterpolation.fromString(interp.string)
                    else
                        .linear,
                };
            }
        }

        // Parse channels
        var channels: []AnimationChannelData = &.{};
        if (obj.get("channels")) |c| {
            channels = try allocator.alloc(AnimationChannelData, c.array.items.len);
            for (c.array.items, 0..) |channel, j| {
                const channel_obj = channel.object;
                const target_obj = channel_obj.get("target").?.object;

                channels[j] = .{
                    .sampler = @intCast(channel_obj.get("sampler").?.integer),
                    .target = .{
                        .node = if (target_obj.get("node")) |n| @intCast(n.integer) else null,
                        .path = AnimationTargetPath.fromString(target_obj.get("path").?.string) orelse .translation,
                    },
                };
            }
        }

        result[i] = .{
            .name = if (obj.get("name")) |v| v.string else null,
            .channels = channels,
            .samplers = samplers,
        };
    }

    return result;
}

fn parseSkins(allocator: std.mem.Allocator, array: std.json.Value) ![]SkinData {
    const items = array.array.items;
    var result = try allocator.alloc(SkinData, items.len);

    for (items, 0..) |item, i| {
        const obj = item.object;

        // Parse joints array
        var joints: []usize = &.{};
        if (obj.get("joints")) |j| {
            joints = try allocator.alloc(usize, j.array.items.len);
            for (j.array.items, 0..) |joint, k| {
                joints[k] = @intCast(joint.integer);
            }
        }

        result[i] = .{
            .name = if (obj.get("name")) |v| v.string else null,
            .inverse_bind_matrices = if (obj.get("inverseBindMatrices")) |v| @intCast(v.integer) else null,
            .skeleton = if (obj.get("skeleton")) |v| @intCast(v.integer) else null,
            .joints = joints,
        };
    }

    return result;
}

/// Helper to parse JSON number (handles both int and float)
fn parseFloat(value: std.json.Value) f32 {
    return switch (value) {
        .integer => |i| @floatFromInt(i),
        .float => |f| @floatCast(f),
        else => 0,
    };
}
