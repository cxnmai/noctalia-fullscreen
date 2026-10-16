const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = std.json.Value;

pub const Name = struct {
    bytes: [256]u8 = undefined,
    len: usize = 0,
    pub fn init(s: []const u8) !Name {
        if (s.len == 0 or s.len >= 256) return error.InvalidOutputName;
        var name = Name{ .len = s.len };
        @memcpy(name.bytes[0..s.len], s);
        return name;
    }
    pub fn slice(self: *const Name) []const u8 {
        return self.bytes[0..self.len];
    }
    pub fn eql(a: *const Name, b: *const Name) bool {
        return std.mem.eql(u8, a.slice(), b.slice());
    }
};
pub const Output = struct {
    name: Name,
    size: [2]f64,
    applied: ?bool = null,
};
pub const Workspace = struct { id: u64, output: ?Name, active: bool, window: ?u64 };
pub const Window = struct { id: u64, workspace: ?u64, size: [2]f64 };

pub const State = struct {
    allocator: Allocator,
    outputs: std.ArrayList(Output) = .empty,
    workspaces: std.ArrayList(Workspace) = .empty,
    windows: std.ArrayList(Window) = .empty,
    pub fn deinit(self: *State) void {
        self.outputs.deinit(self.allocator);
        self.workspaces.deinit(self.allocator);
        self.windows.deinit(self.allocator);
    }
    pub fn desired(self: *const State, output: Output) bool {
        for (self.workspaces.items) |ws| {
            if (!ws.active or ws.output == null or !ws.output.?.eql(&output.name)) continue;
            for (self.windows.items) |window| {
                if (ws.window != window.id or window.workspace != ws.id) continue;
                // Niri's fullscreen tile includes the backdrop for fixed-size clients.
                // Normal/maximized/fake-fullscreen tiles exclude the reserved bar area.
                if (@abs(window.size[0] - output.size[0]) < 0.01 and
                    @abs(window.size[1] - output.size[1]) < 0.01) return true;
            }
        }
        return false;
    }
    pub fn setOutputs(self: *State, value: Value) !void {
        var next: std.ArrayList(Output) = .empty;
        errdefer next.deinit(self.allocator);
        var it = value.object.iterator();
        while (it.next()) |entry| {
            const logical = get(entry.value_ptr.*, "logical");
            if (logical == .null) continue;
            var output = Output{
                .name = try Name.init(entry.key_ptr.*),
                .size = .{ number(get(logical, "width")), number(get(logical, "height")) },
            };
            for (self.outputs.items) |old| {
                if (old.name.eql(&output.name)) {
                    output.applied = old.applied;
                    break;
                }
            }
            try next.append(self.allocator, output);
        }
        self.outputs.deinit(self.allocator);
        self.outputs = next;
    }
    pub fn putWindow(self: *State, value: Value) !void {
        const window = Window{
            .id = id(get(value, "id")),
            .workspace = optionalId(get(value, "workspace_id")),
            .size = size(get(value, "layout")),
        };
        for (self.windows.items) |*old| {
            if (old.id == window.id) {
                old.* = window;
                return;
            }
        }
        try self.windows.append(self.allocator, window);
    }
};

pub fn get(value: Value, key: []const u8) Value {
    return if (value == .object) value.object.get(key) orelse .null else .null;
}
pub fn id(value: Value) u64 {
    return @intCast(value.integer);
}
pub fn optionalId(value: Value) ?u64 {
    return if (value == .null) null else id(value);
}
pub fn number(value: Value) f64 {
    return switch (value) {
        .integer => @floatFromInt(value.integer),
        .float => value.float,
        else => 0,
    };
}
pub fn size(layout: Value) [2]f64 {
    const values = get(layout, "tile_size").array.items;
    return .{ number(values[0]), number(values[1]) };
}
