# ZOOM Implementation Roadmap

Building a DOOM clone in Zig.

## Phase 1: Basic Framework
- [x] Window creation with SDL2
- [ ] Basic game loop implementation
  - [ ] Fixed timestep
  - [ ] Input handling
- [ ] 2D map renderer (top-down view)
  - [ ] Simple rectangle-based walls
  - [ ] Player position indicator
- [ ] Basic player movement
  - [ ] Forward/backward movement
  - [ ] Rotation
  - [ ] Collision detection with walls

## Phase 2: Basic 3D Rendering
- [ ] Raycasting implementation
  - [ ] Basic wall rendering
  - [ ] Distance calculations
  - [ ] Wall height calculations
- [ ] Texture mapping
  - [ ] UV coordinate calculation
  - [ ] Simple texture loader
  - [ ] Wall texturing
- [ ] View rotation and player perspective
- [ ] Floor/ceiling rendering
- [ ] Improved collision detection

## Phase 3: WAD Loading
- [ ] WAD file parser
  - [ ] Directory structure
  - [ ] Lump reading
- [ ] Map data loading
  - [ ] Vertices
  - [ ] Linedefs
  - [ ] Sectors
- [ ] Texture loading from WAD
- [ ] BSP tree implementation
  - [ ] BSP builder
  - [ ] Rendering using BSP

## Phase 4: Game Features
- [ ] Sprite system
  - [ ] Static objects
  - [ ] Animated sprites
- [ ] Enemy implementation
  - [ ] Basic AI
  - [ ] Movement
  - [ ] State management
- [ ] Level features
  - [ ] Doors
  - [ ] Lifts/elevators
  - [ ] Triggers
- [ ] Weapons
  - [ ] Shooting mechanics
  - [ ] Hit detection
  - [ ] Weapon switching
- [ ] Sector lighting
  - [ ] Light levels
  - [ ] Dynamic lighting

## Phase 5: Polish
- [ ] Sound system
  - [ ] Sound effect loading
  - [ ] Sound playback
  - [ ] Background music
- [ ] Menu system
  - [ ] Main menu
  - [ ] In-game menu
- [ ] Save/load system
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