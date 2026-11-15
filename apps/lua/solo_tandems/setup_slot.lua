-- Which saved setup to load when a Solo Tandems session starts.

local M = {}

M.filename = 'Solo Tandems.ini'

function M.relative(track_id, exists)
  if type(exists) ~= 'function' then return nil end
  if type(track_id) == 'string' and track_id ~= '' and track_id ~= 'generic' then
    local track_file = track_id .. '/' .. M.filename
    if exists(track_file) then return track_file end
  end
  local generic_file = 'generic/' .. M.filename
  if exists(generic_file) then return generic_file end
  return nil
end

return M
