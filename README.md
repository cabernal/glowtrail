# Glowtrail

A small standalone Zig/Sokol skate puzzle prototype with rail grinding and shader sparks.

Controls:

- WASD or arrow keys steer and push.
- Space, Space, then Shift near a rail starts a grind.
- While grinding, the rider follows the rail and auto-turns through corners.
- R resets the run.

Build and run:

```sh
zig build run
```

Build web:

```sh
zig build web -Demsdk=/path/to/emsdk
```

Architecture notes and diagram:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
