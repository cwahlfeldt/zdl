const std = @import("std");
const quickjs = @import("quickjs");
const JSRuntime = @import("js_runtime.zig").JSRuntime;

/// JavaScript execution context.
/// Each scene can have its own context for isolation.
pub const JSContext = struct {
    context: quickjs.Context,
    runtime: *JSRuntime,
    allocator: std.mem.Allocator,
    global: quickjs.Value,

    const Self = @This();

    /// Initialize a new JavaScript context.
    pub fn init(runtime: *JSRuntime, allocator: std.mem.Allocator) Self {
        std.debug.print("[JSContext] Creating context from runtime ptr={*}...\n", .{runtime.runtime});
        const ctx = quickjs.Context.init(runtime.runtime);
        std.debug.print("[JSContext] Context created, ptr={?}\n", .{ctx.ptr});

        // Skip intrinsics - they cause crashes with this QuickJS version
        // We'll provide our own Math object implementation
        std.debug.print("[JSContext] Skipping intrinsics (causes crashes)\n", .{});

        std.debug.print("[JSContext] Getting global object...\n", .{});
        const global = ctx.getGlobalObject();
        std.debug.print("[JSContext] Got global object\n", .{});

        return .{
            .context = ctx,
            .runtime = runtime,
            .allocator = allocator,
            .global = global,
        };
    }

    /// Deinitialize the context.
    pub fn deinit(self: *Self) void {
        self.context.freeValue(self.global);
        self.context.deinit();
    }

    /// Evaluate JavaScript code and return the result.
    pub fn eval(self: *Self, code: []const u8, filename: [:0]const u8) !quickjs.Value {
        const result = self.context.eval(code, filename, .{}) catch |err| {
            self.logException();
            return err;
        };

        if (self.context.isException(result)) {
            self.logException();
            return error.Exception;
        }

        return result;
    }

    /// Evaluate JavaScript code as a module.
    pub fn evalModule(self: *Self, code: []const u8, filename: [:0]const u8) !quickjs.Value {
        const result = self.context.eval(code, filename, .{ .type = .module }) catch |err| {
            self.logException();
            return err;
        };

        if (self.context.isException(result)) {
            self.logException();
            return error.Exception;
        }

        return result;
    }

    /// Call a JavaScript function.
    pub fn call(self: *Self, func: quickjs.Value, this: quickjs.Value, args: []const quickjs.Value) !quickjs.Value {
        const result = self.context.call(func, this, args);

        if (self.context.isException(result)) {
            self.logException();
            return error.Exception;
        }

        return result;
    }

    /// Process pending async jobs (promises).
    pub fn processPendingJobs(self: *Self) void {
        while (self.runtime.isJobPending()) {
            _ = self.runtime.runtime.executePendingJob() catch break;
        }
    }

    /// Get a property from an object.
    pub fn getProperty(self: *Self, obj: quickjs.Value, name: [:0]const u8) quickjs.Value {
        return self.context.getPropertyStr(obj, name);
    }

    /// Set a property on an object.
    pub fn setProperty(self: *Self, obj: quickjs.Value, name: [:0]const u8, value: quickjs.Value) !void {
        try self.context.setPropertyStr(obj, name, value);
    }

    /// Set a property on the global object.
    pub fn setGlobal(self: *Self, name: [:0]const u8, value: quickjs.Value) !void {
        try self.context.setPropertyStr(self.global, name, value);
    }

    /// Get a property from the global object.
    pub fn getGlobal(self: *Self, name: [:0]const u8) quickjs.Value {
        return self.context.getPropertyStr(self.global, name);
    }

    /// Create a new JavaScript object.
    pub fn newObject(self: *Self) quickjs.Value {
        return self.context.newObject();
    }

    /// Create a new JavaScript array.
    pub fn newArray(self: *Self) quickjs.Value {
        return self.context.newArray();
    }

    /// Create a JavaScript number from f32.
    pub fn newFloat(self: *Self, value: f32) quickjs.Value {
        return self.context.newFloat64(@floatCast(value));
    }

    /// Create a JavaScript number from f64.
    pub fn newFloat64(self: *Self, value: f64) quickjs.Value {
        return self.context.newFloat64(value);
    }

    /// Create a JavaScript integer.
    pub fn newInt32(self: *Self, value: i32) quickjs.Value {
        return self.context.newInt32(value);
    }

    /// Create a JavaScript boolean.
    pub fn newBool(self: *Self, value: bool) quickjs.Value {
        return self.context.newBool(value);
    }

    /// Create a JavaScript string.
    pub fn newString(self: *Self, str: []const u8) quickjs.Value {
        return self.context.newString(str);
    }

    /// Convert JavaScript value to f32.
    pub fn toFloat32(self: *Self, value: quickjs.Value) !f32 {
        const f64_val = try self.context.toFloat64(value);
        return @floatCast(f64_val);
    }

    /// Convert JavaScript value to f64.
    pub fn toFloat64(self: *Self, value: quickjs.Value) !f64 {
        return try self.context.toFloat64(value);
    }

    /// Convert JavaScript value to i32.
    pub fn toInt32(self: *Self, value: quickjs.Value) !i32 {
        return try self.context.toInt32(value);
    }

    /// Convert JavaScript value to bool.
    pub fn toBool(self: *Self, value: quickjs.Value) !bool {
        return try self.context.toBool(value);
    }

    /// Convert JavaScript value to string (caller must free with freeCString).
    pub fn toCString(self: *Self, value: quickjs.Value) ![*:0]const u8 {
        return try self.context.toCString(value);
    }

    /// Free a C string obtained from toCString.
    pub fn freeCString(self: *Self, str: [*:0]const u8) void {
        self.context.freeCString(str);
    }

    /// Check if a value is a function.
    pub fn isFunction(self: *Self, value: quickjs.Value) bool {
        return self.context.isFunction(value);
    }

    /// Check if a value is an object.
    pub fn isObject(self: *Self, value: quickjs.Value) bool {
        return self.context.isObject(value);
    }

    /// Check if a value is undefined.
    pub fn isUndefined(self: *Self, value: quickjs.Value) bool {
        return self.context.isUndefined(value);
    }

    /// Check if a value is null.
    pub fn isNull(self: *Self, value: quickjs.Value) bool {
        return self.context.isNull(value);
    }

    /// Check if a value is a number.
    pub fn isNumber(self: *Self, value: quickjs.Value) bool {
        return self.context.isNumber(value);
    }

    /// Free a JavaScript value.
    pub fn freeValue(self: *Self, value: quickjs.Value) void {
        self.context.freeValue(value);
    }

    /// Duplicate a JavaScript value (increment reference count).
    pub fn dupValue(self: *Self, value: quickjs.Value) quickjs.Value {
        return self.context.dupValue(value);
    }

    /// Log the current exception to stderr.
    fn logException(self: *Self) void {
        if (!self.context.hasException()) return;

        const exception = self.context.getException();
        defer self.context.freeValue(exception);

        // Try to get the error message
        const str_val = self.context.toString(exception);
        defer self.context.freeValue(str_val);

        if (self.context.toCString(str_val)) |cstr| {
            std.debug.print("[JS Error] {s}\n", .{cstr});
            self.context.freeCString(cstr);
        } else |_| {
            std.debug.print("[JS Error] (unable to get error message)\n", .{});
        }

        // Try to get stack trace
        const stack = self.context.getPropertyStr(exception, "stack");
        defer self.context.freeValue(stack);

        if (!self.context.isUndefined(stack)) {
            if (self.context.toCString(stack)) |stack_cstr| {
                std.debug.print("{s}\n", .{stack_cstr});
                self.context.freeCString(stack_cstr);
            } else |_| {}
        }
    }
};
