--- Deep merge source into target (mutates target). Numbers are added together by default.
---@param target table The target table to merge into.
---@param source table The source table to merge from.
---@param addNumbers? boolean Add numbers instead of replacing (default: true).
---@return table target The merged target table.
function Siku.table.merge(target, source, addNumbers)
  if addNumbers == nil then addNumbers = true end

  for k, sourceVal in pairs(source) do
    local targetVal <const> = target[k]

    if type(targetVal) == 'table' and type(sourceVal) == 'table' then
      Siku.table.merge(targetVal, sourceVal, addNumbers)
    elseif addNumbers and type(targetVal) == 'number' and type(sourceVal) == 'number' then
      target[k] = targetVal + sourceVal
    else
      target[k] = sourceVal
    end
  end

  return target
end
