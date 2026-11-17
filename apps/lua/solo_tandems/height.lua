-- One height gap for the lead car.
-- Wheel hubs say how high the model origin sits when the tyres touch.
-- The lower axle wins, so a taller rear tyre is not pushed through the road.
-- The saved point can sit above that origin. A few agreeing road readings
-- lock the gap down to the tyres. A hit under the track is ignored, and a
-- jump keeps the locked gap.

local M = {}

-- The saved point can sit about a metre above the model origin.
-- A drop past this is a hit on something under the track, not the road.
local MIN_GAP = -1.2
local MAX_GAP = 0.4
local LOCK_COUNT = 5
local LOCK_SPREAD = 0.04

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

function M.plausible(recorded_y, ground, ground_offset)
  if type(recorded_y) ~= 'number' or type(ground) ~= 'number' then return false end
  if type(ground_offset) ~= 'number' then return false end
  local gap = M.measure_gap(recorded_y, ground, ground_offset)
  return gap >= MIN_GAP and gap <= MAX_GAP
end

function M.measure_gap(recorded_y, ground, ground_offset)
  return (ground + (ground_offset or 0)) - recorded_y
end

local function summary(values)
  local copy = {}
  for i = 1, #values do
    copy[i] = values[i]
  end
  table.sort(copy)
  local count = #copy
  local mid
  if count % 2 == 1 then
    mid = copy[(count + 1) / 2]
  else
    mid = (copy[count / 2] + copy[count / 2 + 1]) / 2
  end
  return mid, copy[count] - copy[1]
end

local function blank()
  return { gap = nil, samples = {} }
end

function M.step(state, recorded_y, ground, ground_offset)
  if type(state) ~= 'table' then state = blank() end
  if type(state.samples) ~= 'table' then state.samples = {} end
  if type(recorded_y) ~= 'number' then return recorded_y, state end
  if state.gap ~= nil then
    return recorded_y + state.gap, state
  end
  if M.plausible(recorded_y, ground, ground_offset) then
    local samples = state.samples
    samples[#samples + 1] = M.measure_gap(recorded_y, ground, ground_offset)
    if #samples > LOCK_COUNT then
      table.remove(samples, 1)
    end
    local mid, spread = summary(samples)
    if #samples >= LOCK_COUNT and spread <= LOCK_SPREAD then
      state.gap = mid
    end
    return recorded_y + mid, state
  end
  if #state.samples > 0 then
    local mid = summary(state.samples)
    return recorded_y + mid, state
  end
  return recorded_y, state
end

return M
