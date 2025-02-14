const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    pub fn scale(self: Vec2, scalar: f32) Vec2 {
        return .{
            .x = self.x * scalar,
            .y = self.y * scalar,
        };
    }

    pub fn dot(self: Vec2, other: Vec2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn length(self: Vec2) f32 {
        return @sqrt(self.dot(self));
    }

    pub fn normalize(self: Vec2) Vec2 {
        const len = self.length();
        if (len == 0) return self;
        return self.scale(1.0 / len);
    }
};

pub const Wall = struct {
    start: Vec2,
    end: Vec2,

    pub fn render(self: *const Wall, renderer: *c.SDL_Renderer) void {
        _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
        _ = c.SDL_RenderDrawLine(
            renderer,
            @intFromFloat(self.start.x),
            @intFromFloat(self.start.y),
            @intFromFloat(self.end.x),
            @intFromFloat(self.end.y),
        );
    }
};

pub const Player = struct {
    position: Vec2,
    angle: f32, // in radians

    pub fn init() Player {
        return .{
            .position = .{ .x = 100, .y = 100 },
            .angle = 0,
        };
    }

    pub fn render(self: *const Player, renderer: *c.SDL_Renderer) void {
        // Draw player as a triangle
        _ = c.SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);

        const size: f32 = 15; // Size of the triangle
        const angle = self.angle;

        // Calculate triangle points
        const points = [3]c.SDL_Point{
            // Front point (nose of triangle)
            .{
                .x = @intFromFloat(self.position.x + size * @cos(angle)),
                .y = @intFromFloat(self.position.y + size * @sin(angle)),
            },
            // Back-right point
            .{
                .x = @intFromFloat(self.position.x + size * 0.5 * @cos(angle + 2.4)),
                .y = @intFromFloat(self.position.y + size * 0.5 * @sin(angle + 2.4)),
            },
            // Back-left point
            .{
                .x = @intFromFloat(self.position.x + size * 0.5 * @cos(angle - 2.4)),
                .y = @intFromFloat(self.position.y + size * 0.5 * @sin(angle - 2.4)),
            },
        };

        // Draw the triangle outline
        _ = c.SDL_RenderDrawLine(renderer, points[0].x, points[0].y, points[1].x, points[1].y);
        _ = c.SDL_RenderDrawLine(renderer, points[1].x, points[1].y, points[2].x, points[2].y);
        _ = c.SDL_RenderDrawLine(renderer, points[2].x, points[2].y, points[0].x, points[0].y);

        // Fill the triangle
        var y = @min(@min(points[0].y, points[1].y), points[2].y);
        const max_y = @max(@max(points[0].y, points[1].y), points[2].y);
        while (y <= max_y) : (y += 1) {
            var intersections: [2]i32 = undefined;
            var count: usize = 0;

            // Find intersections with all three edges
            inline for (0..3) |i| {
                const j = (i + 1) % 3;
                const y1 = points[i].y;
                const y2 = points[j].y;

                if ((y1 <= y and y2 > y) or (y2 <= y and y1 > y)) {
                    const x1 = points[i].x;
                    const x2 = points[j].x;
                    if (count < 2) {
                        intersections[count] = @intFromFloat(
                            @as(f32, @floatFromInt(x1)) +
                                (@as(f32, @floatFromInt(y - y1)) * @as(f32, @floatFromInt(x2 - x1))) /
                                @as(f32, @floatFromInt(y2 - y1)),
                        );
                        count += 1;
                    }
                }
            }

            if (count == 2) {
                const x1 = @min(intersections[0], intersections[1]);
                const x2 = @max(intersections[0], intersections[1]);
                _ = c.SDL_RenderDrawLine(renderer, x1, y, x2, y);
            }
        }
    }
};

pub const Map = struct {
    walls: std.ArrayList(Wall),
    player: Player,
    allocator: std.mem.Allocator,
    debug_mode: u8 = 0, // 0: off, 1: collision circle, 2: closest points, 3: all debug info

    const PLAYER_RADIUS: f32 = 8.0;
    const DEBUG_MODES: u8 = 4; // Number of debug modes

    pub fn init(allocator: std.mem.Allocator) !Map {
        var walls = std.ArrayList(Wall).init(allocator);

        // Add some test walls to form a simple room
        try walls.appendSlice(&[_]Wall{
            // Outer walls
            .{ .start = .{ .x = 50, .y = 50 }, .end = .{ .x = 750, .y = 50 } }, // Top
            .{ .start = .{ .x = 750, .y = 50 }, .end = .{ .x = 750, .y = 550 } }, // Right
            .{ .start = .{ .x = 750, .y = 550 }, .end = .{ .x = 50, .y = 550 } }, // Bottom
            .{ .start = .{ .x = 50, .y = 550 }, .end = .{ .x = 50, .y = 50 } }, // Left

            // Inner obstacle
            .{ .start = .{ .x = 300, .y = 200 }, .end = .{ .x = 500, .y = 200 } },
            .{ .start = .{ .x = 500, .y = 200 }, .end = .{ .x = 500, .y = 400 } },
            .{ .start = .{ .x = 500, .y = 400 }, .end = .{ .x = 300, .y = 400 } },
            .{ .start = .{ .x = 300, .y = 400 }, .end = .{ .x = 300, .y = 200 } },
        });

        return .{
            .walls = walls,
            .player = Player.init(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Map) void {
        self.walls.deinit();
    }

    // Find the closest point on a line segment to a point
    fn closestPointOnWall(wall: Wall, point: Vec2) Vec2 {
        const wall_vec = wall.end.sub(wall.start);
        const point_vec = point.sub(wall.start);

        const wall_length_sq = wall_vec.dot(wall_vec);
        if (wall_length_sq == 0) return wall.start;

        const t = std.math.clamp(point_vec.dot(wall_vec) / wall_length_sq, 0, 1);
        return wall.start.add(wall_vec.scale(t));
    }

    pub fn render(self: *const Map, renderer: *c.SDL_Renderer) void {
        // Draw walls
        for (self.walls.items) |*wall| {
            wall.render(renderer);
        }

        // Draw player
        self.player.render(renderer);

        if (self.debug_mode > 0) {
            // Draw collision circle
            _ = c.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
            const steps = 32;
            var i: usize = 0;
            while (i < steps) : (i += 1) {
                const angle1 = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps))) * std.math.tau;
                const angle2 = (@as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(steps))) * std.math.tau;

                const x1: i32 = @intFromFloat(self.player.position.x + PLAYER_RADIUS * @cos(angle1));
                const y1: i32 = @intFromFloat(self.player.position.y + PLAYER_RADIUS * @sin(angle1));
                const x2: i32 = @intFromFloat(self.player.position.x + PLAYER_RADIUS * @cos(angle2));
                const y2: i32 = @intFromFloat(self.player.position.y + PLAYER_RADIUS * @sin(angle2));

                _ = c.SDL_RenderDrawLine(renderer, x1, y1, x2, y2);
            }

            if (self.debug_mode >= 2) {
                // Draw closest points on walls
                _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255);
                for (self.walls.items) |wall| {
                    const closest = closestPointOnWall(wall, self.player.position);
                    const rect = c.SDL_Rect{
                        .x = @intFromFloat(closest.x - 2),
                        .y = @intFromFloat(closest.y - 2),
                        .w = 4,
                        .h = 4,
                    };
                    _ = c.SDL_RenderFillRect(renderer, &rect);

                    if (self.debug_mode >= 3) {
                        // Draw line from player to closest point
                        _ = c.SDL_SetRenderDrawColor(renderer, 255, 0, 255, 255);
                        _ = c.SDL_RenderDrawLine(
                            renderer,
                            @intFromFloat(self.player.position.x),
                            @intFromFloat(self.player.position.y),
                            @intFromFloat(closest.x),
                            @intFromFloat(closest.y),
                        );
                    }
                }
            }
        }
    }

    pub fn tryMovePlayer(self: *Map, dx: f32, dy: f32) void {
        const movement = Vec2{ .x = dx, .y = dy };
        const desired_pos = self.player.position.add(movement);
        var final_pos = desired_pos;
        var push_vector = Vec2{ .x = 0, .y = 0 };

        // Check each wall for collision and accumulate push vectors
        for (self.walls.items) |wall| {
            const closest = closestPointOnWall(wall, desired_pos);
            const to_player = desired_pos.sub(closest);
            const dist = to_player.length();

            if (dist < PLAYER_RADIUS) {
                // Calculate push vector to move player out of collision
                const push = to_player.normalize().scale(PLAYER_RADIUS - dist);
                push_vector = push_vector.add(push);
            }
        }

        // Apply accumulated push vector to final position
        final_pos = final_pos.add(push_vector);

        // Update player position
        self.player.position = final_pos;
    }

    pub fn toggleDebug(self: *Map) void {
        self.debug_mode = (self.debug_mode + 1) % DEBUG_MODES;
    }
};
