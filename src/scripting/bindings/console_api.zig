const std = @import("std");
const quickjs = @import("quickjs");

const JSContext = @import("../js_context.zig").JSContext;

/// Register console.log, console.warn, console.error on the global object.
pub fn register(ctx: *JSContext) !void {
    // Ultra-simple console - only handles first argument
    const console_code =
        \\var console = {
        \\    log: function() {
        \\        if (arguments.length > 0) __zdl_print(arguments[0]);
        \\    },
        \\    warn: function() {
        \\        if (arguments.length > 0) __zdl_print(arguments[0]);
        \\    },
        \\    error: function() {
        \\        if (arguments.length > 0) __zdl_print(arguments[0]);
        \\    },
        \\    info: function() {
        \\        if (arguments.length > 0) __zdl_print(arguments[0]);
        \\    },
        \\    debug: function() {
        \\        if (arguments.length > 0) __zdl_print(arguments[0]);
        \\    }
        \\};
        \\true;
    ;

    const console_result = try ctx.eval(console_code, "<console>");
    ctx.freeValue(console_result);
}

/// Install the native print function.
/// This should be called after registering the console API.
pub fn installPrintFunction(ctx: *JSContext) !void {
    // Create a simple print function that stores messages to be processed
    // Use array indexing instead of push() to avoid toString() calls
    const print_func =
        \\var __zdl_messages = [];
        \\var __zdl_messages_count = 0;
        \\function __zdl_print(msg) {
        \\    __zdl_messages[__zdl_messages_count++] = msg;
        \\}
        \\function __zdl_flush_messages() {
        \\    var msgs = [];
        \\    for (var i = 0; i < __zdl_messages_count; i++) {
        \\        msgs[i] = __zdl_messages[i];
        \\    }
        \\    __zdl_messages = [];
        \\    __zdl_messages_count = 0;
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
