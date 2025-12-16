# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Zig project using SDL3 for graphics and window management. The project name is "zdl" (Zig + SDL).

**Important**: This project has a clean separation between the **game engine** and **game code**. When working on this project:
- Engine code is in `src/engine/` - only modify if changing core engine functionality
- Game code is in `src/game/` - this is where gameplay logic lives
- See [ENGINE_README.md](ENGINE_README.md) for the engine architecture and API

## Build System

- Zig version: 0.15.2
- Build system: Zig's standard build system (`build.zig`)
- Dependencies managed via `build.zig.zon`

### Common Commands

```bash
# Build the project
zig build

# Run the application
zig build run

# Clean build artifacts
rm -rf zig-out .zig-cache
```

## Dependencies

The project uses `zig-sdl3` from Codeberg (7Games/zig-sdl3) for SDL3 bindings. The dependency is declared in `build.zig.zon` and imported as `sdl3` module in the build script.

## Architecture

### Engine-Game Separation

The codebase is organized into two main parts:

**Engine Layer** (`src/engine/`, `src/input/`, `src/renderer/`, `src/math/`, etc.):
- [src/engine/engine.zig](src/engine/engine.zig) - Core engine that manages SDL3, GPU, and game loop
- [src/engine/application.zig](src/engine/application.zig) - Application interface for games
- [src/input/input.zig](src/input/input.zig) - Input system
- [src/renderer/sprite.zig](src/renderer/sprite.zig) - Sprite batching and rendering
- [src/camera.zig](src/camera.zig) - 2D camera with orthographic projection
- [src/math/](src/math/) - Math library (Vec2, Mat4, etc.)

**Game Layer** (`src/game/`):
- [src/game/platformer.zig](src/game/platformer.zig) - Platformer game example
- [src/game/pong.zig](src/game/pong.zig) - Pong game example
- Games implement the `Application` interface with `init()`, `deinit()`, `update()`, `render()`

**Entry Point**:
- [src/main.zig](src/main.zig) - Minimal boilerplate that initializes the engine and runs the game

### Application Interface

Games implement four simple methods:
```zig
pub fn init(self: *MyGame, ctx: *Context) !void
pub fn deinit(self: *MyGame, ctx: *Context) void
pub fn update(self: *MyGame, ctx: *Context, delta_time: f32) !void
pub fn render(self: *MyGame, ctx: *Context) !void
```

The `Context` provides access to:
- `ctx.input` - Input system
- `ctx.camera` - 2D camera
- `ctx.sprite_batch` - Sprite renderer
- `ctx.device`, `ctx.window` - Low-level SDL3 access

### Build Configuration

[build.zig](build.zig) defines:
- Executable target configuration with standard optimization options
- SDL3 dependency resolution and module imports
- Run step for executing the built application
- Command-line argument forwarding to the executable

## Development Notes

- The project uses Zig's defer pattern for resource cleanup
- Engine handles all SDL3 initialization, GPU setup, and the game loop
- Coordinate system: (0, 0) is the center of the screen, Y-down
- Frame timing uses delta time for smooth, framerate-independent movement
- Sprite batching minimizes draw calls for better performance

## Creating a New Game

To create a new game:

1. Create a new file in `src/game/your_game.zig`
2. Implement the Application interface (see `platformer.zig` or `pong.zig` for examples)
3. Update `src/main.zig` to import and run your game
4. Build and run with `zig build run`

The engine takes care of everything else!
