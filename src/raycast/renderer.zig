const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const map_mod = @import("map.zig");
const Map = map_mod.Map;
const Vec2 = map_mod.Vec2;
const texture = @import("texture.zig");
const TextureManager = texture.TextureManager;

pub const Renderer3D = struct {
    // Configuration
    screen_width: u32,
    screen_height: u32,
    fov: f32, // Field of view in radians
    num_rays: u32, // Number of rays to cast (usually equal to screen width)
    max_distance: f32, // Maximum distance to render
    wall_height_scale: f32, // Scale factor for wall heights
    texture_manager: *TextureManager,

    // Texture configuration
    const TEXTURE_SIZE: f32 = 64.0; // Size of texture in pixels
    const HORIZONTAL_TILING_MULTIPLIER: f32 = 4.0; // Number of times to repeat texture horizontally per TEXTURE_SIZE units
    const VERTICAL_TILING_MULTIPLIER: f32 = 2.0; // Number of times to repeat texture vertically

    // Ray casting technique used here:
    // 1. For each vertical column of the screen, cast a ray from player position
    // 2. Ray angle is calculated based on:
    //    - Player's viewing angle (center of screen)
    //    - Field of view (spread of rays)
    //    - Current column position (offset from center)
    // 3. When ray hits a wall:
    //    - Calculate perpendicular distance to avoid fisheye effect
    //    - Use distance to determine wall height (closer = taller)
    //    - Use distance for shading (closer = brighter)
    // 4. Wall intersection uses line-line intersection:
    //    - Convert wall into a line segment
    //    - Calculate intersection point using determinants
    //    - Check if intersection is within wall bounds
    //
    // This creates a pseudo-3D effect known as 2.5D rendering,
    // similar to what was used in games like Wolfenstein 3D.
    // Limitations:
    // - Can't look up/down (all walls are vertical)
    // - No overlapping walls (closest hit is always visible)
    // - No ceiling/floor textures (yet)
    // - No wall textures (yet)

    pub fn init(screen_width: u32, screen_height: u32, texture_manager: *TextureManager) Renderer3D {
        return .{
            .screen_width = screen_width,
            .screen_height = screen_height,
            .fov = std.math.pi / 3.0, // 60 degrees
            .num_rays = screen_width,
            .max_distance = 500.0, // Reduced for better distance scaling
            .wall_height_scale = 32.0,
            .texture_manager = texture_manager,
        };
    }

    pub fn render(
        self: *const Renderer3D,
        renderer: *c.SDL_Renderer,
        game_map: *const Map,
        player_pos: Vec2,
        player_angle: f32,
    ) void {
        // Clear the screen with a dark color
        _ = c.SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255);
        _ = c.SDL_RenderClear(renderer);

        // Draw ceiling and floor with rectangles
        const half_height = @as(i32, @intCast(self.screen_height / 2));

        // Draw ceiling (tan color: RGB 210, 180, 140)
        _ = c.SDL_SetRenderDrawColor(renderer, 210, 180, 140, 255);
        const ceiling_rect = c.SDL_Rect{
            .x = 0,
            .y = 0,
            .w = @intCast(self.screen_width),
            .h = half_height,
        };
        _ = c.SDL_RenderFillRect(renderer, &ceiling_rect);

        // Draw floor (brown color: RGB 139, 69, 19)
        _ = c.SDL_SetRenderDrawColor(renderer, 139, 69, 19, 255);
        const floor_rect = c.SDL_Rect{
            .x = 0,
            .y = half_height,
            .w = @intCast(self.screen_width),
            .h = half_height,
        };
        _ = c.SDL_RenderFillRect(renderer, &floor_rect);

        // Calculate ray angles and cast rays
        const ray_angle_step = self.fov / @as(f32, @floatFromInt(self.num_rays));
        const start_angle = player_angle - (self.fov / 2.0);

        var i: u32 = 0;
        while (i < self.num_rays) : (i += 1) {
            // Calculate angle for this ray:
            // - start_angle is the leftmost ray
            // - Each subsequent ray is offset by ray_angle_step
            // This spreads the rays evenly across our field of view
            const ray_angle = start_angle + (@as(f32, @floatFromInt(i)) * ray_angle_step);
            const ray_dir = Vec2{
                .x = @cos(ray_angle),
                .y = @sin(ray_angle),
            };

            // Cast ray and get distance to nearest wall
            if (self.castRay(game_map, player_pos, ray_dir)) |hit| {
                // Fix fisheye effect by using perpendicular distance
                // Without this, walls appear curved because we're using the direct distance
                // We multiply by cos(angle) to get the distance to the plane of projection
                const perp_distance = hit.distance * @cos(ray_angle - player_angle);

                // Calculate wall height using perspective projection
                // - Screen height is our base size
                // - wall_height_scale controls how tall walls appear
                // - Divide by distance to make further walls appear shorter
                const wall_height = @as(f32, @floatFromInt(self.screen_height)) * (self.wall_height_scale / perp_distance);

                // Center the wall vertically on screen
                const wall_top = @as(i32, @intFromFloat(@as(f32, @floatFromInt(self.screen_height)) / 2.0 - wall_height / 2.0));
                const wall_bottom = @as(i32, @intFromFloat(@as(f32, @floatFromInt(self.screen_height)) / 2.0 + wall_height / 2.0));

                // Calculate texture coordinates
                const hit_vec = hit.hit_point.sub(hit.wall.start);

                // Calculate horizontal texture coordinate (u)
                // Get position along wall and wrap around texture width
                const wall_dist = hit_vec.length();
                const u = @mod(wall_dist / TEXTURE_SIZE * HORIZONTAL_TILING_MULTIPLIER, 1.0);

                // Draw textured wall slice
                if (self.texture_manager.getTexture(hit.wall.texture_name)) |wall_texture| {
                    var y: i32 = wall_top;
                    while (y < wall_bottom) : (y += 1) {
                        if (y < 0 or y >= @as(i32, @intCast(self.screen_height))) continue;

                        // Calculate vertical texture coordinate (v)
                        // Map screen space to texture space and wrap
                        const v = @mod(@as(f32, @floatFromInt(y - wall_top)) / wall_height * VERTICAL_TILING_MULTIPLIER, 1.0);
                        const color = wall_texture.sampleTexture(u, v);

                        // Apply distance-based shading
                        const brightness = std.math.clamp(1.0 - (hit.distance / self.max_distance), 0.2, 1.0);
                        // Color is in RGBA format (0xRRGGBBAA)
                        const r = @as(u8, @intFromFloat(@as(f32, @floatFromInt((color >> 16) & 0xFF)) * brightness));
                        const g = @as(u8, @intFromFloat(@as(f32, @floatFromInt((color >> 8) & 0xFF)) * brightness));
                        const b = @as(u8, @intFromFloat(@as(f32, @floatFromInt(color & 0xFF)) * brightness));

                        _ = c.SDL_SetRenderDrawColor(renderer, r, g, b, 255);
                        _ = c.SDL_RenderDrawPoint(renderer, @intCast(i), y);
                    }
                } else {
                    // Fallback to solid color if texture not found
                    const brightness = std.math.clamp(1.0 - (hit.distance / self.max_distance), 0.2, 1.0);
                    const color = @as(u8, @intFromFloat(255.0 * brightness));
                    _ = c.SDL_SetRenderDrawColor(renderer, color, color, color, 255);
                    _ = c.SDL_RenderDrawLine(renderer, @intCast(i), wall_top, @intCast(i), wall_bottom);
                }
            }
        }
    }

    const RayHit = struct {
        distance: f32,
        wall: map_mod.Wall,
        hit_point: Vec2,
        normal: Vec2,
    };

    fn castRay(self: *const Renderer3D, game_map: *const Map, start: Vec2, dir: Vec2) ?RayHit {
        var closest_hit: ?RayHit = null;

        // Check intersection with each wall
        for (game_map.walls.items) |wall| {
            if (self.rayLineIntersection(start, dir, wall)) |hit| {
                if (closest_hit == null or hit.distance < closest_hit.?.distance) {
                    closest_hit = hit;
                }
            }
        }

        return closest_hit;
    }

    fn rayLineIntersection(self: *const Renderer3D, ray_start: Vec2, ray_dir: Vec2, wall: map_mod.Wall) ?RayHit {
        _ = self;
        const wall_vec = wall.end.sub(wall.start);
        const det = ray_dir.x * wall_vec.y - ray_dir.y * wall_vec.x;

        if (@abs(det) < 0.0001) return null;

        const to_start = wall.start.sub(ray_start);
        const t1 = (to_start.x * wall_vec.y - to_start.y * wall_vec.x) / det;
        const t2 = (to_start.x * ray_dir.y - to_start.y * ray_dir.x) / det;

        if (t1 >= 0.0 and t2 >= 0.0 and t2 <= 1.0) {
            const hit_point = ray_start.add(ray_dir.scale(t1));
            // Calculate wall normal (perpendicular to wall direction)
            var normal = Vec2{
                .x = -wall_vec.y,
                .y = wall_vec.x,
            };
            normal = normal.normalize();

            return RayHit{
                .distance = t1,
                .wall = wall,
                .hit_point = hit_point,
                .normal = normal,
            };
        }

        return null;
    }
};
