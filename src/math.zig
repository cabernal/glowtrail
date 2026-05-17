pub const Pi: f32 = 3.141592653589793;

pub const Vec2 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
};

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn contains(self: Rect, p: Vec2) bool {
        return p.x >= self.x and p.x <= self.x + self.w and p.y >= self.y and p.y <= self.y + self.h;
    }
};

pub const SegmentPoint = struct {
    point: Vec2,
    t: f32,
};

pub fn add(a: Vec2, b: Vec2) Vec2 {
    return .{ .x = a.x + b.x, .y = a.y + b.y };
}

pub fn sub(a: Vec2, b: Vec2) Vec2 {
    return .{ .x = a.x - b.x, .y = a.y - b.y };
}

pub fn scale(v: Vec2, s: f32) Vec2 {
    return .{ .x = v.x * s, .y = v.y * s };
}

pub fn dot(a: Vec2, b: Vec2) f32 {
    return a.x * b.x + a.y * b.y;
}

pub fn length(v: Vec2) f32 {
    return @sqrt(dot(v, v));
}

pub fn distance(a: Vec2, b: Vec2) f32 {
    return length(sub(a, b));
}

pub fn normalized(v: Vec2, fallback: Vec2) Vec2 {
    const len = length(v);
    if (len <= 0.001) return fallback;
    return scale(v, 1.0 / len);
}

pub fn perp(v: Vec2) Vec2 {
    return .{ .x = -v.y, .y = v.x };
}

pub fn lerp(a: Vec2, b: Vec2, t: f32) Vec2 {
    return .{ .x = a.x + (b.x - a.x) * t, .y = a.y + (b.y - a.y) * t };
}

pub fn clamp(v: f32, lo: f32, hi: f32) f32 {
    return @min(@max(v, lo), hi);
}

pub fn clamp01(v: f32) f32 {
    return clamp(v, 0.0, 1.0);
}

pub fn circleOverlapsRect(center: Vec2, radius: f32, rect: Rect) bool {
    const nearest_x = clamp(center.x, rect.x, rect.x + rect.w);
    const nearest_y = clamp(center.y, rect.y, rect.y + rect.h);
    const dx = center.x - nearest_x;
    const dy = center.y - nearest_y;
    return dx * dx + dy * dy <= radius * radius;
}

pub fn closestPointOnSegment(p: Vec2, a: Vec2, b: Vec2) SegmentPoint {
    const ab = sub(b, a);
    const denom = dot(ab, ab);
    if (denom <= 0.001) return .{ .point = a, .t = 0.0 };
    const t = clamp01(dot(sub(p, a), ab) / denom);
    return .{ .point = lerp(a, b, t), .t = t };
}
