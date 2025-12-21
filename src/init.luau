local RunService = game:GetService("RunService")

export type TCleanupKey = boolean | string

export type TDisconnectable = {
	Disconnect: (self: any) -> (),
}

export type TSignalLike<T...> = {
	Connect: (self: any, callback: (T...) -> ()) -> RBXScriptConnection,
	ConnectParallel: (self: any, callback: (T...) -> ()) -> RBXScriptConnection,
	Once: (self: any, callback: (T...) -> ()) -> RBXScriptConnection,
	Wait: (self: any) -> T...,
}

export type Butler = {
	CurrentlyCleaning: boolean,

	Add: <T>(self: Butler, object: T, cleanupMethod: TCleanupKey) -> T,
	Connect: <T...>(
		self: Butler,
		signal: TSignalLike<T...> | RBXScriptSignal<T...>,
		callback: (T...) -> ()
	) -> RBXScriptConnection | TDisconnectable,
	ConnectParallel: <T...>(
		self: Butler,
		signal: RBXScriptSignal<T...>,
		callback: (T...) -> ()
	) -> RBXScriptConnection | TDisconnectable,
	Once: <T...>(
		self: Butler,
		signal: TSignalLike<T...>,
		callback: (T...) -> ()
	) -> RBXScriptConnection | TDisconnectable,
	BindToRenderStep: (self: Butler, name: string, priority: number, callback: (dt: number) -> ()) -> Butler,
	Extend: (self: Butler) -> Butler,
	AttachToInstance: (self: Butler, instance: Instance) -> RBXScriptConnection | TDisconnectable,

	Remove: (self: Butler, object: any?) -> Butler,
	RemoveWithoutCleaning: (self: Butler, object: any?) -> Butler,
	RemoveList: (self: Butler, ...any) -> Butler,
	RemoveListWithoutCleaning: (self: Butler, ...any) -> Butler,

	Clean: (self: Butler) -> (),
	Destroy: (self: Butler) -> (),
}

export type ButlerStatic = {
	new: () -> Butler,
	IsButler: (obj: any) -> boolean,
}

type ButlerPrivate = {
	Objects: { [any]: TCleanupKey },

	CheckCleaning: (self: ButlerPrivate, method: string) -> (),
	CleanObject: <T>(self: ButlerPrivate, object: T, cleanup: TCleanupKey) -> (),
}

local ButlerStatic = {}
local Butler = {}
Butler.__index = Butler

function ButlerStatic.new(): Butler
	local self = setmetatable({
		CurrentlyCleaning = false,
		Objects = {},
	}, Butler)

	return (self :: any) :: Butler
end

function ButlerStatic.IsButler(obj: any): boolean
	return type(obj) == "table" and getmetatable(obj) == Butler
end

function Butler.CheckCleaning(self: Butler & ButlerPrivate, method: string)
	if self.CurrentlyCleaning then error(("Cannot call method '%s' while cleaning"):format(method), 2) end
end

function Butler.Add<T>(self: Butler & ButlerPrivate, object: T, cleanupMethod: TCleanupKey): T
	self:CheckCleaning("Add")
	self.Objects[object] = cleanupMethod

	return object
end

function Butler.Connect<T...>(
	self: Butler & ButlerPrivate,
	signal: TSignalLike<T...> | RBXScriptSignal<T...>,
	callback: (T...) -> ()
): RBXScriptConnection | TDisconnectable
	self:CheckCleaning("Connect")

	local conn = (signal :: any):Connect(callback)
	self:Add(conn, "Disconnect")

	return conn
end

function Butler.ConnectParallel<T...>(
	self: Butler & ButlerPrivate,
	signal: RBXScriptSignal<T...>,
	callback: (T...) -> ()
): RBXScriptConnection | TDisconnectable
	self:CheckCleaning("ConnectParallel")

	local connection = signal:ConnectParallel(callback)
	self:Add(connection, "Disconnect")

	return connection
end

function Butler.Once<T...>(
	self: Butler & ButlerPrivate,
	signal: TSignalLike<T...>,
	callback: (T...) -> ()
): RBXScriptConnection | TDisconnectable
	self:CheckCleaning("Once")

	local connection: RBXScriptConnection | TDisconnectable

	local function extended(...: T...)
		self:Remove(connection)
		callback(...)
	end

	connection = signal:Once(extended :: (T...) -> ())
	self:Add(connection, "Disconnect")

	return connection
end

function Butler.BindToRenderStep(
	self: Butler & ButlerPrivate,
	name: string,
	priority: number,
	callback: (dt: number) -> ()
): Butler
	self:CheckCleaning("BindToRenderStep")

	RunService:BindToRenderStep(name, priority, callback)

	self:Add(function()
		RunService:UnbindFromRenderStep(name)
	end, true)

	return self
end

function Butler.Extend(self: Butler & ButlerPrivate): Butler
	self:CheckCleaning("Extend")
	local child = ButlerStatic.new()
	self:Add(child, "Destroy")
	return child
end

function Butler.AttachToInstance(
	self: Butler & ButlerPrivate,
	instance: Instance
): RBXScriptConnection | TDisconnectable
	self:CheckCleaning("AttachToInstance")
	return self:Connect(instance.Destroying, function()
		self:Destroy()
	end)
end

function Butler.Remove(self: Butler & ButlerPrivate, object: any?): Butler
	if self.CurrentlyCleaning then return self end

	if object == nil then return self end

	local key = self.Objects[object]
	if key ~= nil then
		self.Objects[object] = nil
		self:CleanObject(object, key)
	end

	return self
end

function Butler.RemoveWithoutCleaning(self: Butler & ButlerPrivate, object: any?): Butler
	self:CheckCleaning("RemoveWithoutCleaning")
	if object ~= nil then self.Objects[object] = nil end
	return self
end

function Butler.RemoveList(self: Butler & ButlerPrivate, ...: any): Butler
	self:CheckCleaning("RemoveList")
	for _, obj in { ... } do
		self:Remove(obj)
	end
	return self
end

function Butler.RemoveListWithoutCleaning(self: Butler & ButlerPrivate, ...: any): Butler
	self:CheckCleaning("RemoveListWithoutcleaning")
	for _, obj in { ... } do
		self:RemoveWithoutCleaning(obj)
	end
	return self
end

function Butler.Clean(self: Butler & ButlerPrivate)
	self:CheckCleaning("Clean")
	self.CurrentlyCleaning = true

	for object, cleanupKey in self.Objects do
		self.Objects[object] = nil
		self:CleanObject(object, cleanupKey)
	end

	self.CurrentlyCleaning = false
end

function Butler.Destroy(self: Butler & ButlerPrivate)
	self:Clean()
	table.clear(self)
	setmetatable(self, nil)
end

function Butler.CleanObject<T>(self: Butler & ButlerPrivate, object: T, cleanupMethod: TCleanupKey)
	if type(cleanupMethod) == "boolean" then
		if type(object) == "function" then
			(object :: any)()
		elseif type(object) == "thread" then
			local toCleanup = object :: thread
			if coroutine.status(toCleanup) ~= "dead" and toCleanup ~= coroutine.running() then
				task.cancel(toCleanup)
			end
		else
			warn("[Butler] Object it's not a function nor a thread:", object)
		end
	else
		local methodName = cleanupMethod :: string
		local fn = (object :: any)[methodName]
		if type(fn) ~= "function" then
			error(("Cleanup method '%s' is not a function on the given object"):format(methodName), 2)
		end
		fn(object)
	end
end

return ButlerStatic :: ButlerStatic
