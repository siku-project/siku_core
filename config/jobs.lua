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

  --- Whether hires, dismissals, grade changes and definition edits are
  --- written to `job_audit_log`.
  audit = true,
}
