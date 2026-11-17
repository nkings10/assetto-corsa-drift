-- Ride height for the lead car on a road that changes angle.
-- Wheel hubs say how high the model origin sits when the tyres touch.
-- The lower axle wins, so a taller rear tyre is not pushed through the road.
-- While the saved point is close to that ride, the lead uses the saved height,
-- so a slope stays in the run. A larger gap eases toward the road, and the
-- lead cannot drop through the road in one frame.

local M = {}

local DEAD_ZONE = 0.15
local BIAS_SPEED = 4
local MAX_DELTA = 0.35
local SMOOTH_UP = 12
local SMOOTH_DOWN = 22

function M.hub_offset(radius, hub_y, root_y)
  if type(radius) ~= 'number' or type(hub_y) ~= 'number' then return nil end
  local base = root_y or 0
  if type(base) ~= 'number' then return nil end
  local rel = hub_y - base
  if rel < -2 or rel > 2 then return nil end
  local offset = radius - rel
  if offset < -1 or offset > 2 then return nil end
  return offset
end

function M.average(values)
  if type(values) ~= 'table' then return nil end
  local sum, count = 0, 0
  for i = 1, #values do
    local value = values[i]
    if type(value) == 'number' then
      sum = sum + value
      count = count + 1
    end
  end
  if count == 0 then return nil end
  return sum / count
end

function M.ride_offset(front, rear)
  local front_offset = M.average(front)
  local rear_offset = M.average(rear)
  if front_offset == nil then return rear_offset end
  if rear_offset == nil then return front_offset end
  if rear_offset > front_offset then return rear_offset end
  return front_offset
end

local function blank()
  return { bias = 0, y = nil, seen_road = false }
end

local function clamp_dt(dt)
  if type(dt) ~= 'number' then return 0.016 end
  if dt < 0 then return 0 end
  if dt > 0.1 then return 0.1 end
  return dt
end

function M.step(state, recorded_y, ground, ground_offset, dt, speed_kmh)
  if type(state) ~= 'table' then state = blank() end
  if type(state.bias) ~= 'number' then state.bias = 0 end
  if type(recorded_y) ~= 'number' then return recorded_y, state end
  dt = clamp_dt(dt)

  local target
  local on_road = type(ground) == 'number' and type(ground_offset) == 'number'
  if on_road then
    local diff = (ground + ground_offset) - recorded_y
    local blend = math.min(1, dt * BIAS_SPEED)
    state.bias = state.bias + (diff - state.bias) * blend
    state.seen_road = true
    if math.abs(diff) < DEAD_ZONE then
      target = recorded_y
    else
      target = recorded_y + state.bias
    end
  elseif state.seen_road then
    target = recorded_y + state.bias
  else
    target = recorded_y
  end

  if state.y == nil then
    state.y = target
    return state.y, state
  end

  local delta = target - state.y
  local speed = type(speed_kmh) == 'number' and speed_kmh or 0
  if speed < 0 then speed = 0 end
  local max_delta = MAX_DELTA * math.max(1, speed / 80)
  if delta > max_delta then delta = max_delta end
  if delta < -max_delta then delta = -max_delta end
  local smooth = delta < 0 and SMOOTH_DOWN or SMOOTH_UP
  state.y = state.y + delta * math.min(1, dt * smooth)
  return state.y, state
end

return M
