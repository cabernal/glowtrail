const math = @import("math.zig");

pub const WorldW: f32 = 1280.0;
pub const WorldH: f32 = 720.0;
pub const PlayerRadius: f32 = 13.0;

pub const Rail = struct {
    points: []const math.Vec2,
    loop: bool = false,
    speed: f32 = 330.0,
    tint: [4]f32 = .{ 0.56, 0.84, 0.90, 1.0 },
};

const rail_a_points = [_]math.Vec2{
    .{ .x = 135.0, .y = 562.0 },
    .{ .x = 312.0, .y = 562.0 },
    .{ .x = 312.0, .y = 184.0 },
    .{ .x = 548.0, .y = 184.0 },
    .{ .x = 548.0, .y = 456.0 },
    .{ .x = 704.0, .y = 456.0 },
};

const rail_starter_points = [_]math.Vec2{
    .{ .x = 98.0, .y = 360.0 },
    .{ .x = 156.0, .y = 360.0 },
    .{ .x = 156.0, .y = 562.0 },
    .{ .x = 312.0, .y = 562.0 },
};

const rail_b_points = [_]math.Vec2{
    .{ .x = 598.0, .y = 564.0 },
    .{ .x = 828.0, .y = 564.0 },
    .{ .x = 828.0, .y = 238.0 },
    .{ .x = 1038.0, .y = 238.0 },
    .{ .x = 1128.0, .y = 360.0 },
};

const rail_c_points = [_]math.Vec2{
    .{ .x = 172.0, .y = 164.0 },
    .{ .x = 286.0, .y = 164.0 },
    .{ .x = 286.0, .y = 86.0 },
    .{ .x = 438.0, .y = 86.0 },
};

pub const rails = [_]Rail{
    .{ .points = &rail_starter_points, .speed = 330.0, .tint = .{ 0.98, 0.76, 0.50, 1.0 } },
    .{ .points = &rail_a_points, .speed = 345.0, .tint = .{ 0.45, 0.84, 0.88, 1.0 } },
    .{ .points = &rail_b_points, .speed = 370.0, .tint = .{ 0.74, 0.86, 0.46, 1.0 } },
    .{ .points = &rail_c_points, .speed = 320.0, .tint = .{ 0.86, 0.62, 0.44, 1.0 } },
};

pub const obstacles = [_]math.Rect{
    .{ .x = 220.0, .y = 94.0, .w = 48.0, .h = 418.0 },
    .{ .x = 420.0, .y = 0.0, .w = 54.0, .h = 252.0 },
    .{ .x = 420.0, .y = 430.0, .w = 54.0, .h = 290.0 },
    .{ .x = 665.0, .y = 126.0, .w = 58.0, .h = 330.0 },
    .{ .x = 948.0, .y = 330.0, .w = 64.0, .h = 245.0 },
};

pub const hazards = [_]math.Rect{
    .{ .x = 334.0, .y = 292.0, .w = 270.0, .h = 82.0 },
    .{ .x = 748.0, .y = 310.0, .w = 162.0, .h = 132.0 },
    .{ .x = 1018.0, .y = 462.0, .w = 112.0, .h = 98.0 },
};

pub const start_rect = math.Rect{ .x = 26.0, .y = 290.0, .w = 92.0, .h = 140.0 };
pub const goal_rect = math.Rect{ .x = 1172.0, .y = 274.0, .w = 84.0, .h = 172.0 };

pub fn segmentCount(rail: Rail) usize {
    if (rail.points.len < 2) return 0;
    return rail.points.len - 1 + if (rail.loop) @as(usize, 1) else 0;
}

pub fn railPoint(rail: Rail, index: usize) math.Vec2 {
    if (rail.loop) {
        return rail.points[index % rail.points.len];
    }
    return rail.points[@min(index, rail.points.len - 1)];
}

pub fn isBlocked(pos: math.Vec2, radius: f32) bool {
    if (pos.x < radius or pos.y < radius or pos.x > WorldW - radius or pos.y > WorldH - radius) return true;
    for (obstacles) |obstacle| {
        if (math.circleOverlapsRect(pos, radius, obstacle)) return true;
    }
    return false;
}

pub fn inHazard(pos: math.Vec2) bool {
    for (hazards) |hazard| {
        if (hazard.contains(pos)) return true;
    }
    return false;
}
