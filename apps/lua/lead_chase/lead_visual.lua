-- Physics-rate apply for lead wheel spin and steering.
-- setCarPosition runs at render rate and clears these; this restores them ~333 Hz.

local data = ac.connect({
  ac.StructItem.key('leadChase.visual.v1'),
  active = ac.StructItem.int32(),
  steer = ac.StructItem.float(),
  w0 = ac.StructItem.float(),
  w1 = ac.StructItem.float(),
  w2 = ac.StructItem.float(),
  w3 = ac.StructItem.float(),
})

local LEAD = 1

function script.update(dt)
  if data.active ~= 1 or physics == nil then return end
  if physics.overrideSteering ~= nil then
    pcall(physics.overrideSteering, LEAD, data.steer)
  end
  if physics.setWheelAngularVelocity ~= nil then
    -- 0..3 are wheel indices (masks like Rear=48 also work).
    pcall(physics.setWheelAngularVelocity, LEAD, 0, data.w0)
    pcall(physics.setWheelAngularVelocity, LEAD, 1, data.w1)
    pcall(physics.setWheelAngularVelocity, LEAD, 2, data.w2)
    pcall(physics.setWheelAngularVelocity, LEAD, 3, data.w3)
  end
end
