-- Saved setup names, and the car's final drive (diff ratio). No Custom Shaders Patch calls.

local M = {}

M.filename = 'Solo Tandems.ini'
M.final_drive_id = 'FINAL_GEAR_RATIO'

local function trim(text)
  return (text:match('^%s*(.-)%s*$')) or ''
end

function M.is_default(filename)
  return type(filename) == 'string' and filename:lower() == M.filename:lower()
end

function M.display_name(filename)
  local name = tostring(filename or '')
  if name:lower():sub(-4) == '.ini' then name = name:sub(1, -5) end
  return name
end

function M.entries(track_id, generic_files, track_files)
  local out = {}
  local function add(files, folder, kind)
    if type(files) ~= 'table' then return end
    for i = 1, #files do
      local file = files[i]
      if type(file) == 'string' and file:lower():sub(-4) == '.ini' and not M.is_default(file) then
        out[#out + 1] = {
          label = M.display_name(file) .. ' (' .. kind .. ')',
          path = folder .. '/' .. file,
        }
      end
    end
  end
  add(generic_files, 'generic', 'Car')
  if type(track_id) == 'string' and track_id ~= '' and track_id ~= 'generic' then
    add(track_files, track_id, 'Track')
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

function M.car_default()
  return 'generic/' .. M.filename
end

function M.track_default(track_id)
  if type(track_id) ~= 'string' or track_id == '' or track_id == 'generic' then
    return nil
  end
  return track_id .. '/' .. M.filename
end

function M.named_file(name)
  if type(name) ~= 'string' then return nil end
  name = trim(name)
  if name:lower():sub(-4) == '.ini' then name = trim(name:sub(1, -5)) end
  if name:find('[\\/<>:"|%?%*]') or name:find('%.%.', 1, true) then return nil end
  name = trim(name):gsub('%.+$', '')
  if name == '' or name == '.' or name == '..' then return nil end
  if name:lower() == 'solo tandems' then return nil end
  return 'generic/' .. name .. '.ini'
end

function M.final_drive(spinners)
  if type(spinners) ~= 'table' then return nil end
  for i = 1, #spinners do
    local item = spinners[i]
    if type(item) == 'table' and item.name == M.final_drive_id then
      return item
    end
  end
  return nil
end

function M.final_drive_label(spinner)
  if type(spinner) ~= 'table' then return '' end
  if type(spinner.items) == 'table' then
    local text = spinner.items[(spinner.value or 0) + 1]
    if type(text) == 'string' and text ~= '' then return text end
  end
  local multiplier = spinner.displayMultiplier or 1
  return tostring((spinner.value or 0) * multiplier)
end

return M
