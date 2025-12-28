# Butler

## Installation

```bash
pesde add molyi/butler
```

## Why to use Butler?

* **Fully Typed:** Designed to work with the new Luau type solver.
* **Performance:** Uses a **Doubly Linked List** for O(1) Removal and **LIFO** cleanup structure.

## Usage

### Basics

```lua
local Butler = require(path.to.Butler)
local butler = Butler.new()

-- Clean up an instance
local part = Instance.new("Part")
butler:Add(part, "Destroy")

-- Clean up a connection
butler:Connect(workspace.ChildAdded, function(child)
    print(child.Name)
end)

-- Run a function on cleanup
butler:Add(function()
    print("Cleanup started")
end, true)

-- Cleans everything
butler:Clean()
```

### Signals

```lua
-- Standard
butler:Connect(RunService.Heartbeat, function(dt)
    print("Frame")
end)

-- Once
butler:Once(humanoid.Died, function(dt)
    print("skill issue")
end)

-- Parallel
butler:ConnectParallel(part.Touched, function(hit)
    print("Touched in parallel")
end)

-- Disconnects automatically when butler is cleaned
local conn = butler:Connect(part.Touched, print)
-- Or you can disconnect manually:
butler:Remove(conn)
-- Maybe without cleaning (Without disconnecting)
butler:RemoveWithoutCleaning(conn)

```

### RenderStep

```lua
-- Binds and automatically unbinds on cleanup
butler:BindToRenderStep("Lag", Enum.RenderPriority.Camera.Value, function(dt)
    -- do something unoptimized to lag the game
end)
```

### Instance Linking

```lua
local randomPart = workspace.Part
butler:AttachToInstance(randomPart)
-- If randomPart is destroyed, butler:Destroy() is called.

```

### Nesting

```lua
local mainButler = Butler.new()
local otherButler = mainButler:Extend()

otherButler:Connect(workspace.ChildAdded, print)

-- Cleaning 'mainButler' will also destroy 'otherButler'
mainButler:Clean()
```
