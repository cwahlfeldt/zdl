# User Interface System

## Overview

A flexible, immediate-mode inspired UI system for building in-game interfaces, debug overlays, menus, and HUDs. The system should support both retained-mode widgets for complex UIs and immediate-mode patterns for rapid prototyping and debug tools.

## Current State

ZDL currently has **no UI system**. All rendering goes through the 3D pipeline with mesh renderers. There is no 2D rendering path, text rendering, or input event routing for UI elements.

## Goals

- Render 2D UI elements over the 3D scene
- Support text rendering with bitmap and signed-distance field (SDF) fonts
- Provide common widgets: buttons, sliders, panels, text input, lists
- Enable debug overlays (entity inspector, performance graphs)
- Handle input focus and event routing
- Support theming and styling
- Maintain 60+ FPS with complex UIs

## Architecture

### Directory Structure

```
src/
├── ui/
│   ├── ui.zig                 # Module exports
│   ├── ui_context.zig         # UI state and frame management
│   ├── ui_renderer.zig        # 2D batch renderer
│   ├── font.zig               # Font loading and text layout
│   ├── style.zig              # Theming and styling
│   ├── layout.zig             # Layout engine (flexbox-like)
│   ├── input_router.zig       # UI input handling
│   └── widgets/
│       ├── widget.zig         # Base widget interface
│       ├── panel.zig          # Container panel
│       ├── button.zig         # Clickable button
│       ├── label.zig          # Text label
│       ├── slider.zig         # Value slider
│       ├── text_input.zig     # Text entry field
│       ├── checkbox.zig       # Toggle checkbox
│       ├── dropdown.zig       # Dropdown selector
│       └── scroll_view.zig    # Scrollable container
```

### Core Components

#### UIContext

Central state manager for UI rendering:

```zig
pub const UIContext = struct {
    allocator: std.mem.Allocator,
    renderer: *UIRenderer,
    font: *Font,
    style: Style,

    // Input state
    mouse_pos: Vec2,
    mouse_down: bool,
    hot_id: ?WidgetId,      // Hovered widget
    active_id: ?WidgetId,   // Currently interacting
    focus_id: ?WidgetId,    // Keyboard focus

    // Frame state
    draw_list: DrawList,

    pub fn begin(self: *UIContext) void;
    pub fn end(self: *UIContext) void;
    pub fn render(self: *UIContext, frame: *RenderFrame) void;
};
```

#### UIRenderer

Batched 2D renderer for efficient UI drawing:

```zig
pub const UIRenderer = struct {
    device: *sdl.gpu.Device,
    pipeline_2d: *sdl.gpu.GraphicsPipeline,
    vertex_buffer: *sdl.gpu.Buffer,
    index_buffer: *sdl.gpu.Buffer,
    white_texture: *Texture,

    // Batch state
    vertices: std.ArrayList(Vertex2D),
    indices: std.ArrayList(u32),
    current_texture: ?*Texture,

    pub fn drawRect(self: *UIRenderer, rect: Rect, color: Color) void;
    pub fn drawTexturedRect(self: *UIRenderer, rect: Rect, texture: *Texture, uv: Rect) void;
    pub fn drawText(self: *UIRenderer, text: []const u8, pos: Vec2, font: *Font, color: Color) void;
    pub fn drawLine(self: *UIRenderer, from: Vec2, to: Vec2, color: Color, thickness: f32) void;
    pub fn flush(self: *UIRenderer, frame: *RenderFrame) void;
};
```

#### Font System

Text rendering with multiple backend support:

```zig
pub const Font = struct {
    texture: *Texture,
    glyphs: std.AutoHashMap(u32, Glyph),  // Unicode codepoint -> glyph
    line_height: f32,
    ascender: f32,
    descender: f32,

    pub fn loadBitmap(allocator: Allocator, path: []const u8) !Font;
    pub fn loadSDF(allocator: Allocator, path: []const u8) !Font;
    pub fn measureText(self: *Font, text: []const u8) Vec2;
    pub fn getGlyph(self: *Font, codepoint: u32) ?Glyph;
};

pub const Glyph = struct {
    uv: Rect,           // UV coordinates in atlas
    size: Vec2,         // Glyph size in pixels
    bearing: Vec2,      // Offset from baseline
    advance: f32,       // Horizontal advance
};
```

### Widget System

#### Immediate-Mode API

For quick prototyping and debug UIs:

```zig
// Usage example
pub fn drawDebugUI(ui: *UIContext) void {
    if (ui.beginPanel("Debug Info", .{ .x = 10, .y = 10 })) {
        ui.label("FPS: {d:.1}", .{fps});
        ui.label("Entities: {d}", .{entity_count});

        if (ui.button("Reset Camera")) {
            resetCamera();
        }

        _ = ui.slider("Speed", &speed, 0.0, 10.0);

        ui.endPanel();
    }
}
```

#### Widget Interface

Base interface for all widgets:

```zig
pub const Widget = struct {
    id: WidgetId,
    rect: Rect,
    style: *Style,

    // Callbacks
    onDraw: fn(*Widget, *UIRenderer) void,
    onInput: fn(*Widget, *InputEvent) bool,
    onLayout: fn(*Widget, Constraints) Size,
};

pub const WidgetId = struct {
    hash: u64,

    pub fn from(comptime str: []const u8, index: usize) WidgetId;
    pub fn fromPtr(ptr: *const anyopaque) WidgetId;
};
```

### Layout System

Flexbox-inspired layout for automatic positioning:

```zig
pub const Layout = struct {
    direction: Direction,      // .row or .column
    justify: Justify,          // .start, .center, .end, .space_between
    align_items: Align,        // .start, .center, .end, .stretch
    padding: Insets,
    spacing: f32,

    pub fn compute(self: *Layout, children: []Widget, available: Size) void;
};
```

### Styling

Theming system for consistent appearance:

```zig
pub const Style = struct {
    // Colors
    background: Color,
    foreground: Color,
    accent: Color,
    border: Color,

    // Dimensions
    border_radius: f32,
    border_width: f32,
    padding: Insets,

    // Text
    font_size: f32,

    // States
    hover: StyleModifiers,
    active: StyleModifiers,
    disabled: StyleModifiers,
};

pub const Theme = struct {
    pub fn dark() Theme;
    pub fn light() Theme;
    pub fn custom(config: ThemeConfig) Theme;
};
```

## Implementation Steps

### Phase 1: Foundation
1. Create 2D rendering pipeline with orthographic projection
2. Implement batched quad renderer with texture support
3. Add basic font loading (bitmap fonts, BMFont format)
4. Create UIContext with frame begin/end lifecycle

### Phase 2: Core Widgets
1. Implement widget ID system for state tracking
2. Create panel/window container
3. Add label and button widgets
4. Implement input routing (mouse hover, click, drag)

### Phase 3: Advanced Widgets
1. Slider with drag interaction
2. Text input with cursor and selection
3. Checkbox and radio buttons
4. Dropdown/combo box
5. Scroll view with scrollbars

### Phase 4: Layout Engine
1. Implement constraint-based sizing
2. Add flexbox-style layout containers
3. Support nested layouts
4. Auto-sizing based on content

### Phase 5: Polish
1. SDF font rendering for crisp text at any size
2. Smooth animations and transitions
3. Keyboard navigation
4. Gamepad UI navigation
5. Accessibility considerations

## Integration Points

### Engine Integration

```zig
// In engine.zig
pub const Engine = struct {
    ui_context: ?*UIContext,

    pub fn initUI(self: *Engine) !void {
        self.ui_context = try UIContext.init(self.allocator, self.device);
    }

    // In render loop, after 3D rendering
    if (self.ui_context) |ui| {
        ui.begin();
        update_fn(self, scene, input, delta_time, ui);
        ui.end();
        ui.render(frame);
    }
};
```

### Input System Integration

The UI system needs priority access to input events:

```zig
// Input events flow: Raw SDL → UI System → Game Input
pub fn processEvent(ui: *UIContext, input: *Input, event: sdl.Event) bool {
    // UI gets first chance at input
    if (ui.handleEvent(event)) {
        return true;  // Event consumed by UI
    }
    // Otherwise, pass to game input
    input.handleEvent(event);
    return false;
}
```

### Debug Tools

Built-in debug UIs using the system:

```zig
pub const DebugUI = struct {
    pub fn entityInspector(ui: *UIContext, scene: *Scene) void;
    pub fn performanceOverlay(ui: *UIContext, stats: EngineStats) void;
    pub fn sceneHierarchy(ui: *UIContext, scene: *Scene) void;
    pub fn componentEditor(ui: *UIContext, entity: Entity, scene: *Scene) void;
};
```

## Dependencies

- **Font Loading**: Consider stb_truetype or FreeType bindings for TTF support
- **Text Shaping**: Optional HarfBuzz for complex scripts
- **Image Loading**: Existing SDL image loading for font atlases

## Performance Considerations

- Batch all UI draws to minimize draw calls
- Use texture atlases for icons and glyphs
- Cache layout calculations when UI structure unchanged
- Dirty-rectangle rendering for partial updates (optional optimization)
- Use SDF fonts for resolution-independent text

## Open Questions

1. Should the UI system support multiple windows/viewports?
2. Do we need immediate-mode only, or also retained-mode widgets?
3. What level of accessibility support is required?
4. Should UI support localization/internationalization from the start?

## References

- [Dear ImGui](https://github.com/ocornut/imgui) - Immediate-mode UI inspiration
- [Flutter Layout](https://flutter.dev/docs/development/ui/layout) - Flexbox-like layout
- [BMFont](https://www.angelcode.com/products/bmfont/) - Bitmap font format
- [SDF Text Rendering](https://steamcdn-a.akamaihd.net/apps/valve/2007/SIGGRAPH2007_AlphaTestedMagnification.pdf) - Valve's SDF technique
