-- Wireframe stand-in. Same box as the contact collider, with an arrow for the heading.
-- Width 1 m, height 0.6 m, length 3 m, raised 0.4 m. Heading only, no roll.

local M = {}

local HALF_W = 0.5
local HALF_H = 0.3
local HALF_L = 1.5
local CENTER_Y = 0.4

local function local_corners()
  local corners = {}
  local ys = { CENTER_Y - HALF_H, CENTER_Y + HALF_H }
  local xs = { -HALF_W, HALF_W }
  local zs = { -HALF_L, HALF_L }
  for iy = 1, 2 do
    for iz = 1, 2 do
      for ix = 1, 2 do
        corners[#corners + 1] = { x = xs[ix], y = ys[iy], z = zs[iz] }
      end
    end
  end
  return corners
end

local EDGES = {
  { 1, 2 }, { 2, 4 }, { 4, 3 }, { 3, 1 },
  { 5, 6 }, { 6, 8 }, { 8, 7 }, { 7, 5 },
  { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

local function flat_axes(look)
  local lx = 0
  local lz = 1
  if type(look) == 'table' and type(look.x) == 'number' and type(look.z) == 'number' then
    lx = look.x
    lz = look.z
  end
  local len = math.sqrt(lx * lx + lz * lz)
  if len < 0.001 then
    lx, lz = 0, 1
  else
    lx, lz = lx / len, lz / len
  end
  return lx, lz, lz, -lx
end

function M.world(pos, look, point)
  local lx, lz, sx, sz = flat_axes(look)
  local px = type(pos) == 'table' and pos.x or 0
  local py = type(pos) == 'table' and pos.y or 0
  local pz = type(pos) == 'table' and pos.z or 0
  local x = point.x or 0
  local y = point.y or 0
  local z = point.z or 0
  return {
    x = px + sx * x + lx * z,
    y = py + y,
    z = pz + sz * x + lz * z,
  }
end

function M.segments(pos, look)
  local corners = local_corners()
  local world = {}
  for i = 1, #corners do
    world[i] = M.world(pos, look, corners[i])
  end
  local lines = {}
  for i = 1, #EDGES do
    lines[#lines + 1] = { world[EDGES[i][1]], world[EDGES[i][2]] }
  end
  local y = CENTER_Y
  local nose = HALF_L
  local base = { x = 0, y = y, z = nose }
  local tip = { x = 0, y = y, z = nose + 0.8 }
  local left = { x = -0.25, y = y, z = nose + 0.45 }
  local right = { x = 0.25, y = y, z = nose + 0.45 }
  lines[#lines + 1] = { M.world(pos, look, base), M.world(pos, look, tip) }
  lines[#lines + 1] = { M.world(pos, look, tip), M.world(pos, look, left) }
  lines[#lines + 1] = { M.world(pos, look, tip), M.world(pos, look, right) }
  return lines
end

return M
