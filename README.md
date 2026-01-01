# Butler

## Installation

### Pesde

```bash
pesde add molyi/butler
```

### Wally

```toml
Butler = "molyidev/butler@^1.2.1"
```

## Why use Butler?

* **Fully Typed:** Designed to work with the new Luau type solver.
* **Performance:** Uses a **Doubly Linked List** for O(1) Removal and **LIFO** cleanup structure.

## Usage

### Basics

```lua
local Butler = require(path.to.Butler)

-- Create a butler.
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
butler:Once(humanoid.Died, function()
    print("skill issue")
end)

-- Parallel
butler:ConnectParallel(part.Touched, function(hit)
    print("Touched in parallel")
end)

-- Disconnects automatically when butler is cleaned
local cn = butler:Connect(part.Touched, print)
-- Or you can disconnect manually:
butler:Remove(cn)
-- Maybe without cleaning (Without disconnecting)
butler:RemoveNoClean(cn)
```

### RenderStep

```lua
-- Binds and automatically unbinds on cleanup
local bind = butler:BindToRenderStep("Lag", Enum.RenderPriority.Camera.Value, function(dt)
    -- do something unoptimized to lag the game
end)

-- You can unbind by removing it from the butler or using butler:Clean()
butler:Remove(bind)
```

### Instance Linking

```lua
local randomPart = workspace.Part
local cn = butler:AttachToInstance(randomPart)
-- If randomPart is destroyed, butler:Destroy() is called.

-- You can undo this link by removing the connection:
butler:Remove(cn)
```

### Nesting

```lua
local mainButler = Butler.new()
local otherButler = mainButler:Extend()

otherButler:Connect(workspace.ChildAdded, print)

-- Cleaning 'mainButler' will also destroy 'otherButler'
mainButler:Clean()
```

## API

### Butler Static

| Method | Description |
| --- | --- |
| `.new()` | Creates a new Butler instance. |
| `.CleanupMethods` | An enum of valid cleanup methods: `"Function"`, `"Thread"`, `"Disconnect"`, `"Destroy"`. |
| `.IsButler(obj)` | Returns `true` if `obj` is a Butler instance. |

### Butler

| Method | Description |
| --- | --- |
| `.CurrentlyCleaning` | `boolean` — `true` if the Butler is currently iterating through its cleanup tasks. |
| `:Add(object, cleanupMethod?)` | Adds `object` to the cleanup list. Returns the `object`. |
| `:Connect(signal, fn)` | Connects `fn` to `signal` and adds the connection to the Butler. Returns the `Connection`. |
| `:ConnectParallel(signal, fn)` | Connects `fn` to `signal` in parallel and adds the connection to the Butler. Returns the `Connection`. |
| `:Once(signal, fn)` | Connects `fn` to `signal` once. The connection is automatically removed from the Butler when fired. Returns the `Connection` |
| `:BindToRenderStep(name, priority, fn)` | Wraps `RunService:BindToRenderStep`. Returns the unbinding function. |
| `:Extend()` | Creates and returns a new "child" Butler. If the parent is cleaned/destroyed, the child is destroyed too. |
| `:AttachToInstance(instance)` | Listens for `instance.Destroying` and calls `:Destroy()` on the Butler automatically. Returns the `Connection`. |
| `:Remove(object)` | Removes `object` from the Butler and **immediately** cleans it (calls Destroy/Disconnect etc). Returns itself. |
| `:RemoveNoClean(object)` | Removes `object` from the Butler **without** cleaning it. Returns the `Butler` itself. |
| `:RemoveList(...objects)` | Calls `:Remove()` on all provided objects. Returns the `Butler` itself. |
| `:RemoveListNoClean(...objects)` | Calls `:RemoveNoClean()` on all provided objects. Returns the `Butler` itself. |
| `:Clean()` | Cleans all added objects in order. Returns the `Butler` itself. |
| `:Destroy()` | Calls `:Clean()` and renders the Butler unusable. |

## Inspiration

**Butler** takes inspiration from **[Trove](https://github.com/Sleitnick/RbxUtil/tree/main/modules/trove)** and **[Janitor](https://github.com/howmanysmall/Janitor)**.
If you do not want to use **Butler** and would prefer another option, I highly recommend either of them. However, if I had to choose between the two, I would recommend **Trove**.
