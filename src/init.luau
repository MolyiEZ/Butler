--!native
--!optimize 2

local RunService = game:GetService("RunService")

export type CleanupMethod = string

export type Connection = {
	Connected: boolean,

	Disconnect: (self: any) -> (),
	-- Only works with custom signal modules
	Reconnect: (self: any) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
}

type CleanNode = {
	Object: any,
	CleanupMethod: CleanupMethod,
	Next: CleanNode?,
	Previous: CleanNode?,
}

export type Butler = {
	CurrentlyCleaning: boolean,

	Add: <T>(self: Butler, object: T, cleanupMethod: CleanupMethod?) -> T,
	Connect: <T...>(self: Butler, signal: Signal<T...> | RBXScriptSignal<T...>, callback: (T...) -> ()) -> Connection,
	ConnectParallel: <T...>(self: Butler, signal: RBXScriptSignal<T...>, callback: (T...) -> ()) -> Connection,
	Once: <T...>(self: Butler, signal: Signal<T...> | RBXScriptSignal<T...>, callback: (T...) -> ()) -> Connection,
	BindToRenderStep: (self: Butler, name: string, priority: number, callback: (dt: number) -> ()) -> () -> (),
	Extend: (self: Butler) -> Butler,
	AttachToInstance: (self: Butler, instance: Instance) -> Connection,

	Remove: (self: Butler, object: any?) -> Butler,
	RemoveNoClean: (self: Butler, object: any?) -> Butler,
	RemoveList: (self: Butler, ...any) -> Butler,
	RemoveListNoClean: (self: Butler, ...any) -> Butler,

	Clean: (self: Butler) -> Butler,
	Destroy: (self: Butler) -> (),
}

export type PrivateButler = Butler & {
	Head: CleanNode?,
	Objects: { [any]: CleanNode },
}

local TABLE_CLEANUP_METHODS = table.freeze({ "Disconnect", "disconnect", "Destroy", "destroy" })
local ENUM_CLEANUP_METHODS = table.freeze({
	Function = "Function",
	Thread = "Thread",
	Disconnect = "Disconnect",
	disconnect = "disconnect",
	Destroy = "Destroy",
	destroy = "destroy",
})

export type ButlerStatic = {
	new: () -> Butler,
	CleanupMethods: typeof(ENUM_CLEANUP_METHODS),
	IsButler: (obj: any) -> boolean,
}

local task_cancel = task.cancel
local table_clear = table.clear

--==[ Butler ]==--
local Butler = {}
Butler.__index = Butler

local function checkCleaning(self: Butler | PrivateButler, method: string)
	if self.CurrentlyCleaning then error(`Cannot call method '{method}' while cleaning`, 2) end
end

local function getCleanupMethod(object: any): string
	local objType = typeof(object)

	if objType == "function" then
		return ENUM_CLEANUP_METHODS.Function
	elseif objType == "thread" then
		return ENUM_CLEANUP_METHODS.Thread
	elseif objType == "RBXScriptConnection" then
		return ENUM_CLEANUP_METHODS.Disconnect
	elseif objType == "Instance" then
		return ENUM_CLEANUP_METHODS.Destroy
	elseif objType == "table" then
		for _, cleanupMethod in TABLE_CLEANUP_METHODS do
			if typeof(object[cleanupMethod]) == "function" then return cleanupMethod end
		end
	end

	error(`[Butler] Couldn't get the cleanup method for the object: {object}. With type: {objType}`, 3)
end

local function cleanupErrorHandler(err: string)
	warn("[Butler] Error during cleanup:", err)
end

local function cleanObject<T>(object: T, cleanupMethod: CleanupMethod)
	if cleanupMethod == ENUM_CLEANUP_METHODS.Function then
		xpcall(object, cleanupErrorHandler)
	elseif cleanupMethod == ENUM_CLEANUP_METHODS.Thread then
		local success, err = pcall(task_cancel, object)
		if not success then cleanupErrorHandler(err) end
	else
		local success, err = pcall((object :: any)[cleanupMethod], object)
		if not success then cleanupErrorHandler(err) end
	end
end

local function unlinkNode(self: PrivateButler, node: CleanNode)
	local nextNode = node.Next
	local prevNode = node.Previous

	if nextNode then nextNode.Previous = prevNode end
	if prevNode then
		prevNode.Next = nextNode
	elseif self.Head == node then
		self.Head = node.Next
	end

	node.Next = nil
	node.Previous = nil
end

local function createButler(): Butler
	return (setmetatable({
		CurrentlyCleaning = false,
		Head = nil,
		Objects = {},
	}, Butler) :: any) :: Butler
end

function Butler.Add<T>(self: PrivateButler, object: T, cleanupMethod: CleanupMethod?): T
	checkCleaning(self, "Add")
	if not cleanupMethod then cleanupMethod = getCleanupMethod(object) end

	local node: CleanNode = {
		Object = object,
		CleanupMethod = cleanupMethod :: string,
		Next = self.Head,
		Previous = nil,
	}

	if self.Head then self.Head.Previous = node end
	self.Head = node
	self.Objects[object] = node

	return object
end

function Butler.Connect<T...>(
	self: PrivateButler,
	signal: Signal<T...> | RBXScriptSignal<T...>,
	callback: (T...) -> ()
): Connection
	checkCleaning(self, "Connect")

	local connection = (signal :: any):Connect(callback)
	self:Add(connection, ENUM_CLEANUP_METHODS.Disconnect)

	return connection
end

function Butler.ConnectParallel<T...>(
	self: PrivateButler,
	signal: Signal<T...> | RBXScriptSignal<T...>,
	callback: (T...) -> ()
): Connection
	checkCleaning(self, "ConnectParallel")

	local connection = (signal :: any):ConnectParallel(callback)
	self:Add(connection, ENUM_CLEANUP_METHODS.Disconnect)

	return connection
end

function Butler.Once<T...>(self: PrivateButler, signal: Signal<T...>, callback: (T...) -> ()): Connection
	checkCleaning(self, "Once")
	local connection: Connection

	connection = (signal :: any):Once(function(...: T...)
		if connection then self:Remove(connection) end
		callback(...)
	end)

	self:Add(connection, ENUM_CLEANUP_METHODS.Disconnect)
	return connection
end

function Butler.BindToRenderStep(
	self: PrivateButler,
	name: string,
	priority: number,
	callback: (dt: number) -> ()
): () -> ()
	checkCleaning(self, "BindToRenderStep")

	RunService:BindToRenderStep(name, priority, callback)

	local function fn()
		RunService:UnbindFromRenderStep(name)
	end

	self:Add(fn, ENUM_CLEANUP_METHODS.Function)

	return fn
end

function Butler.Extend(self: PrivateButler): Butler
	checkCleaning(self, "Extend")
	local child = createButler()
	self:Add(child, ENUM_CLEANUP_METHODS.Destroy)
	return child
end

function Butler.AttachToInstance(self: Butler, instance: Instance): Connection
	checkCleaning(self, "AttachToInstance")
	return self:Connect(instance.Destroying, function()
		self:Destroy()
	end)
end

function Butler.Remove(self: PrivateButler, object: any?): Butler
	if self.CurrentlyCleaning or object == nil then return self end

	local node = self.Objects[object]
	if not node then return self end

	unlinkNode(self, node)
	self.Objects[object] = nil
	cleanObject(object, node.CleanupMethod)

	return self
end

function Butler.RemoveNoClean(self: PrivateButler, object: any?): Butler
	if self.CurrentlyCleaning or object == nil then return self end
	local node = self.Objects[object]
	if not node then return self end

	unlinkNode(self, node)
	self.Objects[object] = nil

	return self
end

function Butler.RemoveList(self: Butler, ...: any): Butler
	if self.CurrentlyCleaning then return self end

	for i = 1, select("#", ...) do
		self:Remove(select(i, ...))
	end

	return self
end

function Butler.RemoveListNoClean(self: Butler, ...: any): Butler
	if self.CurrentlyCleaning then return self end

	for i = 1, select("#", ...) do
		self:RemoveNoClean(select(i, ...))
	end

	return self
end

function Butler.Clean(self: PrivateButler): Butler
	checkCleaning(self, "Clean")
	self.CurrentlyCleaning = true

	local current = self.Head
	while current do
		cleanObject(current.Object, current.CleanupMethod)
		local nextNode = current.Next
		current.Next = nil
		current.Previous = nil
		current = nextNode
	end

	self.Head = nil
	table_clear(self.Objects)
	self.CurrentlyCleaning = false

	return self
end

function Butler.Destroy(self: Butler)
	self:Clean()
	setmetatable(self, nil)
end

--==[ ButlerStatic ]==--
local ButlerStatic = {}

ButlerStatic.new = createButler
ButlerStatic.CleanupMethods = ENUM_CLEANUP_METHODS

function ButlerStatic.IsButler(obj: any): boolean
	return type(obj) == "table" and getmetatable(obj) == Butler
end

return ButlerStatic :: ButlerStatic
