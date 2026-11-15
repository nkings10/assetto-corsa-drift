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
  decoded.samples[1].pos = nil
  local broken = logic.create()
  local bad, why = logic.apply_pack(broken, decoded, { trackId = 'test_track' })
  check('import without a position says bad file', bad == nil and why == 'Bad file' and #broken.samples == 0)
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

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 14 * 60 - 1, pose(1, 0, 1))
  check('before 14 minutes stays quiet', state.recording and state.notice == 'Recording')
  logic.capture(state, 1, pose(1, 0, 1))
  check('14 minutes says 60 seconds left', state.recording and state.notice == '60 seconds of recording left')
  logic.capture(state, 1, pose(1, 0, 1))
  check('one second later says 59', state.recording and state.notice == '59 seconds of recording left')
  logic.capture(state, 58, pose(2, 0, 1))
  check('the last second is singular', state.recording and state.notice == '1 second of recording left')
  logic.capture(state, 2, pose(2, 0, 1))
  check('15 minute limit stops the recording', not state.recording and #state.samples == 4)
  check('15 minute limit tells the user', state.notice == '15 minute recording limit reached')
  local stopped = logic.create()
  logic.handle(stopped, logic.RECORD, two)
  logic.capture(stopped, 0.1, pose(1, 0, 1))
  logic.handle(stopped, logic.RECORD, two)
  check('stopping yourself still says saved', stopped.notice == 'Lead run saved')
end

do
  local broken, why = logic.decode('{"kind":"solo_tandems","samples":[{"t":1},null,{"t":2}]}')
  check('null in a lead file is a bad file', broken == nil and why == 'Bad file')
  local missing, missing_why = logic.decode('{"kind":"solo_tandems","samples":[{"pos":null,"dir":{"x":0,"y":0,"z":1}}]}')
  check('null position is a bad file', missing == nil and missing_why == 'Bad file')
  local kept = logic.create()
  kept.samples = { pose(1, 2) }
  local bad_meta, bad_err = logic.apply_pack(kept, {
    kind = 'solo_tandems',
    trackId = 'test_track',
    samples = { { t = 1 } },
  }, { trackId = 'test_track' })
  check(
    'a sample without a position is a bad file',
    bad_meta == nil and bad_err == 'Bad file' and #kept.samples == 1
  )
end

local wetness = dofile('apps/lua/solo_tandems/wetness.lua')

local function material_read(meshes, index, prop)
  local row = meshes[index]
  if type(row) ~= 'table' then return nil end
  return row[prop]
end

do
  local saved = wetness.capture({
    { ksSpecularEXP = 35, fresnelC = 0.12 },
    { fresnelC = 0.4 },
    { ksSpecularEXP = 'missing', fresnelC = false },
  }, {
    { fresnelC = 0.7 },
  }, material_read)
  local writes = wetness.restore_writes(saved)
  local function has(group, index, prop, value)
    for i = 1, #writes do
      local item = writes[i]
      if item.group == group and item.index == index and item.prop == prop and item.value == value then
        return true
      end
    end
    return false
  end
  check('dry paint restores the saved shine', has('body', 1, 'ksSpecularEXP', 35) and has('body', 1, 'fresnelC', 0.12))
  check('dry paint keeps a mesh that only had fresnel', has('body', 2, 'fresnelC', 0.4) and not has('body', 2, 'ksSpecularEXP', 50))
  check('dry tyres restore their own fresnel', has('tyre', 1, 'fresnelC', 0.7))
  check('unreadable material values are skipped', #writes == 4)
  local blank = wetness.capture({ {} }, { {} }, function() return nil end)
  check('no readable materials means nothing to restore', #wetness.restore_writes(blank) == 0)
  check('missing save means nothing to restore', #wetness.restore_writes(nil) == 0)
end

local height = dofile('apps/lua/solo_tandems/height.lua')

do
  local gap = nil
  local y
  y, gap = height.step(gap, 6, 0, 0.05, -0.95)
  check('a jump before a road reading keeps the saved height', math.abs(y - 5.05) < 1e-9 and gap == nil)
  y, gap = height.step(gap, 1.0, nil, 0.05, -0.95)
  check('a missed road keeps the guessed drop', math.abs(y - 0.05) < 1e-9 and gap == nil)
  y, gap = height.step(gap, 1.0, 0, 0.05, -0.95)
  check('a road reading stores the gap', gap ~= nil and math.abs(y - 0.05) < 1e-9)
  local locked = gap
  y, gap = height.step(gap, 4.0, 0, 0.05, -0.95)
  check('a later jump keeps that gap', gap == locked and math.abs(y - (4.0 + locked)) < 1e-9 and math.abs((y - 0.05) - 3) < 1e-9)
  local ignored, still = height.step(nil, 5, 0, 0.05, -0.95)
  check('a high hit does not store a gap', still == nil and math.abs(ignored - 4.05) < 1e-9)
end

if failures > 0 then
  print(failures .. ' failed')
  os.exit(1)
end
print('all passed')
