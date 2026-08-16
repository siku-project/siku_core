ConnectionConfig = {
  --- Whether the connection guard rejects players once sv_maxclients
  --- is reached.
  ---
  --- FXServer never enforces sv_maxclients itself (the historical
  --- `hardcap` resource did it): with this disabled and no other guard,
  --- players can join past the configured limit.
  ---
  --- Default: true
  enforceMaxClients = true,

  --- Seconds before a pending connection (a player still loading) stops
  --- counting toward the limit.
  ---
  --- Protects against stale slots when a client vanishes between the
  --- connection request and the join without emitting any event.
  ---
  --- Default: 120
  pendingTimeout = 120,
}
