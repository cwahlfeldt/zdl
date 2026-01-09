const std = @import("std");
const quickjs = @import("quickjs");
const JSContext = @import("js_context.zig").JSContext;

/// Module loader for ZDL engine modules.
/// Provides ES6 module support for built-in modules like "zdl".
pub const ModuleLoader = struct {
    allocator: std.mem.Allocator,
    modules: std.StringHashMap([]const u8),

    const Self = @This();

    /// Initialize the module loader.
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .modules = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Deinitialize the module loader.
    pub fn deinit(self: *Self) void {
        var it = self.modules.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.modules.deinit();
    }

    /// Register a built-in module with code.
    pub fn registerModule(self: *Self, name: []const u8, code: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        const code_copy = try self.allocator.dupe(u8, code);
        errdefer self.allocator.free(code_copy);

        try self.modules.put(name_copy, code_copy);
    }

    /// Get module code by name.
    pub fn getModuleCode(self: *Self, name: []const u8) ?[]const u8 {
        return self.modules.get(name);
    }

    /// Setup the "zdl" built-in module.
    /// This creates an ES6 module that exports the zdl global object.
    pub fn setupZdlModule(self: *Self) !void {
        const zdl_module_code =
            \\// ZDL Engine Module
            \\// This module provides access to the ZDL game engine APIs.
            \\
            \\// The zdl global object is already registered by the bindings
            \\export default zdl;
            \\
            \\// Named exports for convenience
            \\export const createWindow = zdl.createWindow;
            \\export const createWorld = zdl.createWorld;
            \\
        ;
        try self.registerModule("zdl", zdl_module_code);
    }

    /// Load a module into the context.
    /// For built-in modules, returns the module code.
    /// For file-based modules, reads from the filesystem.
    pub fn loadModule(self: *Self, module_name: []const u8) ![]const u8 {
        // Check if it's a built-in module
        if (self.getModuleCode(module_name)) |code| {
            return code;
        }

        // Try to load from filesystem
        const file = std.fs.cwd().openFile(module_name, .{}) catch |err| {
            std.debug.print("[ModuleLoader] Failed to load module '{s}': {}\n", .{ module_name, err });
            return error.ModuleNotFound;
        };
        defer file.close();

        const max_size = 1024 * 1024; // 1MB max
        const contents = try file.readToEndAlloc(self.allocator, max_size);
        return contents;
    }

    /// Install a simple module resolver in the JavaScript context.
    /// This provides a require() function that can load modules.
    pub fn installRequireFunction(self: *Self, ctx: *JSContext) !void {
        _ = self;

        // Create a simple require() function for module loading
        // This is a fallback for older JavaScript code
        const require_code =
            \\if (typeof require === 'undefined') {
            \\    function require(name) {
            \\        throw new Error('Module "' + name + '" not found. Use ES6 imports instead: import ... from "' + name + '"');
            \\    }
            \\}
            \\true;
        ;

        const result = try ctx.eval(require_code, "<require>");
        ctx.freeValue(result);
    }
};

/// Helper to evaluate code with import support.
/// This transforms simple import statements to work with our global objects.
pub fn evalWithImportSupport(ctx: *JSContext, code: []const u8, filename: [:0]const u8) !quickjs.Value {
    // Transform "import zdl from 'zdl'" or 'import zdl from "zdl"' to use the global
    var transformed: std.ArrayList(u8) = .{};
    defer transformed.deinit(ctx.allocator);

    try transformed.appendSlice(ctx.allocator,
        \\// ZDL Module Loader Wrapper
        \\// Transforms ES6 imports to globals
        \\
    );

    // Simple import statement transformation
    // This is a basic implementation that handles the common case
    var lines = std.mem.splitScalar(u8, code, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Check for "import zdl from 'zdl'" or "import zdl from \"zdl\""
        if (std.mem.startsWith(u8, trimmed, "import ") and
            (std.mem.indexOf(u8, trimmed, "from 'zdl'") != null or
            std.mem.indexOf(u8, trimmed, "from \"zdl\"") != null))
        {
            // For "import zdl from 'zdl'", we don't need to do anything since zdl is already global
            // Just skip the import line entirely
            if (std.mem.indexOf(u8, trimmed, " from ")) |_| {
                continue;
            }
        }

        // Keep other lines as-is
        try transformed.appendSlice(ctx.allocator, line);
        try transformed.append(ctx.allocator, '\n');
    }

    // Create a null-terminated copy for QuickJS
    const code_z = try ctx.allocator.dupeZ(u8, transformed.items);
    defer ctx.allocator.free(code_z);

    return try ctx.eval(code_z, filename);
}

/// Evaluate a JavaScript file as a module with import support.
pub fn evalFile(ctx: *JSContext, path: []const u8) !quickjs.Value {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const max_size = 1024 * 1024; // 1MB max
    const contents = try file.readToEndAlloc(ctx.allocator, max_size);
    defer ctx.allocator.free(contents);

    // Create a null-terminated filename for QuickJS
    const filename_z = try ctx.allocator.dupeZ(u8, path);
    defer ctx.allocator.free(filename_z);

    return try evalWithImportSupport(ctx, contents, filename_z);
}

test "ModuleLoader init/deinit" {
    var loader = ModuleLoader.init(std.testing.allocator);
    defer loader.deinit();

    try std.testing.expect(loader.modules.count() == 0);
}

test "ModuleLoader register and get module" {
    var loader = ModuleLoader.init(std.testing.allocator);
    defer loader.deinit();

    try loader.registerModule("test", "console.log('test');");

    const code = loader.getModuleCode("test");
    try std.testing.expect(code != null);
    try std.testing.expectEqualStrings("console.log('test');", code.?);
}

test "ModuleLoader setup zdl module" {
    var loader = ModuleLoader.init(std.testing.allocator);
    defer loader.deinit();

    try loader.setupZdlModule();

    const zdl_code = loader.getModuleCode("zdl");
    try std.testing.expect(zdl_code != null);
    try std.testing.expect(std.mem.indexOf(u8, zdl_code.?, "export default zdl") != null);
}

test "evalWithImportSupport transforms imports" {
    const JSRuntime = @import("js_runtime.zig").JSRuntime;
    var runtime = try JSRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    var ctx = JSContext.init(&runtime, std.testing.allocator);
    defer ctx.deinit();

    // Set up a fake zdl object
    const setup_code =
        \\var zdl = { test: 'value' };
        \\true;
    ;
    const setup_result = try ctx.eval(setup_code, "<setup>");
    ctx.freeValue(setup_result);

    // Test import transformation
    const test_code =
        \\import zdl from "zdl";
        \\const result = zdl.test;
        \\result;
    ;

    const result = try evalWithImportSupport(&ctx, test_code, "<test>");
    defer ctx.freeValue(result);

    // Check that the import was transformed and executed correctly
    const result_str = try ctx.toCString(result);
    defer ctx.freeCString(result_str);

    try std.testing.expectEqualStrings("value", std.mem.span(result_str));
}
