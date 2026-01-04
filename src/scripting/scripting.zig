// Scripting module for ZDL Engine
// Provides JavaScript scripting support via QuickJS

pub const JSRuntime = @import("js_runtime.zig").JSRuntime;
pub const JSContext = @import("js_context.zig").JSContext;
pub const ScriptComponent = @import("script_component.zig").ScriptComponent;
pub const ScriptSystem = @import("script_system.zig").ScriptSystem;

// Re-export bindings module for advanced usage
pub const bindings = @import("bindings/bindings.zig");
