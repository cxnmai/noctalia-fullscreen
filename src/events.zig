const model = @import("state.zig");
const Value = @import("std").json.Value;
const get = model.get;

// Returns whether output dimensions may have changed. Unknown events are ignored.
pub fn apply(state: *model.State, event: Value) !bool {
    const ws = get(event, "WorkspacesChanged");
    if (ws != .null) {
        state.workspaces.clearRetainingCapacity();
        for (get(ws, "workspaces").array.items) |value| {
            const output = get(value, "output");
            try state.workspaces.append(state.allocator, .{
                .id = model.id(get(value, "id")),
                .output = if (output == .null) null else try model.Name.init(output.string),
                .active = get(value, "is_active").bool,
                .window = model.optionalId(get(value, "active_window_id")),
            });
        }
        return true;
    }
    const activated = get(event, "WorkspaceActivated");
    if (activated != .null) {
        const target = model.id(get(activated, "id"));
        var output: ?model.Name = null;
        for (state.workspaces.items) |workspace| {
            if (workspace.id == target) {
                output = workspace.output;
                break;
            }
        }
        if (output) |name| {
            for (state.workspaces.items) |*workspace| {
                if (workspace.output != null and workspace.output.?.eql(&name)) workspace.active = workspace.id == target;
            }
        }
    }
    const active_window = get(event, "WorkspaceActiveWindowChanged");
    if (active_window != .null) {
        for (state.workspaces.items) |*workspace| {
            if (workspace.id == model.id(get(active_window, "workspace_id"))) {
                workspace.window = model.optionalId(get(active_window, "active_window_id"));
            }
        }
    }
    const windows = get(event, "WindowsChanged");
    if (windows != .null) {
        state.windows.clearRetainingCapacity();
        for (get(windows, "windows").array.items) |window| try state.putWindow(window);
    }
    const opened = get(event, "WindowOpenedOrChanged");
    if (opened != .null) try state.putWindow(get(opened, "window"));
    const closed = get(event, "WindowClosed");
    if (closed != .null) {
        for (state.windows.items, 0..) |window, i| {
            if (window.id == model.id(get(closed, "id"))) {
                _ = state.windows.swapRemove(i);
                break;
            }
        }
    }
    const layouts = get(event, "WindowLayoutsChanged");
    if (layouts != .null) {
        for (get(layouts, "changes").array.items) |change| {
            const pair = change.array.items;
            for (state.windows.items) |*window| {
                if (window.id == model.id(pair[0])) window.size = model.size(pair[1]);
            }
        }
    }
    return layouts != .null or get(event, "ConfigLoaded") != .null;
}
