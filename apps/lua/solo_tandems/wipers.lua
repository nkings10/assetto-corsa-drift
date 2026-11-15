-- Lead wipers follow the recorded sweep.

local M = {}

local SWEEP = math.rad(55)

function M.progress(value)
  if type(value) ~= 'number' then return 0 end
  return value
end

function M.angle(value)
  local progress = M.progress(value)
  if progress < 0 then progress = 0 end
  if progress > 1 then progress = 1 end
  return progress * SWEEP
end

return M
