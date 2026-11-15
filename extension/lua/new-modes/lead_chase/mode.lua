-- Practice shell for lead chase: silence the second car's AI. The Lead chase app moves it.

local silenced = false

local function call(fn, ...)
  if fn == nil then return false end
  return pcall(fn, ...)
end

local function silence_lead()
  if silenced or physics == nil or ac.getSim == nil then return end
  local ok, sim = pcall(ac.getSim)
  if not ok or sim == nil or (sim.carsCount or 0) < 2 then return end
  call(physics.setAILevel, 1, 0)
  call(physics.setAINoInput, 1, true, false)
  call(physics.disableCarCollisions, 1, true, false)
  silenced = true
end

function script.update(dt)
  silence_lead()
end
