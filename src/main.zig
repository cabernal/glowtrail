const std = @import("std");
const builtin = @import("builtin");

const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;
const sgl = sokol.gl;
const sdtx = sokol.debugtext;
const sglue = sokol.glue;
const slog = sokol.log;

const course = @import("course.zig");
const fx = @import("fx.zig");
const math = @import("math.zig");
const render = @import("render.zig");

const Vec2 = math.Vec2;
const SparkParticle = fx.SparkParticle;
const SparkVertex = fx.SparkVertex;

const Pi = math.Pi;
const PlayerRadius = course.PlayerRadius;
const MaxSparks = fx.MaxSparks;
const MaxSparkVertices = fx.MaxSparkVertices;

const add = math.add;
const sub = math.sub;
const scale = math.scale;
const dot = math.dot;
const length = math.length;
const distance = math.distance;
const normalized = math.normalized;
const perp = math.perp;
const lerp = math.lerp;
const clamp01 = math.clamp01;
const closestPointOnSegment = math.closestPointOnSegment;

const rails = course.rails;
const segmentCount = course.segmentCount;
const railPoint = course.railPoint;
const isBlocked = course.isBlocked;
const inHazard = course.inHazard;

const worldToScreen = render.worldToScreen;
const screenToNdc = render.screenToNdc;
const viewScale = render.viewScale;
const drawEllipse = render.drawEllipse;
const drawRotatedRect = render.drawRotatedRect;
const drawCircle = render.drawCircle;
const drawCircleOutline = render.drawCircleOutline;

const Player = struct {
    pos: Vec2 = .{ .x = 70.0, .y = 360.0 },
    vel: Vec2 = .{},
    facing: Vec2 = .{ .x = 1.0, .y = 0.0 },
    airborne: bool = false,
    jump_count: u8 = 0,
    jump_age: f32 = 0.0,
    jump_duration: f32 = 0.42,
    height: f32 = 0.0,
    grind_ready_timer: f32 = 0.0,
    grinding: bool = false,
    rail_index: usize = 0,
    rail_segment: usize = 0,
    rail_t: f32 = 0.0,
    rail_dir: i32 = 1,
};

const AppState = struct {
    pass_action: sg.PassAction = .{},
    keys: [512]bool = [_]bool{false} ** 512,
    player: Player = .{},
    sparks: [MaxSparks]SparkParticle = [_]SparkParticle{.{}} ** MaxSparks,
    spark_vertices: [MaxSparkVertices]SparkVertex = undefined,
    spark_cursor: usize = 0,
    spark_active_count: usize = 0,
    spark_vertex_count: usize = 0,
    spark_emit_accum: f32 = 0.0,
    spark_shader: sg.Shader = .{},
    spark_pipeline: sg.Pipeline = .{},
    spark_vertex_buffer: sg.Buffer = .{},
    rng: std.Random.DefaultPrng = std.Random.DefaultPrng.init(0x515A_7E5C_A7E0_2026),
    message: [160]u8 = [_]u8{0} ** 160,
    message_len: usize = 0,
    message_time: f32 = 0.0,
    elapsed: f32 = 0.0,
    wins: u32 = 0,
    initialized: bool = false,

    fn init(self: *AppState) void {
        self.pass_action = .{};
        self.pass_action.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = .{
                .r = 0.035,
                .g = 0.045,
                .b = 0.052,
                .a = 1.0,
            },
        };

        sg.setup(.{
            .environment = sglue.environment(),
            .logger = .{ .func = slog.func },
        });
        sgl.setup(.{ .logger = .{ .func = slog.func } });
        sdtx.setup(.{
            .fonts = [_]sdtx.FontDesc{
                sdtx.fontKc853(),
                sdtx.fontKc854(),
                sdtx.fontZ1013(),
                sdtx.fontCpc(),
                sdtx.fontC64(),
                sdtx.fontOric(),
                .{},
                .{},
            },
            .logger = .{ .func = slog.func },
        });

        self.initSparkPipeline();
        self.setMessage("Find the line.", .{});
        self.initialized = true;
    }

    fn cleanup(self: *AppState) void {
        if (self.spark_vertex_buffer.id != 0) sg.destroyBuffer(self.spark_vertex_buffer);
        if (self.spark_pipeline.id != 0) sg.destroyPipeline(self.spark_pipeline);
        if (self.spark_shader.id != 0) sg.destroyShader(self.spark_shader);
        sdtx.shutdown();
        sgl.shutdown();
        sg.shutdown();
    }

    fn initSparkPipeline(self: *AppState) void {
        self.spark_shader = sg.makeShader(fx.sparkShaderDesc());

        var pipeline_desc: sg.PipelineDesc = .{};
        pipeline_desc.shader = self.spark_shader;
        pipeline_desc.layout.buffers[0].stride = @sizeOf(SparkVertex);
        pipeline_desc.layout.attrs[0].format = .FLOAT2;
        pipeline_desc.layout.attrs[0].offset = @offsetOf(SparkVertex, "position");
        pipeline_desc.layout.attrs[1].format = .FLOAT2;
        pipeline_desc.layout.attrs[1].offset = @offsetOf(SparkVertex, "uv");
        pipeline_desc.layout.attrs[2].format = .FLOAT4;
        pipeline_desc.layout.attrs[2].offset = @offsetOf(SparkVertex, "color");
        pipeline_desc.layout.attrs[3].format = .FLOAT;
        pipeline_desc.layout.attrs[3].offset = @offsetOf(SparkVertex, "life");
        pipeline_desc.color_count = 1;
        pipeline_desc.colors[0].blend.enabled = true;
        pipeline_desc.colors[0].blend.src_factor_rgb = .SRC_ALPHA;
        pipeline_desc.colors[0].blend.dst_factor_rgb = .ONE;
        pipeline_desc.colors[0].blend.src_factor_alpha = .ONE;
        pipeline_desc.colors[0].blend.dst_factor_alpha = .ONE_MINUS_SRC_ALPHA;
        pipeline_desc.primitive_type = .TRIANGLES;
        pipeline_desc.label = "grind-spark-pipeline";
        self.spark_pipeline = sg.makePipeline(pipeline_desc);

        self.spark_vertex_buffer = sg.makeBuffer(.{
            .usage = .{
                .vertex_buffer = true,
                .stream_update = true,
            },
            .size = @sizeOf(SparkVertex) * MaxSparkVertices,
            .label = "grind-spark-vertices",
        });
    }

    fn frame(self: *AppState) void {
        if (!self.initialized) return;

        var dt: f32 = @floatCast(sapp.frameDuration());
        if (!(dt > 0.0 and dt < 0.08)) {
            dt = 1.0 / 60.0;
        }
        self.elapsed += dt;
        self.update(dt);
        self.draw();
    }

    fn update(self: *AppState, dt: f32) void {
        if (self.message_time > 0.0) {
            self.message_time = @max(0.0, self.message_time - dt);
        }

        if (self.player.grinding) {
            self.updateGrinding(dt);
        } else {
            self.updateGroundMovement(dt);
            self.updateJump(dt);
        }

        self.updateSparks(dt);

        if (course.goal_rect.contains(self.player.pos) and !self.player.grinding) {
            self.wins += 1;
            self.setMessage("Line cleared. Run it back?", .{});
            self.resetPlayer(false);
        }
    }

    fn updateGroundMovement(self: *AppState, dt: f32) void {
        var input = Vec2{};
        if (self.isKeyDown(.A) or self.isKeyDown(.LEFT)) input.x -= 1.0;
        if (self.isKeyDown(.D) or self.isKeyDown(.RIGHT)) input.x += 1.0;
        if (self.isKeyDown(.W) or self.isKeyDown(.UP)) input.y -= 1.0;
        if (self.isKeyDown(.S) or self.isKeyDown(.DOWN)) input.y += 1.0;

        const input_len = length(input);
        if (input_len > 0.01) {
            const dir = scale(input, 1.0 / input_len);
            self.player.facing = dir;
            const control: f32 = if (self.player.airborne) 0.48 else 1.0;
            self.player.vel = add(self.player.vel, scale(dir, 720.0 * control * dt));
        } else {
            self.player.vel = scale(self.player.vel, std.math.pow(f32, 0.0025, dt));
        }

        const max_speed: f32 = if (self.player.airborne) 250.0 else 290.0;
        const speed = length(self.player.vel);
        if (speed > max_speed) {
            self.player.vel = scale(self.player.vel, max_speed / speed);
        }

        self.moveWithCollision(dt);

        if (!self.player.airborne and inHazard(self.player.pos)) {
            self.setMessage("Bailed.", .{});
            self.resetPlayer(false);
        }
    }

    fn moveWithCollision(self: *AppState, dt: f32) void {
        var next = self.player.pos;
        next.x += self.player.vel.x * dt;
        if (!isBlocked(next, PlayerRadius)) {
            self.player.pos.x = next.x;
        } else {
            self.player.vel.x = 0.0;
        }

        next = self.player.pos;
        next.y += self.player.vel.y * dt;
        if (!isBlocked(next, PlayerRadius)) {
            self.player.pos.y = next.y;
        } else {
            self.player.vel.y = 0.0;
        }
    }

    fn updateJump(self: *AppState, dt: f32) void {
        if (self.player.grind_ready_timer > 0.0) {
            self.player.grind_ready_timer = @max(0.0, self.player.grind_ready_timer - dt);
        }
        if (!self.player.airborne) {
            self.player.height = 0.0;
            return;
        }

        self.player.jump_age += dt;
        const u = clamp01(self.player.jump_age / self.player.jump_duration);
        const jump_height: f32 = if (self.player.jump_count >= 2) 52.0 else 36.0;
        self.player.height = @sin(u * Pi) * jump_height;

        if (u >= 1.0) {
            self.player.airborne = false;
            self.player.jump_count = 0;
            self.player.height = 0.0;
            self.player.grind_ready_timer = 0.0;
            if (inHazard(self.player.pos)) {
                self.setMessage("Bailed.", .{});
                self.resetPlayer(false);
            }
        }
    }

    fn jump(self: *AppState) void {
        if (self.player.grinding) {
            const tangent = self.currentRailTangent();
            self.popOffRail(tangent, 275.0);
            self.player.airborne = true;
            self.player.jump_count = 1;
            self.player.jump_age = 0.0;
            self.player.jump_duration = 0.40;
            self.player.height = 12.0;
            return;
        }

        if (self.player.jump_count >= 2) return;
        self.player.airborne = true;
        self.player.jump_count += 1;
        self.player.jump_age = 0.0;
        self.player.jump_duration = if (self.player.jump_count >= 2) 0.50 else 0.42;
        if (self.player.jump_count >= 2) {
            self.player.grind_ready_timer = 1.05;
            self.setMessage("Grind window open.", .{});
        }
    }

    fn tryStartGrind(self: *AppState) void {
        if (self.player.grinding) return;
        if (!self.player.airborne or self.player.jump_count < 2 or self.player.grind_ready_timer <= 0.0) {
            self.setMessage("Needs more pop.", .{});
            return;
        }

        var best = GrindCandidate{};
        for (rails, 0..) |rail, rail_i| {
            const seg_count = segmentCount(rail);
            var seg_i: usize = 0;
            while (seg_i < seg_count) : (seg_i += 1) {
                const a = railPoint(rail, seg_i);
                const b = railPoint(rail, seg_i + 1);
                const nearest = closestPointOnSegment(self.player.pos, a, b);
                const d = distance(self.player.pos, nearest.point);
                if (d < best.distance) {
                    best = .{
                        .distance = d,
                        .rail_index = rail_i,
                        .segment = seg_i,
                        .t = nearest.t,
                    };
                }
            }
        }

        if (best.distance > 34.0) {
            self.setMessage("No rail under you.", .{});
            return;
        }

        const rail = rails[best.rail_index];
        const a = railPoint(rail, best.segment);
        const b = railPoint(rail, best.segment + 1);
        const seg_dir = normalized(sub(b, a), self.player.facing);
        const intent = if (length(self.player.vel) > 20.0) normalized(self.player.vel, self.player.facing) else self.player.facing;

        self.player.grinding = true;
        self.player.rail_index = best.rail_index;
        self.player.rail_segment = best.segment;
        self.player.rail_t = best.t;
        self.player.rail_dir = if (dot(intent, seg_dir) >= 0.0) 1 else -1;
        self.player.airborne = false;
        self.player.jump_count = 0;
        self.player.height = 0.0;
        self.player.grind_ready_timer = 0.0;
        self.player.vel = .{};
        self.player.pos = closestPointOnSegment(self.player.pos, a, b).point;
        self.player.facing = if (self.player.rail_dir > 0) seg_dir else scale(seg_dir, -1.0);
        self.setMessage("Locked.", .{});
        self.spawnSparkBurst(self.player.pos, self.player.facing, 28);
    }

    fn updateGrinding(self: *AppState, dt: f32) void {
        const rail = rails[self.player.rail_index];
        var remaining = rail.speed * dt;
        while (remaining > 0.001 and self.player.grinding) {
            const seg_count = segmentCount(rail);
            if (seg_count == 0) {
                self.player.grinding = false;
                break;
            }

            const a = railPoint(rail, self.player.rail_segment);
            const b = railPoint(rail, self.player.rail_segment + 1);
            const seg = sub(b, a);
            const seg_len = @max(1.0, length(seg));
            const seg_dir = scale(seg, 1.0 / seg_len);
            const signed_dir = if (self.player.rail_dir > 0) seg_dir else scale(seg_dir, -1.0);
            const delta = remaining / seg_len;

            if (self.player.rail_dir > 0) {
                const room = 1.0 - self.player.rail_t;
                if (delta < room) {
                    self.player.rail_t += delta;
                    remaining = 0.0;
                } else {
                    remaining -= room * seg_len;
                    self.player.rail_t = 1.0;
                    if (self.player.rail_segment + 1 < seg_count) {
                        self.player.rail_segment += 1;
                        self.player.rail_t = 0.0;
                        self.spawnSparkBurst(b, signed_dir, 18);
                    } else if (rail.loop) {
                        self.player.rail_segment = 0;
                        self.player.rail_t = 0.0;
                        self.spawnSparkBurst(b, signed_dir, 18);
                    } else {
                        self.player.pos = b;
                        self.popOffRail(signed_dir, 255.0);
                        break;
                    }
                }
            } else {
                const room = self.player.rail_t;
                if (delta < room) {
                    self.player.rail_t -= delta;
                    remaining = 0.0;
                } else {
                    remaining -= room * seg_len;
                    self.player.rail_t = 0.0;
                    if (self.player.rail_segment > 0) {
                        self.player.rail_segment -= 1;
                        self.player.rail_t = 1.0;
                        self.spawnSparkBurst(a, signed_dir, 18);
                    } else if (rail.loop) {
                        self.player.rail_segment = seg_count - 1;
                        self.player.rail_t = 1.0;
                        self.spawnSparkBurst(a, signed_dir, 18);
                    } else {
                        self.player.pos = a;
                        self.popOffRail(signed_dir, 255.0);
                        break;
                    }
                }
            }

            if (self.player.grinding) {
                const next_a = railPoint(rail, self.player.rail_segment);
                const next_b = railPoint(rail, self.player.rail_segment + 1);
                const tangent = normalized(sub(next_b, next_a), self.player.facing);
                self.player.pos = lerp(next_a, next_b, self.player.rail_t);
                self.player.facing = if (self.player.rail_dir > 0) tangent else scale(tangent, -1.0);
            }
        }

        if (self.player.grinding) {
            self.spark_emit_accum += dt * 95.0;
            while (self.spark_emit_accum >= 1.0) : (self.spark_emit_accum -= 1.0) {
                self.spawnGrindSpark(self.player.pos, self.player.facing);
            }
        }
    }

    fn popOffRail(self: *AppState, dir: Vec2, speed: f32) void {
        self.player.grinding = false;
        self.player.vel = scale(normalized(dir, self.player.facing), speed);
        self.player.facing = normalized(dir, self.player.facing);
        self.player.height = 0.0;
        self.player.airborne = false;
        self.player.jump_count = 0;
        self.player.grind_ready_timer = 0.0;
        self.spark_emit_accum = 0.0;
    }

    fn currentRailTangent(self: *const AppState) Vec2 {
        const rail = rails[self.player.rail_index];
        const a = railPoint(rail, self.player.rail_segment);
        const b = railPoint(rail, self.player.rail_segment + 1);
        const tangent = normalized(sub(b, a), self.player.facing);
        return if (self.player.rail_dir > 0) tangent else scale(tangent, -1.0);
    }

    fn spawnSparkBurst(self: *AppState, pos: Vec2, dir: Vec2, count: usize) void {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            self.spawnGrindSpark(pos, dir);
        }
    }

    fn spawnGrindSpark(self: *AppState, pos: Vec2, dir: Vec2) void {
        const slot = self.nextSparkSlot() orelse return;
        var rand = self.rng.random();
        const side = perp(normalized(dir, .{ .x = 1.0, .y = 0.0 }));
        const side_push = rand.float(f32) * 2.0 - 1.0;
        const back_push = 35.0 + rand.float(f32) * 140.0;
        const side_speed = side_push * (90.0 + rand.float(f32) * 105.0);
        const jitter = add(scale(side, side_push * (2.0 + rand.float(f32) * 5.0)), scale(dir, -8.0));

        slot.* = .{
            .active = true,
            .pos = add(pos, jitter),
            .vel = add(scale(dir, -back_push), scale(side, side_speed)),
            .life = 0.18 + rand.float(f32) * 0.34,
            .max_life = 0.18 + rand.float(f32) * 0.34,
            .radius = 3.0 + rand.float(f32) * 6.5,
            .color = if (rand.float(f32) > 0.35)
                .{ 1.0, 0.66 + rand.float(f32) * 0.24, 0.18, 1.0 }
            else
                .{ 0.88, 0.96, 1.0, 1.0 },
        };
    }

    fn nextSparkSlot(self: *AppState) ?*SparkParticle {
        if (self.spark_active_count < self.sparks.len) {
            var checked: usize = 0;
            while (checked < self.sparks.len) : (checked += 1) {
                const idx = self.spark_cursor;
                self.spark_cursor = (idx + 1) % self.sparks.len;
                if (!self.sparks[idx].active) {
                    self.spark_active_count += 1;
                    return &self.sparks[idx];
                }
            }
        }
        return null;
    }

    fn updateSparks(self: *AppState, dt: f32) void {
        for (&self.sparks) |*spark| {
            if (!spark.active) continue;
            spark.life -= dt;
            if (spark.life <= 0.0) {
                spark.active = false;
                if (self.spark_active_count > 0) self.spark_active_count -= 1;
                continue;
            }
            spark.vel = scale(spark.vel, std.math.pow(f32, 0.022, dt));
            spark.pos = add(spark.pos, scale(spark.vel, dt));
        }
    }

    fn resetPlayer(self: *AppState, clear_message: bool) void {
        self.player = .{};
        self.spark_emit_accum = 0.0;
        if (clear_message) {
            self.setMessage("Find the line.", .{});
        }
    }

    fn handleEvent(self: *AppState, ev: sapp.Event) void {
        switch (ev.type) {
            .KEY_DOWN => {
                if (keyIndex(ev.key_code)) |idx| self.keys[idx] = true;
                if (!ev.key_repeat) {
                    if (ev.key_code == .SPACE) {
                        self.jump();
                    } else if (ev.key_code == .LEFT_SHIFT or ev.key_code == .RIGHT_SHIFT) {
                        self.tryStartGrind();
                    } else if (ev.key_code == .R) {
                        self.resetPlayer(true);
                    }
                }
            },
            .KEY_UP => {
                if (keyIndex(ev.key_code)) |idx| self.keys[idx] = false;
            },
            else => {},
        }
    }

    fn draw(self: *AppState) void {
        sg.beginPass(.{
            .action = self.pass_action,
            .swapchain = sglue.swapchain(),
        });

        render.prepareSgl();
        self.drawWorld();
        sgl.draw();
        self.drawSparks();
        self.drawHud();
        sdtx.draw();

        sg.endPass();
        sg.commit();
    }

    fn drawWorld(self: *AppState) void {
        render.drawBackdrop();
        render.drawCourse();
        render.drawRails();
        self.drawPlayer();
    }

    fn drawPlayer(self: *AppState) void {
        const ground = worldToScreen(self.player.pos);
        const rider: Vec2 = .{ .x = ground.x, .y = ground.y - self.player.height * viewScale() * 0.55 };
        const scale_px = viewScale();
        const face = normalized(self.player.facing, .{ .x = 1.0, .y = 0.0 });
        const side = perp(face);

        drawEllipse(ground, 18.0 * scale_px, 8.0 * scale_px, .{ 0.0, 0.0, 0.0, if (self.player.airborne) 0.24 else 0.36 });
        drawRotatedRect(rider, face, 38.0 * scale_px, 12.0 * scale_px, .{ 0.05, 0.07, 0.075, 1.0 });
        drawRotatedRect(add(rider, scale(side, 0.0)), face, 28.0 * scale_px, 6.0 * scale_px, .{ 0.18, 0.82, 0.76, 0.94 });
        drawCircle(add(rider, scale(face, 10.0 * scale_px)), 7.0 * scale_px, .{ 0.94, 0.90, 0.72, 1.0 });
        drawCircle(add(rider, scale(face, -10.0 * scale_px)), 5.5 * scale_px, .{ 0.18, 0.22, 0.27, 1.0 });

        if (self.player.grind_ready_timer > 0.0 and !self.player.grinding) {
            drawCircleOutline(ground, (28.0 + @sin(self.elapsed * 20.0) * 3.0) * scale_px, .{ 1.0, 0.72, 0.20, 0.80 });
        }
    }

    fn drawSparks(self: *AppState) void {
        if (self.spark_pipeline.id == 0 or self.spark_vertex_buffer.id == 0) return;
        self.spark_vertex_count = 0;

        for (self.sparks) |spark| {
            if (!spark.active) continue;
            const fade = clamp01(spark.life / @max(0.001, spark.max_life));
            var color = spark.color;
            color[3] *= fade;
            const size = spark.radius * (0.72 + fade * 1.45);
            self.appendSparkQuad(spark.pos, size, color, fade);
        }

        if (self.spark_vertex_count == 0) return;

        sg.updateBuffer(self.spark_vertex_buffer, sg.asRange(self.spark_vertices[0..self.spark_vertex_count]));
        var bindings: sg.Bindings = .{};
        bindings.vertex_buffers[0] = self.spark_vertex_buffer;
        sg.applyPipeline(self.spark_pipeline);
        sg.applyBindings(bindings);
        sg.draw(0, @intCast(self.spark_vertex_count), 1);
    }

    fn appendSparkQuad(self: *AppState, center_world: Vec2, size_world: f32, color: [4]f32, fade: f32) void {
        if (self.spark_vertex_count + 6 > self.spark_vertices.len) return;
        const center = worldToScreen(center_world);
        const size = size_world * viewScale();
        const x0 = center.x - size;
        const y0 = center.y - size;
        const x1 = center.x + size;
        const y1 = center.y + size;

        self.appendSparkVertex(.{ .x = x0, .y = y0 }, .{ .x = 0.0, .y = 0.0 }, color, fade);
        self.appendSparkVertex(.{ .x = x1, .y = y0 }, .{ .x = 1.0, .y = 0.0 }, color, fade);
        self.appendSparkVertex(.{ .x = x1, .y = y1 }, .{ .x = 1.0, .y = 1.0 }, color, fade);
        self.appendSparkVertex(.{ .x = x0, .y = y0 }, .{ .x = 0.0, .y = 0.0 }, color, fade);
        self.appendSparkVertex(.{ .x = x1, .y = y1 }, .{ .x = 1.0, .y = 1.0 }, color, fade);
        self.appendSparkVertex(.{ .x = x0, .y = y1 }, .{ .x = 0.0, .y = 1.0 }, color, fade);
    }

    fn appendSparkVertex(self: *AppState, screen: Vec2, uv: Vec2, color: [4]f32, fade: f32) void {
        if (self.spark_vertex_count >= self.spark_vertices.len) return;
        const ndc = screenToNdc(screen);
        self.spark_vertices[self.spark_vertex_count] = .{
            .position = .{ ndc.x, ndc.y },
            .uv = .{ uv.x, uv.y },
            .color = color,
            .life = fade,
        };
        self.spark_vertex_count += 1;
    }

    fn drawHud(self: *AppState) void {
        sdtx.canvas(sapp.widthf() / 2.0, sapp.heightf() / 2.0);
        sdtx.origin(1.0, 1.0);
        sdtx.font(4);
        sdtx.color4f(0.88, 0.95, 1.0, 0.92);
        sdtx.pos(0.0, 0.0);
        sdtx.puts("GLOWTRAIL");
        sdtx.crlf();

        var buf: [128]u8 = undefined;
        const status = if (self.player.grinding)
            "grinding"
        else if (self.player.grind_ready_timer > 0.0)
            "ready"
        else if (self.player.airborne)
            "air"
        else
            "rolling";
        const z = std.fmt.bufPrintZ(&buf, "state: {s}   clears: {d}", .{ status, self.wins }) catch return;
        sdtx.color4f(0.72, 0.84, 0.88, 0.86);
        sdtx.puts(z);

        if (self.message_time > 0.0 and self.message_len > 0) {
            sdtx.pos(0.0, 4.0);
            sdtx.color4f(1.0, 0.78, 0.30, clamp01(self.message_time));
            const msg = self.message[0..self.message_len :0];
            sdtx.puts(msg);
        }
    }

    fn setMessage(self: *AppState, comptime fmt: []const u8, args: anytype) void {
        const max_len = self.message.len - 1;
        const text = std.fmt.bufPrint(self.message[0..max_len], fmt, args) catch return;
        self.message_len = text.len;
        self.message[self.message_len] = 0;
        self.message_time = 2.0;
    }

    fn isKeyDown(self: *const AppState, key: sapp.Keycode) bool {
        if (keyIndex(key)) |idx| {
            return self.keys[idx];
        }
        return false;
    }
};

const GrindCandidate = struct {
    distance: f32 = 1000000.0,
    rail_index: usize = 0,
    segment: usize = 0,
    t: f32 = 0.0,
};

var app = AppState{};

fn keyIndex(key: sapp.Keycode) ?usize {
    const raw: i32 = @intFromEnum(key);
    if (raw < 0 or raw >= app.keys.len) return null;
    return @intCast(raw);
}

fn init() callconv(.c) void {
    app.init();
}

fn frame() callconv(.c) void {
    app.frame();
}

fn cleanup() callconv(.c) void {
    app.cleanup();
}

fn event(ev: [*c]const sapp.Event) callconv(.c) void {
    if (ev == null) return;
    app.handleEvent(ev[0]);
}

fn appDesc() sapp.Desc {
    const is_web = builtin.target.cpu.arch.isWasm();
    return .{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 1280,
        .height = 720,
        .sample_count = 1,
        .window_title = "Glowtrail",
        .icon = .{ .sokol_default = true },
        .high_dpi = !is_web,
        .html5 = .{
            .canvas_selector = "#canvas",
            .canvas_resize = true,
            .preserve_drawing_buffer = false,
            .premultiplied_alpha = true,
            .ask_leave_site = false,
        },
        .logger = .{ .func = slog.func },
    };
}

pub fn main() void {
    sapp.run(appDesc());
}
