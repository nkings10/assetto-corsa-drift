-- Saved paint and tyre values for the lead car, so rain can be undone.

local M = {}

local function num(v)
  if type(v) == 'number' then return v end
  return nil
end

function M.capture(body, tyres, read)
  local saved_body = {}
  local body_count = (type(body) == 'table' or type(body) == 'userdata') and #body or 0
  for i = 1, body_count do
    saved_body[i] = {
      spec = num(read(body, i, 'ksSpecularEXP')),
      fresnel = num(read(body, i, 'fresnelC')),
    }
  end
  local saved_tyres = {}
  local tyre_count = (type(tyres) == 'table' or type(tyres) == 'userdata') and #tyres or 0
  for i = 1, tyre_count do
    saved_tyres[i] = num(read(tyres, i, 'fresnelC'))
  end
  return { body = saved_body, tyres = saved_tyres }
end

function M.restore_writes(saved)
  local writes = {}
  if type(saved) ~= 'table' then return writes end
  local body = saved.body
  if type(body) == 'table' then
    for i = 1, #body do
      local row = body[i]
      if type(row) == 'table' then
        local spec = num(row.spec)
        local fresnel = num(row.fresnel)
        if spec ~= nil then
          writes[#writes + 1] = { group = 'body', index = i, prop = 'ksSpecularEXP', value = spec }
        end
        if fresnel ~= nil then
          writes[#writes + 1] = { group = 'body', index = i, prop = 'fresnelC', value = fresnel }
        end
      end
    end
  end
  local tyres = saved.tyres
  if type(tyres) == 'table' then
    for i = 1, #tyres do
      local fresnel = num(tyres[i])
      if fresnel ~= nil then
        writes[#writes + 1] = { group = 'tyre', index = i, prop = 'fresnelC', value = fresnel }
      end
    end
  end
  return writes
end

return M
