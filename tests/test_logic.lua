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
  check('a hub gives the height of the model origin', math.abs(height.hub_offset(0.34, 10.2, 10) - 0.14) < 1e-9)
  check('a hub far from the model is ignored', height.hub_offset(0.33, -1000, 0) == nil)
  check('the lower axle sets the ride height', math.abs(height.ride_offset({ 0.40, 0.42 }, { 0.50, 0.48 }) - 0.49) < 1e-9)
  check('one axle is enough for the ride height', math.abs(height.ride_offset({}, { 0.47 }) - 0.47) < 1e-9)
  check('no hubs leaves the ride unset', height.ride_offset({}, {}) == nil)
  local ride = 0.5
  local upright = math.cos(math.rad(30))
  local pitched = height.pitched_offset(ride, upright)
  check('a slope stretches the ride', math.abs(pitched - (ride / upright)) < 1e-9)
  check('a level car keeps the ride', height.pitched_offset(ride, 1) == ride)
  check('a car on its side keeps the level ride', height.pitched_offset(ride, 0.2) == ride)
  check('a missing lean keeps the ride', height.pitched_offset(ride, nil) == ride)

  local state = nil
  local y
  -- Saved point 10, road contact wants 9.95. Five centimetres is inside the band.
  y, state = height.step(state, 10, 9.2, 0.75, 0.016, 40)
  check('a small slope keeps the saved height', math.abs(y - 10) < 1e-9)
  for _ = 1, 60 do
    y, state = height.step(state, 10.4, 9.6, 0.75, 0.016, 50)
  end
  check('a changing slope stays on the saved height', math.abs(y - 10.4) < 1e-4)
  local seated = nil
  y, seated = height.step(seated, 10, 10 - pitched, pitched, 0.016, 40)
  check('a seated car on a slope keeps the saved height', math.abs(y - 10) < 1e-9)
  y, state = height.step(nil, 6, nil, 0.9, 0.016, 0)
  check('a missed road keeps the saved height', math.abs(y - 6) < 1e-9)
  local buried = nil
  y, buried = height.step(buried, 9.2, 9.2, 0.5, 0.016, 30)
  check('a tyre in the road does not finish correcting in one frame', y > 9.2 and y < 9.5)
  for _ = 1, 120 do
    y, buried = height.step(buried, 9.2, 9.2, 0.5, 0.016, 30)
  end
  check('a tyre in the road eases up to the ride', math.abs(y - 9.7) < 0.05)
  local air = nil
  y, air = height.step(air, 10, 9.2, 0.75, 0.016, 40)
  local air_bias = air.bias
  for _ = 1, 90 do
    y, air = height.step(air, 13, 9.2, 0.75, 0.016, 80)
  end
  check('a jump stays on the saved height', math.abs(y - 13) < 0.05 and math.abs(air.bias - air_bias) < 1e-12)
  local low = nil
  y, low = height.step(low, 10, 9.2, 0.75, 0.016, 40)
  local low_bias = low.bias
  for _ = 1, 90 do
    y, low = height.step(low, 10, 7, 0.75, 0.016, 40)
  end
  check('a hit under the map is ignored', math.abs(y - 10) < 0.05 and math.abs(low.bias - low_bias) < 1e-12)
  local lid = nil
  y, lid = height.step(lid, 10, 9.2, 0.75, 0.016, 40)
  local lid_bias = lid.bias
  for _ = 1, 90 do
    y, lid = height.step(lid, 10, 14, 0.75, 0.016, 40)
  end
  check('a tunnel ceiling is ignored', math.abs(y - 10) < 0.05 and math.abs(lid.bias - lid_bias) < 1e-12)
end

local wipers = dofile('apps/lua/solo_tandems/wipers.lua')

do
  check('a missing wiper reading is parked', wipers.progress(nil) == 0 and wipers.angle(nil) == 0)
  check('a recorded sweep is kept', math.abs(wipers.progress(0.4) - 0.4) < 1e-9)
  check('a full sweep is the wiper travel', math.abs(wipers.angle(1) - math.rad(55)) < 1e-9)
  check('a parked wiper stays at rest', wipers.angle(0) == 0)
end

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  logic.capture(state, 1 / 30, pose(0, 0, 0))
  check('a sample without wipers is parked', state.samples[1].wipers == 0)
  logic.handle(state, logic.CLEAR, two)
  logic.handle(state, logic.RECORD, two)
  local first = pose(1, 0, 0)
  first.wipers = 0.25
  local second = pose(2, 0, 0)
  second.wipers = 0.75
  logic.capture(state, 1 / 30, first)
  logic.capture(state, 1 / 30, second)
  logic.handle(state, logic.RECORD, two)
  check('a sample keeps the wiper position', math.abs(state.samples[1].wipers - 0.25) < 1e-9)
  logic.handle(state, logic.SPAWN, two)
  local held = logic.lead_position(state, 0)
  check('a waiting lead keeps the wiper position', math.abs(held.wipers - 0.25) < 1e-9)
  logic.handle(state, logic.START, two)
  local mid
  local guard = 0
  repeat
    mid = logic.lead_position(state, 1 / 120)
    guard = guard + 1
  until guard > 30 or (state.play_t > state.samples[1].t and state.play_t < state.samples[2].t)
  local a = state.samples[1]
  local b = state.samples[2]
  local u = (state.play_t - a.t) / (b.t - a.t)
  local expect = a.wipers + (b.wipers - a.wipers) * u
  check('playback blends the wiper position', math.abs(mid.wipers - expect) < 1e-6)
end

local car_data = dofile('apps/lua/solo_tandems/car_data.lua')

do
  local spec = car_data.parse('[CONTROLS]\nSTEER_LOCK=520\n', '[FRONT]\nRADIUS=0.31\n[REAR]\nRADIUS=0.34\n')
  check('the car file gives the steering lock', spec.steer_lock == 520)
  check('the car file gives the front tyre size', math.abs(spec.radius_front - 0.31) < 1e-9)
  check('the car file gives the rear tyre size', math.abs(spec.radius_rear - 0.34) < 1e-9)
  local plain = car_data.parse('', '')
  check('a missing car file keeps the old steering lock', plain.steer_lock == 450)
  check('a missing car file keeps the old tyre size', plain.radius_front == 0.33 and plain.radius_rear == 0.33)
end

local car_lights = dofile('apps/lua/solo_tandems/car_lights.lua')

do
  local dir = 'tests/tmp_lights'
  os.execute('mkdir -p ' .. dir .. '/extension')
  local file = io.open(dir .. '/extension/taillights.ini', 'w')
  file:write([[
[EMISSIVE_REVERSE_0]
NAME=rev
COLOR=25, 25, 25
FALLBACK_BRAKES_COLOR=15, 0, 0
FALLBACK_BRAKES_COLOR_HIGHER=1

[EMISSIVE_TURNSIGNAL_LEFT_0]
NAME=ind_l
COLOR=20, 10, 0
FALLBACK_HEADLIGHTS_COLOR=5, 0, 0
]])
  file:close()
  local data = car_lights.load(dir)
  os.execute('rm -rf ' .. dir)
  check('a reverse lens is read from the car', data.reverse[1] == 'rev')
  check('a blinker lens is read from the car', data.turn_left[1] == 'ind_l')
  local reverse_color = car_lights.active_color(data.reverse_entries[1], { reverse = 1 })
  check('reverse uses the reverse color', reverse_color ~= nil and reverse_color.r > 0.9 and reverse_color.g > 0.9)
  local brake_color = car_lights.active_color(data.reverse_entries[1], { reverse = 1, brake = 1 })
  check('brakes replace reverse when the car says so', brake_color ~= nil and brake_color.r > brake_color.g)
  local parked = car_lights.active_color(data.turn_left_entries[1], { left = 1, blink = 0, head = 1 })
  check('a blinker at rest can sit as a tail light', parked ~= nil and parked.r > parked.g)
  local flashing = car_lights.active_color(data.turn_left_entries[1], { left = 1, blink = 1, head = 1 })
  check('a lit blinker uses the blinker color', flashing ~= nil and flashing.g > parked.g)
end

do
  local state = logic.create()
  logic.handle(state, logic.RECORD, two)
  local first = pose(1, 0, 0)
  first.lights = { head = 1, high = 0, left = 1, right = 0, blink = 1 }
  first.gear = 1
  local second = pose(2, 0, 0)
  second.lights = { head = 0, high = 1, left = 0, right = 1, blink = 0 }
  second.gear = -1
  logic.capture(state, 1 / 30, first)
  logic.capture(state, 1 / 30, second)
  logic.handle(state, logic.RECORD, two)
  check('a sample keeps the headlights', state.samples[1].lights.head == 1 and state.samples[1].lights.left == 1)
  check('a sample keeps the blink', state.samples[1].lights.blink == 1)
  logic.handle(state, logic.SPAWN, two)
  local held = logic.lead_position(state, 0)
  check('a waiting lead keeps the headlights', held.lights.head == 1 and held.lights.blink == 1)
  logic.handle(state, logic.START, two)
  local mid
  local guard = 0
  repeat
    mid = logic.lead_position(state, 1 / 120)
    guard = guard + 1
  until guard > 30 or (state.play_t > state.samples[1].t and state.play_t < state.samples[2].t)
  check('playback keeps the recorded light state', mid.lights.head == 1 and mid.lights.high == 0 and mid.lights.blink == 1)
  local dark = logic.create()
  logic.handle(dark, logic.RECORD, two)
  logic.capture(dark, 1 / 30, pose(0, 0, 0))
  check('a missing light reading is off', dark.samples[1].lights.head == 0 and dark.samples[1].lights.blink == 0)
end

local setup_slot = dofile('apps/lua/solo_tandems/setup_slot.lua')

do
  local function has(files)
    return function(path) return files[path] == true end
  end
  check(
    'a track setup is used when it exists',
    setup_slot.relative('spa', has({ ['spa/Solo Tandems.ini'] = true, ['generic/Solo Tandems.ini'] = true }))
      == 'spa/Solo Tandems.ini'
  )
  check(
    'a car setup is used when the track file is missing',
    setup_slot.relative('spa', has({ ['generic/Solo Tandems.ini'] = true })) == 'generic/Solo Tandems.ini'
  )
  check(
    'no setup is loaded when neither file exists',
    setup_slot.relative('spa', has({})) == nil
  )
  check(
    'a missing track still uses the car setup',
    setup_slot.relative('', has({ ['generic/Solo Tandems.ini'] = true })) == 'generic/Solo Tandems.ini'
  )
end

local setups = dofile('apps/lua/solo_tandems/setups.lua')

do
  local entries = setups.entries('spa', {
    'Street.ini',
    'Solo Tandems.ini',
    'notes.txt',
  }, {
    'Grip.ini',
    'solo tandems.INI',
  })
  check('the default setup stays out of the list', #entries == 2)
  check(
    'a car file is labelled Car and a track file is labelled Track',
    entries[1].label == 'Grip (Track)' and entries[1].path == 'spa/Grip.ini'
      and entries[2].label == 'Street (Car)' and entries[2].path == 'generic/Street.ini'
  )
  check(
    'a missing track lists the car files only',
    #setups.entries('', { 'Street.ini', 'Solo Tandems.ini' }, { 'Grip.ini' }) == 1
      and setups.entries('', { 'Street.ini' }, { 'Grip.ini' })[1].path == 'generic/Street.ini'
  )
  check('the car default path is the generic Solo Tandems file', setups.car_default() == 'generic/Solo Tandems.ini')
  check('the track default path uses the track folder', setups.track_default('spa') == 'spa/Solo Tandems.ini')
  check('a missing track has no track default', setups.track_default('') == nil and setups.track_default('generic') == nil)
  check('an empty name does not write a setup', setups.named_file('') == nil and setups.named_file('   ') == nil)
  check(
    'the typed name Solo Tandems does not write the default',
    setups.named_file('Solo Tandems') == nil and setups.named_file('solo tandems.ini') == nil
  )
  check('a typed name is saved as a car setup', setups.named_file(' Wet ') == 'generic/Wet.ini')
  check('a typed path is not saved', setups.named_file('generic/../Wet') == nil)
  local drive = setups.final_drive({
    { name = 'PRESSURE_LF', value = 1 },
    { name = 'FINAL_GEAR_RATIO', value = 1, items = { '4.10', '4.30' } },
  })
  check('the diff ratio is the final gear', drive ~= nil and setups.final_drive_label(drive) == '4.30')
  check('a car with no final gear has no diff ratio', setups.final_drive({ { name = 'PRESSURE_LF' } }) == nil)
end

local model_notice = dofile('apps/lua/solo_tandems/model_notice.lua')

do
  check(
    'a missing car says it is not installed',
    model_notice.message('not-installed', 'ae86') == 'Lead car is not installed: ae86'
  )
  check(
    'a car with no model says so',
    model_notice.message('no-model', 'ae86') == 'Lead car has no model: ae86'
  )
  check(
    'a model that will not load says so',
    model_notice.message('load-failed', 'ae86') == 'Could not load the lead car model: ae86'
  )
  check(
    'the model notices are recognised',
    model_notice.is_notice('Lead car is not installed: ae86')
      and model_notice.is_notice('Could not place the lead car')
      and not model_notice.is_notice('Lead is waiting')
  )
end

local smoke = dofile('apps/lua/solo_tandems/smoke.lua')

do
  local pos = { x = 10, y = 1, z = 20 }
  local look = { x = 0, y = 0, z = 1 }
  local side = { x = 1, y = 0, z = 0 }
  local lx, ly, lz = smoke.contact(pos, look, side, nil, 1)
  local rx, ry, rz = smoke.contact(pos, look, side, nil, -1)
  check('missing wheels keep the fixed rear offset', math.abs(lx - 10.72) < 1e-9 and math.abs(lz - 18.65) < 1e-9 and math.abs(rx - 9.28) < 1e-9 and math.abs(ry - ly) < 1e-9)
  local wx, wy, wz = smoke.contact(pos, look, side, { x = 4, y = 0.8, z = 7 }, 1)
  check('a found wheel is used for the smoke', math.abs(wx - 4) < 1e-9 and math.abs(wy - (0.8 - smoke.radius())) < 1e-9 and math.abs(wz - 7) < 1e-9)
end

if failures > 0 then
  print(failures .. ' failed')
  os.exit(1)
end
print('all passed')
