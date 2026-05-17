const course = @import("course.zig");
const math = @import("math.zig");
const sokol = @import("sokol");
const sapp = sokol.app;
const sgl = sokol.gl;

pub fn prepareSgl() void {
    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.loadIdentity();
    sgl.ortho(0.0, sapp.widthf(), sapp.heightf(), 0.0, -1.0, 1.0);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
}

pub fn drawBackdrop() void {
    const pos = worldToScreen(.{ .x = 0.0, .y = 0.0 });
    drawRect(pos, course.WorldW * viewScale(), course.WorldH * viewScale(), .{ 0.09, 0.105, 0.105, 1.0 });

    var x: f32 = 0.0;
    while (x <= course.WorldW) : (x += 80.0) {
        drawWorldLine(.{ .x = x, .y = 0.0 }, .{ .x = x, .y = course.WorldH }, .{ 0.15, 0.18, 0.18, 0.22 });
    }
    var y: f32 = 0.0;
    while (y <= course.WorldH) : (y += 80.0) {
        drawWorldLine(.{ .x = 0.0, .y = y }, .{ .x = course.WorldW, .y = y }, .{ 0.15, 0.18, 0.18, 0.22 });
    }

    drawWorldRect(course.start_rect, .{ 0.12, 0.36, 0.28, 0.72 });
    drawWorldRect(course.goal_rect, .{ 0.72, 0.82, 0.34, 0.80 });
}

pub fn drawCourse() void {
    for (course.hazards) |hazard| {
        drawWorldRect(hazard, .{ 0.58, 0.12, 0.08, 0.82 });
        var x = hazard.x + 8.0;
        while (x < hazard.x + hazard.w + hazard.h) : (x += 28.0) {
            drawWorldLine(.{ .x = x, .y = hazard.y }, .{ .x = x - hazard.h, .y = hazard.y + hazard.h }, .{ 1.0, 0.44, 0.20, 0.42 });
        }
    }

    for (course.obstacles) |obstacle| {
        drawWorldRect(obstacle, .{ 0.035, 0.045, 0.052, 0.98 });
        drawWorldRectOutline(obstacle, .{ 0.30, 0.34, 0.34, 0.72 });
    }
}

pub fn drawRails() void {
    for (course.rails) |rail| {
        const seg_count = course.segmentCount(rail);
        var i: usize = 0;
        while (i < seg_count) : (i += 1) {
            const a = course.railPoint(rail, i);
            const b = course.railPoint(rail, i + 1);
            drawThickWorldLine(a, b, 15.0, .{ 0.025, 0.035, 0.04, 1.0 });
            drawThickWorldLine(a, b, 7.0, rail.tint);
            drawThickWorldLine(a, b, 2.0, .{ 0.94, 0.98, 0.96, 0.72 });
        }
        for (rail.points) |p| {
            drawCircle(worldToScreen(p), 7.0 * viewScale(), .{ 0.95, 0.98, 0.90, 0.95 });
        }
    }
}

pub fn drawRotatedRect(center: math.Vec2, dir: math.Vec2, length_px: f32, width_px: f32, color: [4]f32) void {
    const f = math.normalized(dir, .{ .x = 1.0, .y = 0.0 });
    const s = math.perp(f);
    const hl = length_px * 0.5;
    const hw = width_px * 0.5;
    const a = math.add(math.add(center, math.scale(f, -hl)), math.scale(s, -hw));
    const b = math.add(math.add(center, math.scale(f, hl)), math.scale(s, -hw));
    const c = math.add(math.add(center, math.scale(f, hl)), math.scale(s, hw));
    const d = math.add(math.add(center, math.scale(f, -hl)), math.scale(s, hw));
    sgl.beginQuads();
    sgl.c4f(color[0], color[1], color[2], color[3]);
    sgl.v2f(a.x, a.y);
    sgl.v2f(b.x, b.y);
    sgl.v2f(c.x, c.y);
    sgl.v2f(d.x, d.y);
    sgl.end();
}

pub fn drawCircle(center: math.Vec2, radius: f32, color: [4]f32) void {
    const steps = 28;
    sgl.beginTriangles();
    sgl.c4f(color[0], color[1], color[2], color[3]);
    var i: i32 = 0;
    while (i < steps) : (i += 1) {
        const a0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)) * 2.0 * math.Pi;
        const a1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(steps)) * 2.0 * math.Pi;
        sgl.v2f(center.x, center.y);
        sgl.v2f(center.x + @cos(a0) * radius, center.y + @sin(a0) * radius);
        sgl.v2f(center.x + @cos(a1) * radius, center.y + @sin(a1) * radius);
    }
    sgl.end();
}

pub fn drawEllipse(center: math.Vec2, rx: f32, ry: f32, color: [4]f32) void {
    const steps = 28;
    sgl.beginTriangles();
    sgl.c4f(color[0], color[1], color[2], color[3]);
    var i: i32 = 0;
    while (i < steps) : (i += 1) {
        const a0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)) * 2.0 * math.Pi;
        const a1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(steps)) * 2.0 * math.Pi;
        sgl.v2f(center.x, center.y);
        sgl.v2f(center.x + @cos(a0) * rx, center.y + @sin(a0) * ry);
        sgl.v2f(center.x + @cos(a1) * rx, center.y + @sin(a1) * ry);
    }
    sgl.end();
}

pub fn drawCircleOutline(center: math.Vec2, radius: f32, color: [4]f32) void {
    const steps = 36;
    sgl.beginLines();
    sgl.c4f(color[0], color[1], color[2], color[3]);
    var i: i32 = 0;
    while (i < steps) : (i += 1) {
        const a0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)) * 2.0 * math.Pi;
        const a1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(steps)) * 2.0 * math.Pi;
        sgl.v2f(center.x + @cos(a0) * radius, center.y + @sin(a0) * radius);
        sgl.v2f(center.x + @cos(a1) * radius, center.y + @sin(a1) * radius);
    }
    sgl.end();
}

pub fn viewScale() f32 {
    return @min(sapp.widthf() / course.WorldW, sapp.heightf() / course.WorldH);
}

pub fn worldToScreen(p: math.Vec2) math.Vec2 {
    const s = viewScale();
    const o = viewOffset();
    return .{ .x = o.x + p.x * s, .y = o.y + p.y * s };
}

pub fn screenToNdc(p: math.Vec2) math.Vec2 {
    return .{
        .x = p.x / sapp.widthf() * 2.0 - 1.0,
        .y = 1.0 - p.y / sapp.heightf() * 2.0,
    };
}

fn viewOffset() math.Vec2 {
    const s = viewScale();
    return .{
        .x = (sapp.widthf() - course.WorldW * s) * 0.5,
        .y = (sapp.heightf() - course.WorldH * s) * 0.5,
    };
}

fn drawWorldRect(rect: math.Rect, color: [4]f32) void {
    drawRect(worldToScreen(.{ .x = rect.x, .y = rect.y }), rect.w * viewScale(), rect.h * viewScale(), color);
}

fn drawWorldRectOutline(rect: math.Rect, color: [4]f32) void {
    drawRectOutline(worldToScreen(.{ .x = rect.x, .y = rect.y }), rect.w * viewScale(), rect.h * viewScale(), color);
}

fn drawWorldLine(a: math.Vec2, b: math.Vec2, color: [4]f32) void {
    sgl.beginLines();
    sgl.c4f(color[0], color[1], color[2], color[3]);
    const sa = worldToScreen(a);
    const sb = worldToScreen(b);
    sgl.v2f(sa.x, sa.y);
    sgl.v2f(sb.x, sb.y);
    sgl.end();
}

fn drawThickWorldLine(a_world: math.Vec2, b_world: math.Vec2, width_world: f32, color: [4]f32) void {
    const a = worldToScreen(a_world);
    const b = worldToScreen(b_world);
    const d = math.normalized(math.sub(b, a), .{ .x = 1.0, .y = 0.0 });
    const p = math.scale(math.perp(d), width_world * viewScale() * 0.5);
    sgl.beginQuads();
    sgl.c4f(color[0], color[1], color[2], color[3]);
    sgl.v2f(a.x + p.x, a.y + p.y);
    sgl.v2f(b.x + p.x, b.y + p.y);
    sgl.v2f(b.x - p.x, b.y - p.y);
    sgl.v2f(a.x - p.x, a.y - p.y);
    sgl.end();
}

fn drawRect(pos: math.Vec2, w: f32, h: f32, color: [4]f32) void {
    sgl.beginQuads();
    sgl.c4f(color[0], color[1], color[2], color[3]);
    sgl.v2f(pos.x, pos.y);
    sgl.v2f(pos.x + w, pos.y);
    sgl.v2f(pos.x + w, pos.y + h);
    sgl.v2f(pos.x, pos.y + h);
    sgl.end();
}

fn drawRectOutline(pos: math.Vec2, w: f32, h: f32, color: [4]f32) void {
    sgl.beginLines();
    sgl.c4f(color[0], color[1], color[2], color[3]);
    sgl.v2f(pos.x, pos.y);
    sgl.v2f(pos.x + w, pos.y);
    sgl.v2f(pos.x + w, pos.y);
    sgl.v2f(pos.x + w, pos.y + h);
    sgl.v2f(pos.x + w, pos.y + h);
    sgl.v2f(pos.x, pos.y + h);
    sgl.v2f(pos.x, pos.y + h);
    sgl.v2f(pos.x, pos.y);
    sgl.end();
}
