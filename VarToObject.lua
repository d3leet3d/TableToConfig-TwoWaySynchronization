-- VarToObject.lua
local VarToObject = {}
VarToObject.__index = VarToObject

-- Mapping Lua types to Roblox Instance classes
VarToObject.VarTypes = {
	["number"] = "NumberValue",
	["string"] = "StringValue",
	["boolean"] = "BoolValue",
	["table"] = "Folder"
}

-- Constructor
function VarToObject.new(name, value)
	local self = setmetatable({}, VarToObject)
	self.Connections = {}
	self.InstanceToPathMap = {}
	self.PathToInstanceMap = {}
	self.MainTable = value
	self.isUpdating = true  -- Prevent synchronization during initialization

	-- Create the root instance
	self.RootInstance = self:CreateInstance(name, value, nil, nil)

	-- Create the proxy
	self.ProxiedTable = self:CreateProxy(value, self.RootInstance)

	self.isUpdating = false  -- Initialization complete
	return self
end

-- Create Roblox Instance based on value type
function VarToObject:CreateInstance(name, value, parentTableRef, parentInstance)
	local varType = type(value)
	local className = self.VarTypes[varType]

	if not className then
		warn("Unsupported type: " .. varType .. " for key: " .. tostring(name))
		return nil
	end

	-- Create the instance
	local varInstance = Instance.new(className)
	varInstance.Name = name

	if varType == "table" then
		-- For tables, create a Folder
		self.InstanceToPathMap[varInstance] = { Name = name, TableRef = value }
		self.PathToInstanceMap[varInstance] = {}

		-- Recursively create child instances
		for key, val in pairs(value) do
			local child = self:CreateInstance(key, val, value, varInstance)
			if child then
				child.Parent = varInstance
			end
		end

		-- Connect events
		local childAddedConn = varInstance.ChildAdded:Connect(function(child)
			self:OnChildAdded(value, varInstance, child)
		end)

		local childRemovedConn = varInstance.ChildRemoved:Connect(function(child)
			self:OnChildRemoved(value, varInstance, child)
		end)

		-- Store connections
		self.Connections[self.InstanceToPathMap[varInstance]] = { childAddedConn, childRemovedConn }
	else
		-- For ValueBase instances
		varInstance.Value = value
		self.InstanceToPathMap[varInstance] = { Name = name, TableRef = parentTableRef }

		-- Connect Changed event
		local changedConn = varInstance:GetPropertyChangedSignal("Value"):Connect(function()
			self:UpdateTable(varInstance, varInstance.Value)
		end)

		self.Connections[self.InstanceToPathMap[varInstance]] = changedConn
	end

	-- Add to parent's PathToInstanceMap
	if parentInstance then
		if not self.PathToInstanceMap[parentInstance] then
			self.PathToInstanceMap[parentInstance] = {}
		end
		self.PathToInstanceMap[parentInstance][name] = varInstance
	end

	return varInstance
end

-- Create Proxy with two-way synchronization
function VarToObject:CreateProxy(tbl, instance)
	local selfRef = self
	local proxy = {}
	local proxies = {}

	setmetatable(proxy, {
		__index = function(t, key)
			local value = tbl[key]
			if value == nil then
				-- Automatically create a new table and proxy for missing keys
				value = {}
				tbl[key] = value

				-- Create the Roblox instance
				selfRef.isUpdating = true
				local newInstance = selfRef:CreateInstance(key, value, tbl, instance)
				newInstance.Parent = instance
				selfRef.PathToInstanceMap[instance][key] = newInstance
				selfRef.isUpdating = false

				-- Create the proxy
				proxies[key] = selfRef:CreateProxy(value, newInstance)
				return proxies[key]
			elseif type(value) == "table" then
				if not proxies[key] then
					-- Create a new proxy for the nested table
					local childInstance = selfRef.PathToInstanceMap[instance][key]
					proxies[key] = selfRef:CreateProxy(value, childInstance)
				end
				return proxies[key]
			else
				return value
			end
		end,
		__newindex = function(t, key, value)
			if selfRef.isUpdating then
				rawset(tbl, key, value)
				return
			end

			selfRef.isUpdating = true

			if value == nil then
				-- Handle key removal
				if tbl[key] ~= nil then
					tbl[key] = nil  -- Remove from main table
					local childInstance = selfRef.PathToInstanceMap[instance][key]
					if childInstance then
						-- Disconnect events
						local pathData = selfRef.InstanceToPathMap[childInstance]
						if pathData and selfRef.Connections[pathData] then
							local con = selfRef.Connections[pathData]
							if typeof(con) == "table" then
								for _, singleCon in pairs(con) do
									singleCon:Disconnect()
								end
							else
								con:Disconnect()
							end
							selfRef.Connections[pathData] = nil
						end

						-- Destroy the instance
						childInstance:Destroy()
						selfRef.PathToInstanceMap[instance][key] = nil
						selfRef.InstanceToPathMap[childInstance] = nil
					end
					proxies[key] = nil  -- Remove the nested proxy if exists
				end
			else
				-- Handle key addition/update
				tbl[key] = value  -- Update the main table

				local childInstance = selfRef.PathToInstanceMap[instance][key]
				if childInstance then
					if type(value) == "table" then
						if not childInstance:IsA("Folder") then
							-- Replace non-folder with folder
							childInstance:Destroy()
							local newFolder = selfRef:CreateInstance(key, value, tbl, instance)
							newFolder.Parent = instance
							selfRef.PathToInstanceMap[instance][key] = newFolder
							childInstance = newFolder
						end
						-- Sync the table to the instance
						selfRef:SyncTableToInstance(value, childInstance)
						if not proxies[key] then
							proxies[key] = selfRef:CreateProxy(value, childInstance)
						end
					else
						if childInstance:IsA("ValueBase") then
							local expectedType = selfRef.VarTypes[type(value)]
							if childInstance.ClassName == expectedType then
								childInstance.Value = value
							else
								-- Replace with correct type
								childInstance:Destroy()
								local newValueInstance = selfRef:CreateInstance(key, value, tbl, instance)
								newValueInstance.Parent = instance
								selfRef.PathToInstanceMap[instance][key] = newValueInstance
							end
						else
							-- Replace non-ValueBase with ValueBase
							childInstance:Destroy()
							local newValueInstance = selfRef:CreateInstance(key, value, tbl, instance)
							newValueInstance.Parent = instance
							selfRef.PathToInstanceMap[instance][key] = newValueInstance
						end
					end
				else
					-- Create new instance
					local newInstance = selfRef:CreateInstance(key, value, tbl, instance)
					newInstance.Parent = instance
					selfRef.PathToInstanceMap[instance][key] = newInstance

					if type(value) == "table" then
						proxies[key] = selfRef:CreateProxy(value, newInstance)
					end
				end
			end

			selfRef.isUpdating = false
		end
	})

	return proxy
end

-- Handle addition of child instances
function VarToObject:OnChildAdded(parentTableRef, parentInstance, child)
	if self.isUpdating then return end

	local childName = child.Name

	self.isUpdating = true

	-- Ensure PathToInstanceMap for parentInstance is initialized
	if not self.PathToInstanceMap[parentInstance] then
		self.PathToInstanceMap[parentInstance] = {}
	end

	if child:IsA("Folder") then
		-- For folders, create a new table and recursively sync its contents
		parentTableRef[childName] = {}
		self.InstanceToPathMap[child] = { Name = childName, TableRef = parentTableRef[childName] }
		self.PathToInstanceMap[parentInstance][childName] = child

		-- Recursively process the folder's children
		self:SyncInstanceToTable(child, parentTableRef[childName])

		-- Connect events for the new folder
		local childAddedConn = child.ChildAdded:Connect(function(grandChild)
			self:OnChildAdded(parentTableRef[childName], child, grandChild)
		end)

		local childRemovedConn = child.ChildRemoved:Connect(function(grandChild)
			self:OnChildRemoved(parentTableRef[childName], child, grandChild)
		end)

		-- Store connections
		self.Connections[self.InstanceToPathMap[child]] = { childAddedConn, childRemovedConn }

	elseif child:IsA("ValueBase") then
		-- For ValueBase instances, set the value directly
		parentTableRef[childName] = child.Value
		self.InstanceToPathMap[child] = { Name = childName, TableRef = parentTableRef }
		self.PathToInstanceMap[parentInstance][childName] = child

		-- Connect the Changed event
		local changedConn = child:GetPropertyChangedSignal("Value"):Connect(function()
			self:UpdateTable(child, child.Value)
		end)
		self.Connections[self.InstanceToPathMap[child]] = changedConn
	end

	self.isUpdating = false
end

-- Handle removal of child instances
function VarToObject:OnChildRemoved(parentTableRef, parentInstance, child)
	if self.isUpdating then return end

	local childName = child.Name

	self.isUpdating = true

	parentTableRef[childName] = nil
	self.PathToInstanceMap[parentInstance][childName] = nil

	-- Disconnect and remove connections
	local pathData = self.InstanceToPathMap[child]
	if pathData and self.Connections[pathData] then
		local con = self.Connections[pathData]
		if typeof(con) == "table" then
			for _, singleCon in pairs(con) do
				singleCon:Disconnect()
			end
		else
			con:Disconnect()
		end
		self.Connections[pathData] = nil
	end

	self.InstanceToPathMap[child] = nil

	self.isUpdating = false
end

-- Update the main table when Roblox Instance changes
function VarToObject:UpdateTable(instance, newValue)
	if self.isUpdating then return end

	local pathData = self.InstanceToPathMap[instance]
	if not pathData then
		warn("No path data for instance:", instance.Name)
		return
	end

	local tableRef = pathData.TableRef

	if tableRef then
		self.isUpdating = true
		tableRef[pathData.Name] = newValue
		self.isUpdating = false
	else
		warn("No table reference for instance:", instance.Name)
	end
end

-- Recursively sync an instance (Folder and its children) to the table
function VarToObject:SyncInstanceToTable(instance, tbl)
	-- Ensure PathToInstanceMap for instance is initialized
	if not self.PathToInstanceMap[instance] then
		self.PathToInstanceMap[instance] = {}
	end

	for _, child in ipairs(instance:GetChildren()) do
		local childName = child.Name
		if child:IsA("Folder") then
			tbl[childName] = {}
			self.InstanceToPathMap[child] = { Name = childName, TableRef = tbl[childName] }
			self.PathToInstanceMap[instance][childName] = child

			-- Recursively sync the child folder
			self:SyncInstanceToTable(child, tbl[childName])

			-- Connect events for the child folder
			local childAddedConn = child.ChildAdded:Connect(function(grandChild)
				self:OnChildAdded(tbl[childName], child, grandChild)
			end)

			local childRemovedConn = child.ChildRemoved:Connect(function(grandChild)
				self:OnChildRemoved(tbl[childName], child, grandChild)
			end)

			-- Store connections
			self.Connections[self.InstanceToPathMap[child]] = { childAddedConn, childRemovedConn }

		elseif child:IsA("ValueBase") then
			tbl[childName] = child.Value
			self.InstanceToPathMap[child] = { Name = childName, TableRef = tbl }
			self.PathToInstanceMap[instance][childName] = child

			-- Connect the Changed event
			local changedConn = child:GetPropertyChangedSignal("Value"):Connect(function()
				self:UpdateTable(child, child.Value)
			end)
			self.Connections[self.InstanceToPathMap[child]] = changedConn
		else
			warn("Unsupported child type:", child.ClassName, "Name:", childName)
		end
	end
end

-- Synchronize table to instance
function VarToObject:SyncTableToInstance(tbl, instance)
	if self.isUpdating then return end

	self.isUpdating = true

	-- Ensure PathToInstanceMap for instance is initialized
	if not self.PathToInstanceMap[instance] then
		self.PathToInstanceMap[instance] = {}
	end

	-- Synchronize existing keys
	for key, val in pairs(tbl) do
		local childInstance = self.PathToInstanceMap[instance][key]
		if childInstance then
			-- Update existing instances
			if type(val) == "table" then
				if childInstance:IsA("Folder") then
					self:SyncTableToInstance(val, childInstance)
				else
					-- Replace non-folder with folder
					childInstance:Destroy()
					local newFolder = self:CreateInstance(key, val, tbl, instance)
					newFolder.Parent = instance
					self.PathToInstanceMap[instance][key] = newFolder
				end
			else
				if childInstance:IsA("ValueBase") then
					local expectedType = self.VarTypes[type(val)]
					if childInstance.ClassName == expectedType then
						childInstance.Value = val
					else
						-- Replace with correct type
						childInstance:Destroy()
						local newValueInstance = self:CreateInstance(key, val, tbl, instance)
						newValueInstance.Parent = instance
						self.PathToInstanceMap[instance][key] = newValueInstance
					end
				else
					-- Replace non-ValueBase with ValueBase
					childInstance:Destroy()
					local newValueInstance = self:CreateInstance(key, val, tbl, instance)
					newValueInstance.Parent = instance
					self.PathToInstanceMap[instance][key] = newValueInstance
				end
			end
		else
			-- Create new instance
			local newInstance = self:CreateInstance(key, val, tbl, instance)
			newInstance.Parent = instance
			self.PathToInstanceMap[instance][key] = newInstance
		end
	end

	-- Remove instances not present in the table
	local keysToRemove = {}
	for key, childInstance in pairs(self.PathToInstanceMap[instance]) do
		if tbl[key] == nil then
			table.insert(keysToRemove, key)
		end
	end

	for _, key in ipairs(keysToRemove) do
		local childInstance = self.PathToInstanceMap[instance][key]
		childInstance:Destroy()
		self.PathToInstanceMap[instance][key] = nil
		self.InstanceToPathMap[childInstance] = nil
	end

	self.isUpdating = false
end

-- Clean up connections and instances
function VarToObject:Destroy()
	for _, con in pairs(self.Connections) do
		if typeof(con) == "table" then
			for _, singleCon in pairs(con) do
				singleCon:Disconnect()
			end
		else
			con:Disconnect()
		end
	end
	self.Connections = {}

	if self.RootInstance then
		self.RootInstance:Destroy()
		self.RootInstance = nil
	end

	self.InstanceToPathMap = {}
	self.PathToInstanceMap = {}
	self.MainTable = nil
	setmetatable(self, nil)
end

return VarToObject
