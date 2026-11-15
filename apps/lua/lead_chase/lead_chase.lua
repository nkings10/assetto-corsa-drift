-- Record a lead run and play it on the second car. The player is the chase car.
-- Custom Shaders Patch 0.2.11. The lead is moved every frame, so a hit does not knock it off the line.

local function app_file(name)
  local folder = 'apps/lua/lead_chase/'
  if ac.getFolder and ac.FolderID and ac.FolderID.ACApps then
    local apps = ac.getFolder(ac.FolderID.ACApps)
    if type(apps) == 'string' and apps ~= '' then
      folder = apps .. '/lua/lead_chase/'
    end
  end
  return folder .. name
end

local logic = dofile(app_file('logic.lua'))

local state = logic.create()
local deck_seq = 0
local deck = nil
local visual = nil
local visual_worker = false
local visual_status = 'off'

local ACTIONS = {
  [1] = logic.RECORD,
  [2] = logic.APPEAR,
  [3] = logic.SPOT,
  [4] = logic.TELEPORT,
  [5] = logic.START,
  [6] = logic.CLEAR,
}

local NAMES = {
  record = logic.RECORD,
  appear = logic.APPEAR,
  spot = logic.SPOT,
  teleport = logic.TELEPORT,
  start = logic.START,
  clear = logic.CLEAR,
}

local function bind(id)
  if ac.ControlButton == nil then return nil end
  local ok, button = pcall(ac.ControlButton, id)
  if ok and button ~= nil then return button end
  return nil
end

local buttons = {
  { key = 'record', button = bind('Lead chase/Record') },
  { key = 'appear', button = bind('Lead chase/Appear') },
  { key = 'spot', button = bind('Lead chase/Chase spot') },
  { key = 'teleport', button = bind('Lead chase/Teleport') },
  { key = 'start', button = bind('Lead chase/Start') },
  { key = 'clear', button = bind('Lead chase/Clear lead') },
}

local function vec3_of(v)
  return vec3(v.x, v.y, v.z)
end

local function read_wheels(car)
  local wheels = { 0, 0, 0, 0 }
  if car.wheels == nil then return wheels end
  for i = 0, 3 do
    local wheel = car.wheels[i]
    if wheel ~= nil and wheel.angularSpeed ~= nil then
      wheels[i + 1] = wheel.angularSpeed
    end
  end
  return wheels
end

local function read_steer(car)
  local lock = car.steerLock
  if lock == nil or lock < 0.001 then return 0 end
  local steer = car.steer or 0
  local n = steer / lock
  if n > 1 then return 1 end
  if n < -1 then return -1 end
  return n
end

local function read_brake(car)
  local brake = car.brake or 0
  local hand = car.handbrake or 0
  if hand > brake then brake = hand end
  if brake < 0.05 then return 0 end
  if brake > 1 then return 1 end
  return brake
end

local function read_pose(car)
  local vel = car.velocity or vec3(0, 0, 0)
  local dir = car.look or vec3(0, 0, 1)
  return {
    pos = { x = car.position.x, y = car.position.y, z = car.position.z },
    dir = { x = dir.x, y = dir.y, z = dir.z },
    vel = { x = vel.x, y = vel.y, z = vel.z },
    brake = read_brake(car),
    steer = read_steer(car),
    wheels = read_wheels(car),
  }
end

local function can_move()
  return physics ~= nil and physics.allowed ~= nil and physics.allowed()
end

local function car_count()
  if ac.getSim == nil then return 1 end
  local ok, sim = pcall(ac.getSim)
  if not ok or sim == nil or sim.carsCount == nil then return 1 end
  return sim.carsCount
end

local function player()
  if ac.getCar == nil then return nil end
  local ok, car = pcall(ac.getCar, 0)
  if not ok then return nil end
  return car
end

local function call(fn, ...)
  if fn == nil then return false end
  return pcall(fn, ...)
end

local function move_car(index, pose, speed)
  if physics == nil or pose == nil then return false end
  local vel = speed or pose.vel
  -- Placement dir is opposite car.look; pass the negated forward vector.
  local dir = vec3_of(pose.dir)
  call(physics.setCarVelocity, index, vec3_of(vel))
  local ok
  if index > 0 and physics.setAICarPosition ~= nil then
    ok = call(physics.setAICarPosition, index, vec3_of(pose.pos), -dir)
  else
    ok = call(physics.setCarPosition, index, vec3_of(pose.pos), -dir)
  end
  call(physics.setCarVelocity, index, vec3_of(vel))
  return ok
end

local function speed_ms(vel)
  if vel == nil then return 0 end
  return math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
end

local function wheel_values(wheels, vel)
  local values = wheels or { 0, 0, 0, 0 }
  local spinning = math.abs(values[1]) + math.abs(values[2]) + math.abs(values[3]) + math.abs(values[4])
  if spinning < 0.01 then
    local omega = speed_ms(vel) / 0.33
    return { omega, omega, omega, omega }
  end
  return values
end

local function ensure_visual()
  if visual ~= nil or ac.connect == nil or ac.StructItem == nil then return end
  local ok, link = pcall(ac.connect, {
    ac.StructItem.key('leadChase.visual.v1'),
    active = ac.StructItem.int32(),
    steer = ac.StructItem.float(),
    w0 = ac.StructItem.float(),
    w1 = ac.StructItem.float(),
    w2 = ac.StructItem.float(),
    w3 = ac.StructItem.float(),
  })
  if ok then visual = link end
end

local function start_visual_worker()
  if visual_worker or physics == nil or physics.startPhysicsWorker == nil then
    if physics == nil or physics.startPhysicsWorker == nil then
      visual_status = 'no worker api'
    end
    return
  end
  ensure_visual()
  if visual == nil then
    visual_status = 'no shared state'
    return
  end
  local ok, err = pcall(physics.startPhysicsWorker, 'lead_visual', 0, function(e)
    visual_status = e and ('err ' .. tostring(e)) or 'stopped'
    visual_worker = false
  end)
  if ok then
    visual_worker = true
    visual_status = 'on'
  else
    visual_status = 'fail ' .. tostring(err)
  end
end

local function publish_visual(active, steer, wheels)
  ensure_visual()
  start_visual_worker()
  if visual == nil then return end
  visual.active = active and 1 or 0
  visual.steer = steer or 0
  local w = wheels or { 0, 0, 0, 0 }
  visual.w0 = w[1] or 0
  visual.w1 = w[2] or 0
  visual.w2 = w[3] or 0
  visual.w3 = w[4] or 0
end

local function apply_wheel_spin(index, values)
  if physics == nil then return end
  local all = 60
  local avg = ((values[1] or 0) + (values[2] or 0) + (values[3] or 0) + (values[4] or 0)) * 0.25
  if physics.setWheelAngularVelocity ~= nil then
    for i = 0, 3 do
      call(physics.setWheelAngularVelocity, index, i, values[i + 1] or 0)
    end
    call(physics.setWheelAngularVelocity, index, all, avg)
  end
  if physics.addWheelTorque ~= nil then
    for i = 0, 3 do
      call(physics.addWheelTorque, index, i, (values[i + 1] or 0) * 0.08)
    end
  end
end

local function set_brake_lights(on)
  if ac.setTargetCar == nil or ac.setBrakingLightsThreshold == nil then return end
  call(ac.setTargetCar, 1)
  -- Default threshold is ~0.01; AI often holds brake, which keeps lights on.
  call(ac.setBrakingLightsThreshold, on and 0.01 or 10)
  call(ac.setTargetCar, 0)
end

local function apply_brake_pedal(index, brake)
  if ac.overrideCarControls == nil then return end
  local ok, controls = pcall(ac.overrideCarControls, index)
  if not ok or controls == nil then return end
  if controls.combineAxis ~= nil then controls.combineAxis = false end
  controls.brake = brake
  controls.handbrake = 0
  controls.gas = 0
  controls.clutch = 1
  controls.steer = math.huge
end

local function apply_steer(steer)
  if physics ~= nil and physics.overrideSteering ~= nil then
    call(physics.overrideSteering, 1, steer or 0)
  end
end

local function park_lead()
  if physics == nil then return end
  call(physics.disableCarCollisions, 1, true, false)
  call(physics.setAILevel, 1, 0)
  call(physics.setAINoInput, 1, true, true)
  call(physics.setCarVelocity, 1, vec3(0, 0, 0))
  if physics.setAICarPosition ~= nil then
    call(physics.setAICarPosition, 1, vec3(0, -500, 0), vec3(0, 0, 1))
  else
    call(physics.setCarPosition, 1, vec3(0, -500, 0), vec3(0, 0, 1))
  end
  publish_visual(false, 0, { 0, 0, 0, 0 })
  set_brake_lights(false)
  if physics.overrideSteering ~= nil then
    local nan = math.nan
    if nan == nil then nan = 0 / 0 end
    call(physics.overrideSteering, 1, nan)
  end
end

local function show_lead(pose)
  if physics == nil or pose == nil then return end
  call(physics.disableCarCollisions, 1, false, false)
  call(physics.setAILevel, 1, 0)
  call(physics.setAINoInput, 1, true, false)
  move_car(1, pose, pose.vel)
  local wheels = wheel_values(pose.wheels, pose.vel)
  apply_wheel_spin(1, wheels)
  apply_steer(pose.steer)
  publish_visual(true, pose.steer, wheels)
  local braking = (pose.brake or 0) > 0.05
  set_brake_lights(braking)
  -- Only push the pedal when lights should be on. Leaving override off lets threshold hide AI brake.
  if braking then
    apply_brake_pedal(1, pose.brake)
  end
end

local function teleport_player()
  local spot = state.spot
  if spot == nil or physics == nil then return end
  local pose = { pos = spot.pos, dir = spot.dir, vel = { x = 0, y = 0, z = 0 } }
  move_car(0, pose, pose.vel)
  -- engagedGear uses 0 for neutral.
  call(physics.engageGear, 0, 0)
end

local function context()
  local car = player()
  return {
    cars = car_count(),
    can_move = can_move(),
    pose = car and read_pose(car) or nil,
  }
end

local function press(action)
  logic.handle(state, action, context())
  if state.pulse == 'teleport' then
    state.pulse = nil
    teleport_player()
  end
end

local function button_down(button)
  if button == nil or button.pressed == nil then return false end
  if type(button.pressed) == 'boolean' then return button.pressed end
  if type(button.pressed) == 'function' then
    local ok, down = pcall(button.pressed, button)
    return ok and down == true
  end
  return false
end

local function ensure_deck()
  if deck ~= nil or ac.connect == nil or ac.StructItem == nil then return end
  local ok, link = pcall(ac.connect, {
    ac.StructItem.key('leadChase.v1'),
    seq = ac.StructItem.int32(),
    action = ac.StructItem.int32(),
  })
  if ok then deck = link end
end

local function deck_action()
  ensure_deck()
  if deck == nil or deck.seq == deck_seq then return end
  deck_seq = deck.seq
  local action = ACTIONS[deck.action]
  if action ~= nil then press(action) end
end

function script.update(dt)
  deck_action()
  for i = 1, #buttons do
    local item = buttons[i]
    if button_down(item.button) then
      press(NAMES[item.key])
    end
  end

  local car = player()
  if state.recording and car ~= nil then
    logic.capture(state, dt, read_pose(car))
  end

  if car_count() >= 2 and can_move() then
    local pose = logic.lead_pose(state, dt)
    if pose == nil then
      park_lead()
    else
      show_lead(pose)
    end
  end
end

function script.windowMain(dt)
  ui.text(state.notice)
  ui.text(state.recording and 'Recording' or 'Not recording')
  ui.text('Lead samples: ' .. tostring(#state.samples))
  if state.placed then
    ui.text(state.playing and 'Lead is running' or 'Lead is waiting')
  else
    ui.text('Lead is hidden')
  end
  ui.text(state.spot and 'Chase spot saved' or 'No chase spot')
  ui.text(can_move() and 'Extended physics on' or 'Extended physics off')
  ui.text('Cars: ' .. tostring(car_count()))
  ui.text('Visual worker: ' .. visual_status)
  if ac.getCar ~= nil then
    local ok, lead = pcall(ac.getCar, 1)
    if ok and lead ~= nil then
      local omega = 0
      if lead.wheels ~= nil and lead.wheels[2] ~= nil then
        omega = lead.wheels[2].angularSpeed or 0
      end
      ui.text(string.format(
        'Lead brake %.2f  lights %s  RL omega %.1f  steer %.2f',
        lead.brake or -1,
        tostring(lead.brakeLightsActive),
        omega,
        lead.steer and lead.steerLock and (lead.steer / lead.steerLock) or 0
      ))
    end
  end
  ui.text('Stream Deck actions: lead.record, lead.appear, lead.spot, lead.teleport, lead.start, lead.clear')
  ui.text('CSP controls: Lead chase/Record, Appear, Chase spot, Teleport, Start, Clear lead')
end
