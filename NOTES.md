# Development Notes

## Collision Detection Approaches

### Current Implementation: Separation Vector (Push Vector)
Also known as "Minimum Translation Vector" (MTV) method.

**Implementation Details:**
- Calculate closest point on each wall to player
- Create push vectors away from walls when too close
- Accumulate push vectors for smooth multi-wall interaction
- Use collision radius to determine "too close"

**Pros:**
- Simple to understand and implement
- Works well for simple shapes and basic movement
- Good for games where exact physics isn't critical
- Natural sliding along walls
- Easy to debug and visualize

**Cons:**
- Can have edge cases with fast movement
- Not physically accurate for bouncing/ricochet
- Can have issues with multiple simultaneous collisions

**Debug Visualization:**
- Green circle: Shows collision radius
- Yellow dots: Closest points on walls
- Magenta lines: Direction of push vectors

### Alternative Approaches

#### 1. Swept Collision Detection
Checks entire path of movement instead of just final position.

**Pros:**
- More accurate for fast-moving objects
- Better for platformers and precise movement
- Can handle tunneling (objects moving through thin walls)

**Cons:**
- More complex to implement
- More computationally expensive

#### 2. Physics Engine Approach (Box2D style)
Full physics simulation with continuous collision detection.

**Pros:**
- Physically accurate
- Handles complex interactions (bouncing, sliding, friction)
- Good for physics-based games

**Cons:**
- Much more complex
- Overkill for simple movement
- Can be harder to control game feel

#### 3. Grid/Cell-Based Collision
World divided into grid cells for collision checking.

**Pros:**
- Very fast for large numbers of objects
- Good for tile-based games
- Simple to implement for grid-aligned objects

**Cons:**
- Less precise for non-grid-aligned objects
- Can be memory intensive for large worlds
- Not great for rotating objects

#### 4. Spatial Partitioning
Uses data structures like Quadtrees or Spatial Hashing.

**Pros:**
- Efficient for many objects
- Good for open world games
- Works well with dynamic objects

**Cons:**
- More complex to implement
- Overhead for maintaining spatial structure
- Can be overkill for simple games

### DOOM-Style Games Specifically

**Original DOOM:**
- Used simplified collision system with bounding boxes
- Focused on speed and simplicity

**Modern DOOM-likes typically use:**
- Separation vectors (like our implementation)
- Swept collision for more precise movement
- Sometimes simplified physics engines

### Potential Future Improvements

1. **Add swept collision for fast movement**
   - Would prevent tunneling at high speeds
   - More complex but more accurate

2. **Implement spatial partitioning**
   - Would be needed for many moving objects
   - Could use quadtree or spatial hash

3. **Add proper physics for projectiles/explosions**
   - More realistic projectile behavior
   - Better explosion effects

4. **Hybrid approach**
   - Different collision systems for different object types
   - Balance between accuracy and performance

### Current Implementation Details

```zig
// Key components of our collision system:
pub fn tryMovePlayer(self: *Map, dx: f32, dy: f32) void {
    const movement = Vec2{ .x = dx, .y = dy };
    const desired_pos = self.player.position.add(movement);
    var final_pos = desired_pos;
    var push_vector = Vec2{ .x = 0, .y = 0 };

    // Check each wall for collision
    for (self.walls.items) |wall| {
        const closest = closestPointOnWall(wall, desired_pos);
        const to_player = desired_pos.sub(closest);
        const dist = to_player.length();

        if (dist < PLAYER_RADIUS) {
            const push = to_player.normalize().scale(PLAYER_RADIUS - dist);
            push_vector = push_vector.add(push);
        }
    }

    final_pos = final_pos.add(push_vector);
    self.player.position = final_pos;
}
```

This implementation provides a good balance of:
- Simplicity
- Performance
- Natural feeling movement
- Easy debugging
- Maintainable code 