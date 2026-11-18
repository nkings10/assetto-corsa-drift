-- Match a skin folder's images to the model's texture names.

local M = {}

function M.is_image(name)
  if type(name) ~= 'string' then return false end
  local ext = name:lower():match('%.([^%.]+)$')
  return ext == 'dds' or ext == 'png' or ext == 'jpg'
end

function M.mapping(texture_names, files)
  local by_lower = {}
  if type(files) == 'table' then
    for i = 1, #files do
      local file = files[i]
      if type(file) == 'table' and type(file.name) == 'string' and type(file.path) == 'string' then
        by_lower[file.name:lower()] = file.path
      end
    end
  end
  local map = {}
  local count = 0
  if type(texture_names) == 'table' then
    for i = 1, #texture_names do
      local tex = texture_names[i]
      if type(tex) == 'string' then
        local path = by_lower[tex:lower()]
        if path ~= nil then
          map[tex] = path
          count = count + 1
        end
      end
    end
  end
  if count == 0 and type(files) == 'table' then
    for i = 1, #files do
      local file = files[i]
      if type(file) == 'table' and type(file.name) == 'string' and type(file.path) == 'string' then
        map[file.name] = file.path
      end
    end
  end
  return map
end

return M
