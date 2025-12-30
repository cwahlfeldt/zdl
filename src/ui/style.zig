// ZDL UI Style System
// Theming and styling for consistent UI appearance

const Color = @import("../engine/engine.zig").Color;

/// Padding/margin insets
pub const Insets = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,

    pub fn all(value: f32) Insets {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }

    pub fn symmetric(h: f32, v: f32) Insets {
        return .{ .top = v, .right = h, .bottom = v, .left = h };
    }

    pub fn horizontalSum(self: Insets) f32 {
        return self.left + self.right;
    }

    pub fn verticalSum(self: Insets) f32 {
        return self.top + self.bottom;
    }
};

/// Style modifiers for different widget states
pub const StyleModifiers = struct {
    background: ?Color = null,
    foreground: ?Color = null,
    border: ?Color = null,
};

/// Complete style for a widget
pub const Style = struct {
    // Colors
    background: Color = Color.init(0.2, 0.2, 0.2, 0.9),
    foreground: Color = Color.init(1.0, 1.0, 1.0, 1.0),
    accent: Color = Color.init(0.3, 0.5, 0.8, 1.0),
    border: Color = Color.init(0.4, 0.4, 0.4, 1.0),

    // Dimensions
    border_radius: f32 = 4.0,
    border_width: f32 = 1.0,
    padding: Insets = Insets.all(8.0),

    // Text
    font_size: f32 = 14.0,

    // State modifiers
    hover: StyleModifiers = .{
        .background = Color.init(0.3, 0.3, 0.3, 0.9),
    },
    active: StyleModifiers = .{
        .background = Color.init(0.15, 0.15, 0.15, 0.9),
    },
    disabled: StyleModifiers = .{
        .foreground = Color.init(0.5, 0.5, 0.5, 1.0),
    },

    /// Get the effective background color for a given state
    pub fn getBackground(self: Style, hovered: bool, active: bool, disabled: bool) Color {
        if (disabled) {
            return self.disabled.background orelse self.background;
        }
        if (active) {
            return self.active.background orelse self.background;
        }
        if (hovered) {
            return self.hover.background orelse self.background;
        }
        return self.background;
    }

    /// Get the effective foreground color for a given state
    pub fn getForeground(self: Style, hovered: bool, active: bool, disabled: bool) Color {
        _ = hovered;
        _ = active;
        if (disabled) {
            return self.disabled.foreground orelse self.foreground;
        }
        return self.foreground;
    }
};

/// Theme presets
pub const Theme = struct {
    // Widget styles
    panel: Style,
    button: Style,
    label: Style,
    input: Style,
    slider: Style,

    /// Dark theme (default)
    pub fn dark() Theme {
        return .{
            .panel = .{
                .background = Color.init(0.15, 0.15, 0.15, 0.95),
                .foreground = Color.init(1.0, 1.0, 1.0, 1.0),
                .border = Color.init(0.3, 0.3, 0.3, 1.0),
                .border_width = 1.0,
                .border_radius = 6.0,
                .padding = Insets.all(12.0),
            },
            .button = .{
                .background = Color.init(0.25, 0.25, 0.25, 1.0),
                .foreground = Color.init(1.0, 1.0, 1.0, 1.0),
                .accent = Color.init(0.3, 0.5, 0.8, 1.0),
                .border = Color.init(0.35, 0.35, 0.35, 1.0),
                .border_width = 1.0,
                .border_radius = 4.0,
                .padding = Insets.symmetric(16.0, 8.0),
                .hover = .{
                    .background = Color.init(0.35, 0.35, 0.35, 1.0),
                    .border = Color.init(0.45, 0.45, 0.45, 1.0),
                },
                .active = .{
                    .background = Color.init(0.2, 0.2, 0.2, 1.0),
                },
            },
            .label = .{
                .background = Color.init(0, 0, 0, 0),
                .foreground = Color.init(1.0, 1.0, 1.0, 1.0),
                .padding = Insets.all(0),
                .border_width = 0,
            },
            .input = .{
                .background = Color.init(0.1, 0.1, 0.1, 1.0),
                .foreground = Color.init(1.0, 1.0, 1.0, 1.0),
                .border = Color.init(0.3, 0.3, 0.3, 1.0),
                .border_width = 1.0,
                .border_radius = 4.0,
                .padding = Insets.symmetric(8.0, 6.0),
            },
            .slider = .{
                .background = Color.init(0.2, 0.2, 0.2, 1.0),
                .foreground = Color.init(1.0, 1.0, 1.0, 1.0),
                .accent = Color.init(0.3, 0.5, 0.8, 1.0),
                .border = Color.init(0.3, 0.3, 0.3, 1.0),
                .border_radius = 4.0,
                .padding = Insets.symmetric(0, 4.0),
            },
        };
    }

    /// Light theme
    pub fn light() Theme {
        return .{
            .panel = .{
                .background = Color.init(0.95, 0.95, 0.95, 0.98),
                .foreground = Color.init(0.1, 0.1, 0.1, 1.0),
                .border = Color.init(0.8, 0.8, 0.8, 1.0),
                .border_width = 1.0,
                .border_radius = 6.0,
                .padding = Insets.all(12.0),
            },
            .button = .{
                .background = Color.init(0.9, 0.9, 0.9, 1.0),
                .foreground = Color.init(0.1, 0.1, 0.1, 1.0),
                .accent = Color.init(0.2, 0.4, 0.7, 1.0),
                .border = Color.init(0.75, 0.75, 0.75, 1.0),
                .border_width = 1.0,
                .border_radius = 4.0,
                .padding = Insets.symmetric(16.0, 8.0),
                .hover = .{
                    .background = Color.init(0.85, 0.85, 0.85, 1.0),
                },
                .active = .{
                    .background = Color.init(0.8, 0.8, 0.8, 1.0),
                },
            },
            .label = .{
                .background = Color.init(0, 0, 0, 0),
                .foreground = Color.init(0.1, 0.1, 0.1, 1.0),
                .padding = Insets.all(0),
                .border_width = 0,
            },
            .input = .{
                .background = Color.init(1.0, 1.0, 1.0, 1.0),
                .foreground = Color.init(0.1, 0.1, 0.1, 1.0),
                .border = Color.init(0.7, 0.7, 0.7, 1.0),
                .border_width = 1.0,
                .border_radius = 4.0,
                .padding = Insets.symmetric(8.0, 6.0),
            },
            .slider = .{
                .background = Color.init(0.85, 0.85, 0.85, 1.0),
                .foreground = Color.init(0.1, 0.1, 0.1, 1.0),
                .accent = Color.init(0.2, 0.4, 0.7, 1.0),
                .border = Color.init(0.7, 0.7, 0.7, 1.0),
                .border_radius = 4.0,
                .padding = Insets.symmetric(0, 4.0),
            },
        };
    }
};
