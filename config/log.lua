LogConfig = {
  --- Whether structured logs and traces are collected at all.
  ---
  --- • true (default): every resource using the SDK buffers its events
  ---   and the core serves them to the SIKU Agent
  --- • false: Siku.log calls return immediately, nothing is buffered
  enabled = true,

  --- Records the core keeps for the agent before dropping the oldest.
  --- Each record is one event or one span, already encoded.
  bufferRecords = 20000,

  --- Bytes of encoded records the core keeps before dropping the oldest.
  bufferBytes = 16 * 1024 * 1024,

  --- Delay (ms) between two deliveries from a resource to the core, and
  --- from a client to the server. A full batch is delivered sooner.
  flushMs = 200,

  --- Records a resource hands to the core in one delivery.
  batchSize = 100,

  --- Optional token the agent must present to read the records, for the
  --- rare setups where FXServer sits behind a local proxy. Empty (default):
  --- only loopback addresses may read.
  ---
  --- Set it from server.cfg with `set siku:logToken "…"`; this value is a
  --- fallback when the convar is absent.
  token = '',

  client = {
    --- Records one player may send per second, with the burst allowed.
    perSecond = 30,
    burst = 90,

    --- Bytes one player may send per second.
    bytesPerSecond = 32 * 1024,

    --- Largest encoded batch a client sends, in bytes, and the records it
    --- carries at most. Anything beyond is counted as dropped on the client.
    maxBatchBytes = 24 * 1024,
    maxBatchRecords = 50,
  },

  identity = {
    --- Identifiers written in player.joined and player.dropped events.
    --- Nothing else carries them: other events name the character and
    --- the user id, which stay resolvable afterwards.
    identifiers = { 'license', 'discord' },
  },

  tracing = {
    --- Whether spans are recorded.
    enabled = true,

    --- Share of new traces kept, between 0 and 1. Spans of a dropped trace
    --- cost nothing and leave no id on the logs emitted inside them.
    sampleRate = 1.0,

    --- Share kept among the traces the core opens on its own: callbacks
    --- and commands reached outside any span. These can be very frequent.
    autoSampleRate = 0.2,

    --- Automatic instrumentation of what the core controls.
    sql = true,
    callbacks = true,
    commands = true,

    --- Spans kept per trace and attributes kept per span.
    maxSpans = 200,
    maxAttributes = 64,
  },

  limits = {
    message = 2048,
    string = 1024,
    keys = 32,
    depth = 3,
    list = 50,
    entities = 16,
    stack = 16 * 1024,
    data = 16 * 1024,
  },

  print = {
    --- Whether Siku.print.warn and Siku.print.error also record a
    --- script.warning or script.error event.
    emit = true,
  },
}
