# Security audit: remotes, economy and payout

Date: 2026-11-16. Branch: `purchase-service`. Read-only pass: no game code was changed for this document.
(The purchase hardening listed at the end was done earlier, in the adversarial pass, and is committed separately.)

**Update, later on 2026-11-16:** the owner asked for the three high findings to be fixed. H1, H2 and H3 below
each end with a "Fixed" note saying what was done and what is left. The medium and low findings are unchanged.

## What was reviewed

- Every remote. There are 17 client-to-server RemoteEvents and no RemoteFunctions (`Shared/Util/Net`):
  `Hello`, `PickRole`, `QuickJoin`, `Ping`, `KickVote`, `TimingTap`, `ConnectSubmit`, `TraceSubmit`, `GaugeHold`,
  `CancelTask`, `DropItem`, `DriveInput`, `MachineInput`, `SaveSettings`, `Company`, `Shop`, `Purchase`.
- `EconomyService` (cash, payout formula, pay boost) and the payout in `JobService.finish`.
- The prompt handlers that spend or grant: site buttons, slots, piles, truck loading, dealer, tool shop, coffee.
- `DataService` saving and session lock, as far as it affects money and purchases.
- `PurchaseService` and the three boosts.

Not reviewed in depth: `CompanyService` beyond its remote entry point and rate limits (about 900 lines of
DataStore logic), and client controllers (they are untrusted by design, so only what the server accepts matters).

Nothing here was tested against a live server. Findings come from reading the code, plus the Studio tests noted.

## Summary

| # | Severity | Finding |
|---|---|---|
| H1 | High, fixed | Character position is trusted for every reach check: a teleporting client finishes Place tasks instantly at 100% |
| H2 | High, fixed | One finished task pays a full paycheck: late joiners and idlers can leech pay, XP and company points |
| H3 | High, fixed | Anyone can take the free Foreman slot and kick players instantly, or refuse to start jobs |
| M1 | Medium | Every mini-game can be auto-played for top accuracy (the data needed is sent to the client) |
| M2 | Medium | Trades can be switched every 0.5 s mid-job: one player can do every trade, and each switch resets a bot |
| M3 | Medium | 2x Pay relies on Roblox refreshing its ownership cache when the purchase event fires: untested live |
| M4 | Medium | Retry Inspection can be used to delay the crew's payout by several minutes |
| M5 | Medium | The session lock is taken over after about 8 seconds even if the other server is alive |
| M6 | Medium | Client-driven vehicles may go 25% over top speed (plus 12 studs per check) before the guard reacts |
| L1 | Low | `Ping` accepts a position with NaN in X or Z and broadcasts it |
| L2 | Low | `ConnectSubmit` counts every key of the table it is sent before rejecting an oversized one |
| L3 | Low | Payout cash is added before the save: a crash in between loses the paycheck |
| L4 | Low | A fake "prompt closed" signal can shorten the retry offer's hold |
| L5 | Low | A boost bought, then not used, is auto-used if its receipt arrives within 3 minutes in a new job |
| L6 | Low | A bad number in `Config/Products` (non-integer cash) would leave that product's receipts unresolved |
| I1 | Info | Dev switches are all Studio-gated; test hooks exist only in Studio |

No way was found for a client to add cash, set a price, grant itself a product, or get a purchase granted twice.

## High

### H1. Character position is trusted for every reach check

Where: `JobService.near` (used by `onSlot`, `onPile`, `onLoadTruck`, `onDockStack`, site buttons), `TaskEngine`
`MAX_WANDER`, and the dealer, tool shop and coffee counters.

Players own their character's physics, so `HumanoidRootPart.Position` is whatever the client says. A client that
teleports can stand at a pile, then at a slot, with no travel time. Place tasks have no mini-game and complete at
accuracy 1.0 (`onSlot`: `done(1)`), so one cheater can place every piece of their trade in seconds, ignore the
carry slowdown, and never produce weak work. That raises the job grade, the pay of everyone on the job, their XP
and the company score.

Suggested fix: track each character on the server (distance moved per second against walk speed with slack, and
pull back or ignore prompts when it is exceeded), and require a minimum time between `Carry.PickUp` and the
matching Place equal to the distance divided by the carry speed.

**Fixed (2026-11-16): `Services/MoveGuard`.** The server keeps a trusted spot per player that follows the
character but moves no faster than the server-side walk speed times 1.3 (so carrying slows it too), with up to
2.5 seconds of allowance that builds up while standing or lagging. `JobService.near` uses that spot for players,
so slots, piles, truck loading and site buttons no longer believe the raw position. Riding in a seat counts when
the player reached the seat honestly; the crew shuttle and the trip back to the RV tell the guard where the
server put the player. Nobody is pulled back: a prompt simply does not work until the trusted spot arrives, with
a message saying why.
Measured in Studio: an honest walk stayed within 0.4 studs; a 300-stud teleport was trusted after 12.1 seconds
(walking takes 18.8); a 118-stud teleport to a pile was refused for 5.1 seconds; riding 150 studs and the shuttle
stayed at 0 lag.
What is left: a cheater still gets up to 1.3 times walking speed and one 2.5-second burst (about 52 studs after
standing still), which covers a short pile-to-slot hop about 25% sooner than walking. The dealer, tool shop and
coffee counters still read the raw position; they only decide where a player may spend their own cash. Someone
standing (not seated) on a moving truck falls behind and must wait a few seconds after stepping off.

### H2. One finished task pays a full paycheck

Where: `JobService.finish` (`if tasks > 0 then pay ...`), `QualityService.Contributors`.

Pay is not tied to how much a player did. Anyone on the server with one recorded task gets the full pay, the job
XP and company points. A player can ride out with the site button near the end, place one piece (or just be the
driver credited for a drive-through load), and collect. With the 2x Pay pass that is doubled. Rush Delivery also
records the Deliver task for the buyer, so 39 R$ buys the one task needed (it now needs a trade first, which is
the same bar as any task).

Suggested fix: scale pay by share of the job (for example full pay at 15% or more of a fair share of tasks, less
below that), or require a minimum time on site.

**Fixed (2026-11-16): `EconomyService.PayShare` and `TasksForFullPay`, used in `JobService.finish`.** A paycheck is
now multiplied by the player's share, which is the smaller of two parts:
- by work: tasks done out of the tasks needed for full pay. Needed = 10% of the job's tasks, never fewer than 3
  or more than 10 (Shed 4, Starter House 7), or every task the player's main trade has on that job when that is
  fewer, so a small trade that did all of its work is paid in full;
- by time: a player on the server for less than half of the job is paid in proportion (joining at the end).
Job XP and company points need a share of at least 50%. The numbers live in `ServerStorage/Config/Jobs`
(`ShareTasks`, `ShareTasksMin`, `ShareTasksMax`, `SharePresent`). The payout panel shows the share and why.
What is left: a player who is present from the start and does the needed handful of tasks, then idles, is still
paid in full. That idler's own trade stalls unless they keep working, so the crew notices.

### H3. The Foreman slot gives an instant kick and control of job starts

Where: `CrewService` `KickVote` (`roles[p] == "Foreman"` kicks at once) and `CanStartJobs`.

Foreman is first come, first served (`Max = 1`). A griefer who takes it can kick every other player, one every
2 seconds, and can also refuse to start a job while everyone else is told to ask the Foreman. This is the design
in CLAUDE.md ("Foreman can kick"), but on public servers it lets one player empty a server.

Suggested fix: give the instant kick only to the player who started the current job, add a cooldown and a
per-session limit, and let the crew start a job by vote when the Foreman has not started one for a few minutes.

**Fixed (2026-11-16): `CrewService`.** Nobody removes a player alone any more. A kick always takes at least two
voters: with the Foreman among them one more crew member is enough, otherwise most of the rest of the crew as
before (`Crew.VotesNeeded`). Votes now expire after 120 seconds. In a server of two, nobody can be kicked.
The Foreman keeps the first say on starting a job for 90 seconds after the crew becomes free (server start or a
job cleared); after that anyone may start one. The 90 seconds are counted from when the crew became free, so
dropping and re-taking Foreman does not reset them.
Tested: the vote rule as a function (1, 2 and 5 other players, with and without the Foreman). Not tested: a real
kick or a real start after the grace period, which need two or more players.
What is left: a Foreman with one accomplice can still remove players, and a Foreman can still delay each job
start by up to 90 seconds.

## Medium

### M1. Mini-games can be auto-played

Where: `TaskEngine` Timing, Gauge, Trace and Connect.

The server judges honestly on its own clock, but the client gets everything needed to play perfectly: the needle's
start time, period and zone (Timing), the full gauge parameters (Gauge), the seam points (Trace) and the puzzle
(Connect). The Studio test scripts used in this project do exactly that and score 0.93 to 1.0 every time. A
cheater gets top accuracy, never collapses anything and pushes pay to the 1.5x quality cap.

This cannot be fully prevented. Cheap mitigations: log per-player accuracy and timing variance (a human does not
tap within 10 ms of center 30 times in a row), flag outliers for review, and keep the leaderboard based on team
results rather than one player's accuracy.

### M2. Trades can be switched freely during a job

Where: `CrewService` `PickRole` (0.5 s cooldown, refused only while busy or when the trade is full).

One player can rotate through all six trades and do every task, which removes the reason for a crew. Each switch
also clocks a bot out and back in, cancelling the bot's task and sending a toast to everyone, so rapid switching
is a way to disrupt a job.

Suggested fix: a 20 to 30 second cooldown on switching while a job is running.

### M3. 2x Pay ownership check is untested against live Roblox

Where: `PurchaseService.onPassPromptFinished`.

The pass is never granted from the event's "purchased" flag alone. It is granted when
`UserOwnsGamePassAsync` says so after the event, which Roblox's documentation says is refreshed when that event
fires. That behavior cannot be exercised in Studio. If the refresh were slower than the 15 seconds of retries, a
real buyer would get the pass only on their next join. If Roblox ever reported ownership from a forged signal, a
cheater would get 2x for that session only (ownership is never saved in the profile).

Needed: one live test with a second account. Buy the pass in game and confirm the toast and the doubled payout;
cancel a prompt and confirm nothing is granted.

### M4. Retry Inspection can delay the crew

Where: `InspectionService` (`RETRY_WINDOW` 25 s, `RETRY_HOLD` 60 s once per offer, `RETRY_SECONDS` 180 s,
`MAX_RETRIES` 2).

A player who takes a retry and then does not rebuild their own trade's pieces makes the crew wait up to 180
seconds, twice, plus the offer windows: about 9 minutes in the worst case. Each retry costs Robux and the result
can never be worse than the first inspection, so this is a nuisance, not a loss. Pressing the retry button and
leaving the purchase prompt open also holds the offer for 60 seconds, once.

Suggested fix: after 60 seconds let any trade do the rebuild tasks, or end the rebuild early when the crew votes.

### M5. Session lock is taken over after about 8 seconds

Where: `DataService.load` (`attempt < 5` with 2 second waits; `LOCK_SECONDS = 300` is effectively unused).

If a player hops servers quickly, the new server takes the profile while the old one may still be saving. The old
server's later saves are then refused (it no longer holds the lock), so the last seconds of progress on the old
server can be lost. No duplication path was found: the profile is one record, and a purchase in flight returns
NotProcessedYet when the lock is lost. This is a data-loss risk rather than an exploit.

Suggested fix: honor the lock for 30 to 60 seconds before taking over.

### M6. Vehicle guard slack

Where: `VehicleService.guard` (documented exception in CLAUDE.md coding rule 1).

The driver's client owns the truck. The server check allows 1.25 times top speed plus 12 studs per check and
rejects jumps over 150 studs. So a modified client can drive about 25% faster. Truck position gates loading (45
studs from the dock) and delivery (the pad radius), so the gain is a shorter drive, nothing more.

## Low

- **L1. `Ping` NaN.** `CrewService` checks `pos.Y ~= pos.Y` only. A position with NaN in X or Z passes the range
  test (comparisons with NaN are false) and is sent to every client. Check all three components.
- **L2. `ConnectSubmit` size.** The handler counts every key of the submitted table before comparing with the
  puzzle size. A very large table costs CPU once per 0.3 seconds per player. Stop counting once past the puzzle
  size. (`TraceSubmit` already checks its length first.)
- **L3. Payout before save.** `finish` adds the cash, then starts a save in the background. A server crash in
  between loses that paycheck. No gain for anyone.
- **L4. Retry hold release.** `PromptProductPurchaseFinished` is used only to end the offer's hold early, and only
  for the player who is holding it. If that signal can be forged, the worst case is a shorter window; the buyer's
  retry is then kept as a saved credit.
- **L5. Auto-use window.** A boost is used automatically when its receipt arrives within 180 seconds of the Buy
  tap. If the job ended and another started in that time, it is used on the new job.
- **L6. Config numbers.** `EconomyService.AddCash` asserts a non-negative integer. A typo such as `Cash = 1500.5`
  in `Config/Products` would make every receipt for that pack fail and stay unresolved. Check the file after
  editing ids.

## Informational

- **I1. Dev switches.** `DevReturningPlayer`, `DevUnlockAll`, `DevChaos`, `DevCompanies`, `DevForceTouchUI` and
  `DevMockPurchases` are each checked together with `RunService:IsStudio()`. `ServerStorage.DevTrigger` and
  `ServerStorage.DevPurchase` are created only in Studio. A switch left set in the published place does nothing
  live.
- **Economy.** Cash is a server-owned leaderstats value. No remote carries an amount, a price or an item the
  server does not look up itself. `TrySpend` checks the balance; dealer and tool shop prices come from
  `ServerStorage/Config`.
- **Rate limits.** All 17 remotes have one: per-action cooldowns (`Guard.Allow`) or per-second budgets (drive,
  machine and gauge input). Unknown actions and wrong types are dropped.

## Purchase system: what was attacked and what happened

Tested in Studio with fake receipts through the real handler (real purchases cannot run in Studio):

| Attack | Result |
|---|---|
| Same receipt delivered again | PurchaseGranted, nothing added the second time |
| Same receipt three times at the same moment | One grant |
| Save fails after the grant, receipt delivered again | NotProcessedYet while failing; one grant in total once it saves |
| Unknown product id, buyer not in the server, profile not loaded, empty purchase id | NotProcessedYet, nothing granted |
| Buy a boost with no job, no trade, or nothing to use it on | Refused before any purchase prompt |
| Receipt arrives with nothing to use it on | Saved as a credit, later used for free |
| Third Hire a Pro on one job | Refused by the limit of 2, credit kept |
| Second take of one retry offer | Refused |
| Unknown action, wrong types, 500-character key, 40 Buy calls at once | Ignored; rate limit held |
| Player takes the hired pro's trade | Pro stays |

Hardening done in the adversarial pass (commit "Purchase hardening"):

1. No ordinary save, and so no purchase confirmation, once a player is leaving or the server is closing. Before
   this, a purchase confirmed against a write could be overwritten by the final save taken a moment earlier.
2. Rush Delivery needs a trade, like any task, because the delivery is credited to the buyer.
3. At most 2 hired pros per job, so pros speed a crew up and do not replace it.
4. No retry offer, and no 25 second wait, when the retry is not on sale and nobody has one saved. With the
   placeholder ids this would otherwise have delayed every failed inspection.
5. Only the player holding a retry offer open can release that hold.

Not tested, because it needs real purchases or real DataStores: a real receipt, the session-lock paths, a save
that fails for real, redelivery on rejoin, and the pass purchase flow (M3).
