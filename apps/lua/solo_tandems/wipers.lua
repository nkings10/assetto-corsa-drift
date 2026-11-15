-- Lead wipers run only while rain is falling.

local M = {}

function M.active(intensity)
  return type(intensity) == 'number' and intensity > 0.01
end

return M
