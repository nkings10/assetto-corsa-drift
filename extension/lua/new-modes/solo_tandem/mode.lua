-- Solo Tandem: Practice shell. Disable lap-cut invalidation for free roaming / chase.
-- The Solo Tandem app owns the visual ghost.

local cuts_ready = false

local function disarm_cuts()
  if physics ~= nil and physics.setAllowedTyresOut ~= nil then
    pcall(physics.setAllowedTyresOut, 4)
  end
  if ac.blockSystemMessages ~= nil and not cuts_ready then
    pcall(function()
      ac.blockSystemMessages(function(msg)
        if type(msg) ~= 'string' then return false end
        local lower = msg:lower()
        return lower:find('cut', 1, true) ~= nil
      end)
    end)
    pcall(ac.blockSystemMessages, true)
    cuts_ready = true
  end
end

function script.update(dt)
  disarm_cuts()
end
