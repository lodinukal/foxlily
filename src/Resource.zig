const std = @import("std");

pub const Audio = @import("resource/Audio.zig");
pub const Bytes = @import("resource/Bytes.zig");
pub const Image = @import("resource/Image.zig");
pub const Mesh = @import("resource/Mesh.zig");
pub const Model = @import("resource/Model.zig");
pub const Shader = @import("resource/Shader.zig");
pub const Font = @import("resource/Font.zig");

pub const Handle = enum(u64) {
    null = std.math.maxInt(u64),
};

pub const Kind = enum(u8) {
    /// ila's representation of an audio clip
    audio,
    /// any generic data in the asset system
    bytes,
    /// ila's representation of an image (just bytes on the cpu loaded as rgba10)
    image,
    /// ila's representation of a mesh (a collection of submesh lods, each with a vertex buffer and an index buffer)
    mesh,
    /// ila's representation of a model (a collection of meshes, materials, and animations)
    model,
    /// ila's representation of a shader (a collection of shader stages for different targets)
    shader,
    /// ila's representation of a font (contains glyphs and metadata for rendering text)
    font,
};

pub const Any = union(Kind) {
    audio: Audio,
    bytes: Bytes,
    image: Image,
    mesh: Mesh,
    model: Model,
    shader: Shader,
    font: Font,

    pub fn deinit(self: Any) void {
        switch (self) {
            .audio => {}, // TODO: Implement when Audio.deinit is available
            .bytes => {}, // TODO: Implement when Bytes.deinit is available
            .image => |image| image.deinit(),
            .mesh => {}, // TODO: Implement when Mesh.deinit is available
            .model => {}, // TODO: Implement when Model.deinit is available
            .shader => {}, // TODO: Implement when Shader.deinit is available
            .font => {}, // TODO: Implement when Font.deinit is available
        }
    }
};
