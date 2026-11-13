# Town plan: small town, RV start, 4 sites

Source of truth for positions: `src/ReplicatedStorage/Shared/Config/TownLayout.luau`.
Builder (dev tool, never runs in game): `src/ServerStorage/DevTools/TownBuilder.luau`.

Build order: **1 terrain + roads (done 2026-11-08)** → **2 RV park + coffee + truck lot (done 2026-11-08)** → **3 sites (done 2026-11-08)** → **4 session flow + filler buildings (done 2026-11-08)**. All four stages are built. 3 sites + filler buildings → 4 session flow.

## Top-down map (north is up, studs; 1 row ≈ 150 studs)

```
 x:      -1000          -500            0            500           1000
 z
-2500  [SITE 4 LUXURY]
       (-960..-680)
-2200  +=========Hilltop Dr=======+
                                  ‖                       ( hill )
                                  ‖ Oak Ave
-1550                             ‖                        [SITE 3 TWO-STORY]
                                  ‖                         (800..1040)
-1400  +==========Ridge Rd========#=============================+ (ends x 1040)
       ‖                          ‖
-1100  ‖                   [house]‖[house]
-950   ‖[SITE 2 STARTER]   [house]‖[house]
       ‖ (-972..-772)      [house]‖[house]       (-700, -900, -1100)
       ‖ Pine Rd                  ‖
-480   ‖             [HARDWARE]   ‖  [GAS]
-400   +==========Main St=========T======================[gate]====| (ends x 1100)
                              [RV PARK]                [SITE 1 SHED]
-180                        (-160..160)                (920..1080)

0..150                  gray-box test yard (spawn, job board, Phase 2 shed job)
```

Roads are 32 studs of asphalt with 8-stud pavement sidewalks, 0.6-stud concrete curbs (open at
driveways and corners), double yellow center lines, zebra crossings at Main/Oak and 58 streetlights.

## Drive times from the RV park gate (starter truck, top speed 36 studs/s)

| Site | Route | Road distance | Time |
|---|---|---|---|
| 1 Shed | Main St east | ~1,010 | **~31 s (measured: 28.6 s gate to gate + driveway turn)** |
| 2 Starter house | Main St west → Pine Rd north | ~1,560 | ~48 s (estimated) |
| 3 Two-story | Oak Ave north → Ridge Rd east | ~1,930 | ~59 s (estimated) |
| 4 Luxury | Oak Ave north → Hilltop Dr west | ~2,630 | ~78 s (estimated) |

Site 1 is right at the 30 s minimum. If you want a longer warm-up drive, move the RV park west.

## Folder and script structure for the new systems

```
Workspace/
  Town/            Roads (curbs, center lines, crosswalks), Streetlights, Lots (invisible lot bounds + temp signs)   [stage 1]
  RVPark/          RVs, coffee stand, truck lot + site board, loading dock                                          [stage 2]
  Sites/Site_T1..4 fence, trailer, dumpster, porta-potty, staging, tier/pay sign                                    [stage 3]
  Filler/          gas station, hardware store, 6 houses                                                             [stage 3]
ReplicatedStorage/Shared/Config/
  TownLayout       all positions (done)
  Sites            display copy: site name, tier, sign text
ServerStorage/
  Config/Sites     AUTHORITATIVE: tier, pay, unlock rule, blueprint per site
  DevTools/        TownBuilder (done), RVParkBuilder, SiteBuilder: edit-time builders, never required by the game
ServerScriptService/Services/
  SessionService   RV spawn at 4:00 → coffee → site board → load truck → drive → job; first-timer bypass
  BuffService      "Awake" buff: server-held flag, read by TaskEngine (e.g. slower Timing needle, +walk speed)
  DayNightService  Lighting.ClockTime 4:00 → sunrise during the drive; streetlights on/off
  LoadingService   loading dock → truck cargo, reusing TaskEngine.Carry (no new task type)
  JobService       (existing) starts the job at the chosen site's origin instead of the gray-box yard
StarterPlayerScripts/Controllers/
  SessionController  dark-start fade, coffee tip, arrow to the loading dock then the site
```

The existing task engine is not rewritten. Sites only change where `JobService` builds the blueprint.

## Props: built with code vs. Creator Store

**Built with code (simple shapes, real materials, no Plastic):** terrain, roads, curbs, lines,
crosswalks, streetlights (done); site fences (Metal posts + chain-link texture), site trailer, dumpster,
porta-potty, pallets and material stacks, tier/pay signs, coffee stand counter and awning, loading dock,
truck-lot board, block-style filler buildings (gas station canopy, hardware store, houses).

**Better from the Creator Store (you pick, I place):** RVs and campers (3–5), trees and bushes (a pack),
parked cars, gas pumps, a coffee cup tool model, a detailed porta-potty, a chain-link fence texture.
Before inserting anything: check that it contains **no scripts** (free models are a common source of
backdoors), and pick low part-count, well-rated models.

## Stage 2: RV park layout (inside x -160..160, z -372..-180)

```
 z -372  ===fence===[ARCH "RV PARK" gate x=0]===fence======================== (Main St north of here)
         [RV1][RV2][RV3]  [COFFEE stand + patio]  |entry|  [SITE BOARD]      [LOADING canopy]
 z -300  ======= camp lane (asphalt) =============|road |  truck lot          [dock + stacks:
         [RV4][RV5][RV6][RV7]                     |     |  [1][2][3][4][5][6]  Lumber/Post/
 z -236                                           |     |   (stalls, nose N)   Sheet/Stake]
                    (campfire)                    footpath
 z -180  ===fence================================[gap]===fence========================
                                                  |  footpath south to the gray-box yard
```
- Each RV has a hidden `SpawnPoint` part (attribute `RVSpawn` = 1..7) for the stage 4 spawn.
- Stalls `Stall_1..6` (attribute `TruckStall`) are where stage 4 spawns crew trucks.
- Material stacks carry the attribute `MaterialStack` for stage 4 loading.
- Every light the day/night cycle should switch has the attribute `NightLight`.
- The site board is display only for now; site picking (only unlocked tiers) comes with the session flow.

## Stage 3: construction sites

Each site lot gets a chain-link fence with a 32-stud road gate, a site office trailer (front corner), dumpster
(back-right), porta-potties (back-left, 2 on tiers 3-4), staging and delivery signs, floodlights (2, or 4 on tiers 3-4)
and a tier/pay sign facing the road. The job itself is spawned at runtime by JobService on the same lot.

| Site | Road / gate | Job | Tasks | Pay each | Time limit | Release |
|---|---|---|---|---|---|---|
| 1 | Main St, north gate | Shed | 33 | $500 | 8 min | Launch |
| 2 | Pine Rd, west gate | Starter House | 67 | $1,500 | 15 min | Launch |
| 3 | Ridge Rd, south gate | Two-Story Home | 99 | $4,000 | 25 min | Update (Studio only) |
| 4 | Hilltop Dr, south gate | Luxury Home | 139 | $10,000 | 35 min | Update (Studio only) |

Start a job: RV park truck lot → the colored SITE buttons under the JOB SITES board. The loaded truck appears in
stall 1; drive it to the site's DELIVERY pad and unload, then build. Loading at the dock and unlock rules come in stage 4.

## Stage 4: session flow

| Who | Where they start | What happens |
|---|---|---|
| First-time player (no payout yet) | Camp lane by the coffee stand at the RV park, 4:00 AM (owner rule 2026-11-11) | Pick a trade, coffee, start Site 1 at the board, load at Crew Supply, drive. First job has no chaos. First payout unlocks their own RV. |
| Returning player | Their own RV (RV 1-7), 4:00 AM, dark | Coffee (Awake buff) -> site board (only unlocked tiers) -> drive truck from stall 1 to the dock, load the bundles -> drive; the sun rises over the drive -> unload at DELIVERY -> build -> paid -> back to the RV at 4:00 AM |

Site unlocks (best trade level): Site 1 always, Site 2 level 3, Site 3 level 8, Site 4 level 15 (sites 3-4 are also
"Update" releases: Studio only). Truck loads: Shed 2 lumber + 1 sheet, Starter House 4 + 2, Two-Story 5 + 3, Luxury 5 + 3 (starter truck holds 4, Work pickup 8; bigger loads take more trips).
Filler buildings: Quick Stop gas station, Hardware & Lumber store, 6 houses on Oak Ave.
