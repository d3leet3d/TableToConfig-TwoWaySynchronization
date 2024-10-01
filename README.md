**VarToObject** is a Lua module designed for Roblox developers that seamlessly maps Lua tables to Roblox Instances. It enables two-way synchronization between your Lua tables and the Roblox Instance hierarchy, allowing dynamic and real-time data manipulation within your games.

## Features
- **Two-Way Synchronization:** Automatically syncs changes between Lua tables and Roblox Instances.
- **Dynamic Updates:** Handles additions, updates, and removals of table keys in real-time.
- **Type Mapping:** Supports `number`, `string`, `boolean`, and `table` types, mapping them to appropriate Roblox Instance classes.
- **Proxy Tables:** Utilizes Lua's metatables to create proxy tables for seamless interaction.
- **Event Handling:** Listens to Roblox Instance events to maintain synchronization.

## Installation

1. **Download the Module:**
   - Clone the repository or download the `VarToObject.lua` file directly.

2. **Add to Your Project:**
   - Place `VarToObject.lua` in a suitable location within your Roblox project, such as `ReplicatedStorage` or `ServerScriptService`.

## Usage

### Setup

1. **Require the Module:**
 ```lua
   local VarToObject = require(script.VarToObject)
```

2.**Create a Main Table:**
Define the Lua table you want to synchronize with Roblox Instances.
```lua
local mainTable = {
    Health = 100,
    Name = "Player1",
    Settings = {
        Volume = 75,
        Difficulty = "Hard"
    }
}
```

3.**Initialize VarToObject:**
Create a new VarToObject instance, specifying a name for the root instance and passing the main table.

```lua
local varObj = VarToObject.new("PlayerData", mainTable)
```
4.**Parent the Root Instance:**
Set the parent of the root instance to a suitable location in the Roblox hierarchy, such as ServerStorage.

```lua
varObj.RootInstance.Parent = game.ServerStorage
```
5.**Interact with the Proxy Table:**
Use the proxied table to make changes that will automatically synchronize with the Roblox Instances.
```lua
local proxy = varObj.ProxiedTable
proxy.Health = 150
proxy.Settings.Volume = 85
proxy.Score = 2500
```
##Example
Below is a comprehensive example demonstrating how to use VarToObject in a Roblox script.
```lua
-- ExampleUsage.lua

local VarToObject = require(script.VarToObject)

-- Define the main table
local mainTable = {
    Health = 100,
    Name = "Player1",
    Settings = {
        Volume = 75,
        Difficulty = "Hard"
    }
}

-- Initialize VarToObject
local varObj = VarToObject.new("PlayerData", mainTable)

-- Parent the root instance to ServerStorage
varObj.RootInstance.Parent = game.ServerStorage

-- Access the proxied table
local proxy = varObj.ProxiedTable

-- Modify table values
proxy.Health = 150
proxy.Settings.Volume = 85
proxy.Score = 2500

-- Schedule changes using delays
task.delay(8, function()
    proxy.Settings = nil -- Removes the Settings key
end)

task.delay(5, function()
    proxy.Stats = { Gold = 2000 }
    for i = 1, 6 do
        proxy.Stats.Gold = math.random(1, 8000)
        task.wait(4)
    end
end)

-- Continuously print the main table
while true do
    print(mainTable)
    task.wait(4)
end
```
