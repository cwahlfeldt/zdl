const std = @import("std");
const quickjs = @import("quickjs");

const Entity = @import("../ecs/entity.zig").Entity;
const JSContext = @import("js_context.zig").JSContext;
const bindings = @import("bindings/bindings.zig");

/// Component that attaches a JavaScript script to an entity.
/// Scripts have lifecycle hooks: onStart, onUpdate, onDestroy.
pub const ScriptComponent = struct {
    /// Path to the script file
    script_path: []const u8,

    /// Cached JavaScript instance object
    instance: quickjs.Value,

    /// Cached method references for performance
    on_start: quickjs.Value,
    on_update: quickjs.Value,
    on_destroy: quickjs.Value,

    /// Whether onStart has been called
    started: bool,

    /// Whether this component is enabled
    enabled: bool,

    /// Last modification time (for hot reload)
    last_modified: i128,

    /// Whether the script loaded successfully
    loaded: bool,

    const Self = @This();

    /// Create a new ScriptComponent with a script path.
    pub fn init(script_path: []const u8) Self {
        return .{
            .script_path = script_path,
            .instance = quickjs.UNDEFINED,
            .on_start = quickjs.UNDEFINED,
            .on_update = quickjs.UNDEFINED,
            .on_destroy = quickjs.UNDEFINED,
            .started = false,
            .enabled = true,
            .last_modified = 0,
            .loaded = false,
        };
    }

    /// Load and compile the script.
    pub fn load(self: *Self, ctx: *JSContext, entity: Entity, allocator: std.mem.Allocator) !void {
        // Read script file
        const file = std.fs.cwd().openFile(self.script_path, .{}) catch |err| {
            std.debug.print("[Script] Failed to open script '{s}': {any}\n", .{ self.script_path, err });
            return err;
        };
        defer file.close();

        const stat = try file.stat();
        self.last_modified = stat.mtime;

        const code = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(code);

        // Wrap the script to avoid global redeclarations on hot-reload.
        const wrapped_code = try wrapScriptForEval(allocator, code);
        defer allocator.free(wrapped_code);

        // Create null-terminated filename
        var filename_buf: [256]u8 = undefined;
        const filename = std.fmt.bufPrintZ(&filename_buf, "{s}", .{self.script_path}) catch "<script>";

        // Evaluate the script to get the class constructor
        const class_result = ctx.eval(wrapped_code, filename) catch |err| {
            std.debug.print("[Script] Failed to evaluate script '{s}': {any}\n", .{ self.script_path, err });
            return err;
        };

        // If the result is a function (class), instantiate it
        if (ctx.isFunction(class_result)) {
            // Create instance using 'new'
            // Build the instantiation code
            const inst_code =
                \\(function(__Class, __entity) {
                \\var __instance = new __Class();
                \\__instance.entity = __entity;
                \\__instance.transform = __entity_getTransform(__entity);
                \\__instance.getTransform = function() { return __entity_getTransform(this.entity); };
                \\return __instance;
                \\})
            ;

            const inst_fn = ctx.eval(inst_code, "<instantiate>") catch {
                ctx.freeValue(class_result);
                return error.Exception;
            };
            defer ctx.freeValue(inst_fn);

            // Create entity JS object
            const entity_js = bindings.entityToJS(ctx, entity);

            // Call the instantiation function
            const instance = ctx.call(inst_fn, quickjs.UNDEFINED, &.{ class_result, entity_js }) catch {
                ctx.freeValue(class_result);
                ctx.freeValue(entity_js);
                return error.Exception;
            };
            ctx.freeValue(class_result);
            ctx.freeValue(entity_js);

            self.instance = instance;
        } else if (ctx.isObject(class_result)) {
            // Result is already an object instance
            self.instance = class_result;

            // Set entity and transform on the instance
            const entity_js = bindings.entityToJS(ctx, entity);
            ctx.setProperty(self.instance, "entity", entity_js) catch {};

            // Build transform getter code
            var get_transform_code: [128]u8 = undefined;
            const transform_code_str = std.fmt.bufPrintZ(&get_transform_code, "__entity_getTransform({{id:{d},valid:true}})", .{entity.id}) catch return error.Exception;
            const transform_js = ctx.eval(transform_code_str, "<transform>") catch return error.Exception;
            ctx.setProperty(self.instance, "transform", transform_js) catch {};
        } else {
            ctx.freeValue(class_result);
            std.debug.print("[Script] Script '{s}' did not return a class or object\n", .{self.script_path});
            return error.InvalidScript;
        }

        self.loaded = true;

        // Cache method references
        self.on_start = ctx.getProperty(self.instance, "onStart");
        self.on_update = ctx.getProperty(self.instance, "onUpdate");
        self.on_destroy = ctx.getProperty(self.instance, "onDestroy");

        std.debug.print("[Script] Loaded: {s}\n", .{self.script_path});
    }

    fn wrapScriptForEval(allocator: std.mem.Allocator, code: []const u8) ![]u8 {
        var end = code.len;
        while (end > 0 and std.ascii.isWhitespace(code[end - 1])) : (end -= 1) {}

        if (end == 0) return allocator.dupe(u8, code);

        if (code[end - 1] == ';') {
            end -= 1;
            while (end > 0 and std.ascii.isWhitespace(code[end - 1])) : (end -= 1) {}
        }

        if (end == 0) return allocator.dupe(u8, code);

        var start = end;
        while (start > 0 and isIdentChar(code[start - 1])) : (start -= 1) {}

        if (start == end or !isIdentStart(code[start])) {
            return allocator.dupe(u8, code);
        }

        const ident = code[start..end];

        var wrapped = std.array_list.Managed(u8).init(allocator);
        errdefer wrapped.deinit();

        try wrapped.appendSlice("(function(){\n");
        try wrapped.appendSlice(code[0..start]);
        try wrapped.appendSlice("return ");
        try wrapped.appendSlice(ident);
        try wrapped.appendSlice(";\n})();");

        return wrapped.toOwnedSlice();
    }

    fn isIdentChar(ch: u8) bool {
        return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '$';
    }

    fn isIdentStart(ch: u8) bool {
        return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$';
    }

    /// Check if the script file has been modified.
    pub fn needsReload(self: *Self) bool {
        const file = std.fs.cwd().openFile(self.script_path, .{}) catch return false;
        defer file.close();

        const stat = file.stat() catch return false;
        return stat.mtime > self.last_modified;
    }

    /// Reload the script (call onDestroy first if started).
    pub fn reload(self: *Self, ctx: *JSContext, entity: Entity, allocator: std.mem.Allocator) !void {
        // Call onDestroy if the script was started
        if (self.started and self.loaded) {
            self.callDestroy(ctx);
        }

        // Free old references
        self.cleanup(ctx);

        // Reload
        try self.load(ctx, entity, allocator);

        // Call onStart again
        if (self.loaded) {
            self.callStart(ctx);
        }
    }

    /// Call the onStart lifecycle hook.
    pub fn callStart(self: *Self, ctx: *JSContext) void {
        if (self.started or !self.enabled or !self.loaded) return;

        if (ctx.isFunction(self.on_start)) {
            const result = ctx.call(self.on_start, self.instance, &.{}) catch {
                std.debug.print("[Script] Error in onStart: {s}\n", .{self.script_path});
                return;
            };
            ctx.freeValue(result);
        }

        self.started = true;
    }

    /// Call the onUpdate lifecycle hook.
    pub fn callUpdate(self: *Self, ctx: *JSContext, delta_time: f32) void {
        if (!self.started or !self.enabled or !self.loaded) return;

        if (ctx.isFunction(self.on_update)) {
            const dt_val = ctx.newFloat(delta_time);
            defer ctx.freeValue(dt_val);
            const result = ctx.call(self.on_update, self.instance, &.{dt_val}) catch {
                std.debug.print("[Script] Error in onUpdate: {s}\n", .{self.script_path});
                return;
            };
            ctx.freeValue(result);
        }
    }

    /// Call the onDestroy lifecycle hook.
    pub fn callDestroy(self: *Self, ctx: *JSContext) void {
        if (!self.started or !self.loaded) return;

        if (ctx.isFunction(self.on_destroy)) {
            const result = ctx.call(self.on_destroy, self.instance, &.{}) catch {
                std.debug.print("[Script] Error in onDestroy: {s}\n", .{self.script_path});
                return;
            };
            ctx.freeValue(result);
        }
    }

    /// Clean up JavaScript references.
    pub fn cleanup(self: *Self, ctx: *JSContext) void {
        if (!ctx.isUndefined(self.on_start)) {
            ctx.freeValue(self.on_start);
            self.on_start = quickjs.UNDEFINED;
        }
        if (!ctx.isUndefined(self.on_update)) {
            ctx.freeValue(self.on_update);
            self.on_update = quickjs.UNDEFINED;
        }
        if (!ctx.isUndefined(self.on_destroy)) {
            ctx.freeValue(self.on_destroy);
            self.on_destroy = quickjs.UNDEFINED;
        }
        if (!ctx.isUndefined(self.instance)) {
            ctx.freeValue(self.instance);
            self.instance = quickjs.UNDEFINED;
        }

        self.loaded = false;
        self.started = false;
    }
};
