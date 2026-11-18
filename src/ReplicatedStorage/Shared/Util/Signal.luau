--!strict
-- A plain Lua signal for server-side events that carry tables (crews, jobs). BindableEvents copy every table they
-- pass, so a listener would get a copy of the crew or job instead of the real one (2026-11-17). Same shape as a
-- BindableEvent: sig.Event:Connect(fn), sig:Fire(...). Handlers run right away, each in its own thread.
local Signal = {}
Signal.__index = Signal

export type Signal = {
	Event: any,
	Connect: (self: any, fn: (...any) -> ()) -> { Disconnect: () -> () },
	Fire: (self: any, ...any) -> (),
}

function Signal.new(): Signal
	local self = setmetatable({ handlers = {} :: { (...any) -> () } }, Signal) :: any
	self.Event = self
	return self
end

function Signal:Connect(fn: (...any) -> ()): { Disconnect: () -> () }
	table.insert(self.handlers, fn)
	return {
		Disconnect = function()
			local i = table.find(self.handlers, fn)
			if i then
				table.remove(self.handlers, i)
			end
		end,
	}
end

function Signal:Fire(...: any)
	for _, fn in table.clone(self.handlers) do
		task.spawn(fn, ...)
	end
end

return Signal
