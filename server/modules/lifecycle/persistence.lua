local AUTOSAVE_INTERVAL <const> = 900000

Siku.SetInterval(AUTOSAVE_INTERVAL, function()
  local saved <const> = Siku.SaveAllPlayers()

  if saved > 0 then
    Siku.print.debug(('Autosave wrote %d player(s)'):format(saved))
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= Siku.name then
    return
  end

  local saved <const> = Siku.SaveAllPlayers()

  if saved > 0 then
    Siku.print.info(T('persistence_shutdown_saved', saved))
  end
end)
