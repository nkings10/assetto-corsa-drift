-- Record a lead run and play it on the second car. The player is the chase car.
-- Custom Shaders Patch 0.2.11. The lead is moved every frame, so a hit does not knock it off the line.
-- Wheel spin and steer are drawn on WHEEL_* nodes in draw3D; physics teleport clears physics wheel state.

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

local visual = {
  shown = false,
  steer = 0,
  omega = { 0, 0, 0, 0 },
  spin = { 0, 0, 0, 0 },
  last_t = nil,
  nodes = nil,
  node_ok = false,
}

-- Split capture vs inject so we can see which side is broken.
local diag = {
  force_wheels = false,
  force_brake = false,
  force_steer = 0,
  draw3d_frames = 0,
  last_live = nil,
  last_sample = nil,
  history = {},
  history_t = 0,
  dump_t = 0,
  dump_ok = nil,
  dump_path = nil,
}

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

local function set_lead_lights(braking)
  if ac.setTargetCar == nil then return end
  call(ac.setTargetCar, 1)
  if ac.setTurningLights ~= nil and ac.TurningLights ~= nil then
    call(ac.setTurningLights, ac.TurningLights.None)
  end
  if ac.setBrakingLightsThreshold ~= nil then
    -- Default threshold is ~0.01; AI often holds brake, which keeps lights on.
    -- Use 0 when we want lights so any pedal > 0 counts.
    call(ac.setBrakingLightsThreshold, braking and 0 or 10)
  end
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

local function sample_summary(pose)
  if pose == nil then return nil end
  return {
    brake = pose.brake or 0,
    steer = pose.steer or 0,
    rl = pose.wheels and (pose.wheels[3] or 0) or 0,
    speed = speed_ms(pose.vel),
  }
end

local function diag_path()
  if diag.dump_path ~= nil then return diag.dump_path end
  diag.dump_path = 'c:/Users/P3/Projects/assetto-corsa-drift/.diag/lead_chase.json'
  return diag.dump_path
end

local function lead_readback()
  if ac.getCar == nil then return nil end
  local ok, lead = pcall(ac.getCar, 1)
  if not ok or lead == nil then return nil end
  local rl = 0
  if lead.wheels ~= nil and lead.wheels[2] ~= nil then
    rl = lead.wheels[2].angularSpeed or 0
  end
  return {
    brake = lead.brake or -1,
    lights = lead.brakeLightsActive == true,
    signals = (lead.turningLeftLights == true) or (lead.turningRightLights == true),
    rl = rl,
  }
end

local function recording_slices()
  local n = #state.samples
  if n == 0 then return nil end
  local function at(i)
    return sample_summary(state.samples[i])
  end
  return {
    count = n,
    first = at(1),
    mid = at(math.max(1, math.floor((n + 1) / 2))),
    last = at(n),
  }
end

local function write_diag(reason)
  if io == nil or io.save == nil then
    diag.dump_ok = false
    return false
  end
  local dir = 'c:/Users/P3/Projects/assetto-corsa-drift/.diag'
  if io.createDir ~= nil then
    pcall(io.createDir, dir)
  end
  local payload = {
    t = os.time and os.time() or 0,
    reason = reason or 'auto',
    notice = state.notice,
    recording = state.recording == true,
    placed = state.placed == true,
    playing = state.playing == true,
    cars = car_count(),
    physics = can_move(),
    draw3d_frames = diag.draw3d_frames,
    nodes_ok = visual.node_ok == true,
    force = {
      wheels = diag.force_wheels,
      brake = diag.force_brake,
      steer = diag.force_steer,
    },
    inject = {
      steer = visual.steer or 0,
      rl_omega = visual.omega[3] or 0,
      shown = visual.shown == true,
    },
    live = diag.last_live,
    last_sample = diag.last_sample,
    recording_slices = recording_slices(),
    history = diag.history,
    lead = lead_readback(),
  }
  local text
  if JSON ~= nil and JSON.stringify ~= nil then
    local ok, encoded = pcall(JSON.stringify, payload)
    if ok then text = encoded end
  end
  if text == nil and stringify ~= nil then
    local ok, encoded = pcall(stringify, payload)
    if ok then text = encoded end
  end
  if text == nil then
    text = string.format(
      '{"reason":"%s","samples":%d,"draw3d":%d,"nodes":%s,"live_brake":%.3f,"live_steer":%.3f,"live_rl":%.3f,"force_wheels":%s,"force_brake":%s}',
      tostring(reason or 'auto'),
      #state.samples,
      diag.draw3d_frames,
      tostring(visual.node_ok == true),
      diag.last_live and diag.last_live.brake or -1,
      diag.last_live and diag.last_live.steer or 0,
      diag.last_live and diag.last_live.rl or 0,
      tostring(diag.force_wheels),
      tostring(diag.force_brake)
    )
  end
  local ok = io.save(diag_path(), text, true)
  diag.dump_ok = ok == true
  return diag.dump_ok
end

local function set_visual(pose)
  if pose == nil and not diag.force_wheels and diag.force_steer == 0 and not diag.force_brake then
    visual.shown = false
    visual.omega = { 0, 0, 0, 0 }
    return
  end
  if pose == nil and not visual.shown then return end
  visual.shown = true
  if diag.force_wheels then
    visual.omega = { 40, 40, 40, 40 }
  elseif pose ~= nil then
    visual.omega = wheel_values(pose.wheels, pose.vel)
  end
  if diag.force_steer ~= 0 then
    visual.steer = diag.force_steer
  elseif pose ~= nil then
    visual.steer = pose.steer or 0
  end
end

local function ensure_wheel_nodes()
  if visual.nodes ~= nil then return visual.node_ok end
  if ac.findNodes == nil then
    visual.nodes = false
    visual.node_ok = false
    return false
  end
  local ok, root = pcall(ac.findNodes, 'carRoot:1')
  if not ok or root == nil then
    visual.nodes = false
    visual.node_ok = false
    return false
  end
  local names = { 'WHEEL_LF', 'WHEEL_RF', 'WHEEL_LR', 'WHEEL_RR' }
  local nodes = {}
  for i = 1, 4 do
    local found, node = pcall(function()
      return root:findNodes(names[i])
    end)
    nodes[i] = found and node or nil
  end
  visual.nodes = nodes
  visual.node_ok = nodes[1] ~= nil and nodes[3] ~= nil
  return visual.node_ok
end

local function apply_wheel_node(node, spin, steer)
  if node == nil or node.getTransformationRaw == nil then return false end
  local ok, raw = pcall(function()
    return node:getTransformationRaw()
  end)
  if not ok or raw == nil or raw.position == nil then return false end
  local p = raw.position
  local rot = mat4x4.rotation(steer, vec3(0, 1, 0)):mul(mat4x4.rotation(spin, vec3(1, 0, 0)))
  local mat = mat4x4.translation(vec3(p.x, p.y, p.z)):mul(rot)
  pcall(function()
    raw:set(mat)
  end)
  return true
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
  set_visual(nil)
  set_lead_lights(false)
end

local function show_lead(pose)
  if physics == nil or pose == nil then return end
  call(physics.disableCarCollisions, 1, false, false)
  call(physics.setAILevel, 1, 0)
  call(physics.setAINoInput, 1, true, false)
  move_car(1, pose, pose.vel)
  set_visual(pose)
  local braking = diag.force_brake or (pose.brake or 0) > 0.05
  set_lead_lights(braking)
  if braking then
    -- Full pedal so lights light even if AI input was zeroed.
    apply_brake_pedal(1, 1)
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
  if car ~= nil then
    diag.last_live = sample_summary(read_pose(car))
  end
  if state.recording and car ~= nil then
    logic.capture(state, dt, read_pose(car))
  end
  if #state.samples > 0 then
    diag.last_sample = sample_summary(state.samples[#state.samples])
  else
    diag.last_sample = nil
  end

  diag.history_t = diag.history_t + (dt or 0)
  if diag.history_t >= 0.5 and diag.last_live ~= nil then
    diag.history_t = 0
    diag.history[#diag.history + 1] = {
      brake = diag.last_live.brake,
      steer = diag.last_live.steer,
      rl = diag.last_live.rl,
      speed = diag.last_live.speed,
      recording = state.recording == true,
    }
    if #diag.history > 40 then
      table.remove(diag.history, 1)
    end
  end

  diag.dump_t = diag.dump_t + (dt or 0)
  if diag.dump_t >= 1 then
    diag.dump_t = 0
    write_diag('auto')
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

function script.draw3D()
  diag.draw3d_frames = diag.draw3d_frames + 1
  if not visual.shown then return end
  if not ensure_wheel_nodes() then return end

  local now = os.preciseClock and os.preciseClock() or nil
  local step = 0.016
  if visual.last_t ~= nil and now ~= nil then
    step = now - visual.last_t
  end
  if now ~= nil then visual.last_t = now end
  if step > 0.1 then step = 0.1 end
  if step < 0 then step = 0 end

  -- Recorded steer is -1..1; ~0.55 rad is a usable road-car visual lock.
  local steer_rad = (visual.steer or 0) * 0.55
  for i = 1, 4 do
    visual.spin[i] = visual.spin[i] + (visual.omega[i] or 0) * step
    local steer = (i <= 2) and steer_rad or 0
    apply_wheel_node(visual.nodes[i], visual.spin[i], steer)
  end
end

local function fmt_sample(label, s)
  if s == nil then
    ui.text(label .. ': none')
    return
  end
  ui.text(string.format(
    '%s: brake %.2f  steer %.2f  RL %.1f  speed %.1f',
    label, s.brake, s.steer, s.rl, s.speed
  ))
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
  ui.text(can_move() and 'Extended physics on' or 'Extended physics off')
  ui.text('Cars: ' .. tostring(car_count()))

  ui.separator()
  ui.text('DIAGNOSTIC')
  fmt_sample('Live player', diag.last_live)
  fmt_sample('Last sample', diag.last_sample)
  ui.text(string.format(
    'draw3D frames %d  nodes %s',
    diag.draw3d_frames,
    visual.node_ok and 'ok' or 'missing'
  ))
  ui.text(string.format('Inject aim: steer %.2f  RL omega %.1f', visual.steer or 0, visual.omega[3] or 0))

  if ui.button(diag.force_wheels and 'Force wheels: ON' or 'Force wheels: off') then
    diag.force_wheels = not diag.force_wheels
    write_diag('force_wheels')
  end
  ui.sameLine(0, 8)
  if ui.button(diag.force_brake and 'Force brake lights: ON' or 'Force brake lights: off') then
    diag.force_brake = not diag.force_brake
    write_diag('force_brake')
  end
  if ui.button(diag.force_steer < 0 and 'Force steer: LEFT' or 'Force steer left') then
    diag.force_steer = diag.force_steer < 0 and 0 or -1
    write_diag('force_steer')
  end
  ui.sameLine(0, 8)
  if ui.button(diag.force_steer > 0 and 'Force steer: RIGHT' or 'Force steer right') then
    diag.force_steer = diag.force_steer > 0 and 0 or 1
    write_diag('force_steer')
  end
  if ui.button('Dump for agent') then
    write_diag('manual')
  end
  ui.text(diag.dump_ok == nil and 'Dump: waiting' or (diag.dump_ok and 'Dump: ok' or 'Dump: FAILED'))
  ui.text(diag_path())

  local lead = lead_readback()
  if lead ~= nil then
    ui.text(string.format('Lead readback: brake %.2f  lights %s  RL %.1f', lead.brake, tostring(lead.lights), lead.rl))
  else
    ui.text('Lead readback: no car 1')
  end

  ui.text('1) Record with steer/brake. 2) Appear lead. 3) Toggle Force *. 4) Dump for agent.')
end
