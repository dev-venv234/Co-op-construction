--!strict
-- Keyboard/gamepad shortcuts for on-screen buttons, through ContextActionService.
-- Every action also has a big on-screen button, so touch players never need these.
local ContextActionService = game:GetService("ContextActionService")

local Input = {}

local PRIORITY = Enum.ContextActionPriority.High.Value + 10

-- Calls cb on press. Sinks the key while bound (so Space taps don't also jump).
function Input.BindTap(name: string, cb: () -> (), ...: Enum.KeyCode)
	ContextActionService:BindActionAtPriority(name, function(_, state)
		if state == Enum.UserInputState.Begin then
			cb()
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, ...)
end

function Input.Unbind(name: string)
	ContextActionService:UnbindAction(name)
end

return Input
