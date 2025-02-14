const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const map = @import("map.zig");
const Map = map.Map;
const Vec2 = map.Vec2;

pub const Renderer3D = struct {
    // Configuration
    screen_width: u32,
    screen_height: u32,
    fov: f32, // Field of view in radians
    num_rays: u32, // Number of rays to cast (usually equal to screen width)
    max_distance: f32, // Maximum distance to render
    wall_height_scale: f32, // Scale factor for wall heights

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

    pub fn init(screen_width: u32, screen_height: u32) Renderer3D {
        return .{
            .screen_width = screen_width,
            .screen_height = screen_height,
            .fov = std.math.pi / 3.0, // 60 degrees
            .num_rays = screen_width,
            .max_distance = 500.0, // Reduced for better distance scaling
            .wall_height_scale = 32.0,
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
            if (self.castRay(game_map, player_pos, ray_dir)) |distance| {
                // Fix fisheye effect by using perpendicular distance
                // Without this, walls appear curved because we're using the direct distance
                // We multiply by cos(angle) to get the distance to the plane of projection
                const perp_distance = distance * @cos(ray_angle - player_angle);

                // Calculate wall height using perspective projection
                // - Screen height is our base size
                // - wall_height_scale controls how tall walls appear
                // - Divide by distance to make further walls appear shorter
                const wall_height = @as(f32, @floatFromInt(self.screen_height)) * (self.wall_height_scale / perp_distance);

                // Center the wall vertically on screen
                const wall_top = @as(i32, @intFromFloat(@as(f32, @floatFromInt(self.screen_height)) / 2.0 - wall_height / 2.0));
                const wall_bottom = @as(i32, @intFromFloat(@as(f32, @floatFromInt(self.screen_height)) / 2.0 + wall_height / 2.0));

                // Shade walls based on distance
                // - Closer walls are brighter (brightness closer to 1.0)
                // - Further walls are darker (brightness closer to 0.2)
                // - Clamp keeps brightness between 0.2 and 1.0
                const brightness = std.math.clamp(1.0 - (distance / self.max_distance), 0.2, 1.0);
                const color = @as(u8, @intFromFloat(255.0 * brightness));
                _ = c.SDL_SetRenderDrawColor(renderer, color, color, color, 255);

                // Draw vertical line for this wall slice
                _ = c.SDL_RenderDrawLine(renderer, @intCast(i), wall_top, @intCast(i), wall_bottom);
            }
        }
    }

    fn castRay(self: *const Renderer3D, game_map: *const Map, start: Vec2, dir: Vec2) ?f32 {
        var closest_hit: ?f32 = null;

        // Check intersection with each wall
        for (game_map.walls.items) |wall| {
            if (self.rayLineIntersection(start, dir, wall.start, wall.end)) |distance| {
                if (closest_hit == null or distance < closest_hit.?) {
                    closest_hit = distance;
                }
            }
        }

        return closest_hit;
    }

    fn rayLineIntersection(self: *const Renderer3D, ray_start: Vec2, ray_dir: Vec2, line_start: Vec2, line_end: Vec2) ?f32 {
        _ = self;
        // Wall intersection uses the parametric form of both lines:
        // Ray: P = ray_start + t1 * ray_dir
        // Wall: Q = line_start + t2 * (line_end - line_start)
        // where t1, t2 are scalars between 0 and 1
        const line_vec = line_end.sub(line_start);

        // Calculate determinant to solve for intersection
        // det = 0 means lines are parallel
        // det = ray_dir × line_vec (cross product in 2D)
        const det = ray_dir.x * line_vec.y - ray_dir.y * line_vec.x;

        // If lines are parallel (or nearly parallel), no intersection
        if (@abs(det) < 0.0001) return null;

        // Calculate intersection parameters using Cramer's rule
        const to_start = line_start.sub(ray_start);
        // t1 tells us how far along the ray the intersection occurs
        const t1 = (to_start.x * line_vec.y - to_start.y * line_vec.x) / det;
        // t2 tells us if intersection is within the wall segment
        const t2 = (to_start.x * ray_dir.y - to_start.y * ray_dir.x) / det;

        // Check if intersection is valid:
        // - t1 >= 0: Intersection is in front of ray
        // - t2 >= 0 && t2 <= 1: Intersection is within wall segment
        if (t1 >= 0.0 and t2 >= 0.0 and t2 <= 1.0) {
            return t1; // Return distance along ray to intersection
        }

        return null;
    }
};
