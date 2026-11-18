-- Wheel spin from the saved speed of that wheel.
-- A locked wheel stays still. The car's speed is used only when that reading is missing.

local M = {}

function M.rate(saved, speed_ms, radius)
  if type(saved) == 'number' then return saved end
  local speed = type(speed_ms) == 'number' and speed_ms or 0
  if speed < 0 then speed = 0 end
  local size = type(radius) == 'number' and radius or 0
  if size <= 0 then return 0 end
  return speed / size
end

return M
