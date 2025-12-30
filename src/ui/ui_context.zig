// ZDL UI Context
// Central state manager for immediate-mode UI rendering

const std = @import("std");
const sdl = @import("sdl3");
const Vec2 = @import("../math/vec2.zig").Vec2;
const Color = @import("../engine/engine.zig").Color;
const Input = @import("../input/input.zig").Input;

const ui = @import("ui.zig");
const Rect = ui.Rect;
const WidgetId = ui.WidgetId;

const UIRenderer = @import("ui_renderer.zig").UIRenderer;
const Font = @import("font.zig").Font;
const Style = @import("style.zig").Style;
const Theme = @import("style.zig").Theme;
const Insets = @import("style.zig").Insets;

/// UI Context - manages state for immediate-mode UI
pub const UIContext = struct {
    allocator: std.mem.Allocator,

    // Core components
    renderer: UIRenderer,
    font: ?Font,
    theme: Theme,

    // Input state (updated each frame)
    mouse_x: f32,
    mouse_y: f32,
    mouse_down: bool,
    mouse_clicked: bool, // Just pressed this frame
    mouse_released: bool, // Just released this frame

    // Widget interaction state
    hot_id: ?WidgetId, // Currently hovered widget
    active_id: ?WidgetId, // Currently interacting widget (e.g., dragging)
    focus_id: ?WidgetId, // Keyboard focus

    // Layout state for immediate-mode layout
    cursor_x: f32,
    cursor_y: f32,
    line_height: f32,
    indent: f32,

    // Panel stack for nested containers
    panel_stack: std.array_list.Managed(PanelState),

    // Screen dimensions
    screen_width: f32,
    screen_height: f32,

    // Statistics
    widget_count: u32,

    const PanelState = struct {
        rect: Rect,
        content_start_y: f32,
        cursor_x: f32,
        cursor_y: f32,
        style: Style,
    };

    pub fn init(allocator: std.mem.Allocator) UIContext {
        return .{
            .allocator = allocator,
            .renderer = UIRenderer.init(allocator),
            .font = null,
            .theme = Theme.dark(),
            .mouse_x = 0,
            .mouse_y = 0,
            .mouse_down = false,
            .mouse_clicked = false,
            .mouse_released = false,
            .hot_id = null,
            .active_id = null,
            .focus_id = null,
            .cursor_x = 0,
            .cursor_y = 0,
            .line_height = 24,
            .indent = 0,
            .panel_stack = std.array_list.Managed(PanelState).init(allocator),
            .screen_width = 800,
            .screen_height = 600,
            .widget_count = 0,
        };
    }

    pub fn deinit(self: *UIContext, device: ?*sdl.gpu.Device) void {
        if (device) |dev| {
            self.renderer.deinit(dev);
        }
        if (self.font) |*f| f.deinit();
        self.panel_stack.deinit();
    }

    /// Initialize GPU resources
    pub fn initGpu(self: *UIContext, device: *sdl.gpu.Device, swapchain_format: sdl.gpu.TextureFormat) !void {
        try self.renderer.initGpu(device, swapchain_format);

        // Create built-in font
        self.font = try Font.createBuiltin(self.allocator, device);
    }

    /// Load a custom BMFont
    pub fn loadFont(self: *UIContext, device: *sdl.gpu.Device, fnt_path: []const u8) !void {
        if (self.font) |*f| f.deinit();
        self.font = try Font.loadBMFont(self.allocator, device, fnt_path);
    }

    /// Set screen dimensions
    pub fn setScreenSize(self: *UIContext, width: f32, height: f32) void {
        self.screen_width = width;
        self.screen_height = height;
        self.renderer.setScreenSize(width, height);
    }

    /// Update input state (call at start of frame before UI calls)
    pub fn updateInput(self: *UIContext, input: *Input) void {
        self.mouse_x = input.mouse_x;
        self.mouse_y = input.mouse_y;

        const was_down = self.mouse_down;
        self.mouse_down = input.isMouseButtonDown(.left);
        self.mouse_clicked = self.mouse_down and !was_down;
        self.mouse_released = !self.mouse_down and was_down;
    }

    /// Begin a new UI frame
    pub fn begin(self: *UIContext) void {
        self.widget_count = 0;
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.indent = 0;
        self.panel_stack.clearRetainingCapacity();

        // Reset hot widget (will be set during widget processing)
        self.hot_id = null;
    }

    /// End the UI frame
    pub fn end(self: *UIContext) void {
        // If mouse was released and no widget was clicked, clear active
        if (self.mouse_released) {
            self.active_id = null;
        }
    }

    /// Upload UI data to GPU (call before render pass)
    pub fn uploadData(self: *UIContext, device: *sdl.gpu.Device) !void {
        try self.renderer.uploadData(device);
    }

    /// Render the UI (call during render pass)
    pub fn render(self: *UIContext, cmd: sdl.gpu.CommandBuffer, pass: sdl.gpu.RenderPass) void {
        self.renderer.render(cmd, pass);
    }

    /// Clear renderer state (call at end of frame)
    pub fn clear(self: *UIContext) void {
        self.renderer.clear();
    }

    // ==================== Widget Helpers ====================

    /// Check if a widget is hovered
    pub fn isHovered(self: *UIContext, id: WidgetId) bool {
        if (self.hot_id) |hot| {
            return hot.eql(id);
        }
        return false;
    }

    /// Check if a widget is active (being interacted with)
    pub fn isActive(self: *UIContext, id: WidgetId) bool {
        if (self.active_id) |active| {
            return active.eql(id);
        }
        return false;
    }

    /// Update hot/active state for a widget rect
    fn updateWidgetState(self: *UIContext, id: WidgetId, rect: Rect) void {
        if (rect.contains(self.mouse_x, self.mouse_y)) {
            self.hot_id = id;
            if (self.mouse_clicked) {
                self.active_id = id;
            }
        }
    }

    // ==================== Immediate-Mode Widgets ====================

    /// Begin a panel/window container
    pub fn beginPanel(self: *UIContext, comptime title: []const u8, x: f32, y: f32, width: f32) bool {
        const id = WidgetId.from(title, 0);
        self.widget_count += 1;

        const style = self.theme.panel;
        const title_height: f32 = 24;
        const header_rect = Rect.init(x, y, width, title_height);

        // Update interaction state for header (for dragging in future)
        self.updateWidgetState(id, header_rect);

        // Draw panel background (we'll extend height later)
        // For now, use a minimum height
        const min_height: f32 = 100;
        const panel_rect = Rect.init(x, y, width, min_height);

        // Draw panel
        self.renderer.drawRect(panel_rect, style.background);
        self.renderer.drawRectBorder(panel_rect, style.border, style.border_width);

        // Draw title bar
        const header_bg = Color.init(
            style.background.r * 0.8,
            style.background.g * 0.8,
            style.background.b * 0.8,
            style.background.a,
        );
        self.renderer.drawRect(header_rect, header_bg);

        // Draw title text
        if (self.font) |*font| {
            font.drawText(
                &self.renderer,
                title,
                x + style.padding.left,
                y + (title_height - font.line_height) / 2,
                style.foreground,
            );
        }

        // Push panel state
        self.panel_stack.append(.{
            .rect = panel_rect,
            .content_start_y = y + title_height,
            .cursor_x = x + style.padding.left,
            .cursor_y = y + title_height + style.padding.top,
            .style = style,
        }) catch return false;

        self.cursor_x = x + style.padding.left;
        self.cursor_y = y + title_height + style.padding.top;

        return true;
    }

    /// End a panel
    pub fn endPanel(self: *UIContext) void {
        if (self.panel_stack.items.len > 0) {
            _ = self.panel_stack.pop();
        }

        // Restore cursor from parent panel if any
        if (self.panel_stack.items.len > 0) {
            const parent = self.panel_stack.items[self.panel_stack.items.len - 1];
            self.cursor_x = parent.cursor_x;
            self.cursor_y = parent.cursor_y;
        }
    }

    /// Draw a text label with format arguments
    pub fn labelFmt(self: *UIContext, comptime fmt: []const u8, args: anytype) void {
        self.widget_count += 1;

        var buf: [256]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, fmt, args) catch return;

        if (self.font) |*font| {
            font.drawText(
                &self.renderer,
                formatted,
                self.cursor_x + self.indent,
                self.cursor_y,
                self.theme.label.foreground,
            );

            self.cursor_y += self.line_height;
        }
    }

    /// Draw a text label (simple string version)
    pub fn label(self: *UIContext, str: []const u8) void {
        self.widget_count += 1;

        if (self.font) |*font| {
            font.drawText(
                &self.renderer,
                str,
                self.cursor_x + self.indent,
                self.cursor_y,
                self.theme.label.foreground,
            );

            self.cursor_y += self.line_height;
        }
    }

    /// Draw a clickable button, returns true if clicked
    pub fn button(self: *UIContext, comptime label_text: []const u8) bool {
        const id = WidgetId.from(label_text, self.widget_count);
        self.widget_count += 1;

        const style = self.theme.button;

        // Measure text
        var text_size = Vec2.init(80, 16);
        if (self.font) |*font| {
            text_size = font.measureText(label_text);
        }

        // Calculate button rect
        const width = text_size.x + style.padding.horizontalSum();
        const height = text_size.y + style.padding.verticalSum();
        const rect = Rect.init(self.cursor_x + self.indent, self.cursor_y, width, height);

        // Update state
        self.updateWidgetState(id, rect);
        const hovered = self.isHovered(id);
        const active = self.isActive(id);

        // Determine colors based on state
        const bg_color = style.getBackground(hovered, active, false);
        const fg_color = style.getForeground(hovered, active, false);
        const border_color = if (hovered)
            style.hover.border orelse style.border
        else
            style.border;

        // Draw button
        self.renderer.drawRect(rect, bg_color);
        self.renderer.drawRectBorder(rect, border_color, style.border_width);

        // Draw text centered
        if (self.font) |*font| {
            const text_x = rect.x + (rect.width - text_size.x) / 2;
            const text_y = rect.y + (rect.height - text_size.y) / 2;
            font.drawText(&self.renderer, label_text, text_x, text_y, fg_color);
        }

        // Advance cursor
        self.cursor_y += height + 4;

        // Return true if clicked (was active and mouse released)
        return active and self.mouse_released;
    }

    /// Draw a horizontal slider, returns true if value changed
    pub fn slider(self: *UIContext, comptime label_text: []const u8, value: *f32, min_val: f32, max_val: f32) bool {
        const id = WidgetId.from(label_text, self.widget_count);
        self.widget_count += 1;

        const style = self.theme.slider;
        const width: f32 = 200;
        const height: f32 = 20;
        const handle_width: f32 = 10;

        // Draw label
        if (self.font) |*font| {
            var buf: [64]u8 = undefined;
            const slider_label = std.fmt.bufPrint(&buf, "{s}: {d:.2}", .{ label_text, value.* }) catch label_text;
            font.drawText(&self.renderer, slider_label, self.cursor_x + self.indent, self.cursor_y, style.foreground);
        }
        self.cursor_y += self.line_height;

        // Slider track rect
        const rect = Rect.init(self.cursor_x + self.indent, self.cursor_y, width, height);

        // Update state
        self.updateWidgetState(id, rect);
        const active = self.isActive(id);

        // Draw track
        self.renderer.drawRect(rect, style.background);
        self.renderer.drawRectBorder(rect, style.border, 1);

        // Calculate handle position
        const range = max_val - min_val;
        const normalized = if (range > 0) (value.* - min_val) / range else 0;
        const handle_x = rect.x + normalized * (rect.width - handle_width);

        // Draw handle
        const handle_rect = Rect.init(handle_x, rect.y, handle_width, height);
        self.renderer.drawRect(handle_rect, style.accent);

        // Handle dragging
        var changed = false;
        if (active and self.mouse_down) {
            const new_normalized = std.math.clamp(
                (self.mouse_x - rect.x - handle_width / 2) / (rect.width - handle_width),
                0,
                1,
            );
            const new_value = min_val + new_normalized * range;
            if (new_value != value.*) {
                value.* = new_value;
                changed = true;
            }
        }

        self.cursor_y += height + 4;
        return changed;
    }

    /// Draw a checkbox, returns true if value changed
    pub fn checkbox(self: *UIContext, comptime label_text: []const u8, checked: *bool) bool {
        const id = WidgetId.from(label_text, self.widget_count);
        self.widget_count += 1;

        const style = self.theme.button;
        const box_size: f32 = 18;
        const gap: f32 = 8;

        // Checkbox rect
        const rect = Rect.init(self.cursor_x + self.indent, self.cursor_y + 2, box_size, box_size);

        // Update state
        self.updateWidgetState(id, rect);
        const hovered = self.isHovered(id);
        const active = self.isActive(id);

        // Draw checkbox box
        const bg_color = style.getBackground(hovered, active, false);
        self.renderer.drawRect(rect, bg_color);
        self.renderer.drawRectBorder(rect, style.border, 1);

        // Draw checkmark if checked
        if (checked.*) {
            const inner = Rect.init(rect.x + 4, rect.y + 4, box_size - 8, box_size - 8);
            self.renderer.drawRect(inner, style.accent);
        }

        // Draw label
        if (self.font) |*font| {
            font.drawText(
                &self.renderer,
                label_text,
                rect.x + box_size + gap,
                self.cursor_y,
                style.foreground,
            );
        }

        self.cursor_y += self.line_height;

        // Toggle on click
        if (active and self.mouse_released) {
            checked.* = !checked.*;
            return true;
        }
        return false;
    }

    /// Add spacing between widgets
    pub fn spacing(self: *UIContext, amount: f32) void {
        self.cursor_y += amount;
    }

    /// Add a horizontal separator line
    pub fn separator(self: *UIContext) void {
        const width: f32 = 200;
        const rect = Rect.init(self.cursor_x + self.indent, self.cursor_y + 4, width, 1);
        self.renderer.drawRect(rect, self.theme.panel.border);
        self.cursor_y += 12;
    }

    /// Indent following widgets
    pub fn pushIndent(self: *UIContext, amount: f32) void {
        self.indent += amount;
    }

    /// Remove indentation
    pub fn popIndent(self: *UIContext, amount: f32) void {
        self.indent = @max(0, self.indent - amount);
    }

    /// Set the theme
    pub fn setTheme(self: *UIContext, theme: Theme) void {
        self.theme = theme;
    }
};
