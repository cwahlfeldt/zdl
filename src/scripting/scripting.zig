// Scripting module for ZDL Engine
// Provides JavaScript scripting support via QuickJS

pub const JSRuntime = @import("js_runtime.zig").JSRuntime;
pub const JSContext = @import("js_context.zig").JSContext;
pub const ScriptComponent = @import("script_component.zig").ScriptComponent;
pub const ScriptSystem = @import("script_system.zig").ScriptSystem;
pub const ModuleLoader = @import("module_loader.zig").ModuleLoader;

// Re-export bindings module for advanced usage
pub const bindings = @import("bindings/bindings.zig");

// Re-export module loading utilities
pub const evalWithImportSupport = @import("module_loader.zig").evalWithImportSupport;
pub const evalFile = @import("module_loader.zig").evalFile;
