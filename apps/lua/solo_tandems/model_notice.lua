-- Plain reasons when the lead car model cannot be shown.

local M = {}

function M.message(kind, car_id)
  local name = car_id
  if type(name) ~= 'string' or name == '' then name = 'unknown' end
  if kind == 'no-car' then return 'No lead car' end
  if kind == 'no-cars-folder' then return 'Cannot find the cars folder' end
  if kind == 'not-installed' then return 'Lead car is not installed: ' .. name end
  if kind == 'no-model' then return 'Lead car has no model: ' .. name end
  if kind == 'load-failed' then return 'Could not load the lead car model: ' .. name end
  if kind == 'place-failed' then return 'Could not place the lead car' end
  return 'Could not load the lead car model: ' .. name
end

function M.is_notice(text)
  if type(text) ~= 'string' then return false end
  if text == 'No lead car' or text == 'Cannot find the cars folder' or text == 'Could not place the lead car' then
    return true
  end
  if text:find('Lead car is not installed: ', 1, true) == 1 then return true end
  if text:find('Lead car has no model: ', 1, true) == 1 then return true end
  if text:find('Could not load the lead car model: ', 1, true) == 1 then return true end
  return false
end

return M
