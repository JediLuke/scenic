# ViewPort Overview

The ViewPort is the central coordinator in Scenic that connects Scenes to Drivers. It manages the rendering pipeline, input routing, and maintains the semantic element registry for testing and automation.

## Core Responsibilities

### 1. Graph Management

When a Scene calls `push_graph/2`, the ViewPort:
- Compiles the graph into a binary script (via GraphCompiler)
- Stores the script in an ETS table for fast access
- Sends the script to all connected drivers for rendering
- Compiles semantic metadata for testing (in parallel, zero overhead)

### 2. Input Routing

User input flows through the ViewPort:
- Driver captures input (mouse, keyboard, etc.)
- ViewPort receives input events
- Input is routed to appropriate Scenes based on focus and capture state
- Scenes handle input and update their graphs

### 3. Driver Coordination

The ViewPort manages one or more drivers:
- Drivers handle actual rendering (OpenGL, etc.)
- Multiple drivers can connect (multi-monitor support)
- ViewPort ensures all drivers receive graph updates
- Drivers report size, capabilities, and input back to ViewPort

### 4. Semantic Element Registry

The ViewPort maintains a semantic registry of UI elements for testing and automation:
- Elements with IDs are automatically registered
- Fast lookup by ID via ETS tables
- Hierarchical relationships tracked
- Enables Playwright-like testing

[Read more about testing and automation here.](testing_and_automation.html)

## Starting a ViewPort

ViewPorts are typically started by your application supervisor:

```elixir
children = [
  {Scenic.ViewPort,
   name: :main_viewport,
   size: {800, 600},
   default_scene: MyApp.Scene.Main,
   drivers: [
     [module: Scenic.Driver.Local]
   ]},
  # ... other children
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Configuration Options

- `:name` - Atom name for the viewport (required)
- `:size` - `{width, height}` tuple (required)
- `:default_scene` - Initial scene module to display
- `:drivers` - List of driver configurations
- `:semantic_registration` - Enable/disable semantic system (default: `true`)

## Querying ViewPort Info

Get the current ViewPort state:

```elixir
{:ok, viewport} = Scenic.ViewPort.info(:main_viewport)

# Access fields
viewport.size          #=> {800, 600}
viewport.pid           #=> #PID<0.123.0>
viewport.script_table  #=> ETS table reference
viewport.semantic_table #=> ETS table reference (if enabled)
```

## Common Operations

### Setting a Scene

```elixir
Scenic.ViewPort.set_root(:main_viewport, MyApp.Scene.Other)
```

### Updating Graph

From within a Scene:

```elixir
def handle_info(:update, scene) do
  graph =
    scene.assigns.graph
    |> Graph.modify(:my_text, &text(&1, "Updated!"))

  scene = push_graph(scene, graph)
  {:noreply, scene}
end
```

### Sending Input (Testing)

```elixir
# Send input directly (for testing)
input = {:cursor_button, {:btn_left, 1, [], {100, 50}}}
Scenic.ViewPort.input(:main_viewport, input)
```

For production testing, use the semantic system instead:

```elixir
{:ok, viewport} = Scenic.ViewPort.info(:main_viewport)
{:ok, coords} = Scenic.ViewPort.Semantic.click_element(viewport, :my_button)
```

## Architecture

```
┌─────────────────────────────────────────────┐
│              Application                     │
└─────────────────┬───────────────────────────┘
                  │
        ┌─────────▼─────────┐
        │     ViewPort      │
        │                   │
        │  - Script Table   │
        │  - Semantic Table │
        │  - Input Routing  │
        └─────────┬─────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
   ┌────▼────┐       ┌──────▼──────┐
   │  Scene  │       │   Driver    │
   │         │       │             │
   │  Graph  │──────▶│  Rendering  │
   └─────────┘       └─────────────┘
```

## Performance

The ViewPort is designed for high performance:
- **ETS tables** - O(1) lookups for scripts and semantic elements
- **Parallel compilation** - Semantic compilation doesn't block rendering
- **Minimal copying** - Scripts shared via ETS, not message passing
- **Configurable** - Semantic system can be disabled if not needed

## What to Read Next?

- [Testing and Automation](testing_and_automation.html) - Semantic element system
- [Scene Overview](overview_scene.html) - Building Scenes
- [Driver Overview](overview_driver.html) - Understanding Drivers