---@param msg string
---@param level? integer
return function(msg, level)
  vim.notify("[ProjecTab] " .. msg, level)
end
