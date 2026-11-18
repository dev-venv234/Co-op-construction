# Co Op construction — CLAUDE.md

Roblox Studio place name: **Co Op construction** (exact). Design doc: `PLAN.md` (working title "Construction Crew").
Studio connection: **Roblox Studio MCP** (`mcp__Roblox_Studio__*` tools). Code lives in the place; the
`src/` tree in this folder mirrors Studio's services 1:1 so Rojo can be added later without moving anything.

**The Studio place (confirmed by the owner 2026-11-07):** Place ID `133389756938824`, Universe/Game ID `10775216932`.
Its Roblox name is still the default "Mig_3402's Place: 11072026_1" until renamed. Before editing, run
`list_roblox_studios` and only touch the instance whose placeId is `133389756938824`.
Starting state: empty Baseplate (Terrain, SpawnLocation, Baseplate), 0 scripts.

## The game in one line
Co-op job site: a crew of 2–6 players, each in a real trade, races to finish a building before the
deadline while things go wrong, then gets paid and upgrades. Players *are* the crew — no top-down tycoon.

## Game rules
- **Core loop:** show up → pick a trade → build together on a ghost blueprint → pass inspection → get paid → upgrade → bigger job.
- **Joining (owner rule, 2026-11-11, replaces the old drop-in):** everyone who joins spawns at the **RV park** (returning
  players at their own RV, first-timers on the camp lane by the coffee stand) and starts Site 1 from the board; nobody is
  dropped into a job. Someone joining while a crew is out at a site rides there with that site's board button. A
  newcomer's first job has no chaos events. The RV and truck dealer unlock after the **first payout**.
- **Crews:** Quick Join matches you to any crew needing your trade, or form a crew as Foreman and pick the job tier. Empty slots get **bot workers** (slower, make mistakes, run the same task engine as players).
  Since 2026-11-17 a server holds up to 6 crews at once, each on its own lot with its own job (see "Several crews per server").
- **Trades:** each levels up separately. Every phase gives every trade work — **no trade idle more than 1 minute**.
- **Building:** only fill glowing ghost outlines. No freeform building (prevents griefing, makes scoring easy).
- **Four task types** power every trade: **Carry** (haul to zone, weight slows you), **Place** (snap into ghost outline), **Timing** (hit a moving window), **Connect** (route puzzle A→B).
  Since 2026-11-13 (owner request) two more: **Trace** (follow a weld seam) and **Gauge** (hold to keep a needle in the green).
- **Quality score:** accuracy of every task rolls up into a job grade.
- **Inspection:** inspector walks the house; mistakes cost pay; skipped steps cause partial **collapse**.
- **Payout:** base pay × quality (0.5×–1.5×), +25% for finishing early, minus damage/rework. Whoever causes damage gets no pay for it.
  Since 2026-11-16 the paycheck is also × your share of the job: full pay needs about 10% of the job's tasks (3–10, or all of your trade's tasks if fewer) and being there for half the job; less pays in proportion.
- **Drives** to site stay under 60 seconds.
- **Griefers:** crew kick vote (most of the crew; since 2026-11-16 the Foreman's vote counts like anyone's).
- **Monetization rule:** sell speed, style and status. **Never sell** auto-build, skip-phase, or anything that finishes a job without the crew. Best truck must stay earnable by grinding.

### Job tiers (starting numbers, tune in playtests)
| Tier | Job | Length | Crew | Base pay / player | Unlock | Release |
|---|---|---|---|---|---|---|
| 1 | Shed / garage | 8 min | 2–3 | $500 | Start | **Launch** |
| 2 | Starter house | 15 min | 3–5 | $1,500 | Trade level 3 | **Launch** |
| 3 | Two-story home | 25 min | 4–6 | $4,000 | Trade lvl 8 + mid truck | Update |
| 4 | Luxury custom home | 35 min | 5–6 | $10,000 | Trade lvl 15 | Update |
| 5 | Commercial | 45 min | 6 | $25,000 | Company license | Update |

Starter house phases: Site prep (0–2) → Foundation (2–5) → Framing (5–9) → Rough-in (9–12) → Finish & inspection (12–15). Per-trade tasks per phase are in `PLAN.md` page 7.

## Launch features (only these ship at launch — everything else waits)
- **Onboarding:** drop-in first job; guided first job (arrows/tips, once); hub unlock after first payout.
- **Crews:** Quick Join; form a crew; bot workers; tap-to-ping crew chat (no typing); kick vote.
- **Roles (4):** Foreman (blueprint view, task pings, calls inspection), Laborer (carry, staging, nail-gun framing, cleanup), Operator (excavator, skid steer, crane), Electrician (panel, wire routing, fixtures). *Plumber and Concrete are updates.*
- **Building:** task engine (carry/place/timing/connect); ghost blueprints; quality score; inspection; collapse physics.
- **Jobs:** Tier 1 shed, Tier 2 starter house.
- **Chaos:** surprise inspector, rain delay (no pouring, mud slows vehicles), crane mishap.
- **Vehicles:** rusty single-cab starter truck; work pickup (more cargo).
- **Progression:** cash & payouts; per-trade levels.
- **Economy:** DataStore saving (cash, trucks, levels); server-side checks on every placement and payout.
- **Monetization:** dev products — rush delivery (whole crew), hire a pro, retry inspection, cash packs; game pass — 2× pay (buyer only).
- **Retention:** daily contract with streaks; codes; Roblox group reward.
- **Platform:** mobile tap controls & on-screen prompts; settings (graphics, sound, control layout).

Not at launch: Plumber, Concrete, tiers 3–5, oil rigs, extra chaos events, dually/custom trucks,
truck customization, tool upgrades, premium trucks/cosmetics, invite bonus.
(Companies + the company leaderboard were on this list; the owner pulled them in on 2026-11-12, see Roadmap status.
The owner also pulled in two more trades, Welder and HVAC, and a tool shop on 2026-11-13: 6 trades now.)

## Coding rules (non-negotiable)
1. **The server owns all money and all placement.** The client only *requests*; the server validates and applies.
   - Cash, XP, trade levels, unlocks, payouts, purchases and DataStore writes happen **only** in `ServerScriptService`/`ServerStorage` code.
   - Every Place/Carry/Timing/Connect result is re-checked on the server: right player, right trade, right phase, task not already done, part within tolerance of its ghost slot, player within reach distance, sane timing (rate limits / cooldowns).
   - Quality score, damage and the payout formula are computed on the server from server-side state, never from numbers the client sends.
   - Never trust client-sent amounts, prices, positions-as-truth, item IDs the player doesn't own, or "I finished" flags.
   - One deliberate exception (2026-11-12, owner complained driving felt bad): the player in a vehicle's driver seat gets
     network ownership so it drives without lag. The server still decides who may drive, and `VehicleService.guard`
     checks the distance every second (top speed x 1.25 + 12 studs, no jumps over 150, no flying up 30); a vehicle
     that breaks it goes back to its last good spot, server-owned, for 5 s. Nothing that pays or places trusts the
     truck's position more than before (dock / pad reach checks are unchanged).
   - Remotes take minimal, typed arguments; validate type and range of every argument; reject and log anything else.
   - Developer product grants go through a single `ProcessReceipt` handler that is idempotent (track receipt IDs) and saves before returning `PurchaseGranted`.
   - Economy numbers (prices, pay, tier unlocks) live in server-readable config modules; the client may read display copies but they are never authoritative.
2. **Every control works on mobile.** Design for touch first, then add keyboard/gamepad.
   - All actions are reachable by tap: `ProximityPrompt`s and on-screen buttons, never key-only or mouse-hover-only input.
   - Bind input with `ContextActionService` (with touch buttons) — never `UserInputService` keycodes alone.
   - Minigames (timing, routing, placing) must be playable with a single finger: tap / hold / drag.
   - Tap targets ≥ 44 px; UI uses `Scale`, `UIAspectRatioConstraint`, and respects `GuiService:GetGuiInset()` / safe areas; never covers the thumbstick or jump button.
   - Vehicles use on-screen throttle/brake/steer controls on touch devices.
   - Every new feature gets tested in Studio's device emulator (phone) before it's called done; real-phone test weekly.
3. **One task engine.** Trades reuse the four task types; bots use the same engine as players. No bespoke per-trade systems.
   (Machine tasks, owner 2026-11-12: excavator holes and crane lifts are done by hand with the machine's controls
   instead of a Timing tap; they're still blueprint slots graded by accuracy, and bots use the same controls.)
4. **Ghost blueprints only.** No freeform building tools ship.
5. **Scope:** build only Launch features until soft launch. Follow the roadmap gates in `PLAN.md`.
6. **Style:** Luau with `--!strict` where practical; ModuleScripts for logic, thin Scripts/LocalScripts as entry points; no globals (`_G`/`shared`); clean up connections; use `task.*` not `wait`/`spawn`.
7. **Studio MCP workflow:** inspect the place (`search_game_tree`, `script_read`) before editing; keep the Studio tree matching the folder structure below; playtest with `start_stop_play` and check `get_console_output` after changes.

## Roadmap status
- **Phase 1 — Paper design (done on paper 2026-11-07):** `design/StarterHouse_Job.md` has the minute-by-minute
  starter-house job, the shed job, the chaos windows, and the gate check (passes). The site sketch is in Studio at
  `Workspace.SiteSketch_StarterHouse` (anchored parts, no scripts).
  **Decided (owner, 2026-11-08):** until the Concrete and Plumber roles ship, the Operator runs the concrete chute and the Laborer screeds; Plumbing is an NPC sub the crew supplies with pipe. The driveway is gravel (Operator).
- **Phase 2 — Gray box (built 2026-11-08, gate NOT passed yet):** all four task types, ghost blueprints, the
  starter truck, and the 33-task shed job (Foreman, Laborer, Operator) run end to end in Studio: job board → build →
  inspection → payout ($934 on a perfect fast run). Cash is leaderstats only (no saving until DataService, Phase 3).
  Small-crew rule: if nobody holds a trade, anyone may do its tasks (bots replace this in Phase 3).
  Still to do before the gate: phone-emulator pass, then the gate itself — owner + 2 friends play 3 runs and want a 4th.

- **Phone truck controls (done 2026-11-08):** `VehicleController` shows big < > steer buttons, GAS and BRAKE/REV
  pedals and EXIT while seated on touch devices, and hides the default thumbstick/jump
  (`GuiService.TouchControlsEnabled`). Input goes through the `DriveInput` remote: driver-only, clamped, rate-limited.
  Studio check on desktop: set the workspace attribute `DevForceTouchUI = true`.
- **Town map (owner request 2026-11-08, plan in `design/Town_Plan.md`):** stage 1 terrain + roads DONE; stage 2 RV park +
  coffee + truck lot DONE; stage 3 four sites DONE; stage 4 session flow + filler buildings DONE (2026-11-08). The town plan is complete. Positions live in
  `Shared/Config/TownLayout`; the town is built by `ServerStorage/DevTools/TownBuilder` (edit-time only).
  Scope note: sites 3–4 (tiers 3–4) and the RV/coffee start aren't in the launch list above yet; confirm with
  the owner before giving them gameplay.

- **Awake buff (stage 2):** `BuffService` grants it at the RV park coffee counter (server prompt, 1.2 s hold, reach-checked).
  Effects: walk speed x1.15 (also while carrying) and a 25% wider Timing green zone; it ends when the next job ends.
  Hooks: `Carry.SetSpeedMultiplier`, `TaskEngine.SetTimingWidth`; no task-engine rewrite.
- **Prompts outside JobService** (coffee, later the loading dock and site board) register through
  `JobService.RegisterPrompt(pp, fn)` so `DevTrigger` tests and Phase 3 bots use the same path as a player tap.

- **Sites (stage 3):** `ServerStorage/Config/Sites` (authoritative: tier, job, yaw, release) + `Config/Jobs` (pay, deadline).
  Jobs start from the 4 buttons under the RV park site board; JobService builds the blueprint at the site's lot center,
  turned so the blueprint's front (local -Z) faces the road gate, and spawns the loaded truck in RV lot stall 1.
  Tiers 2-4 use `Shared/Blueprints/House` (generator: size + floors -> slots): Starter House 67 tasks,
  Two-Story 99, Luxury 139; Shed stays hand-made (33). Tier 3-4 sites start only in Studio (`Release = "Update"`).
  Site props come from `ServerStorage/DevTools/SiteBuilder`. The gray-box yard is retired (spawn is on the RV park
  camp lane until stage 4 adds per-RV spawns).

- **Session flow (stage 4):** `DataService` (DataStore profiles: cash, trade XP, FirstPayout; session lock; autosave;
  memory-only when Studio API access is off), `ProgressionService` (XP per task 10 x accuracy, +50 per job; level L
  needs 60(L-1)^2 XP; site unlocks by best trade level via `Config/Sites.MinLevel`), `DayNightService` (4:00 AM at
  the RV park, sunrise over the site's `DriveSeconds` once the truck leaves the park, morning light while working,
  NightLight/streetlights switch automatically), `SessionService` (first-timers drop straight into a Shed job at Site 1
  with a pre-loaded truck; first payout unlocks the RV start; returning players spawn at their own RV; after a job,
  everyone goes back to their RV for the next 4:00 AM shift).
  Loading: the truck spawns empty in RV lot stall 1; stop it under the LOADING canopy at Crew Supply (within 45 studs of
  the dock) and it loads itself (see "Driving, wheels, loading rework"; `Config/Jobs.Load`); loads bigger than the
  truck take several trips (see Work pickup below).
  Studio-only switches (workspace attributes): `DevReturningPlayer` (start as a returning player), `DevUnlockAll`,
  `DevForceTouchUI`, `DevChaos`, `DevCompanies`. Set them in Edit mode only for a test and remove them right after.
- **Filler buildings:** `ServerStorage/DevTools/FillerBuilder` builds `Workspace.Filler` (gas station, hardware store,
  6 houses) from the Filler lots in TownLayout, each facing its road.

- **Saved progress (2026-11-09):** profile v2 = Cash, XP for all 4 trades, FirstPayout, LastTrade (auto re-picked on join
  via `CrewService.TryRestore`), Stats (JobsDone, TotalEarned, BestGrade), Vehicles. Old profiles upgrade in place.
  Untested against real DataStores until Studio API access is enabled (Game Settings > Security).
- **Electrician (4th trade):** per floor: 4 outlet boxes (Place "Box") -> circuit (Connect) -> 2 ceiling fixtures
  (Place "Fixture"); after the roof: breaker panel (Place "Panel") -> Power on (Timing). Electrical piles stand on the
  right of each house with an ELECTRICAL sign. Shed: the work light is the Electrician's.
- **Heavy equipment (`EquipmentService`):** the excavator (drivable via `VehicleService.Register`, Operator only) digs every
  pier/post hole (`Equipment = "Excavator"`, within 14 studs); the mobile crane (60-stud luffing boom, Operator in its
  cab) lifts house roofs (`Equipment = "Crane"`, tiers 2-4). Equipment spots come from the blueprint's `Equipment`
  table. Since 2026-11-12 both are worked by hand and the crane drives in: see "Drivable crane + hands-on machine
  controls" below.
- **Detail pass:** crew truck rebuilt (~66 parts: cab, doors, glass, headlights with beams, grille, chrome, rust patches,
  plate) with a "Drive truck" prompt; RVs got caps, framed windows, A/C, ladder, lights, propane, hitch (~98 parts each).

- **Bot workers (`BotService`, 2026-11-09):** every trade no player holds gets a bot (2 Laborers on tiers 3-4), 8 s after a
  job starts; when a player picks that trade the bot clocks out (and back). Bots go only through JobService's bot entry
  points (`OpenSlotsFor`, `BotPickUp`, `BotPlace`, `BotBegin/BotFinish/BotAbort`, `BotDeliver`), which apply the same
  slot checks as a player's tap, and score with the engine's own `TimingTask.JudgeAt` / `ConnectTask.Accuracy`.
  Slower (75% walk speed, pauses, slow wiring) and they miss sometimes (tap error), which lowers the job grade a bit.
  Bot Operators run the excavator (steered through `VehicleService.Drive`, the pedal input path) and the crane, and
  drive the truck onto the pad only when it is already at the site; loading at the dock and the drive from the RV
  park stay with players. Bots are never paid and get no XP. R15 rigs in the trade color with a hard hat.
  `Carry` accepts any worker (Player or bot Model); bot speed comes from the model's `SpeedScale` attribute.

- **Chaos events (`ChaosService`, 2026-11-09):** 1 event per job, 50% chance of a 2nd, planned at job start from what the
  job has (Rain needs pours, Crane mishap needs a crane, Inspector always). First-timer drop-in jobs get none.
  * **Rain delay:** starts the moment the first pour opens or anyone reaches for one (`Chaos.Blocks`). 45 s of no
    pouring (players get a toast, bots skip pours), mud cuts every vehicle's top speed to 60%
    (`VehicleService.SetSpeedFactor`), darker sky (Lighting/Atmosphere/Clouds, restored after). Clients read
    `workspace.RainUntil` for the rain particles and the countdown banner (`RainController`).
  * **Surprise inspector:** at 50% of the blueprint an NPC inspector (`BotService.MakeBody`) walks to the worst work
    (task accuracy < 0.85, max 4; machine tasks excluded) and red-flags it. Each flag adds a `fix_<id>` Timing task for that
    trade; fixing it sets that task's accuracy to 0.9 and removes its fine. Each unfixed flag costs each paid player 5%
    of base pay; the payout panel shows "Inspector fines".
  * **Crane mishap:** the next crane lift swings, slips and drops its load beside the house (`EquipmentService.FinishWork`
    `onMishap`). The roof waits on a new `restack_<id>` Laborer task (per-slot `extraRequires`, the blueprint defs are never
    changed); the mishap records 0.4 accuracy in the grade.
  * Rework tasks are added with `JobService.AddSlot(def, cf, cleanup, onDone)` (built by `BlueprintService.AddSlot`), so
    bots and players do them through the normal slot rules.
  * Studio-only switch: workspace attribute `DevChaos` = `"All"` or e.g. `"Rain,Inspector"` forces events (also on drop-ins).
  * Playtested 2026-11-09 (chaos) with bots + one human Laborer: Starter House with all three (rain 45 s, 4 flags left unfixed
    -> -$300, crane drop -> re-stack -> roof; A, $2,417); Shed with flags fixed (A+, $909, no fines); truck 21.5 vs 35.9
    studs/s in rain vs dry.

- **Work pickup + truck dealer (2026-11-09):** `ServerStorage/Config/Vehicles` (authoritative): rusty starter truck holds
  **4** bundles, Work pickup holds **8** and costs **$3,000**. Job loads are now Shed 3, Starter House 6, Two-Story 8,
  Luxury 8, so the starter truck makes 2 trips for a house and the pickup 1.
  * Trips (`JobService`): each trip must be a full truck (or whatever is left); the first unload of an item makes its
    pile, so the crew can start building after trip 1; the Deliver slot completes when the whole load is at the site.
    The dock refuses bundles that are no longer needed, and the truck refuses loading past its capacity.
  * Dealer (`DealerService`, built at runtime on `Stall_6`): showroom pickup (`VehicleService.BuildDisplay`), sign, and
    a kiosk prompt. Opens after the first paycheck. One tap: buy (`EconomyService.TrySpend`, then `DataService.GrantVehicle`
    and a save) or switch the truck your jobs use. `DealerController` (client) only rewrites the prompt text from the
    player attributes `Trucks` / `Truck` / `RVUnlocked`.
  * The job's truck is the starting player's selected truck (`DataService.SelectedTruck`); drop-ins use the starter
    truck. Sites 3-4 have `Truck = "WorkPickup"` in `Config/Sites` ("trade lvl 8 + mid truck"): starting them needs it.
  * Profile v3 adds `Truck` (selected kind); `Vehicles` holds what's owned. Both truck kinds share `VehicleService`
    (`SpawnTruck(cf, parent, kind)`, per-kind cargo layout and capacity, model name `CrewTruck`, attribute `TruckKind`).
  * Playtested 2026-11-09: starter truck Starter House = 2 trips (5th bundle refused, empty/partial unload refused,
    piles after trip 1); buy at $0 refused, buy at $3,500 -> $500, switch both ways free; pickup = 6 bundles in 1 trip,
    no cargo clipping; pickup drives at 36 studs/s; Site 3 refused without the pickup.

- **Real vehicle models (2026-11-09, owner chose AI-generated over Creator Store):** original, unbranded meshes made with
  Studio's `generate_mesh`, fitted per axis to each rig and stored in `ServerStorage.VehicleModels` (pivot = the rig's local
  origin, front = -Z): `StarterTruck` (rusty red pickup), `WorkPickup` (white work pickup, orange stripe, light bar),
  `Excavator` + `ExcavatorArm`, `CraneCarrier` + `CraneBoom`.
  * The part-built rigs still do everything (physics, hitboxes, seats, prompts, cargo spots); `VehicleService.Skin` clones the
    look on (no collision, massless, welded or anchored) and `HideBuilt` makes the old parts invisible. No model in the
    folder -> the part-built look stays, so nothing breaks if one is deleted.
  * Moving parts: the arm mesh is welded to ArmRoot (pivot = the body model's `ArmHinge` attribute, so it bends at the mesh's
    own hinge); the boom mesh is in the boom list (swings + luffs). `CraneCarrier` attributes `TurretOffset`, `BoomPivot`,
    `RestLuff` (0.06: the boom rests stowed flat over the cab, matching the mesh) override the crane constants.
  * Known look issues: the crane mesh's lifting strut is part of the carrier, so it stays folded while the boom is up; a
    stowed hook in the boom mesh shows as a dark block near the boom foot. Fix by regenerating the crane in more pieces.
  * Bot fix found while testing: when the bot's drive is blocked it now re-places the machine upright on a clear spot
    (overlap check, 12 candidates around the target) instead of dropping it onto placed posts (the excavator tipped over).
  * Playtested 2026-11-09: Starter House with skinned truck (2 trips), excavator (all holes, stays upright), crane (roof
    lift); A+, $2,749. Saving the place keeps the meshes (the assets are published to the owner's account).

- **Look + guide pass (2026-11-10):**
  * Lighting retuned (warm sun, soft shadows, atmosphere haze, bloom, sun rays, DoF, `Lighting.Grade` color correction,
    clouds, terrain grass). `Lighting.Technology` can't be set through the MCP (capability error): the owner sets Future.
  * Bots (`BotService.MakeBody`): real Shirt/Pants templates (tinted toward the trade color), faces, the mesh hard hat
    (trade color) and an occasional beard from `ServerStorage.NPCs.BotKit` (harvested from free models, scripts removed),
    and server-side idle/walk animations (Roblox default R15 ids).
  * `GuideController` (client): hint bar under the status bar + yellow beam, outline and distance arrow to the next step,
    plus a screen-edge arrow when the target is off-screen. Worked out from the job state, `Carrying`, the seat, and prompt
    attributes (`Kind`, `Item`, `Equipment` on slot prompts; `Machine` on machine prompts; `LoadTruck` on the truck bed).
    It sends the player only to their own trade's tasks or trades with no bot. First-time players (no paycheck) get a
    "How it works" card. GUIDE button toggles it. Toasts moved down to y=100 to make room.

- **Crew Supply store (2026-11-10, owner chose free pickup):** `Workspace.SupplyStore`, built by
  `ServerStorage/DevTools/SupplyStoreBuilder` (edit-time) in front of the hardware store (lot "Hardware", Main St).
  Drive-in LOADING canopy, raised `Dock` (truck within `DOCK_REACH` 30 of its center), 4 pallet stacks (`MaterialStack`
  Lumber x2, Sheet x2), lumber/sheet racks, pallets, street pylon, NightLight lamps. JobService hooks the store's stacks and
  Dock at Start; the old RV park `LoadingArea` is in `ServerStorage.Archive` (with the hardware lot's old parking lines,
  cart corral and light poles). Re-running FillerBuilder would bring those back: archive them again.
  Playtested: grab works anywhere, loading refused with the truck at the RV lot, 3/3 loaded under the canopy, delivered.

- **Forest + textures (2026-11-10):**
  * `ServerStorage.Nature.Pines`: 12 PBR Ponderosa pines from a free Creator Store pack (no scripts), pivots moved to the
    trunk base, attributes `Height`/`Radius`. `ServerStorage/DevTools/NatureBuilder` scatters them into `Workspace.Nature`
    (seeded, 34-stud grid, clear of roads + sidewalks + every lot + existing parts, on the terrain, denser away from roads,
    scale 1.6-2.6, no collision except an invisible `TrunkCollider`): ~4,200 trees. `Workspace.YardPines` replaced the 14
    old ball trees (originals in `ServerStorage.Archive.BlobTrees_old`). Watch phone performance; lower density if needed.
  * AI-generated MaterialVariants in MaterialService: CoopRoad, CoopShingles, CoopBrick, CoopSidewalk (set as base-material
    overrides for Asphalt, RoofShingles, Brick, Concrete, so terrain roads and built houses use them too), CoopSiding
    (filler house walls/gables, WoodPlanks), CoopMetalSiding (site trailer bodies/roofs). Hardware store walls are Brick.
  * `Workspace.Decor`: oil-stain decals (free, original uploads; skip assets ripped from other games) at the RV lot stalls,
    the Crew Supply lane and the gas pumps.

- **Mountains (2026-11-10):** `ServerStorage/DevTools/MountainBuilder` fills a Terrain ring 1,400 studs wide outside
  `TownLayout.Bounds` (16-stud columns, ridged noise, peaks ~300-800 studs, rising over 520 studs from the town edge):
  grass foothills < 120, dirt < 200, rock < 470, snow above. Columns are a 64-stud shell, not solid (memory). The town is
  untouched. `NatureBuilder.BuildSlopes()` adds ~820 pines on the grass/dirt slopes (`Workspace.Nature.Slopes`).

- **Final inspection + collapse (`InspectionService`, 2026-11-10):** tapping the Inspect slot no longer pays at once:
  an inspector NPC walks the building's corners (footprint from the finished slots) and stops at weak work (accuracy
  < 0.75, worst 5, no machine/paperwork/rework tasks). Each weak piece and the finished pieces that `Requires` it collapse
  (unanchored with an impulse, max 8). 6% of base pay per weak piece comes off the pay of the player who built it
  (`QualityService.RecordOf`); bot work costs nobody. Then `finish(true, damage, fallen)`; the payout panel shows the
  collapse line. `cur.inspecting` pauses the deadline and shows phase "Final inspection". Playtested: Shed with 4 sloppy
  pours -> 8 pieces fell, -$120 for the human Laborer, $762 paid.
- **Crew tools (`CrewService` + client `CrewController`, 2026-11-10):** QUICK JOIN (server picks the trade the crew needs,
  last trade first), Foreman-only job start when a player is Foreman (`CrewService.CanStartJobs`), PING with 4 presets
  (marker at the camera's aim point, <= 300 studs from the sender, 1.2 s rate limit, `PingShown` to all), CREW panel with
  KICK (Foreman: instant; others: vote, need max(2, half of the others + 1)). Remotes `QuickJoin`, `Ping`, `KickVote`,
  `PingShown`. Kick and the Foreman-only start rule need 2+ real players to test (not tested yet).

- **Full game test (2026-11-11), all in Studio with bots + one scripted human:**
  * Passed: first-timer drop-in (job in 4 s, How-it-works card, Shed A $902, first paycheck -> RV unlock -> back at RV 1 at
    4:00 AM); returning flow (coffee Awake x1.15 speed, Site 2 locked at Laborer 2, "New job site unlocked" at level 3,
    loading refused away from Crew Supply, sunrise when the truck leaves the park, bot Operator drives the truck onto
    the pad); Starter House with all chaos forced (2 trips, rain 45 s, 4 inspector flags unfixed -$300, crane drop +
    re-stack, final inspection 8 pieces fell, -$270 for the human's 3 weak pours, $2,113 = panel math); dealer (refused
    at $2,113, bought at $3,500); Two-Story (pickup 8 bundles 1 trip, both roofs, A+ $7,285); crane reach on tiers 3-4
    (worst 52.8 of 57); pings (rate limit, bad kind, out of range rejected); 15 kinds of bad/spammed remote input
    rejected, no errors; all 24 buttons >= 44 px on a phone-size estimate; phone drive pedals shown; 60 fps / 60 Hz.
  * Fixed during the test: (1) bots got stuck seated after touch-seating a machine -> `leaveSeat` also clears an
    accidental `SeatPart`, `sitIn` unseats first; (2) the excavator was left inside the house footprint after the last
    hole and got wedged on the floor -> the bot parks it at `rig.home` (EquipmentService) and climbs out;
    (3) QUICK JOIN switched a player who already had a trade (and clocked out a bot) -> now it only gives a trade to
    players without one.
  * Not testable here: kick votes and the Foreman-only start (need 2+ real players), DataStore saving (Studio API access
    off), real-phone performance (~9.5k parts streamed on the client, 5k of them pine meshes).
  * Follow-up fixes (owner: "fix them", 2026-11-11): final inspection only collapses structural work a player built
    (`InspectionService.structural` excludes the level check, Power on and wiring; `builtByPlayer` skips bot work, whose
    misses already lower the grade); guide says "Tap Pick trade" and has its own lines for "Final inspection" and
    "Finished"; the status bar says "Unload the truck at DELIVERY" when the loaded truck is already at the site
    (drop-ins). Re-tested: drop-in Shed, 2 weak human pours -> exactly 2 pieces fell (-$60), no bot work fell, $839.
  * Still open: AI texture warnings ("No asset content representation") on 4 vehicle textures until Roblox finishes
    processing them (not a script issue).

- **RV park spawn for everyone (2026-11-11):** `SessionService` no longer starts drop-in jobs (JobService still supports
  `dropIn` if it's ever wanted back). Join -> own RV (returning) or the camp-lane SpawnLocation (first-timer); respawn
  during a job you've worked on -> its site; job cleared -> everyone back to the park. A site button whose site is
  running gives a ride there (`JobService.hookSiteButton`, refused while carrying or mid-task); other site buttons say
  where the crew is. `GuideController` tells a player far from a running site (after delivery) to ride out.
  `Job.Started` now fires (siteId, dropIn, firstJob); ChaosService plans no chaos when firstJob.
- **Sound (2026-11-11):** `Shared/Config/Sounds` (ids, volumes, group). `Net.Cue(name, pos)` on the server fires the
  `Sfx` remote: JobService (task done: Hammer for Timing work, Place for placed pieces / delivery / crane lifts, Spark for
  electrical; Place on loading; CrashMetal on a crane drop), InspectionService (Whistle at the start, CrashWood per
  collapse), ChaosService (Whistle when the inspector arrives). Client `SoundController`: SoundGroups Music / Effects /
  Ambient (x Master), engines on DriverSeat / OperatorSeat / CraneSeat while occupied (pitch 0.85-1.4 with speed; crane
  follows its hook), birds by day / crickets at night / rain + thunder during RainUntil, APM music playlist, Miss on
  a missed tap, Cash on payout, Chime on level-up, Ping on toasts (throttled), Click on every button (not the pedals).
  Sources: ProSoundEffects + APMOfficial (licensed by Roblox), two public uploads, rbxasset sounds; all load-checked.
- **Settings (2026-11-11):** SETTINGS button under GUIDE -> panel: Master / Music / Effects / World volume (10% steps),
  Graphics Low / Medium / High ("Auto" until chosen = Medium on touch-only devices), Drive buttons Right / Left hand,
  Button size Normal / Large (1.3x). Saved in profile v4 `Settings` via the `SaveSettings` remote (DataService keeps only
  known keys, clamps volumes, rejects bad values, 0.5 s rate limit) and sent back as the player's `Settings` attribute.
  Graphics apply on the client only: Low = no shadows / bloom / sun rays / DoF, 30% of the forest; Medium = shadows +
  bloom, 60%; trees are thinned by a fixed hash of their position (same trees every visit, re-applied as they stream
  in); rain particles 300 / 600 / 900. Pedals: EXIT now sits above the brake; PING/CREW hide while driving on touch.
  Playtested: first-timer at the camp lane at 4 AM (crickets + music), settings save + junk rejected + applied live
  (5,053 -> 1,466 trees on Low, pedals mirrored and 1.3x), first job chaos-free, load cues, engine pitch 0.90 -> 1.40,
  ride-out button + guide hint, respawn at the site, 10 hammer + 12 place cues while building, no script errors.

- **Companies + leaderboard (owner request 2026-11-12; was post-launch in PLAN.md, owner pulled it in):**
  `CompanyService` (server) + `CompanyController` (client). Owner rule: players with people **found** a company (type a
  name) and **invite** them; players without a crew **ask to join** a company from FIND and a member **accepts**.
  * Records in DataStore `Companies_v1` (`{Id, Name, Owner, Members{uid={Name,Joined,Points}}, Requests, Score, Jobs}`),
    ranks in OrderedDataStores `CompanyScores_v1` (points) and `CompanyActive_v1` (FIND = recently active with room).
    No DataStores (Studio) -> memory for this server. A failed read never removes anyone (`getRecord` returns readOk).
  * Names: 3-24 chars, letters/numbers/space/- & ' . only, then the Roblox text filter (any change = refused).
    Max 12 members; owner can REMOVE; last one out closes the company; the owner leaving passes it to the oldest member.
    Invites live 120 s in this server; requests are answered from any server and reach the requester on the next
    30 s refresh or their next join (`reconcile`). Profile keys `CompanyId`, `CompanyRequest`.
  * Points: `JobService.finish` calls `Company.AddJob(paidPlayers, BasePay, grade)`: each paid member adds
    BasePay/10 x grade (A+ 1.5, A 1.25, B 1, C 0.75, D 0.5). Titles: Startup < 500 < Local Contractor < 2,500 < Builder <
    10,000 < Regional Builder < 40,000 < Construction Empire. Top 20 on the COMPANY panel; top 10 on the runtime sign
    `RVPark.CompanyLeaderboard` (first clear spot by the coffee stand). Leaderstats column `Company`.
  * Remotes `Company` (action, a, b; per-action rate limits, unknown actions ignored) and `CompanyData` (Mine / Board /
    Find / Invite). Client button: left column under CREW, says **TEAM UP** with a gold outline until you're in one.
  * Studio-only switch `DevCompanies` seeds 4 sample companies (memory mode). Remove after the test.
  * Playtested: bad names refused, found / second found refused / leave / request / cancel / junk ids and 30 junk
    actions ignored, FIND right after opening the panel, Shed A+ -> +75 points -> rank 5 of 5, sign shows the board.
    Not testable with one player: invites, accepting a request, kick (need 2 real players), DataStore mode.
- **Lively town (2026-11-12):**
  * `ServerStorage/DevTools/LifeBuilder` (edit-time, `require(it).All()`) built `Workspace.TownLife`: Props (benches with a
    `BenchSeat`, bins, hydrants, mailboxes; 57) and ParkedCars (driveways, gas pumps, hardware lot; 11), every spot
    overlap-checked. Templates: `ServerStorage.PropModels`, `ReplicatedStorage.TownCars` (Sedan, Hatchback, Minivan,
    SUV: anchored invisible `Root` PrimaryPart at the bottom center, front -Z, `Headlight` Glass parts with SpotLights,
    `Taillight` Neon). All AI-generated meshes. Fixed after the first build: the ground ray now starts 8 studs up (it
    landed 4 cars on the gas station canopy) and props are lifted by template pivot - bbox bottom (they were half buried).
  * `TownLifeService` (server): 6 sidewalk walkers (Main St, Oak Ave), 2 regulars at the coffee stand, 2 people on
    benches. Built with `BotService.MakeBody(name, shirt, nil, at)` (nil hat = no hard hat), attribute `Townsperson`,
    folder `Workspace.Townsfolk`. They never touch jobs.
  * `TrafficController` (client only, folder `Traffic_Local`): cars on the right-hand lane (7 off center, 26 studs/s) on
    the town loop both ways plus out-and-back runs on Main St, Ridge Rd and Oak Ave/Hilltop Dr. They stop for players,
    townsfolk, bots and the crew truck / excavator in a `JobSite_*` (and each other; 4 s deadlock timeout), headlights
    at night, quiet engine in the Effects group, count by Graphics (Low 5 / Medium 9 / High 13), hidden past 700 studs.
    Playtested: a car stopped ~12 studs (center to center) from a player standing in its lane.
  * Left column moved to the screen middle so it fits a landscape phone: Pick trade (0.5,-78), QUICK JOIN (0.5,-47),
    CREW (0.5,5), COMPANY (0.5,57). Guide hint says "Pick trade (left side)".
- **Driving, wheels, loading rework (2026-11-12, owner: "the driving is just ass, the wheels dont spin, loading is
  akward"):**
  * Driving: `VehicleService.setOwner` gives the driver network ownership (model attribute `DriverId`); the drive model
    runs in `VehicleController.driveStep` (Stepped): eased throttle (0 -> 36 in ~2 s), coasting, hard braking then
    reverse, steering that eases in with less lock at speed (34 deg slow -> 11 deg fast), car-like turning
    (yaw = v x tan(angle) / wheelbase; tracked machines turn on the spot), and the real velocity caps the model's
    speed so walls take speed off. Limits ride on model attributes (MaxFwd, MaxRev, Accel, Brake, Turn, Wheelbase,
    SpeedFactor = mud). Bots and empty vehicles stay server-driven as before. Guard: see coding rule 1.
  * Trucks ride on 4 invisible frictionless `RideBall`s at the wheels (the flat `Skid` no longer collides), so curbs and
    bumps don't stop them dead.
  * Wheels: the AI wheel mesh was split with `segment_mesh` into `Wheel_FL/FR/RL/RR` in `ServerStorage.VehicleModels`
    (StarterTruck, WorkPickup). The skin hangs them on `WheelMotor` Motor6Ds (attributes Front, Radius) and tags the
    truck `SpinWheels`; client `WheelController` rolls them by distance moved and steers the fronts (own truck from
    `LocalSteer`, others' from their turn rate). Motor6D.Transform is client-local: looks only.
  * Loading: with the truck parked under the LOADING canopy, holding a Crew Supply stack (0.5 s) loads every bundle of
    that kind the trip still needs; they fly into the bed one by one (each still counts as the player's task). With the
    truck elsewhere the stack says to park it first. Carrying a bundle and tapping the bed still works.
  * Playtested: 0 -> 36 studs/s in ~2 s, full-speed 90 deg turn without stalling, over a 0.6-stud curb, stop from top
    speed in ~1 s, reverse at 14; a faked 200-stud client teleport was caught and put back, ownership returned after
    5 s; wheels roll and the fronts steer; Shed load = 2 holds (Lumber x2, Sheet x1). Not tested: a player driving the
    excavator (now client-driven too), real phone feel, the 2-player view of someone else's wheels.
  * Follow-up (owner: "it dont let me get out the car and the loading is way to hard"):
    - Getting out: jumping out bounced players off the cab roof back onto the seat (seats grab whoever touches them).
      `VehicleService.placeOutside` now puts a player who leaves the seat on the ground beside the driver's door (else
      the other side, else on the roof) and disables the seat for 1.2 s. Keyboard/gamepad drivers also get an
      on-screen "EXIT (Space)" button (bottom-right); touch keeps EXIT above the brake.
    - Drive-through loading (`JobService.driveThrough`, every 0.4 s): the job's truck stopped (< ~3 studs/s for ~1 s)
      within `DOCK_REACH` (now 45) of the Crew Supply dock gets everything this trip needs loaded from the stacks, no
      button. The driver (else the nearest player within 60) gets the task credit. Holding a stack still works.
    - Playtested: jump out -> standing 5.4 studs from the seat and stays out; truck stopped 18 studs from the dock ->
      Shed load (Lumber x2, Sheet x1) on board in 3 s, status moved on to "Drive to Site 1", no errors.
  * Faster trucks + speedometer (owner, 2026-11-12): `VehicleService` TRUCK_SPEC maxFwd 58 / rev 18 / accel 26 /
    brake 60, PICKUP_SPEC 68 / 18 / 30 / 64 (the pickup is now the faster upgrade too). Steering lock for wheeled
    vehicles = min(34 deg, atan(MAX_YAW 0.9 x wheelbase / speed)), so the turn rate never passes ~52 deg/s at any
    speed. `VehicleController` dash (`DriveControls.Speedometer`): MPH (1 stud = 1 foot: 58 -> 40, 68 -> 46), gear
    D / N / R, bar vs top speed (green -> orange), "MUD: SLOW" tag when SpeedFactor < 1; bottom center, moved above the
    pedals when the phone is too narrow (Large buttons). Playtested: 0 -> 40 mph in ~2.7 s, steady turns at top speed,
    stop in ~1.2 s, reverse 12 mph, no guard trips. The pickup's 68 is untested in play; the dealer sign doesn't
    mention speed yet. Drives to site got shorter (the < 60 s rule still holds).
- **Unlock progress (2026-11-12, owner couldn't tell how to reach Site 2):** sites unlock by best trade level
  (Site 2 = level 3 = 240 XP in one trade; XP = 10 x accuracy per own task + 50 per paid job; bot work gives none).
  `ProgressionService.publish` adds player attributes NextSiteTier / NextSiteLevel / NextSiteXP (lowest locked site
  playable here; Studio counts Update sites) and ProgressTrade / ProgressXP (the trade with the most XP).
  `SiteBoardController` draws a bar on that site's LOCKED cover ("Level 3 in any trade", "Laborer 30 / 240 XP"; no
  trade name at 0 XP); `AwardJob` toasts "Site N unlocks at level L in any trade: your <trade> is at X / Y XP".
  Playtested: 0/240 at start, 30/240 after drive-through loading, Shed ($920) -> Laborer 3 -> Site 2 opened, toast and
  bar moved on to Site 3 (270 / 2940). Reminder: Studio profiles are memory-only, so progress resets every playtest.
- **Drivable crane + hands-on machine controls (2026-11-12, owner: "i wish the crane could be driveable and we could
  control the movements of the crane and digger"; chose full manual with a guide; houses' looks come next):**
  * Crane arrival: `EquipmentService.SpawnFor` (excavator first) puts the crane on its wheels 32-48 studs from its
    glowing `CranePad` (the blueprint's crane spot), facing it, trying the road side then the other sides, and only
    where both the crane and its lane to the pad are clear (the staging lumber/sign blocked the first try). No room ->
    it spawns set up on the pad (old behaviour). While driving, every part is welded to `Carrier`, low parts don't
    collide, 4 `RideBall`s (`VehicleService.AddRideBalls`) carry it, and it's a VehicleService vehicle ("Drive crane"
    at `DriveCab`, Operator only, 28 studs/s, Wheelbase 15.5). Standing still within 7 studs of the pad for 1 s (or the
    pad's "Set up crane here" prompt) runs `setUp`: level, anchor, drop the drive welds/balls, recompute `frame`, put
    the driver on clear ground beside it, destroy the drive seat, enable the crane cab. Model attribute `Mode`
    (drive / setting / set).
  * Controls: remote `MachineInput` (a, b, c in -1..1; seated operator only; 40/s). Crane: swing 0.5 rad/s (+ right),
    boom luff 0.28 rad/s within 0.2-1.35 (+ up), hook 7 studs/s (+ up); the hook / load can't go into the ground or
    through the roof unless lined up (`craneLimits`). Excavator: arm 0.9 rad/s within -0.55..0.45 (+ up); driving is
    the normal vehicle drive. Client `MachineController`: crane buttons < SWING > (bottom-left), BOOM / HOOK up-down
    columns (bottom-right), EXIT; keys A/D, W/S, R/F (ContextActionService, sinks them while seated). Excavator: ARM UP
    / DOWN above the steering buttons, keys R/F. Info panel under the hint bar (hint + "X studs off"), plus a glowing
    target column/ring and a marker straight under the hook/load/bucket that turns green when lined up (local only).
  * Tasks (`BeginManual`, replaces the Timing tap for equipment slots, players and bots): Dig = bucket bottom
    (`Bucket` part - 0.8) goes below y -0.3 within 3 studs of the hole and back above 1.2, 3 times (dirt mound grows);
    Lift = lower the hook onto the `RoofSection` laid on clear ground ~20 studs from the crane (hooks within 2.5 studs,
    0.6 above it), then set the load within 2.5 studs of the roof slot and 0.9 of its height (sets down by itself).
    Grade = 1 - 0.5 x error / tolerance (0.5..1). Leaving the seat cancels the task. Crane mishap (chaos) still drops
    the load on release. Model attributes for the client: Session, TargetPos, Hint, Err, Scoops, ScoopsNeed.
  * Bots: `EquipmentService.Autopilot(rig, alive, aim 1.4 studs)` drives the same `SetInput` (crane: pose by
    `poseFor`, stays high while swinging; excavator: drives to a digging spot 10.6 studs from the hole, backing off
    first if it's sitting on it, faces it, then down/up). BotService `operate` drives the crane onto its pad first.
    Tracked machines now turn on the spot in the server drive too.
  * Getting out of the crane cab puts the player on the ground beside the carrier (cab is up on the turret).
  * Playtested: hand dig (3 scoops, 0.5/0.4/0.1 studs off); human drove the crane 48 studs onto its pad (2.9 s) ->
    set up, driver on the ground; cab controls (boom up, swing, hook stops at the ground); bot Operator dug all 10
    holes and drove/set up/lifted the roof (Starter House A, $2,709); human lift by controls hooked in 7.9 s and set
    the roof at 11.1 s (job A, $2,698). Seen once, not reproduced: the player popped out of the crane cab while
    working the controls. Not tested: a crane mishap during a hand lift, the button layout on a real phone, Two-Story
    (2 roofs).
- **Small details + better-looking buildings (2026-11-12, owner: "its all about the small details like the tracks on the
  digger and crane make them move ... the houses and the sheds look basic"):**
  * Tracks: the excavator is tagged `SpinTracks` with TrackGauge / TrackY / TrackLength / TrackHeight / TrackWidth
    (measured from the mesh's `crawler_tracks`); client `TrackController` draws 30 tread plates per side in a loop
    around each track and rolls them by the real movement (left/right separately: opposite ways when it turns on the
    spot). Looks only (`Tracks_Excavator` folder, client-side, BulkMoveTo, skipped past 250 studs).
  * Crane wheels: the carrier mesh was split with `segment_mesh` (body + 4 axle meshes `Wheel_A1..A4` in
    `ServerStorage.VehicleModels.CraneCarrier`); `spawnCrane` hangs them on `WheelMotor` Motor6Ds (Front = false) and
    tags the crane `SpinWheels`, so WheelController rolls them while it drives.
  * Excavator rides on 4 frictionless ride balls (its skid no longer collides): it rolls over footings/pours and turns
    freely. Its autopilot accepts a slightly-off line-up after 6 s (still within reach of the hole).
  * `DetailService` (server, in the boot ORDER after BlueprintService; JobService.complete calls `OnDone`): per job a
    palette (5 house / 3 shed). Walls -> siding color + CoopSiding variant, skirt + frieze boards, a window on walls
    >= 5 long (glass, muntins, trim, sill, shutters on houses); the walk-through segment -> door (panels, knob, porch
    light on houses; X-braced barn door on the shed) with frame and a concrete stoop. Nail markers go invisible once
    nailed. Last sheet on a roof deck -> pitched roof over it (two RoofShingles slopes, ridge along the long side,
    siding gable wedges with a vent, ridge cap, fascia, gutters, corner downspouts with elbows, brick chimney on
    houses). All decor is welded to its slot part, unanchored, non-colliding (falls with it on a collapse).
  * Playtested: tracks roll forward/back and counter-rotate on a turn (plates line up with the mesh: 8.45 x 2.63);
    crane axles roll while driving; Starter House dressed (screenshot: siding, shuttered windows, red door + stoop,
    shingle roof, chimney, gutters) A $2,712; Shed (green barn shed, X door, window, shingle roof) A $906; no errors.

- **Welder + HVAC trades, better mini-games, tool shop (owner request 2026-11-13: "build the welding trade, a tool shop,
  and all the beter mini games and the hvac"). Scope change: 6 trades now, not the 4 launch roles in PLAN.md.**
  * Two new task kinds in the one task engine (bots use them too):
    - **Trace** (`TaskEngine/Trace`, client `TaskControllers/Trace`): weld a seam on a steel plate with one finger /
      the mouse, from the green START to the red END. Seam from `Shared/Util/TracePath` (zig-zag, steps or curve). The
      client sends its samples (flat x, y, t; max 280) through `TraceSubmit`; the server judges: start near START, no
      skipping > 25%, reach 92%, < 20% of samples more than 2 tol off, no jumps > 4.4 panel widths/s, not faster than
      the seam allows, not claiming more time than has passed. Accuracy = 1 - 0.5 x mean distance / tol (0.45..1).
      A bad weld = a miss with the reason on screen and a new seam.
    - **Gauge** (`TaskEngine/Gauge`, client `TaskControllers/Gauge`, math in `Shared/Util/Gauge`): HOLD to raise the
      needle, let go and it falls; keep it in the green until the bar fills. The client only sends held / let go
      (`GaugeHold`, 30 per second budget); the server replays the times with its own clock (latency capped at 0.2 s).
      Styles: Pour (concrete form filling), Level (bubble; eased 2026-11-13 to rise 0.55 / fall 0.4 / band 0.16 after
      a simulated 0.18 s-reaction player only scored 0.53), Charge (refrigerant pressure), Voltage. Accuracy drops
      when you slip out after getting in (0.5..1); out of time = a miss and a new round. Hold key: Space / gamepad A
      (`Input.BindHold`).
    - Timing `Hits`: nailing is 3 taps in a row ("Nail wall 2/3"), the green shrinks a bit each hit.
  * Blueprints: pours -> Gauge Pour, level check -> Gauge Level, Power on -> Gauge Voltage, nails -> 3 hits.
    **Welder** (Max 2, orange): House = plates on the 4 corner piers (before the level check), 2 brackets per roof
    section, 2 stair rails at the end; Shed = 2 door hinges + a roof bracket. **HVAC** (Max 2, teal): per floor 2 ducts
    (Place "Duct") -> route the ductwork (Connect) -> 2 floor vents (Place "Vent"); after the roof + vents: AC unit
    (Place "ACUnit", DetailService dresses it: fan grille, fins, pad) -> Charge refrigerant (Gauge Charge,
    `NotStructural`, so inspection never collapses it). HVAC piles stand behind the house (Duct / Vent / ACUnit).
    The Shed has no HVAC work. Bots: Trace 4-8 s at 0.66-0.95, Gauge need + 2-4.5 s at 0.7-0.96, Timing averages
    its hits. The trade picker is now a 2 x 3 grid (buttons 263 x 93 on a desktop window).
  * **Tool shop** (`Workspace.ToolShop`, built by `ServerStorage/DevTools/ToolShopBuilder`, south side of Main St at
    x 240, z -468, facing the road; counter at (240, 2.3, -472)). "Browse tools" at the counter -> `ToolShopController`
    panel (BUY $X / OWNED, closes past 24 studs). `ToolShopService` checks every buy: a real catalog id, at the counter
    (20 studs), not owned, `EconomyService.TrySpend`, then `DataService.GrantTool` + save; 0.4 s rate limit. Catalog
    (authoritative) `ServerStorage/Config/Tools`: Pro Framing Hammer $1,200 (timing x1.2), Laser Level $1,500
    (gauge:Level x1.35), Concrete Vibrator $1,500 (gauge:Pour x1.35), Auto-Dark Welding Helmet $1,800 (trace x1.3),
    Digital Manifold Gauges $1,800 (gauge:Charge x1.35), Insulated Lineman's Pliers $1,400 (connect x1.5,
    gauge:Voltage x1.25), Precision Joysticks $2,200 (machine controls x1.3). Tools only widen the green / give more
    room or time; they never do the work (monetization rule). `TaskEngine.SetBonus(fn(p, what))` is the hook.
  * Profile v5: XP for Welder and HVAC, `Tools` = { [id] = true } (player attribute `Tools` = comma list).
  * Playtested 2026-11-13: shop (refused at $0, bought 2 tools, refused re-buy / junk ids / spam / away from the
    counter, panel closes when walking off; Economy log matches); Shed as a human Laborer (4 Gauge pours ~4.2 s each
    with the Vibrator's 0.189 band, 3-hit nails, Welder bot did the hinges + bracket; A, $896); Starter House as a human
    Welder (8 traces, 2.9-4.2 s each, helmet tol 0.0715; HVAC bot did ducts, route, vents, AC unit, charge; surprise
    inspector flags fixed; A, $2,677 with 435 s left); Trace judge against good / shaky / too fast / half / backwards /
    jump / time-travel recordings; every Gauge style finishable in time; 120 GaugeHold spam + junk TraceSubmit / Shop
    args gave no errors. Not tested: a human Level / Voltage / Charge run (same code path as Pour), the Trace and
    Gauge panels on a real phone, the Joysticks bonus in a hand lift, HVAC on a Two-Story (2 floors). Screenshots timed
    out this session, so the shop and new panels haven't been looked at on screen yet.

- **PurchaseService: monetization for launch (2026-11-16, branch `purchase-service`, owner away: built autonomously).**
  Plan and assumptions (logged while building; the final summary is at the end of this entry):
  * Checkpoint: the tree was clean and Studio matched `src/` (77 scripts hashed), so there was nothing to commit;
    tag `checkpoint-before-PurchaseService` marks db5b968 instead of an empty commit. All work is on `purchase-service`.
  * One `MarketplaceService.ProcessReceipt` handler (`PurchaseService`). The receipt id and what it gave are written in
    the same profile save; PurchaseGranted only after that save succeeds; anything else returns NotProcessedYet.
  * A receipt is never left unresolved because of game state (Roblox does not refund unresolved purchases): a boost
    bought with nothing to use it on becomes a saved **credit** the player can USE later for free.
  * The server prompts purchases (`PromptProductPurchase` from the server) only after its own checks pass, so "no
    active job" means no prompt and no charge. Clients never send prices or product ids, only a product key.
  * Assumptions: (1) Hire a Pro upgrades / adds a skilled bot on the empty trade with the most work left (server
    picks; no trade argument from the client); it stays for the whole job even if a player later picks that trade.
    (2) Retry Inspection = after a final inspection with collapses, the crew gets a short window to take a retry:
    the fallen pieces become rebuild tasks (normal task engine) and the inspector walks again; unrebuilt pieces are
    still charged, so a retry can never cost more than the first result. Deadline misses are not covered.
    (3) 2x Pay doubles the buyer's net paycheck (after fines and damage). (4) Cash packs: 49 R$ = $1,500,
    149 R$ = $5,000, 299 R$ = $11,000, 499 R$ = $20,000 (tune later). (5) Prices: Rush 39 R$, Pro 79 R$, Retry 35 R$,
    2x Pay 299 R$ (inside PLAN.md's ranges). (6) Mock purchases run only in Studio with the workspace attribute
    `DevMockPurchases` set, or through the server-only `ServerStorage.DevPurchase` test hook.
    Added during the adversarial pass: (7) at most 2 hired pros per job; (8) Rush Delivery needs a trade first
    (the delivery is credited to the buyer like any task); (9) no retry offer, and no wait, when the retry is not on
    sale and nobody on the server has one saved.
  * **Final summary (2026-11-16). Ids filled in on 2026-11-17 (see the Creator Dashboard item below).**
  * **What was built** (10 commits on `purchase-service`, one per piece; `main` untouched, nothing pushed):
    - `ServerStorage/Config/Products` (authoritative): 3 boosts, 4 cash packs, the 2x Pay pass; `Id = 0` = not on sale.
    - `DataService` profile v6: `Receipts` (granted purchase ids, newest 150), `Credits` (paid boosts not used yet),
      `RobuxSpent`. `Data.Save` now returns (ok, why) and is true only when the profile was written under this
      server's session lock; `CanPersist`; no ordinary save once a player is leaving or the server is closing.
    - `PurchaseService`: the one `ProcessReceipt` handler (grant in memory + record the id, save, then
      PurchaseGranted; NotProcessedYet for an unknown product, absent buyer, unloaded or unsavable profile, failed
      save). Remote `Purchase` (Open / Buy + key; 0.5 s / 1 s limits) and `PurchaseData` (catalog). The server opens
      the prompt itself. Player attributes `Credits` (JSON) and `DoublePay` are display copies.
    - 2x Pay: asked from Roblox on join (retrying until answered) and after `PromptGamePassPurchaseFinished`, never
      from that event's flag alone; not saved in the profile. `EconomyService.PayBoost(p)` returns 1 or 2 and
      `JobService.finish` multiplies the net paycheck; payout field `passBonus`, panel line "2x Pay pass: +$N".
    - Cash packs: `EconomyService.AddCash` (now returns whether it added).
    - Rush Delivery: `JobService.CanRush` / `RushDelivery(buyer)` = the bookkeeping of the last unload (piles, truck
      emptied, Deliver slot completed for the buyer). Bundles still flying into the truck stop.
    - Hire a Pro: `BotService.CanHirePro` / `HirePro(buyer)`. The empty trade with the most work left gets a pro
      (16 walk speed, 0.3-0.6 s pauses, tap spread 0.1, weld 0.9-1.0, gauge 0.92-1.0, machine aim 0.6 studs, gold
      hard hat, "Pro <Trade>"). Same slot rules and task engine. Stays if a player takes that trade; gone on cleanup.
    - Retry Inspection: `InspectionService` `CanRetry` / `TakeRetry` / `HoldRetry` / `ReleaseRetry`. After a walk
      with collapses: 25 s offer (workspace attribute `RetryOfferUntil`; held up to 60 s once while a buyer is in the
      prompt), then one `redo<n>_<id>` Timing slot per fallen piece for its trade, up to 180 s, then a second walk.
      A rebuilt piece is put back and takes the rebuild's accuracy and builder; an unrebuilt piece stays down and is
      charged as before. Max 2 retries per job. `JobService.DropSlot` and `SetPhaseNote` support it.
    - Client `StoreController`: STORE button (left edge under the top bar, 96 x 44), panel with 8 rows (buttons
      136 x 60: price, USE (n), OWNED or SOON), and a 64 px tall RETRY INSPECTION button with a countdown.
    - `design/Security_Audit.md`: read-only audit of all 17 remotes, the economy and the payout (3 high, 6 medium,
      6 low). The high ones are not purchase bugs: trusted character position, one task pays a full paycheck, and
      the Foreman's instant kick. None is fixed yet.
  * **What was tested** (Studio, mock receipts through the real handler; real purchases can't run in Studio):
    - Receipts: fresh, replayed id, save failing twice then working (one grant), unknown product, buyer not in the
      server, profile not loaded, empty id, three copies of one receipt at once (one grant).
    - Remote: unknown actions, wrong types, a 500-character key, 40 Buy calls at once: ignored or rate limited.
    - No job: every boost refused before any prompt; receipts arriving anyway were saved as credits.
    - Shed run 1: mock pass + Rush (deliver closed in 5 s) + Pro (Foreman) + 4 sloppy pours -> 4 collapsed -> retry
      -> 4 rebuilds -> re-inspection passed -> $899 x 2 = $1,798 with the pass line on the panel.
    - Shed run 2: saved credits used with no new purchase (Rush, 2 pros, retry); a third pro refused by the limit;
      the pro stayed when the player took its trade; a second take of one offer refused; rebuilds left undone on
      purpose -> after 3:00 the 4 pieces were still charged ($120, the same as the first result), $753 paid.
    - Store panel: 8 rows, mock cash pack and pass update it, retry button text and countdown. No script errors.
    - Studio and `src/` match on all 80 scripts (hash check); dev switches cleared.
  * **What was NOT tested:** any real purchase or real receipt; real DataStores (Studio API access is off), so the
    session-lock, failed-save and leaving-player paths ran only as simulations or not at all; redelivery on rejoin;
    the pass bought in game (`PromptGamePassPurchaseFinished` + ownership check); the retry hold while a real prompt
    is open; a second retry on one job; Hire a Pro on a house (machines, Welder, HVAC as the pro); two or more
    players (who sees what, a crew member joining or leaving mid-boost was reasoned through, not run); the store on
    a real phone. Screenshots are still unavailable, so the store has not been looked at on screen.
  * **Creator Dashboard (DONE 2026-11-17, created by Claude in the dashboard with the owner signed in; all on sale,
    fixed prices, managed pricing off, no icons yet):** Rush Delivery 3732927916 (39 R$), Hire a Pro 3732928088
    (79), Retry Inspection 3732928149 (35), Cash: Toolbox 3732928197 (49), Cash: Truckload 3732928261 (149),
    Cash: Payroll 3732928337 (299), Cash: Contractor 3732928414 (499); game pass 2x Pay 2093810959 (299). The ids are
    in `ServerStorage/Config/Products`. A price changed in the dashboard needs the same change to `Robux` there (the
    store's display text). Still to do by the owner:
    4. Game Settings > Security: enable Studio access to API services to test saving, then publish.
    5. Test live with a second account: one cash pack (cash arrives once; rejoin and it is still there), one boost
       with and without a job, and the pass (toast, doubled paycheck; a cancelled prompt grants nothing).

- **Audit fixes H1-H3 (2026-11-16, owner: "Yes, fix them"; details in `design/Security_Audit.md`):**
  * H1 `Services/MoveGuard` (in the boot ORDER): a server-trusted spot per player that moves at most at the server
    walk speed x 1.3 with a 2.5 s allowance; `JobService.near` uses it for players. `MoveGuard.Snap(p, pos)` after any
    server teleport (crew shuttle, `SessionService.place`); `DevTrigger` snaps by default (3rd argument true = don't).
    Studio hook `ServerStorage.DevMoveGuard`. Tested: walk lag 0.4 studs; 300-stud teleport trusted after 12.1 s;
    pile refused 5.1 s after a 118-stud teleport; riding and shuttle at 0 lag.
  * H2 pay share: `EconomyService.TasksForFullPay` / `PayShare`, numbers in `Config/Jobs` (`ShareTasks` 0.1, min 3,
    max 10, `SharePresent` 0.5); `JobService` tracks `startedAt` / `joined`; payout fields `share`, `shareWhy`,
    `needTasks`; job XP and company points need a share >= 0.5. Tested: full worker share 1 ($895); 1 of 3 Welder
    tasks then idle = 33% ($293, no job XP). The late-join part was tested only as a function.
  * H3 `CrewService`: a kick always needs 2 voters (Foreman + 1, or most of the crew; votes last 120 s); anyone may
    start a job 90 s after the crew became free. Tested only as functions: needs 2+ real players.
  * Learned: on the Shed the roof is an Operator task, so an idle player holding Operator stalled the job.
  * Second pass (owner: "so fix these"): MoveGuard 1.12 x walk speed, 1.2 s allowance (no false alarms walking or
    jumping; 100-stud teleport trusted after 4.4 s vs 6.2 s walking). Full pay = `ShareFair` 0.4 of your trade's
    tasks split between its players (min 3). Helper bots: a trade a player holds but hasn't worked for 60 s while
    its work waits gets a bot until that player finishes a task of it (`Job.StalledRoles`, `PlayerWorkedSince`;
    BotService reconciles every 5 s during a job). Kicks: most of the rest of the crew, Foreman counts as one; start
    grace 60 s.

- **Studio-only switch added:** `DevMockPurchases` (the store's Buy button runs a fake receipt). Same rule as the
  others: Edit mode only, for a test, removed right after.

- **Camp + Crew Supply polish (2026-11-17, branch `camp-polish`, owner: "the spawn point area looks really bare, the
  rvs look bland, the coffee area also, and the crew supply is akward"; owner away, done autonomously):**
  * `ServerStorage/DevTools/CampPolishBuilder` (edit-time, `require(it).Build()`, re-runnable): a `Polish` model in each
    `RVPark.RVs.RV_n` (livery per RV: repainted body / stripe / caps, dark window band, pinstripe, brand name, headlights,
    bumpers, solar panels, dish, spare wheel; the old flat `Awning` is hidden and replaced by a striped one with a
    valance and string lights; rug, two camp chairs, potted plants, grill, cooler, table lantern, SITE n post, power
    pedestal) and `RVPark.Polish` (spawn plaza: the `SpawnLocation` restyled to slate with its decal removed, a stone
    circle with lanterns, flower beds, a signpost to COFFEE / TRUCK LOT + JOBS / CREW SUPPLY / CAMPFIRE, a CREW CAMP
    welcome board; festoon lights zigzagging over the camp lane; 13 pines + 60 shrubs on open grass only (`NO_GO`
    rects keep pads, lane, patio, campfire, tents and the walk to the café clear); campfire stumps, firewood, string
    lights, two tents; café: giant cup with steam on the kiosk roof, red/white awning stripes + valance, OPEN sign,
    menu board, A-frame, round umbrellas, two more tables, string lights on four poles, planters, patio heaters,
    coffee sacks, bike rack). Decor doesn't collide except poles, posts, tents, planters and tree trunks. 24 lights,
    all `NightLight` (DayNightService switches them). Terrain under the plaza is Ground (no grass poking through).
  * `ServerStorage/DevTools/SupplyStoreBuilder` rebuilt as a one-way drive-through: IN driveway at x -49, OUT at
    x -155 (curb cut, asphalt), the old middle driveway (x -112..-88, it ran into a canopy post) closed back to grass
    and sidewalk; yellow LOADING BAY box under the canopy, arrows, IN / OUT words, a hanging "STOP IN THE YELLOW BAY"
    sign, ENTER / EXIT signs, post guards, the CREW SUPPLY pylon moved onto the grass between the driveways, hedges,
    a forklift, cones. Fixed: two side racks divided by zero (`length / 0`: parts at NaN positions far outside the map).
    The hardware store's three parked cars (`TownLife.ParkedCars.Parked_Hardware`) stood in the loading lane: moved to
    a new staff lot east of the store (x -46, z -500..-524), and `LifeBuilder` now parks them there too.
    The terrain grid along Main St's north side runs on z = 2 mod 4 (grass -430..-422, sidewalk -422..-418).
  * GuideController's first hint now lists all 6 trades.
  * Tested in Studio: before / after screenshots of the park, spawn, an RV, the café, the campfire and Crew Supply;
    drive-through loading still works in the new bay (Shed load 3/3); no script errors. Not tested: phone frame rate
    with the extra ~1,600 parts and 24 lights (all non-colliding decor), and a player actually driving the IN -> OUT
    route (the truck was placed in the bay by script).

- **Several crews per server (2026-11-17, branch `multi-crew`, owner: "dont we need more lots/sites like do 5-8
  companies per server?"; owner left the numbers to me):** up to **6 crews** a server (`CrewService.MAX_CREWS`), up to
  6 players each (`MAX_MEMBERS`); each crew runs its own job on its own lot at the same time. Server size set to 30
  on 2026-11-17 (Creator Dashboard > place > Access > Maximum Visitor Count; was 50). Scripts can't change it
  (Players.MaxPlayers is read-only) and Open Cloud `universe.place:write` isn't granted.
  * **Crews (`CrewService`, rewritten):** crew = { id 1..6, name, companyId, members, roles, idleSince, votes, barred }.
    Picking a trade without a crew puts you in your company's crew on the server (if it has room), else a new crew of
    your own (bots fill the other trades), else (6 crews already) the crew with room that needs your trade. Name: the
    founder's company name, else "Crew <id>". QUICK JOIN prefers a crew already on a job that needs your trade.
    Remote `CrewAction` ("Join", id) / ("New") / ("Leave"). Player attributes `CrewId`, `CrewName`. CanDo / Snapshot /
    IsRoleHeld / CanStartJobs (Foreman grace) work inside the crew. Kick vote = most of the rest of the crew (min 2);
    voted out = out of the crew and barred from it, **not kicked from the server**. Pings go to crewmates only.
    The last member leaving ends the crew's job with no pay and frees its lot (`Emptied`).
  * **Jobs (`JobService`, rewritten):** `jobs[crew]` and `lotJob[lotId]`. Board buttons are still per tier
    (`StartSite` = "Site_T1".."Site_T4"); StartJob takes the tier's first free lot from `Config/Sites` `Lots`, else
    "every Site N lot has a crew on it". Blueprint yaw comes from the lot's gate (`Shared/Util/Lots.Yaw`). Site model
    `JobSite_<bp>_<crewId>` with attributes `CrewId`, `Lot`. Every slot / pile / truck-bed prompt checks the worker is
    on the owning crew (`onCrew`); vehicles and machines too (`JobService.MayUse`, used by VehicleService and
    EquipmentService). Labels "Site 1A/1B/1C". Truck stalls: `Stall_k` in the RV truck lot minus the dealer's
    (`DealerService.STALL` = Stall_6): crews 1-5 -> stalls 1-5, crew 6 -> new Stall_7. Drive-through loading runs per
    job (`cur.loading`, `cur.yardStill`), so two trucks can load at Crew Supply at once. API: `Of(crew)`,
    `ForPlayer(p)`, `All()`, `Live(cur)`, `Owning(inst)`, `Toast(cur, msg)`; everything that was "the current job"
    now takes `cur`. State goes to each player for their own crew (coalesced `Broadcast()`, plus every 3 s while
    jobs run); remote `Crews` sends everyone the board (crews, their jobs/phases, open trades, free lots per tier).
  * **Per-job state** lives on the job table: `cur.quality` (QualityService functions take it first), `cur.botState`
    (BotService: bots, pros, helpers), `cur.chaos`, `cur.insp` (inspection walks + retry offer), `cur.detail`,
    `cur.sky`. Store boosts (Rush Delivery, Hire a Pro, Retry Inspection) act on the buyer's crew's job.
  * **Per-crew client stuff:** rain and the retry offer are **player attributes** (`RainUntil`, `RetryOfferUntil`)
    on that crew's members, not workspace attributes. **Day/night is now client-side** (`DayNightController`, new):
    the server's `DayNightService` only sets `cur.sky` (predawn / sunrise t0+dur / day); each client sets
    Lighting.ClockTime, ambient, NightLight/streetlight switching and the rain darkening locally. The server no longer
    touches Lighting. Rain mud only slows that crew's vehicles (`VehicleService.SetSpeedFactor(f, site)`).
  * **Client:** PromptFilter hides another crew's prompts (`UI.Foreign`); the guide ignores them; CREW panel lists
    your crew (KICK, LEAVE) and every crew on the server (what it's doing, trades it needs, JOIN), plus NEW CREW. HUD
    shows the crew name / "SHED Site 1B".
  * **Map:** 4 new lots in `TownLayout`: Site_T1b (x 720..880) and Site_T1c (x 520..680) on Main St next to Site 1;
    Site_T2b (z -1292..-1092) and Site_T2c (z -812..-612) on Pine Rd next to Site 2. Tiers 3-4 keep one lot each (8
    lots). Built with the new `DevTools/LotBuilder` (ground + driveway terrain, curb cut, trees cleared, lot marker,
    Stall_7) then `SiteBuilder.All()` (now loops lots; no longer touches the spawn or the board buttons).
  * **Gotcha:** BindableEvents copy tables, so a listener got a copy of the crew/job and nothing matched. Crew and job
    events (`CrewService.Changed/Emptied`, `JobService.Started/Ended/Cleared`) are now `Shared/Util/Signal` (plain Lua).
  * Tested in Studio (one test player): picking a trade makes Crew 1; Site 1 job on lot 1A with truck in stall 1 and
    bots after 8 s; HUD "SHED Site 1A"; only my trade's prompts on; LEAVE ends the job and clears site + bots; NEW
    crew; a starter house on lot 2B and a shed on lot 1C (config order flipped for the test, then restored) laid out
    inside their lots, screenshots OK. **Not tested:** two crews at the same time (Studio here runs one player:
    needs a Team Test / live server with 2+ players), another crew's prompts being hidden, two trucks loading at once,
    company crews, kick votes, phone performance with several jobs and their bots running.

- **Crew vs crew (2026-11-17, owner: "its still co op in your team/company/crew but your competing against other
  crews"):** `LeagueService` (new, server). Co-op inside a crew, competition between crews on the same server.
  * Crew points per passed job: round(BasePay / 100 x grade mult (A+ 1.5, A 1.3, B 1.1, C 1, D 0.8)) + 2 if early
    + 5 for a race win (shed A = 7, starter house A = 20). Kept per crew while it exists on the server. Standings
    go out with the crew board (`Crews` remote, field `league`) and show at the top of the CREW panel. The leading
    crew gets player attribute `TopCrew` (gold "#1" tag) and the server is told when the lead changes.
  * Races: a crew starting the same site (tier key) as another crew within 90 s is paired with it (`cur.race`). The
    first to pass inspection wins: `JobService.finish` asks `LeagueService.ClaimRace(cur)` before payout, and each
    paid member gets +20% of their net paycheck (`raceBonus` on the payout screen; not doubled by the 2x pass). The
    loser gets normal pay. A rival that fails or leaves drops out; the other wins by passing. HUD race bar (under the
    toasts, y 246): "RACE vs Crew 2 | you 12/36 | them 9/36", green when ahead (`state.race` from `RaceInfo`).
  * `CrewTagController` (client, new): crew name over other players' heads in the crew's color, gold "#1" for the
    leading crew.
  * Tested: LeagueService unit test with stand-in crews/jobs (pairing, 90 s window, one bonus per race, points,
    standings order, drop-out win) all pass; in-game the standings reach clients and a job starts with no errors.
    **Not tested:** a real race with two crews, and the race bonus on a real payout (needs 2+ players).

## Studio workflow notes (learned the hard way)
- BindableEvents copy any table passed through them (a listener gets a copy, not the same table). Pass tables between
  services with `Shared/Util/Signal` or direct calls.
- Seats auto-seat whoever touches them. Any seat with a trade rule must also check `Occupant` on the server and eject.
- Animate client UI on `RunService.Heartbeat`, not RenderStepped: RenderStepped doesn't fire when Studio isn't rendering
  (and test runs stall).
- `require` inside `execute_luau` caches modules across calls. To check edited blueprints, clone the modules into a
  temporary folder first.
- Long test runs: `execute_luau` calls time out after ~60 s and kill their thread. Run long tests in `task.spawn` and
  poll results from a separate call.
- Never take `screen_capture` with `camera_position` in Edit mode: it can leave `CurrentCamera.CameraType` stuck on
  Scriptable (and save it into the place). If it happens: `task.delay(3, function() workspace.CurrentCamera.CameraType
  = Enum.CameraType.Fixed end)` (the MCP restores the camera type after each call), then check in a separate call.
  Check placement with geometry queries (GetPartBoundsInBox) instead of screenshots.
- Material names in this Studio: corrugated metal is `CorrodedMetal` (not CorrugatedMetal/CorrugatedSteel).
  Check with `Enum.Material:GetEnumItems()` before using a new one.
- Terrain renders a full top voxel 2 studs above it. Fill to y = -2 so the walkable ground is at y = 0
  (everything in the game assumes ground y = 0). The old Baseplate and Phase 1 sketch are in `ServerStorage.Archive`.
- Studio blocks HTTP to localhost from the MCP ("not in the Assistant HTTP allowlist"), so code goes into Studio by
  setting `.Source` through `execute_luau`. After any change, confirm Studio and `src/` match (hash every script).
- Code run through `execute_luau` gets its own `require` cache, so it can't reach the running services. Tests go through
  `ServerStorage.DevTrigger` (a BindableFunction created only when `RunService:IsStudio()`), which calls
  `JobService.Trigger(player, prompt)`, the same path a real tap takes.
- The test player is a first-timer, so a drop-in Shed starts on join. For any site-board test, set `DevReturningPlayer`
  (and `DevChaos` etc.) in Edit mode *before* starting play, then clear them after.
- The truck's `AssemblyLinearVelocity` reads 0 while it drives (LinearVelocity mover); measure speed by pivot displacement.
- `generate_mesh` only works in Edit mode (it fails with "should only be called from the server" during play). Its
  part labels are unreliable and proportions ignore the requested size: always look at the result before using it.
  Check orientation from a play-mode screenshot with a Scriptable client camera (never camera_position in Edit mode);
  StreamingEnabled hides far models from the client, so set the model's `ModelStreamingMode = Persistent` for the look.
  `segment_mesh` needs a single MeshPart. `RBX_AI_*` attributes can't be removed by scripts (harmless).
- Never use weak-keyed tables keyed by Instances; the entries vanish. Use normal tables and clear them on `Destroying`.
- `Enum.Material[name]` throws on a bad name (it's `CorrugatedMetal`, not `CorrugatedSteel`); look it up inside pcall.

## Folder structure (approved 2026-11-07)
`src/` mirrors the Studio DataModel. Keep Studio and this tree in sync. New trades/tiers are added as
config + blueprint + role files, not rewrites.

```
src/
├─ ReplicatedStorage/
│  ├─ Shared/
│  │  ├─ Config/          JobTiers, Trades, Vehicles, Products, ChaosEvents (display copies only)
│  │  ├─ Types/           shared Luau types (TaskDef, JobState, CrewState)
│  │  ├─ Blueprints/      ghost-outline data: Shed, StarterHouse (phases → slots)
│  │  └─ Util/            Signal, Trove, math helpers
│  ├─ Remotes/            one RemoteEvent/RemoteFunction per action (created by server)
│  └─ Assets/             ghost parts, tool models, VFX, sounds
├─ ServerScriptService/
│  ├─ Main.server.luau    boots services in order
│  └─ Services/
│     ├─ DataService        DataStore save/load, session lock, autosave
│     ├─ EconomyService     cash, payout formula, 2× pass
│     ├─ PurchaseService    ProcessReceipt, game passes, receipt dedupe
│     ├─ ProgressionService trade XP/levels, unlocks, hub unlock
│     ├─ CrewService        Quick Join, form crew, trade slots, kick vote, pings
│     ├─ JobService         job lifecycle, phases, deadline, site spawn
│     ├─ TaskEngine/        Carry, Place, Timing, Connect validators + anti-cheat
│     ├─ BlueprintService   ghost slots, server placement confirmation
│     ├─ QualityService     per-task accuracy → job grade
│     ├─ InspectionService  inspector walk, penalties, collapse trigger
│     ├─ ChaosService       surprise inspector, rain delay, crane mishap
│     ├─ BotService         bot workers on the same task engine
│     ├─ VehicleService     truck spawning, ownership, cargo
│     ├─ OnboardingService  drop-in first job, guided-job flags
│     └─ RetentionService   daily contract/streaks, codes, group reward
├─ ServerStorage/
│  ├─ Config/             AUTHORITATIVE prices, pay, unlocks, codes
│  ├─ Sites/              Shed, StarterHouse
│  ├─ Vehicles/           StarterTruck, WorkPickup, Excavator, SkidSteer, Crane
│  └─ NPCs/               Bot rig, Inspector rig
├─ StarterPlayer/
│  ├─ StarterPlayerScripts/
│  │  ├─ Main.client.luau  boots controllers
│  │  └─ Controllers/
│  │     ├─ InputController      ContextActionService + touch buttons
│  │     ├─ TaskControllers/     Carry, Place, Timing, Connect UI (tap/hold/drag)
│  │     ├─ RoleControllers/     Foreman, Laborer, Operator, Electrician
│  │     ├─ VehicleController    on-screen throttle/steer on touch
│  │     ├─ PingController       tap-to-mark crew pings
│  │     ├─ StoreController      Robux store panel and retry button (only asks; PurchaseService decides)
│  │     ├─ OnboardingController arrows and tips
│  │     └─ UIController         HUD, shop, job board, settings
│  └─ StarterCharacterScripts/
├─ StarterGui/            HUD, TaskPrompt, CrewPanel, Shop, JobBoard, Settings, Payout
└─ Workspace/             Hub (yard, dealer, job board), spawn locations
```
