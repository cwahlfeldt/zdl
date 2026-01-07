// IBL (Image-Based Lighting) module
// Provides environment mapping and pre-filtered reflections for PBR

pub const BrdfLut = @import("brdf_lut.zig").BrdfLut;
pub const EnvironmentMap = @import("environment_map.zig").EnvironmentMap;
pub const HdrImage = @import("hdr_loader.zig").HdrImage;
pub const loadHDR = @import("hdr_loader.zig").loadHDR;
pub const equirectToCubemap = @import("equirect_to_cubemap.zig").equirectToCubemap;
// pub const IBLBaker = @import("ibl_baker.zig").IBLBaker;
