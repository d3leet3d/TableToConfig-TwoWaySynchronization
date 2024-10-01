local TableToConfig = {}
TableToConfig.__index = TableToConfig

-- Constructor
function TableToConfig.new(name, value)
	local self = setmetatable({}, TableToConfig)
	self.Connections = {}
	self.InstanceToPathMap = {}
	self.PathToInstanceMap = {}
	self.MainTable = value
	self.isUpdating = true  -- Prevent synchronization during initialization

	-- Create the root instance
	self.RootInstance = self:CreateInstance(name, value, nil, nil)

	-- Create the proxy
	self.ProxiedTable = self:CreateProxy(value, self.RootInstance) :: typeof(value)

	self.isUpdating = false  -- Initialization complete
	return self
end

-- Create Roblox Instance based on value type
function TableToConfig:CreateInstance(name, value, parentTableRef, parentInstance)
	local varType = type(value)

	local varInstance = Instance.new("Configuration")
	varInstance.Name = name

	self.InstanceToPathMap[varInstance] = { Name = name, TableRef = value }
	self.PathToInstanceMap[varInstance] = {}

	-- Set attributes or create child Configurations
	for key, val in pairs(value) do
		if type(val) == "table" then
			-- Create child Configuration instance
			local child = self:CreateInstance(key, val, value, varInstance)
			child.Parent = varInstance
		else
			-- Set attribute
			varInstance:SetAttribute(key, val)

			-- Connect attribute changed event
			local attrChangedConn = varInstance:GetAttributeChangedSignal(key):Connect(function()
				self:UpdateTableAttribute(varInstance, key, varInstance:GetAttribute(key))
			end)

			-- Store connection
			self.Connections[varInstance.Name .. "." .. key] = attrChangedConn
		end
	end

	-- Connect child added and removed events
	local childAddedConn = varInstance.ChildAdded:Connect(function(child)
		self:OnChildAdded(value, varInstance, child)
	end)

	local childRemovedConn = varInstance.ChildRemoved:Connect(function(child)
		self:OnChildRemoved(value, varInstance, child)
	end)

	-- Store connections
	self.Connections[varInstance] = { childAddedConn, childRemovedConn }

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
function TableToConfig:CreateProxy(tbl, instance)
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
					-- Remove attribute or child instance
					if type(tbl[key]) == "table" then
						local childInstance = selfRef.PathToInstanceMap[instance][key]
						if childInstance then
							-- Disconnect events
							selfRef:DisconnectInstance(childInstance)
							-- Destroy the instance
							childInstance:Destroy()
							selfRef.PathToInstanceMap[instance][key] = nil
							selfRef.InstanceToPathMap[childInstance] = nil
						end
						proxies[key] = nil  -- Remove the nested proxy if exists
					else
						-- Remove attribute
						instance:SetAttribute(key, nil)
						-- Disconnect attribute changed event
						local connKey = instance.Name .. "." .. key
						if selfRef.Connections[connKey] then
							selfRef.Connections[connKey]:Disconnect()
							selfRef.Connections[connKey] = nil
						end
					end
				end
			else
				-- Handle key addition/update
				tbl[key] = value  -- Update the main table

				if type(value) == "table" then
					local childInstance = selfRef.PathToInstanceMap[instance][key]
					if childInstance then
						-- Sync the table to the instance
						selfRef:SyncTableToInstance(value, childInstance)
						if not proxies[key] then
							proxies[key] = selfRef:CreateProxy(value, childInstance)
						end
					else
						-- Create new child Configuration
						local newInstance = selfRef:CreateInstance(key, value, tbl, instance)
						newInstance.Parent = instance
						selfRef.PathToInstanceMap[instance][key] = newInstance
						proxies[key] = selfRef:CreateProxy(value, newInstance)
					end
				else
					-- Set attribute
					instance:SetAttribute(key, value)
					-- Connect attribute changed event
					local connKey = instance.Name .. "." .. key
					if selfRef.Connections[connKey] then
						selfRef.Connections[connKey]:Disconnect()
					end
					local attrChangedConn = instance:GetAttributeChangedSignal(key):Connect(function()
						selfRef:UpdateTableAttribute(instance, key, instance:GetAttribute(key))
					end)
					selfRef.Connections[connKey] = attrChangedConn
				end
			end

			selfRef.isUpdating = false
		end
	})

	return proxy
end

-- Handle addition of child instances
function TableToConfig:OnChildAdded(parentTableRef, parentInstance, child)
	if self.isUpdating then return end

	if child:IsA("Configuration") then
		local childName = child.Name
		self.isUpdating = true

		-- Ensure PathToInstanceMap for parentInstance is initialized
		if not self.PathToInstanceMap[parentInstance] then
			self.PathToInstanceMap[parentInstance] = {}
		end

		-- For Configurations, create a new table and recursively sync its contents
		parentTableRef[childName] = {}
		self.InstanceToPathMap[child] = { Name = childName, TableRef = parentTableRef[childName] }
		self.PathToInstanceMap[parentInstance][childName] = child

		-- Recursively process the Configuration's attributes and children
		self:SyncInstanceToTable(child, parentTableRef[childName])

		-- Connect events for the new Configuration
		local childAddedConn = child.ChildAdded:Connect(function(grandChild)
			self:OnChildAdded(parentTableRef[childName], child, grandChild)
		end)

		local childRemovedConn = child.ChildRemoved:Connect(function(grandChild)
			self:OnChildRemoved(parentTableRef[childName], child, grandChild)
		end)

		-- Store connections
		self.Connections[child] = { childAddedConn, childRemovedConn }

		self.isUpdating = false
	end
end

-- Handle removal of child instances
function TableToConfig:OnChildRemoved(parentTableRef, parentInstance, child)
	if self.isUpdating then return end

	if child:IsA("Configuration") then
		local childName = child.Name
		self.isUpdating = true

		parentTableRef[childName] = nil
		self.PathToInstanceMap[parentInstance][childName] = nil

		-- Disconnect and remove connections
		self:DisconnectInstance(child)
		self.InstanceToPathMap[child] = nil

		self.isUpdating = false
	end
end

-- Update the main table when an attribute changes
function TableToConfig:UpdateTableAttribute(instance, key, newValue)
	if self.isUpdating then return end

	local pathData = self.InstanceToPathMap[instance]
	if not pathData then
		warn("No path data for instance:", instance.Name)
		return
	end

	local tableRef = pathData.TableRef

	if tableRef then
		self.isUpdating = true
		tableRef[key] = newValue
		self.isUpdating = false
	else
		warn("No table reference for instance:", instance.Name)
	end
end

-- Recursively sync an instance (Configuration and its children) to the table
function TableToConfig:SyncInstanceToTable(instance, tbl)
	-- Ensure PathToInstanceMap for instance is initialized
	if not self.PathToInstanceMap[instance] then
		self.PathToInstanceMap[instance] = {}
	end

	-- Sync attributes
	for key, value in pairs(instance:GetAttributes()) do
		tbl[key] = value

		-- Connect attribute changed event
		local connKey = instance.Name .. "." .. key
		if self.Connections[connKey] then
			self.Connections[connKey]:Disconnect()
		end
		local attrChangedConn = instance:GetAttributeChangedSignal(key):Connect(function()
			self:UpdateTableAttribute(instance, key, instance:GetAttribute(key))
		end)
		self.Connections[connKey] = attrChangedConn
	end

	-- Sync child Configurations
	for _, child in ipairs(instance:GetChildren()) do
		if child:IsA("Configuration") then
			local childName = child.Name
			tbl[childName] = {}
			self.InstanceToPathMap[child] = { Name = childName, TableRef = tbl[childName] }
			self.PathToInstanceMap[instance][childName] = child

			-- Recursively sync the child Configuration
			self:SyncInstanceToTable(child, tbl[childName])

			-- Connect events for the child Configuration
			local childAddedConn = child.ChildAdded:Connect(function(grandChild)
				self:OnChildAdded(tbl[childName], child, grandChild)
			end)

			local childRemovedConn = child.ChildRemoved:Connect(function(grandChild)
				self:OnChildRemoved(tbl[childName], child, grandChild)
			end)

			-- Store connections
			self.Connections[child] = { childAddedConn, childRemovedConn }
		end
	end
end

-- Synchronize table to instance
function TableToConfig:SyncTableToInstance(tbl, instance)
	if self.isUpdating then return end

	self.isUpdating = true

	-- Ensure PathToInstanceMap for instance is initialized
	if not self.PathToInstanceMap[instance] then
		self.PathToInstanceMap[instance] = {}
	end

	-- Synchronize existing keys
	for key, val in pairs(tbl) do
		if type(val) == "table" then
			local childInstance = self.PathToInstanceMap[instance][key]
			if childInstance then
				self:SyncTableToInstance(val, childInstance)
			else
				-- Create new child Configuration
				local newInstance = self:CreateInstance(key, val, tbl, instance)
				newInstance.Parent = instance
				self.PathToInstanceMap[instance][key] = newInstance
			end
		else
			-- Set attribute
			instance:SetAttribute(key, val)
			-- Connect attribute changed event
			local connKey = instance.Name .. "." .. key
			if self.Connections[connKey] then
				self.Connections[connKey]:Disconnect()
			end
			local attrChangedConn = instance:GetAttributeChangedSignal(key):Connect(function()
				self:UpdateTableAttribute(instance, key, instance:GetAttribute(key))
			end)
			self.Connections[connKey] = attrChangedConn
		end
	end

	-- Remove attributes and child instances not present in the table
	local attributes = instance:GetAttributes()
	for key, _ in pairs(attributes) do
		if tbl[key] == nil then
			instance:SetAttribute(key, nil)
			local connKey = instance.Name .. "." .. key
			if self.Connections[connKey] then
				self.Connections[connKey]:Disconnect()
				self.Connections[connKey] = nil
			end
		end
	end

	local childrenToRemove = {}
	for key, childInstance in pairs(self.PathToInstanceMap[instance]) do
		if tbl[key] == nil then
			table.insert(childrenToRemove, key)
		end
	end

	for _, key in ipairs(childrenToRemove) do
		local childInstance = self.PathToInstanceMap[instance][key]
		self:DisconnectInstance(childInstance)
		childInstance:Destroy()
		self.PathToInstanceMap[instance][key] = nil
		self.InstanceToPathMap[childInstance] = nil
	end

	self.isUpdating = false
end

-- Disconnect all events related to an instance
function TableToConfig:DisconnectInstance(instance)
	if self.Connections[instance] then
		local conns = self.Connections[instance]
		if typeof(conns) == "table" then
			for _, conn in pairs(conns) do
				conn:Disconnect()
			end
		else
			conns:Disconnect()
		end
		self.Connections[instance] = nil
	end
	-- Disconnect attribute changed events
	for key, _ in pairs(instance:GetAttributes()) do
		local connKey = instance.Name .. "." .. key
		if self.Connections[connKey] then
			self.Connections[connKey]:Disconnect()
			self.Connections[connKey] = nil
		end
	end
	-- Disconnect child instances recursively
	for _, child in ipairs(instance:GetChildren()) do
		if child:IsA("Configuration") then
			self:DisconnectInstance(child)
		end
	end
end

-- Clean up connections and instances
function TableToConfig:Destroy()
	self:DisconnectInstance(self.RootInstance)
	if self.RootInstance then
		self.RootInstance:Destroy()
		self.RootInstance = nil
	end

	self.Connections = {}
	self.InstanceToPathMap = {}
	self.PathToInstanceMap = {}
	self.MainTable = nil
	setmetatable(self, nil)
end

return TableToConfig
