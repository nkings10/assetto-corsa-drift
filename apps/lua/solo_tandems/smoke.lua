-- Rear-tyre smoke points. A found wheel is used. Otherwise the old fixed offset.

local M = {}

local BASE = 1.35
local HALF = 0.72
local RADIUS = 0.33

function M.radius()
  return RADIUS
end

function M.intensity(slip)
  if type(slip) ~= 'number' then return 0 end
  if slip <= 1 then return 0 end
  local amount = (slip - 1) / 3
  if amount > 1 then return 1 end
  return amount
end

function M.contact(pos, look, side, wheel, sign, radius)
  local drop = RADIUS
  if type(radius) == 'number' and radius > 0 then drop = radius end
  if type(wheel) == 'table'
    and type(wheel.x) == 'number'
    and type(wheel.y) == 'number'
    and type(wheel.z) == 'number' then
    return wheel.x, wheel.y - drop, wheel.z
  end
  local s = sign or 1
  return pos.x - look.x * BASE + side.x * HALF * s,
    pos.y - look.y * BASE + side.y * HALF * s + 0.02,
    pos.z - look.z * BASE + side.z * HALF * s
end

return M
