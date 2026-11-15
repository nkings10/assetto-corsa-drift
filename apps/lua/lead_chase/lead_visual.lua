-- Physics-rate apply for lead wheel spin and steering.
-- Runs after render-rate placement so spin/steer are not left cleared.

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
local ALL = 60

function script.update(dt)
  if data.active ~= 1 or physics == nil then return end
  if physics.overrideSteering ~= nil then
    pcall(physics.overrideSteering, LEAD, data.steer)
  end
  local w0, w1, w2, w3 = data.w0, data.w1, data.w2, data.w3
  local avg = (w0 + w1 + w2 + w3) * 0.25
  if physics.setWheelAngularVelocity ~= nil then
    pcall(physics.setWheelAngularVelocity, LEAD, 0, w0)
    pcall(physics.setWheelAngularVelocity, LEAD, 1, w1)
    pcall(physics.setWheelAngularVelocity, LEAD, 2, w2)
    pcall(physics.setWheelAngularVelocity, LEAD, 3, w3)
    pcall(physics.setWheelAngularVelocity, LEAD, ALL, avg)
  end
  if physics.addWheelTorque ~= nil then
    pcall(physics.addWheelTorque, LEAD, 0, w0 * 0.08)
    pcall(physics.addWheelTorque, LEAD, 1, w1 * 0.08)
    pcall(physics.addWheelTorque, LEAD, 2, w2 * 0.08)
    pcall(physics.addWheelTorque, LEAD, 3, w3 * 0.08)
  end
end
