const component_api = @import("scripting/bindings/component_api.zig");
const query_api = @import("scripting/bindings/query_api.zig");
const world_api = @import("scripting/bindings/world_api.zig");
const js_component_storage = @import("scripting/js_component_storage.zig");

test {
    _ = component_api;
    _ = query_api;
    _ = world_api;
    _ = js_component_storage;
}
