local logic = dofile('apps/lua/solo_tandems/logic.lua')

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
  logic.handle(state, logic.SPAWN, two)
  check('spawn without a lead run does nothing', not state.placed and state.notice == 'No lead run recorded')
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0.1, pose(0, 0, 1))
  logic.handle(state, logic.SPAWN, two)
  check('spawn waits until recording stops', not state.placed)
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.SPAWN, { cars = 1, can_move = true })
  check('spawn works with one car', state.placed and not state.playing)
  logic.handle(state, logic.CLEAR, two)
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0.1, pose(0, 0, 1))
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.SPAWN, two)
  check('spawn places the lead car', state.placed and not state.playing)
  local held = logic.lead_position(state, 0.016)
  check('waiting lead stays on the first sample', held.pos.x == state.samples[1].pos.x and held.vel.x == 0)
end

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0, pose(0, 0, 0))
  logic.capture(state, 1, pose(10, 0, 10))
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.SPAWN, two)
  logic.handle(state, logic.START, two)
  local early = logic.lead_position(state, 0)
  check('playback holds the first moment', early.pos.x == 0 and state.playing)
  local mid
  for _ = 1, 5 do mid = logic.lead_position(state, 0.1) end
  check('playback is halfway', math.abs(mid.pos.x - 5) < 0.001 and math.abs(mid.vel.x - 5) < 0.001)
  local done
  for _ = 1, 5 do done = logic.lead_position(state, 0.1) end
  check('playback returns lead to start', not state.playing and done.pos.x == 0 and done.vel.x == 0 and state.pulse == nil)
end

do
  local state = logic.create()
  logic.handle(state, logic.TELEPORT, two)
  check('teleport needs chase car set', state.pulse == nil)
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.CHASE, two)
  check('chase car can be set while recording', state.recording and state.chase_start.pos.x == 1)
  logic.handle(state, logic.CLEAR, two)
  logic.handle(state, logic.CHASE, two)
  check('chase start is the car pose', state.chase_start.pos.x == 1 and state.chase_start.pos.z == 2)
  logic.handle(state, logic.TELEPORT, two)
  check('teleport with no lead moves only the chase car', state.pulse == 'teleport' and not state.placed)
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0.2, pose(4, 0, 3))
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.SPAWN, two)
  logic.handle(state, logic.START, two)
  logic.handle(state, logic.TELEPORT, two)
  check('teleport resets a recorded lead', state.pulse == 'teleport' and state.placed and not state.playing)
  local held = logic.lead_position(state, 1)
  check('reset lead is the first sample', held.pos.x == 4)
end

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0.2, pose(4, 0, 3))
  logic.handle(state, logic.CLEAR, two)
  check('clear removes the lead', not state.recording and #state.samples == 0 and not state.placed)
  logic.handle(state, logic.CHASE, two)
  logic.handle(state, logic.TELEPORT, two)
  check('teleport after clear is the chase car only', state.pulse == 'teleport' and not state.placed)
end

do
  local state = logic.create()
  logic.handle(state, logic.START, two)
  check('start before the lead is placed does nothing', not state.playing)
  logic.handle(state, logic.CHASE, { cars = 2, can_move = false, pose = pose(1, 2) })
  logic.handle(state, logic.TELEPORT, { cars = 2, can_move = false, pose = pose(1, 2) })
  check('teleport waits for extended physics', state.pulse == nil and state.notice == 'Extended physics is off')
end

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0, pose(0, 0, 0, 0, { 1, 2, 3, 4 }, -0.5))
  logic.capture(state, 1, pose(10, 0, 10, 1, { 5, 6, 7, 8 }, 0.5))
  logic.handle(state, logic.RECORD, two)
  logic.handle(state, logic.SPAWN, two)
  local held = logic.lead_position(state, 0)
  check('waiting clears wheel spin and brake', held.brake == 0 and held.wheels[3] == 0)
  check('waiting keeps steer', held.steer == -0.5)
  logic.handle(state, logic.START, two)
  local mid
  for _ = 1, 5 do mid = logic.lead_position(state, 0.1) end
  check('playback blends brake', math.abs(mid.brake - 0.5) < 0.001)
  check('playback blends rear wheel speed', math.abs(mid.wheels[3] - 5) < 0.001)
  check('playback blends steer', math.abs(mid.steer - 0) < 0.001)
end

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 0.1, pose(1, 2, 3, 0.2, { 1, 2, 3, 4 }, -0.25))
  logic.capture(state, 0.2, pose(5, 6, 7, 0.8, { 4, 5, 6, 7 }, 0.5))
  logic.handle(state, logic.RECORD, two)
  local packed = logic.pack(state, { carId = 'test_car', trackId = 'test_track' })
  check('pack has samples', packed ~= nil and packed.sampleCount == 2 and packed.carId == 'test_car')
  local text = logic.encode(packed)
  check('encode makes text', type(text) == 'string' and #text > 20)
  local decoded = logic.decode(text)
  check('decode roundtrip', decoded ~= nil and decoded.sampleCount == 2)
  local other = logic.create()
  local meta = logic.apply_pack(other, decoded, { trackId = 'test_track' })
  check('import restores lead', meta.carId == 'test_car' and #other.samples == 2 and other.samples[2].pos.x == 5)
  check('import hides lead until Spawn', not other.placed and not other.recording)
  local blocked = logic.create()
  local ok, err = logic.apply_pack(blocked, decoded, { trackId = 'other_track' })
  check(
    'import rejects wrong track',
    ok == nil and #blocked.samples == 0 and type(err) == 'string' and err:find('Needs track: test_track', 1, true)
  )
end

do
  local link = { seen = false, seq = 0 }
  check('opening ignores the last deck press', logic.sync_deck(link, 5) == false and link.seq == 5)
  check('same deck count does not press again', logic.sync_deck(link, 5) == false)
  check('a new deck press is taken', logic.sync_deck(link, 6) == true and link.seq == 6)
  local fresh = { seen = false, seq = 0 }
  check('opening at zero waits', logic.sync_deck(fresh, 0) == false)
  check('first press after open is taken', logic.sync_deck(fresh, 1) == true)
end

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  local frame = 1 / 120
  for _ = 1, 120 do
    logic.capture(state, frame, pose(state.elapsed, 0, 8))
  end
  logic.handle(state, logic.RECORD, two)
  check('120 fps keeps about 30 samples in one second', #state.samples == 31)
  local spaced = #state.samples >= 3
  for i = 3, #state.samples do
    local gap = state.samples[i].t - state.samples[i - 1].t
    if gap < (1 / 30) - 0.002 or gap > (1 / 30) + 0.002 then
      spaced = false
    end
  end
  check('samples stay 1/30 apart', spaced)
  logic.handle(state, logic.SPAWN, two)
  logic.handle(state, logic.START, two)
  local mid
  local guard = 0
  repeat
    mid = logic.lead_position(state, frame)
    guard = guard + 1
  until guard > 120 or (state.play_t > state.samples[4].t and state.play_t < state.samples[5].t)
  local a = state.samples[4]
  local b = state.samples[5]
  local u = (state.play_t - a.t) / (b.t - a.t)
  local expect = a.pos.x + (b.pos.x - a.pos.x) * u
  check(
    'playback blends between samples',
    mid ~= nil and math.abs(mid.pos.x - expect) < 0.0001 and u > 0.01 and u < 0.99
  )
  check('playback keeps its place in the list', state.play_i == 4)
end

if failures > 0 then
  print(failures .. ' failed')
  os.exit(1)
end
print('all passed')
