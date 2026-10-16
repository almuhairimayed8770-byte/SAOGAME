--!strict
--[[
	Signal: a small typed event with Connect / Once / Wait / Fire / Destroy.

	Services talk to each other through Signals, never by reaching into each other's state.
	Handlers run on their own threads (task.spawn) so a slow or erroring handler cannot stall
	the firer. Errors in handlers are logged, never raised.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	Destroy: (self: Signal<T...>) -> (),
	ConnectionCount: (self: Signal<T...>) -> number,
}

type HandlerRecord = {
	handler: (...any) -> (),
	once: boolean,
	connection: Connection,
}

local Signal = {}
Signal.__index = Signal

local function newConnection(records: { HandlerRecord }, record: HandlerRecord): Connection
	local connection = { Connected = true } :: any
	function connection.Disconnect(self: Connection)
		if not self.Connected then
			return
		end
		self.Connected = false
		local index = table.find(records, record)
		if index then
			table.remove(records, index)
		end
	end
	return connection
end

--- Creates a new Signal.
function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _records = {} :: { HandlerRecord }, _destroyed = false }, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal.Connect(self: any, handler: (...any) -> ()): Connection
	assert(not self._destroyed, "Signal is destroyed")
	local record = { handler = handler, once = false } :: any
	record.connection = newConnection(self._records, record)
	table.insert(self._records, record)
	return record.connection
end

function Signal.Once(self: any, handler: (...any) -> ()): Connection
	assert(not self._destroyed, "Signal is destroyed")
	local record = { handler = handler, once = true } :: any
	record.connection = newConnection(self._records, record)
	table.insert(self._records, record)
	return record.connection
end

function Signal.Wait(self: any): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.Fire(self: any, ...: any)
	if self._destroyed then
		return
	end
	-- Copy so handlers that disconnect during the fire do not skip a neighbour.
	local snapshot = table.clone(self._records)
	for _, record in snapshot do
		if not record.connection.Connected then
			continue
		end
		if record.once then
			record.connection:Disconnect()
		end
		task.spawn(function(...)
			local ok, err = pcall(record.handler, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end, ...)
	end
end

function Signal.ConnectionCount(self: any): number
	return #self._records
end

function Signal.Destroy(self: any)
	self._destroyed = true
	for _, record in self._records do
		record.connection.Connected = false
	end
	table.clear(self._records)
end

return Signal
