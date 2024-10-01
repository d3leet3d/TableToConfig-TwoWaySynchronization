## TableToConfig Module

The `TableToConfig` module allows you to map a Lua table into Roblox's `Configuration` instances. This is useful for creating a dynamic and synchronized configuration structure in your game.

### Features
- Automatically syncs Lua table structures with `Configuration` instances.
- Handles attribute changes and child configurations in Roblox.
- Provides a proxy table to easily update values in both Lua and Roblox instances.

### Usage

1. **Include the `TableToConfig` module** in your game by requiring it:

   ```lua
   local TableToConfig = require(script.TableToConfig)
   ```

2. **Create a table that you want to sync with Roblox**. For example, a player's stats:

   ```lua
   local PlayerData = {
       Gold = 200,
       MainStats = {
           Defense = 200,
           Attack = 40,
           SubStats = {
               Armor = 20
           }
       }
   }
   ```

3. **Initialize the `TableToConfig` with the table**. The first argument is the name for the root `Configuration` instance, and the second is the table you want to synchronize:

   ```lua
   local Cache = TableToConfig.new("PlayerData", PlayerData)
   Cache.RootInstance.Parent = game.ServerStorage  -- Parent the root instance to Roblox storage/somewhere.
   local ProxyTable = Cache.ProxiedTable  -- Get the proxy for future updates
   ```

4. **Update values dynamically** using the proxy table. Changes made to this proxy table will automatically reflect in the Roblox `Configuration` instances:

   ```lua
   task.delay(8, function()
       ProxyTable.Gold = math.random(1, 200)  -- Update Gold value after 8 seconds
   end)
   ```

5. **Print or log table values**:

   ```lua
   print(PlayerData.Gold)  -- Prints the initial value of Gold
   ```

### Example

Here is a full example that sets up a player data configuration, updates a value randomly, and prints the table:

```lua
local TableToConfig = require(script.TableToConfig)

-- Define player data
local PlayerData = {
    Gold = 200,
    MainStats = {
        Defense = 200,
        Attack = 40,
        SubStats = {
            Armor = 20
        }
    }
}

-- Create a new TableToConfig
local Cache = TableToConfig.new("PlayerData", PlayerData)
Cache.RootInstance.Parent = game.ServerStorage
local ProxyTable = Cache.ProxiedTable

-- Print the initial value of Gold
print(PlayerData.Gold)

-- Update Gold randomly after 8 seconds
task.delay(8, function()
    ProxyTable.Gold = math.random(1, 200)
end)

-- Continuously print the PlayerData every 4 seconds, This just shows that the table was updated.
while true do
    print(PlayerData)
    task.wait(4)
end
```

### Notes
- Ensure the `TableToConfig.lua` file is located in a directory accessible by your script.
- The proxy table (`ProxiedTable`) allows you to update Lua table values and sync them with the configuration instance.
- Use the `Destroy()` method to clean up all instances and connections when they are no longer needed.
