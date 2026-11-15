-- Record a lead run and play it as a visual KN5 ghost. The player is the chase car.
-- Custom Shaders Patch 0.2.11. No second physics car — wheels/lights animate on the ghost.

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
local ghost = dofile(app_file('ghost_visual.lua'))

local state = logic.create()
local deck_seq = 0
local deck = nil
local ghost_car_id = nil

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

local function read_drift(car, vel, look)
  local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
  if speed < 5 then return 0 end
  local vx, vy, vz = vel.x / speed, vel.y / speed, vel.z / speed
  local lx, ly, lz = look.x, look.y, look.z
  local llen = math.sqrt(lx * lx + ly * ly + lz * lz)
  if llen > 0.001 then lx, ly, lz = lx / llen, ly / llen, lz / llen end
  local dot = vx * lx + vy * ly + vz * lz
  if dot > 1 then dot = 1 elseif dot < -1 then dot = -1 end
  local angle = math.deg(math.acos(dot))
  local cy = vz * lx - vx * lz
  if cy < 0 then angle = -angle end
  return angle
end

local function read_pose(car)
  local vel = car.velocity or vec3(0, 0, 0)
  local dir = car.look or vec3(0, 0, 1)
  local up = car.up or vec3(0, 1, 0)
  local side = car.side
  if side == nil then
    side = vec3(dir.z * up.y - dir.y * up.z, dir.x * up.z - dir.z * up.x, dir.y * up.x - dir.x * up.y)
  end
  return {
    pos = { x = car.position.x, y = car.position.y, z = car.position.z },
    dir = { x = dir.x, y = dir.y, z = dir.z },
    up = { x = up.x, y = up.y, z = up.z },
    side = { x = side.x, y = side.y, z = side.z },
    vel = { x = vel.x, y = vel.y, z = vel.z },
    brake = read_brake(car),
    steer = read_steer(car),
    gas = car.gas or 0,
    rpm = car.rpm or 0,
    gear = car.gear or 0,
    drift = read_drift(car, vel, dir),
    speed = car.speedKmh or math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z) * 3.6,
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

local function player_car_id()
  if ac.getCarID == nil then return nil end
  local ok, id = pcall(ac.getCarID, 0)
  if ok and type(id) == 'string' and id ~= '' then return id end
  return nil
end

local function call(fn, ...)
  if fn == nil then return false end
  return pcall(fn, ...)
end

local function move_car(index, pose, speed)
  if physics == nil or pose == nil then return false end
  local vel = speed or pose.vel
  local dir = vec3_of(pose.dir)
  call(physics.setCarVelocity, index, vec3_of(vel))
  local ok = call(physics.setCarPosition, index, vec3_of(pose.pos), -dir)
  call(physics.setCarVelocity, index, vec3_of(vel))
  return ok
end

local function teleport_player()
  local spot = state.spot
  if spot == nil or physics == nil then return end
  local pose = { pos = spot.pos, dir = spot.dir, vel = { x = 0, y = 0, z = 0 } }
  move_car(0, pose, pose.vel)
  call(physics.engageGear, 0, 0)
end

local function ensure_ghost()
  local id = ghost_car_id or player_car_id()
  if id == nil then return false end
  ghost_car_id = id
  return ghost.ensure(id)
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
  if action == logic.RECORD and state.recording then
    ghost_car_id = player_car_id()
  end
  if action == logic.CLEAR or (action == logic.RECORD and state.recording) then
    ghost.hide()
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

  local pose = logic.lead_pose(state, dt)
  if pose == nil then
    ghost.hide()
  else
    if ensure_ghost() then
      ghost.show(pose, dt)
    end
  end
end

function script.draw3D()
  ghost.draw_glows()
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
  ui.text(can_move() and 'Extended physics on' or 'Extended physics off (teleport only)')
  ui.text('Ghost: ' .. tostring(ghost.status()))
  if ghost_car_id ~= nil then
    ui.text('Car: ' .. ghost_car_id)
  end

  ui.separator()
  if ui.button('Record') then press(logic.RECORD) end
  ui.sameLine(0, 8)
  if ui.button('Appear') then press(logic.APPEAR) end
  ui.sameLine(0, 8)
  if ui.button('Start') then press(logic.START) end
  if ui.button('Chase spot') then press(logic.SPOT) end
  ui.sameLine(0, 8)
  if ui.button('Teleport') then press(logic.TELEPORT) end
  ui.sameLine(0, 8)
  if ui.button('Clear') then press(logic.CLEAR) end
end
