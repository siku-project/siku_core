CallbackConfig = {
  --- Maximum time (ms) to wait for a callback answer.
  ---
  --- • 10000 (default): ten seconds before the call gives up
  ---
  --- When the delay expires the pending request is dropped and the
  --- calling thread resumes with ok = false and a timeout reason.
  --- The thread never hangs, whatever happens on the other side.
  ---
  --- Lower values surface unresponsive callbacks faster but may cut
  --- off legitimate slow work such as heavy database queries.
  ---
  --- Values below 1000 are raised to 1000.
  timeout = 10000,

  --- Minimum time (ms) between two calls of the same callback by the
  --- same player. Server-side anti-spam protection.
  ---
  --- • 0 (default): no limit, every request is answered
  --- • 100: the same player must wait 100ms before repeating a call
  ---
  --- A rejected call is answered with ok = false and a rate limit
  --- reason, and a warning naming the player is printed server-side.
  ---
  --- Only applies to client to server callbacks. Server to client
  --- calls are never rate limited.
  rateLimit = 0,
}
