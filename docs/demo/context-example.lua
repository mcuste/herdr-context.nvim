-- herdr-context.nvim demo
local function greet(person)
  local message = 'Hello, ' .. person
  return message
end

local team = {
  'Ada',
  'Grace',
  'Linus',
}

for _, person in ipairs(team) do
  print(greet(person))
end
