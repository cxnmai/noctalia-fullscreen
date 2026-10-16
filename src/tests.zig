const std = @import("std");
const model = @import("state.zig");
const events = @import("events.zig");
const expect = std.testing.expect;

fn fixture() !model.State {
    var state = model.State{ .allocator = std.testing.allocator };
    errdefer state.deinit();
    const first = try model.Name.init("DP-1");
    const second = try model.Name.init("eDP-1");
    try state.outputs.append(state.allocator, .{ .name = first, .size = .{ 1920, 1080 } });
    try state.outputs.append(state.allocator, .{ .name = second, .size = .{ 1536, 960 } });
    try state.workspaces.append(state.allocator, .{ .id = 1, .output = first, .active = true, .window = 10 });
    try state.workspaces.append(state.allocator, .{ .id = 2, .output = first, .active = false, .window = 20 });
    try state.workspaces.append(state.allocator, .{ .id = 3, .output = second, .active = true, .window = 30 });
    try state.windows.append(state.allocator, .{ .id = 10, .workspace = 1, .size = .{ 1920, 1047 } });
    try state.windows.append(state.allocator, .{ .id = 20, .workspace = 2, .size = .{ 1920, 1080 } });
    try state.windows.append(state.allocator, .{ .id = 30, .workspace = 3, .size = .{ 1536, 960 } });
    return state;
}
fn apply(state: *model.State, json: []const u8) !bool {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    return events.apply(state, parsed.value);
}

test "ignore hidden fullscreen; independently detect unfocused monitor fullscreen" {
    var state = try fixture();
    defer state.deinit();
    try expect(!state.desired(state.outputs.items[0]));
    try expect(state.desired(state.outputs.items[1]));
}
test "real fullscreen enters and exits from layout events" {
    var state = try fixture();
    defer state.deinit();
    try expect(try apply(&state,
        \\{"WindowLayoutsChanged":{"changes":[[10,{"tile_size":[1920.0,1080.0]}]]}}
    ));
    try expect(state.desired(state.outputs.items[0]));
    _ = try apply(&state,
        \\{"WindowLayoutsChanged":{"changes":[[10,{"tile_size":[1920.0,1047.0]}]]}}
    );
    try expect(!state.desired(state.outputs.items[0]));
}
test "workspace switch reveals and then hides bar without closing fullscreen" {
    var state = try fixture();
    defer state.deinit();
    _ = try apply(&state, "{\"WorkspaceActivated\":{\"id\":2,\"focused\":true}}");
    try expect(state.desired(state.outputs.items[0]));
    _ = try apply(&state, "{\"WorkspaceActivated\":{\"id\":1,\"focused\":true}}");
    try expect(!state.desired(state.outputs.items[0]));
    try expect(state.desired(state.outputs.items[1]));
}
test "inactive fullscreen column and closed fullscreen do not hide bar" {
    var state = try fixture();
    defer state.deinit();
    _ = try apply(&state,
        \\{"WorkspaceActiveWindowChanged":{"workspace_id":3,"active_window_id":null}}
    );
    try expect(!state.desired(state.outputs.items[1]));
    _ = try apply(&state,
        \\{"WorkspaceActiveWindowChanged":{"workspace_id":3,"active_window_id":30}}
    );
    _ = try apply(&state, "{\"WindowClosed\":{\"id\":30}}");
    try expect(!state.desired(state.outputs.items[1]));
}
test "fixed-size client uses tile backdrop, not client size" {
    var state = try fixture();
    defer state.deinit();
    _ = try apply(&state,
        \\{"WindowOpenedOrChanged":{"window":{"id":10,"workspace_id":1,"layout":{"tile_size":[1920,1080],"window_size":[640,480]}}}}
    );
    try expect(state.desired(state.outputs.items[0]));
}
test "output refresh handles hotplug and keeps successfully applied mode" {
    var state = try fixture();
    defer state.deinit();
    state.outputs.items[0].applied = true;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"DP-1":{"logical":{"width":2560,"height":1440}},"disabled":{"logical":null}}
    , .{});
    defer parsed.deinit();
    try state.setOutputs(parsed.value);
    try expect(state.outputs.items.len == 1);
    try expect(state.outputs.items[0].applied.?);
    try expect(!state.desired(state.outputs.items[0]));
}
test "unknown future events are ignored" {
    var state = try fixture();
    defer state.deinit();
    try expect(!try apply(&state, "{\"NewEvent\":{\"anything\":true}}"));
}
