Siku = {}
_SikuInternal = {}

Siku.print = {}
Siku.math = {}
Siku.table = {}

Siku.name = GetCurrentResourceName()
Siku.context = IsDuplicityVersion() and 'server' or 'client'

exports('objectExport', function()
  return Siku
end)
