-- One height gap for the lead car. Measured on the road, then kept.

local M = {}

-- The saved point sits in the car body. Farther above the road than this is a jump.
local MIN_ABOVE = 0.25
local MAX_ABOVE = 2.0

function M.on_road(recorded_y, ground)
  if type(recorded_y) ~= 'number' or type(ground) ~= 'number' then return false end
  local above = recorded_y - ground
  return above >= MIN_ABOVE and above <= MAX_ABOVE
end

function M.measure_gap(recorded_y, ground, ground_offset)
  return (ground + (ground_offset or 0)) - recorded_y
end

function M.step(gap, recorded_y, ground, ground_offset, fallback_drop)
  local locked = gap
  if locked == nil and M.on_road(recorded_y, ground) then
    locked = M.measure_gap(recorded_y, ground, ground_offset)
  end
  local y
  if locked ~= nil then
    y = recorded_y + locked
  else
    y = recorded_y + (fallback_drop or 0)
  end
  return y, locked
end

return M
