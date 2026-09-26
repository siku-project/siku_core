JobsConfig = {
  --- Rules of each domain. A job registered without a domain is legal.
  ---
  --- • maxJobs    how many jobs of this domain a character may hold at
  ---              once, false for no limit
  --- • maxOnDuty  legal only: how many of those jobs a character may be
  ---              on duty in at the same time, false for no limit. A duty
  ---              the limit refuses is refused outright: the job resource
  ---              decides whether to offer a switch.
  domains = {
    legal = {
      maxJobs = 2,
      maxOnDuty = 1,
    },
    illegal = {
      maxJobs = 1,
    },
  },

  --- Unemployment: a character holding no legal job is unemployed, whatever
  --- illegal organisation it belongs to. Nothing is stored for it.
  unemployment = {
    --- TEMPORARY allowance, until the economy exists. Every interval the
    --- core fires `siku:jobs:unemploymentAllowance(sessionId, characterId,
    --- amount)` for each unemployed character in play and, when
    --- siku_inventory is started and `item` is set, hands that many of the
    --- item over. Replace it with the bank when it comes.
    allowance = {
      enabled = true,
      amount = 200,
      interval = 15 * 60000,
      item = 'cash',
    },
  },

  --- Whether hires, dismissals, grade changes and definition edits are
  --- written to `job_audit_log`.
  audit = true,
}
