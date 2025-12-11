# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Zig project using SDL3 for graphics and window management. The project name is "zdl" (Zig + SDL).

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

### Entry Point

[src/main.zig](src/main.zig) - Contains the main application entry point with:
- SDL3 initialization and cleanup
- Window and renderer creation
- Event loop handling (quit and key events)
- Frame rendering with timing control (~60 FPS)

### Module Structure

The executable imports SDL3 as a module named `sdl3`. Key SDL3 subsystems used:
- `sdl.init()` / `sdl.quit()` - SDL initialization/cleanup
- `sdl.render.Renderer` - Rendering context
- `sdl.events.poll()` - Event polling
- `sdl.timer.delayMilliseconds()` - Frame timing

### Build Configuration

[build.zig](build.zig) defines:
- Executable target configuration with standard optimization options
- SDL3 dependency resolution and module imports
- Run step for executing the built application
- Command-line argument forwarding to the executable

## Development Notes

- The project uses Zig's defer pattern for resource cleanup (window, renderer, SDL quit)
- Event handling uses Zig's pattern matching on SDL event types
- The renderer clears to a blue color (RGB: 30, 30, 80) each frame
- Frame timing is implemented with a simple 16ms delay for ~60 FPS
