---@param msg string
---@param level? integer
return function(msg, level)
  vim.notify("[Projectab] " .. msg, level)
end
