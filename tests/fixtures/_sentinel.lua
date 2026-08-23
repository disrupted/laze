local M = {}

--- Sentinel value: marks a field that should hold a function.
M.FN = setmetatable({}, {
	__tostring = function()
		return "<function>"
	end,
})

return M
