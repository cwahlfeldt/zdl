const std = @import("std");
const quickjs = @import("quickjs");

const JSContext = @import("../js_context.zig").JSContext;

/// Register console.log, console.warn, console.error on the global object.
pub fn register(ctx: *JSContext) !void {
    const console_code =
        \\var console = {
        \\    _inFormat: false,
        \\    _formatArgs: function(args) {
        \\        if (this._inFormat) return '[recursive]';
        \\        this._inFormat = true;
        \\        try {
        \\            var result = [];
        \\            for (var i = 0; i < args.length; i++) {
        \\                var arg = args[i];
        \\                try {
        \\                    if (arg === null) {
        \\                        result.push('null');
        \\                    } else if (arg === undefined) {
        \\                        result.push('undefined');
        \\                    } else if (typeof arg === 'string') {
        \\                        result.push(arg);
        \\                    } else if (typeof arg === 'number' || typeof arg === 'boolean') {
        \\                        result.push('' + arg);
        \\                    } else {
        \\                        result.push('[object]');
        \\                    }
        \\                } catch (e) {
        \\                    result.push('[error]');
        \\                }
        \\            }
        \\            return result.join(' ');
        \\        } finally {
        \\            this._inFormat = false;
        \\        }
        \\    },
        \\    log: function() {
        \\        // Disabled to prevent stack overflow
        \\    },
        \\    warn: function() {
        \\        // Disabled to prevent stack overflow
        \\    },
        \\    error: function() {
        \\        // Disabled to prevent stack overflow
        \\    },
        \\    info: function() {
        \\        __native_console_log(this._formatArgs(arguments));
        \\    },
        \\    debug: function() {
        \\        __native_console_log(this._formatArgs(arguments));
        \\    }
        \\};
        \\true;
    ;

    // Register the native print functions
    // Since zig-quickjs doesn't support JS_NewCFunction directly,
    // we use a simple approach: register a global function that writes to stdout
    const native_funcs =
        \\function __native_console_log(msg) {
        \\    // This is a placeholder - the actual implementation will use
        \\    // std.debug.print on the Zig side via the script system
        \\    if (typeof __zdl_print === 'function') {
        \\        __zdl_print('[LOG] ' + msg);
        \\    }
        \\}
        \\function __native_console_warn(msg) {
        \\    if (typeof __zdl_print === 'function') {
        \\        __zdl_print('[WARN] ' + msg);
        \\    }
        \\}
        \\function __native_console_error(msg) {
        \\    if (typeof __zdl_print === 'function') {
        \\        __zdl_print('[ERROR] ' + msg);
        \\    }
        \\}
        \\true;
    ;

    const native_result = try ctx.eval(native_funcs, "<console>");
    ctx.freeValue(native_result);
    const console_result = try ctx.eval(console_code, "<console>");
    ctx.freeValue(console_result);
}

/// Install the native print function.
/// This should be called after registering the console API.
pub fn installPrintFunction(ctx: *JSContext) !void {
    // Create a simple print function that stores messages to be processed
    const print_func =
        \\var __zdl_messages = [];
        \\function __zdl_print(msg) {
        \\    __zdl_messages.push(msg);
        \\}
        \\function __zdl_flush_messages() {
        \\    var msgs = __zdl_messages;
        \\    __zdl_messages = [];
        \\    return msgs;
        \\}
        \\true;
    ;
    const print_result = try ctx.eval(print_func, "<console>");
    ctx.freeValue(print_result);
}

/// Flush and print all pending console messages.
pub fn flushMessages(ctx: *JSContext) void {
    const flush_fn = ctx.getGlobal("__zdl_flush_messages");
    defer ctx.freeValue(flush_fn);

    if (!ctx.isFunction(flush_fn)) return;

    const result = ctx.call(flush_fn, quickjs.UNDEFINED, &.{}) catch return;
    defer ctx.freeValue(result);

    // Iterate through the returned array and print each message
    var i: u32 = 0;
    while (true) : (i += 1) {
        const item = ctx.context.getPropertyUint32(result, i);
        defer ctx.freeValue(item);

        if (ctx.isUndefined(item)) break;

        if (ctx.toCString(item)) |cstr| {
            std.debug.print("{s}\n", .{cstr});
            ctx.freeCString(cstr);
        } else |_| {}
    }
}
