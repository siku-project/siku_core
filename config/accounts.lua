AccountsConfig = {
  --- Whether a balance may go below zero.
  ---
  --- • false (default): a mutation that would take a balance under zero is
  ---   refused with `insufficient_balance`
  --- • true: every account may go negative
  ---
  --- A consumer may allow it on one account only, at creation with
  --- `allowNegative` or later with `setNegativeAllowed`, whatever this says.
  allowNegative = false,

  --- Whether every balance mutation is written to `account_mutations`: the
  --- account, the delta, the balance after, the resource that asked, the
  --- reason it gave and the character acting. This is a technical trace the
  --- core keeps for itself, not a bank statement.
  journal = true,

  --- Largest number of mutations one batch may carry. A batch is applied
  --- whole or not at all.
  maxBatchSize = 25,

  --- Largest amount one mutation may move, false for no limit.
  maxAmount = false,
}
