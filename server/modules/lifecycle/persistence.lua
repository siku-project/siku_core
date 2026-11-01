local AUTOSAVE_INTERVAL <const> = 900000

Siku.timers.setInterval(AUTOSAVE_INTERVAL, function()
  local saved <const> = Siku.persistence.saveAll()

  if saved > 0 then
    Siku.log.debug('lifecycle.autosaved', ('Autosave wrote %d player(s)'):format(saved), { players = saved })
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= Siku.name then
    return
  end

  local saved <const> = Siku.persistence.saveAll()

  if saved > 0 then
    Siku.log.info('lifecycle.shutdown_saved', T('persistence_shutdown_saved', saved), { players = saved })
  end
end)
