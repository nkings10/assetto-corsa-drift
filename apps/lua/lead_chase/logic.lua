-- Recording and chase rules. No Custom Shaders Patch calls, so the tests can run it.

local M = {}

M.RECORD = 'record'
M.APPEAR = 'appear'
M.SPOT = 'spot'
M.TELEPORT = 'teleport'
M.START = 'start'
M.CLEAR = 'clear'

local MAX_SECONDS = 15 * 60

local function copy3(v)
  return { x = v.x, y = v.y, z = v.z }
end

local function length(v)
  return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function normalize(v)
  local len = length(v)
  if len < 0.0001 then return { x = 0, y = 0, z = 1 } end
  return { x = v.x / len, y = v.y / len, z = v.z / len }
end

local function lerp3(a, b, u)
  return {
    x = a.x + (b.x - a.x) * u,
    y = a.y + (b.y - a.y) * u,
    z = a.z + (b.z - a.z) * u,
  }
end

local function copy_wheels(wheels)
  if wheels == nil then return { 0, 0, 0, 0 } end
  return {
    wheels[1] or 0,
    wheels[2] or 0,
    wheels[3] or 0,
    wheels[4] or 0,
  }
end

local function lerp_wheels(a, b, u)
  a = a or { 0, 0, 0, 0 }
  b = b or { 0, 0, 0, 0 }
  return {
    a[1] + (b[1] - a[1]) * u,
    a[2] + (b[2] - a[2]) * u,
    a[3] + (b[3] - a[3]) * u,
    a[4] + (b[4] - a[4]) * u,
  }
end

local function copy_up(up)
  if up == nil then return { x = 0, y = 1, z = 0 } end
  return normalize(up)
end

local function copy_side(side, dir, up)
  if side ~= nil then return normalize(side) end
  dir = dir or { x = 0, y = 0, z = 1 }
  up = up or { x = 0, y = 1, z = 0 }
  return normalize({
    x = dir.z * up.y - dir.y * up.z,
    y = dir.x * up.z - dir.z * up.x,
    z = dir.y * up.x - dir.x * up.y,
  })
end

local function pose_copy(pose)
  local dir = normalize(pose.dir)
  local up = copy_up(pose.up)
  return {
    pos = copy3(pose.pos),
    dir = dir,
    up = up,
    side = copy_side(pose.side, dir, up),
    vel = copy3(pose.vel or { x = 0, y = 0, z = 0 }),
    brake = pose.brake or 0,
    steer = pose.steer or 0,
    gas = pose.gas or 0,
    rpm = pose.rpm or 0,
    gear = pose.gear or 0,
    drift = pose.drift or 0,
    speed = pose.speed or 0,
    wheels = copy_wheels(pose.wheels),
  }
end

local function hold_pose(sample)
  return {
    pos = copy3(sample.pos),
    dir = copy3(sample.dir),
    up = copy_up(sample.up),
    side = copy_side(sample.side, sample.dir, sample.up),
    vel = { x = 0, y = 0, z = 0 },
    brake = 0,
    steer = sample.steer or 0,
    gas = 0,
    rpm = math.min(sample.rpm or 900, 900),
    gear = sample.gear or 0,
    drift = 0,
    speed = 0,
    wheels = { 0, 0, 0, 0 },
  }
end

function M.create()
  return {
    recording = false,
    samples = {},
    elapsed = 0,
    placed = false,
    playing = false,
    play_t = 0,
    spot = nil,
    pulse = nil,
    notice = 'Ready',
  }
end

function M.has_lead(state)
  return #state.samples > 0
end

local function stop_playback(state)
  state.playing = false
  state.play_t = 0
end

local function hide_lead(state)
  state.placed = false
  stop_playback(state)
end

function M.handle(state, action, ctx)
  ctx = ctx or {}
  local can_move = ctx.can_move ~= false
  state.pulse = nil

  if action == M.RECORD then
    if state.recording then
      state.recording = false
      if #state.samples == 0 then
        state.notice = 'Recording is empty'
      else
        state.notice = 'Lead saved'
      end
      return state
    end
    state.recording = true
    state.samples = {}
    state.elapsed = 0
    hide_lead(state)
    state.notice = 'Recording'
    return state
  end

  if action == M.CLEAR then
    state.recording = false
    state.samples = {}
    state.elapsed = 0
    hide_lead(state)
    state.notice = 'Lead cleared'
    return state
  end

  if action == M.SPOT then
    if ctx.pose == nil then
      state.notice = 'No car to mark'
      return state
    end
    local pose = pose_copy(ctx.pose)
    state.spot = { pos = pose.pos, dir = pose.dir }
    state.notice = 'Chase spot saved'
    return state
  end

  if state.recording then
    state.notice = 'Stop the recording first'
    return state
  end

  if action == M.APPEAR then
    if #state.samples == 0 then
      state.notice = 'No lead recorded'
      return state
    end
    state.placed = true
    stop_playback(state)
    state.notice = 'Lead is waiting'
    return state
  end

  if action == M.START then
    if not state.placed then
      state.notice = 'Put the lead in place first'
      return state
    end
    state.playing = true
    state.play_t = 0
    state.notice = 'Lead is running'
    return state
  end

  if action == M.TELEPORT then
    if state.spot == nil then
      state.notice = 'Save a chase spot first'
      return state
    end
    if not can_move then
      state.notice = 'Extended physics is off'
      return state
    end
    state.pulse = 'teleport'
    if #state.samples == 0 then
      state.notice = 'Teleported'
      return state
    end
    state.placed = true
    stop_playback(state)
    state.notice = 'Teleported. Lead is waiting'
    return state
  end

  state.notice = 'Unknown action'
  return state
end

function M.capture(state, dt, pose)
  if not state.recording or pose == nil then return end
  dt = dt or 0
  if dt < 0 then dt = 0 end
  if state.elapsed + dt > MAX_SECONDS then
    state.recording = false
    state.notice = 'Lead saved'
    return
  end
  state.elapsed = state.elapsed + dt
  local sample = pose_copy(pose)
  sample.t = state.elapsed
  state.samples[#state.samples + 1] = sample
end

function M.lead_pose(state, dt)
  if not state.placed or #state.samples == 0 then
    return nil, 'hidden'
  end
  if not state.playing then
    return hold_pose(state.samples[1]), 'hold'
  end
  dt = dt or 0
  if dt < 0 then dt = 0 end
  if dt > 0.1 then dt = 0.1 end
  state.play_t = state.play_t + dt
  local samples = state.samples
  local first = samples[1]
  local last = samples[#samples]
  if state.play_t <= first.t then
    return {
      pos = copy3(first.pos),
      dir = copy3(first.dir),
      up = copy_up(first.up),
      side = copy_side(first.side, first.dir, first.up),
      vel = copy3(first.vel),
      brake = first.brake or 0,
      steer = first.steer or 0,
      gas = first.gas or 0,
      rpm = first.rpm or 0,
      gear = first.gear or 0,
      drift = first.drift or 0,
      speed = first.speed or 0,
      wheels = copy_wheels(first.wheels),
    }, 'play'
  end
  if last.t - state.play_t <= 0.0001 then
    state.playing = false
    state.play_t = 0
    state.pulse = 'teleport'
    state.notice = 'Lead ready'
    return hold_pose(first), 'hold'
  end
  local t = state.play_t
  local b = samples[1]
  local a = samples[1]
  for i = 2, #samples do
    if t <= samples[i].t then
      a = samples[i - 1]
      b = samples[i]
      break
    end
  end
  local span = b.t - a.t
  local u = span > 0 and (t - a.t) / span or 0
  local dir = normalize(lerp3(a.dir, b.dir, u))
  local up = normalize(lerp3(a.up or { x = 0, y = 1, z = 0 }, b.up or { x = 0, y = 1, z = 0 }, u))
  return {
    pos = lerp3(a.pos, b.pos, u),
    dir = dir,
    up = up,
    side = normalize(lerp3(
      a.side or copy_side(nil, a.dir, a.up),
      b.side or copy_side(nil, b.dir, b.up),
      u
    )),
    vel = lerp3(a.vel, b.vel, u),
    brake = (a.brake or 0) + ((b.brake or 0) - (a.brake or 0)) * u,
    steer = (a.steer or 0) + ((b.steer or 0) - (a.steer or 0)) * u,
    gas = (a.gas or 0) + ((b.gas or 0) - (a.gas or 0)) * u,
    rpm = (a.rpm or 0) + ((b.rpm or 0) - (a.rpm or 0)) * u,
    gear = a.gear or 0,
    drift = (a.drift or 0) + ((b.drift or 0) - (a.drift or 0)) * u,
    speed = (a.speed or 0) + ((b.speed or 0) - (a.speed or 0)) * u,
    wheels = lerp_wheels(a.wheels, b.wheels, u),
  }, 'play'
end

return M
