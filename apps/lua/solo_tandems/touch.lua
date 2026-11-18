-- One crash sound when the chase car first meets the lead.
-- The next sound waits until the cars have been apart.

local M = {}

local CLEAR = 0.1

function M.step(touching, age, collided)
  if collided then
    local play = not touching
    return true, play
  end
  if touching and type(age) == 'number' and age > CLEAR then
    return false, false
  end
  return touching == true, false
end

return M
