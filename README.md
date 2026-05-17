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

Web deployment:

- Latest deployed build: [glowtrail.cbrnl.com](https://glowtrail.cbrnl.com)
- Workflow: `.github/workflows/deploy-pages.yml`
- Expected DNS: `CNAME` `glowtrail` -> `cabernal.github.io`

The Pages workflow builds with Zig `0.15.2` and Emscripten `4.0.14`, copies
`zig-out/web/glowtrail.html` to `zig-out/web/index.html`, writes
`glowtrail.cbrnl.com` to `zig-out/web/CNAME`, and deploys `zig-out/web`.

Architecture notes and diagram:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
