# ZOOM Implementation Roadmap

Building a DOOM clone in Zig.

## Phase 1: Basic Framework ✅
- [x] Window creation with SDL2
- [x] Basic game loop implementation
  - [x] Fixed timestep
  - [x] Input handling
- [x] 2D map renderer (top-down view)
  - [x] Simple rectangle-based walls
  - [x] Player position indicator
- [x] Basic player movement
  - [x] Forward/backward movement
  - [x] Rotation
  - [x] Collision detection with walls
    - [x] Separation vector (MTV) based collision
    - [x] Wall sliding
    - [x] Debug visualization
    - [ ] Fast movement edge cases (tunneling)

## Phase 2: Basic 3D Rendering
- [x] Raycasting implementation
  - [x] Basic wall rendering
  - [x] Distance calculations
  - [x] Wall height calculations
  - [x] Fisheye correction
  - [x] Distance-based shading
- [ ] Floor and ceiling
  - [x] Basic solid colors
  - [ ] Distance-based shading
  - [ ] Proper perspective projection
- [x] Texture mapping
  - [x] UV coordinate calculation
  - [x] Simple texture loader
  - [x] Wall texturing
  - [x] Texture alignment and scaling
- [x] View rotation and player perspective
- [ ] Improved collision detection
  - [ ] Sliding along walls more smoothly
  - [ ] Prevent getting stuck on corners

## Phase 3: WAD Loading
- [ ] WAD file parser
  - [ ] Directory structure
  - [ ] Lump reading
  - [ ] Error handling for malformed WADs
- [ ] Map data loading
  - [ ] Vertices
  - [ ] Linedefs
  - [ ] Sectors
  - [ ] Things (player starts, items, etc)
- [ ] Texture loading from WAD
  - [ ] Palette handling
  - [ ] Texture composition
  - [ ] Animated textures
- [ ] BSP tree implementation
  - [ ] BSP builder
  - [ ] Rendering using BSP
  - [ ] Subsector handling

## Phase 4: Game Features
- [ ] Sprite system
  - [ ] Static objects
  - [ ] Animated sprites
  - [ ] Sprite sorting and clipping
- [ ] Enemy implementation
  - [ ] Basic AI
  - [ ] Movement
  - [ ] State management
  - [ ] Pathfinding
- [ ] Level features
  - [ ] Doors
  - [ ] Lifts/elevators
  - [ ] Triggers
  - [ ] Switches and buttons
- [ ] Weapons
  - [ ] Shooting mechanics
  - [ ] Hit detection
  - [ ] Weapon switching
  - [ ] Projectiles
- [ ] Sector lighting
  - [ ] Light levels
  - [ ] Dynamic lighting
  - [ ] Light diminishing

## Phase 5: Polish
- [ ] Sound system
  - [ ] Sound effect loading
  - [ ] Sound playback
  - [ ] Background music
  - [ ] 3D positional audio
- [ ] Menu system
  - [ ] Main menu
  - [ ] In-game menu
  - [ ] Options/settings
  - [ ] Save/load game UI
- [ ] Save/load system
  - [ ] Game state serialization
  - [ ] Save file management
  - [ ] Loading screen
- [ ] Performance optimizations
  - [ ] Rendering optimizations
  - [ ] Memory usage improvements
  - [ ] Profiling and benchmarking
  - [ ] Static linking of SDL2 for better distribution

## Technical Notes

### Memory Management
- Use arena allocators for level data
- Fixed-size allocators for frequently allocated objects
- Careful management of texture and sprite resources

### Math Implementation
- Fixed-point arithmetic for compatibility
- Binary Angle Measurement (BAM) for rotations
- Lookup tables for performance

### Dependencies
- SDL2 for window management and input (currently dynamically linked)
- (Optional) SDL2_mixer for audio 