# Graphics System Refactoring Plan

## Overview
Refactoring the graphics system to better handle DOOM's various graphic formats with a clean separation of concerns.

## Documentation Links
- [DOOM WAD Format](https://doomwiki.org/wiki/WAD)
- [Picture Format](https://doomwiki.org/wiki/Picture_format)
- [Patch Format](https://doomwiki.org/wiki/Patch)
- [Sprite Format](https://doomwiki.org/wiki/Sprite)
- [Flat Format](https://doomwiki.org/wiki/Flat)
- [Texture Format](https://doomwiki.org/wiki/Texture)
- [DOOM Source Code](https://github.com/id-Software/DOOM)
- [DOOM Technical Specs](https://www.gamers.org/dhs/helpdocs/dmsp1666.html)
- [Decoding DOOM Picture Files (Detailed Tutorial)](https://www.cyotek.com/blog/decoding-doom-picture-files)
- [DOOM FAQ Picture Format Specs](https://www.gamers.org/docs/FAQ/DOOM.FAQ.Specs.Chapters.5.html)

## Phase 1: Base Picture Format ✅
1. Create base `Picture` format in `src/graphics/picture.zig`
   - [x] Header structure
   - [x] Column-based format
   - [x] Post data handling
   - [x] Pixel retrieval
   - [x] Memory management
   - [x] Unit tests

## Phase 2: Patch Format ✅
1. Move patch code to `src/graphics/patch.zig`
   - [x] Use composition with base `Picture` format
   - [x] Update rendering capabilities
   - [x] Fix memory management
   - [x] Update unit tests
2. Update imports and references
   - [x] Update `texture.zig`
   - [x] Update `texture_viewer.zig`
   - [x] Fix build system

## Phase 3: Sprites ✅
1. Create sprite format in `src/graphics/sprite.zig`
   - [x] Use composition with base `Picture` format
   - [x] Add sprite-specific metadata
   - [x] Frame sequence handling
   - [x] Rotation state handling
   - [x] Rendering capabilities
   - [x] Unit tests

## Phase 4: Flats ✅
1. Create flat format in `src/graphics/flat.zig`
   - [x] Raw pixel data format (64x64)
   - [x] Size validation
   - [x] Rendering capabilities
   - [x] Unit tests

## Phase 5: Composite Textures ✅
1. Create composite texture format
   - [x] TEXTURE1/TEXTURE2 parsing
   - [x] Patch assembly
   - [x] Texture cache management
   - [x] Unit tests

## Phase 6: Animation Support
1. Add animation capabilities
   - [ ] Animated walls
   - [ ] Animated flats
   - [ ] Switch textures
   - [ ] Unit tests 