# Glowtrail Architecture

Glowtrail is a compact Zig/Sokol game. The game is currently built as a small set of focused modules so iteration stays fast during prototyping.

```mermaid
flowchart TD
    MainFile["src/main.zig<br/>game loop and gameplay"] --> SokolApp["Sokol app callbacks<br/>init, frame, event, cleanup"]
    User["Player input<br/>WASD, Space, Shift, R"] --> SokolApp
    SokolApp --> AppState["AppState<br/>persistent game state"]

    AppState --> Input["Input state<br/>key array and actions"]
    AppState --> Player["Player state<br/>position, velocity, jump, grind state"]
    CourseFile["src/course.zig<br/>rails, obstacles, hazards, start, goal"] --> Course["Course data"]
    MathFile["src/math.zig<br/>Vec2, Rect, collision helpers"] --> Course
    AppState --> Sparks["Spark particle pool<br/>lifetime, velocity, color"]
    FxFile["src/fx.zig<br/>spark types and shader sources"] --> GpuFx["GPU resources<br/>spark shader, pipeline, vertex buffer"]
    AppState --> GpuFx

    Input --> Update["Update step"]
    Player --> Update
    Course --> Update
    Sparks --> Update

    Update --> GroundMove["Ground skating<br/>manual facing and collision"]
    Update --> Jump["Jump system<br/>double jump opens grind window"]
    Update --> Grind["Rail grind system<br/>snap to rail, advance along segments, auto-turn"]
    Update --> SparkSim["Spark simulation<br/>emit while grinding, fade particles"]
    Update --> Goal["Goal and reset checks"]

    GroundMove --> Player
    Jump --> Player
    Grind --> Player
    SparkSim --> Sparks
    Goal --> Player

    AppState --> Render["Render step"]
    RenderFile["src/render.zig<br/>view transform and drawing helpers"] --> Render
    Render --> SglDraw["Sokol GL immediate draws<br/>course, rails, rider, HUD text"]
    Render --> SparkDraw["Batched spark draw<br/>particle quads to dynamic vertex buffer"]
    SparkDraw --> SparkShader["Spark shader<br/>glow, streak, grain"]
    SglDraw --> Screen["Frame"]
    SparkShader --> Screen
```

## Main Files

- `build.zig` defines native and web build targets and links Sokol.
- `web/shell.html` is the browser shell and visible web controls prompt.
- `src/main.zig` contains the Sokol callbacks, `AppState`, gameplay update flow, player movement, jumping, grinding, spark emission, and HUD.
- `src/course.zig` owns the course constants: world size, rail point lists, obstacles, hazards, start, and goal.
- `src/math.zig` owns small geometry types and helpers like `Vec2`, `Rect`, `closestPointOnSegment`, and collision math.
- `src/render.zig` owns view transforms and reusable Sokol GL drawing helpers for the course and player shapes.
- `src/fx.zig` owns spark particle/vertex types and the platform-specific spark shader source strings.

## Runtime Flow

1. Sokol calls `init`, which initializes graphics, debug text, and the spark shader pipeline.
2. Sokol calls `event` whenever keys are pressed or released. The game stores key state and triggers actions like jump, grind, or reset.
3. Sokol calls `frame` every tick. The frame computes `dt`, updates the simulation, and renders.
4. The update step chooses ground skating or rail grinding, advances jump state, emits spark particles, and checks hazards or the goal.
5. The render step uses `render.zig` for course/player drawing, then draws spark particles through the custom GPU shader in `fx.zig`.

## Gameplay Systems

- Manual skating: WASD or arrow keys accelerate the rider and set facing.
- Jumping: Space starts a jump. Pressing Space again opens a short grind window.
- Grinding: Shift near a rail during the grind window snaps the rider to the nearest rail segment. Rail movement advances segment by segment, so corners auto-turn.
- Sparks: grinding emits particles from a fixed pool. Each live particle becomes a small quad sent to the GPU spark shader.

## Data Ownership

`AppState` owns mutable state:

- input key states
- player state
- spark particle pool
- GPU spark resources
- HUD message state

The course layout is immutable global data:

- rail point arrays
- obstacle rectangles
- hazard rectangles
- start and goal rectangles

This separation keeps the current prototype easy to reset, tune, and eventually split into modules.
