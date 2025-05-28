pub const Audio = @import("media/Audio.zig");
pub const Image = @import("media/Image.zig");
pub const Model = @import("media/Model.zig");

comptime {
    _ = Audio;
    _ = Image;
    _ = Model;
}
