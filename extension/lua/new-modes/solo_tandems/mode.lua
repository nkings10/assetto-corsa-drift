-- Solo Tandems: Practice shell. Disable lap-cut invalidation for free roaming / chase.
-- The Solo Tandems app owns the visual lead.

local function disarm_cuts()
  if physics ~= nil and physics.setAllowedTyresOut ~= nil then
    pcall(physics.setAllowedTyresOut, -1)
  end
end

function script.update(dt)
  disarm_cuts()
end
