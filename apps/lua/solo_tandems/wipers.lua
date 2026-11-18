-- Lead wipers follow the live rain. A dry track parks them.
-- A wet track with no rain sweeps slowly. Rain sweeps faster as it gets heavier.

local M = {}

local SWEEP = math.rad(55)
local DRY = 0.01

function M.progress(value)
  if type(value) ~= 'number' then return 0 end
  return value
end

function M.period(wetness, intensity)
  wetness = type(wetness) == 'number' and wetness or 0
  intensity = type(intensity) == 'number' and intensity or 0
  if intensity < 0 then intensity = 0 end
  if intensity > 1 then intensity = 1 end
  if intensity > DRY then
    return 1.5 - 0.5 * intensity
  end
  if wetness > DRY then
    return 2.5
  end
  return nil
end

function M.sweep(elapsed, period)
  if type(period) ~= 'number' or period <= 0 then return 0 end
  elapsed = type(elapsed) == 'number' and elapsed or 0
  if elapsed < 0 then elapsed = 0 end
  local u = (elapsed % period) / period
  if u < 0.5 then return u * 2 end
  return (1 - u) * 2
end

function M.angle(value)
  local progress = M.progress(value)
  if progress < 0 then progress = 0 end
  if progress > 1 then progress = 1 end
  return progress * SWEEP
end

return M
