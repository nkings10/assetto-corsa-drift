local logic = dofile('apps/lua/lead_chase/logic.lua')

local failures = 0

local function check(name, ok)
  if ok then
    print('ok ' .. name)
  else
    failures = failures + 1
    print('FAIL ' .. name)
  end
end

local function pose(x, z, vx, brake, wheels, steer)
  return {
    pos = { x = x, y = 0, z = z },
    dir = { x = 0, y = 0, z = 1 },
    vel = { x = vx or 0, y = 0, z = 0 },
    brake = brake or 0,
    steer = steer or 0,
    wheels = wheels or { 0, 0, 0, 0 },
  }
end

local function drive(state, seconds)
  for _ = 1, seconds * 10 do
    logic.capture(state, 0.1, pose(state.elapsed, 0, 5))
  end
end

local two = { cars = 2, can_move = true, pose = pose(1, 2) }

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  check('record starts', state.recording and #state.samples == 0)
  drive(state, 2)
  check('record stores samples', #state.samples == 20 and state.samples[1].t == 0.1)
  logic.handle(state, logic.RECORD, two)
  check('record stops and keeps the lead', not state.recording and #state.samples == 20)
end

do
  local state = logic.create()
  logic.handle(state, logic.APPEAR, two)
  check('appear without a lead does nothing', not state.placed and state.notice == 'No lead recorded')
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0.1, pose(0, 0, 1))
  logic.handle(state, logic.APPEAR, two)
  check('appear waits until recording stops', not state.placed)
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.APPEAR, { cars = 1, can_move = true })
  check('appear needs a second car', not state.placed)
  logic.handle(state, logic.APPEAR, two)
  check('appear places the lead', state.placed and not state.playing)
  local held = logic.lead_pose(state, 0.016)
  check('waiting lead stays on the first sample', held.pos.x == state.samples[1].pos.x and held.vel.x == 0)
end

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0, pose(0, 0, 0))
  logic.capture(state, 1, pose(10, 0, 10))
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.APPEAR, two)
  logic.handle(state, logic.START, two)
  local early = logic.lead_pose(state, 0)
  check('playback holds the first moment', early.pos.x == 0 and state.playing)
  local mid
  for _ = 1, 5 do mid = logic.lead_pose(state, 0.1) end
  check('playback is halfway', math.abs(mid.pos.x - 5) < 0.001 and math.abs(mid.vel.x - 5) < 0.001)
  local done
  for _ = 1, 5 do done = logic.lead_pose(state, 0.1) end
  check('playback holds the end', not state.playing and done.pos.x == 10 and done.vel.x == 0)
end

do
  local state = logic.create()
  logic.handle(state, logic.TELEPORT, two)
  check('teleport needs a chase spot', state.pulse == nil)
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.SPOT, two)
  check('chase spot can be saved while recording', state.recording and state.spot.pos.x == 1)
  logic.handle(state, logic.CLEAR, two)
  logic.handle(state, logic.SPOT, two)
  check('chase spot is the car pose', state.spot.pos.x == 1 and state.spot.pos.z == 2)
  logic.handle(state, logic.TELEPORT, two)
  check('teleport with no lead moves only the chase car', state.pulse == 'teleport' and not state.placed)
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0.2, pose(4, 0, 3))
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.APPEAR, two)
  logic.handle(state, logic.START, two)
  logic.handle(state, logic.TELEPORT, two)
  check('teleport resets a recorded lead', state.pulse == 'teleport' and state.placed and not state.playing)
  local held = logic.lead_pose(state, 1)
  check('reset lead is the first sample', held.pos.x == 4)
end

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0.2, pose(4, 0, 3))
  logic.handle(state, logic.CLEAR, two)
  check('clear removes the lead', not state.recording and #state.samples == 0 and not state.placed)
  logic.handle(state, logic.SPOT, two)
  logic.handle(state, logic.TELEPORT, two)
  check('teleport after clear is the chase car only', state.pulse == 'teleport' and not state.placed)
end

do
  local state = logic.create()
  logic.handle(state, logic.START, two)
  check('start before the lead is placed does nothing', not state.playing)
  logic.handle(state, logic.SPOT, { cars = 2, can_move = false, pose = pose(1, 2) })
  logic.handle(state, logic.TELEPORT, { cars = 2, can_move = false, pose = pose(1, 2) })
  check('teleport waits for extended physics', state.pulse == nil and state.notice == 'Extended physics is off')
end

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0, pose(0, 0, 0, 0, { 1, 2, 3, 4 }, -0.5))
  logic.capture(state, 1, pose(10, 0, 10, 1, { 5, 6, 7, 8 }, 0.5))
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.APPEAR, two)
  local held = logic.lead_pose(state, 0)
  check('waiting clears wheel spin and brake', held.brake == 0 and held.wheels[3] == 0)
  check('waiting keeps steer', held.steer == -0.5)
  logic.handle(state, logic.START, two)
  local mid
  for _ = 1, 5 do mid = logic.lead_pose(state, 0.1) end
  check('playback blends brake', math.abs(mid.brake - 0.5) < 0.001)
  check('playback blends rear wheel speed', math.abs(mid.wheels[3] - 5) < 0.001)
  check('playback blends steer', math.abs(mid.steer - 0) < 0.001)
end

if failures > 0 then
  print(failures .. ' failed')
  os.exit(1)
end
print('all passed')
