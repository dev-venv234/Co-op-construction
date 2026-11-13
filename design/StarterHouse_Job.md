# Phase 1 — Paper design: Starter house (Tier 2, 15:00)

Roadmap Phase 1 (Week 1): write the starter-house job minute by minute per role, sketch one site.
**Gate:** no role idle for more than one minute on paper. Result: **passes** (see Gate check at the end).

Task types: **Carry**, **Place**, **Timing**, **Connect** (see CLAUDE.md). Every task is a tap / hold / drag
on mobile. All results are confirmed by the server.

## Launch-role decision (approved by the owner 2026-11-08)
At launch only Foreman, Laborer, Operator and Electrician are playable. The plan's Concrete and
Plumber work for the starter house is handled like this until those roles ship:
- **Concrete work is split:** the Operator runs the concrete-truck chute (Timing), and the Laborer screeds (Timing).
  The driveway becomes an Operator **gravel** driveway (Carry + Place with the skid steer).
- **Plumbing is an NPC "sub" (bot plumber)** working in the background. The crew still feeds it: the Laborer
  stages pipe and the Foreman schedules it. That fits the plan's "waiting on subs" flavor and costs no player time.
When the Concrete and Plumber roles ship, they take these tasks back and the timeline below gains their columns.

## Hard dependencies (what really blocks what)
Footings dug → forms set → rebar in → **pour** → slab cure (60 s) → walls raised → trusses set →
sheathing/roof → wire runs → panel → outlets → **power on** → final inspection.
**Soft dependencies:** the ghost blueprint is visible from second 0, so nobody waits on the Foreman to start.
Foreman stakes and checks **raise quality**; they never block work.

## Minute-by-minute timeline (crew of 4)

| Time | Phase | Foreman | Laborer | Operator | Electrician |
|---|---|---|---|---|---|
| 0:00–0:30 | Site prep | Opens blueprint; pings the corner stake spots | Unloads truck → staging (Carry) | Walks to excavator, starts it | Carries temp power pole to its marker (Carry) |
| 0:30–1:30 | Site prep | Drives 4 corner stakes + string line (Place ×4) | Sets form boards on the stake lines (Place) | Digs footing trenches, 4 sides (Timing/precision) | Sets the temp pole (Place), hooks up the meter (Connect) |
| 1:30–2:00 | Site prep | Checks trench depth; marks mistakes | Stages drain pipe for the NPC plumber (Carry) | Last trench, parks excavator | Drives the grounding rod (Timing) |
| 2:00–2:30 | Foundation | Laser-level check on the forms (Timing) | Lays rebar in the forms (Place ×6) | Backs the concrete truck to the chute spot (precision drive) | Places conduit stub-ups in the slab (Place) and bonds a ground wire to the rebar (Connect) |
| 2:30–4:00 | Foundation | Watches levels, pings low spots; calls foundation check | Screeds behind the pour (Timing, 4 sections) | Runs the chute: hold to fill each section (Timing ×4) | Carries wire spools and the panel to staging (Carry), then pre-wires the panel at a workbench (Connect) |
| 4:00–5:00 | Foundation (60 s cure) | Assigns the wall order with pings | Carries framing lumber from the delivery to the slab edge (Carry) | Moves the concrete truck out, drives the crane to its pad | Pre-drills stud packs at staging (Timing) |
| 5:00–6:00 | Framing | Square check (Timing), places wall braces (Place) | Nail-guns wall panels 1–2 (Timing), raises them (Place) | Skid-steers lumber packs to each wall (Carry, heavy) | Marks box spots on raised walls (Place) |
| 6:00–7:00 | Framing | Braces walls 3–4; marks framing mistakes | Nail-guns and raises walls 3–4 | Rigs the truss bundle (Connect: pick sling points; bad rig → crane mishap) | Pre-drills raised studs (Timing) |
| 7:00–8:30 | Framing | Signal person for the crane (pings each truss slot) | Nails trusses as they land (Timing) | Crane-lifts trusses (Place ×6, precision) | Sets electrical boxes (Place) |
| 8:30–9:00 | Framing | Calls the framing inspection (button) | Nails the last truss | Lowers the roofing pallets onto the slab edge | Finishes boxes |
| 9:00–10:00 | Rough-in | Schedules the rough inspection; orders finish materials (rush-delivery hook) | Hangs wall sheathing (Place) | Crane-lifts roofing pallets onto the roof (Place) | Runs circuits 1–2 through the studs (Connect) |
| 10:00–11:00 | Rough-in | QA walk: marks mistakes (pings) | Sheathing done → roofing bundles (Place + Timing nail) | Skid-steers the driveway base (Carry gravel) | Runs circuits 3–4 (Connect) |
| 11:00–12:00 | Rough-in | Fixes flagged items or helps carry (Carry) | Finishes roofing | Hauls scrap to the dumpster (Carry) | Mounts the panel and lands the circuits (Place + Connect) |
| 12:00–13:30 | Finish | Punch list: pings every open item | Cleanup: debris → dumpster (Carry); punch fixes | Spreads the gravel driveway (Place) | Outlets and light fixtures (Place + Connect) |
| 13:30–14:00 | Finish | Greets the inspector, starts the walk | Last cleanup | Hauls the dumpster out (truck) | **Power on** at the panel (Timing) |
| 14:00–15:00 | Inspection | Walks the inspector; tap to answer each check | Fixes items the inspector flags | Fixes items the inspector flags (moves misplaced loads) | Fixes flagged electrical items |

**Crew of 3 (minimum):** a bot fills the empty slot (slower, makes mistakes). **Crew of 5:** the 5th player is a
second Laborer; Laborer tasks split in half, which leaves room for chaos recovery.

## Chaos windows (1–2 per job)
| Event | When | Effect | What the idle-free fix is |
|---|---|---|---|
| Rain delay | Just before the pour (≈2:20) | 45 s of no pouring; mud slows vehicles | Everyone pulls framing prep forward: Laborer carries lumber, Operator drives the crane in early, Electrician pre-drills |
| Crane mishap | Truss lifts (7:00–8:30) | A badly rigged load swings and drops | Laborer and Foreman re-stack, Operator re-rigs; costs ~30 s and quality |
| Surprise inspector | Any time in rough-in (9:00–12:00) | Every visible mistake costs money | Foreman pings the fixes; whoever is closest fixes them |

## Payout check (from PLAN.md)
Base $1,500 per player × quality (0.5–1.5×), +25% if finished early, minus damage/rework.
The server computes all of it from server state.

## Gate check — "no role idle for more than one minute"
| Role | Longest gap with nothing to do | Pass |
|---|---|---|
| Foreman | 0 s; every block has a check, ping or brace task | ✅ |
| Laborer | 0 s; Carry fills every wait | ✅ |
| Operator | ~30 s (2:00–2:30 truck positioning is short); no block over 1 min | ✅ |
| Electrician | 0 s; prep work (panel pre-wire, pre-drilling) fills the pour and the cure | ✅ |
Risk to watch in gray box: the **4:00–5:00 slab cure** is the most likely place a player stands around. If
playtests show it, shorten the cure to 45 s or add a "cover the slab" Carry task.

---

# Shed job (Tier 1, 8:00): used for the gray box and the first-time player drop-in
Crew of 2–3: Foreman, Laborer, Operator (bots fill the gaps). No Electrician at Tier 1.

| Time | Foreman | Laborer | Operator |
|---|---|---|---|
| 0:00–1:30 | Stakes (Place ×4) | Unloads and stages (Carry) | Digs 4 post holes with the skid-steer auger (Timing) |
| 1:30–3:00 | Level check (Timing) | Sets posts (Place), pours bagged concrete (Timing) | Brings the lumber pack to the pad (Carry) |
| 3:00–5:30 | Braces and marks mistakes | Nail-guns floor and walls (Timing + Place) | Crane-lifts the roof panel (Place) |
| 5:30–7:00 | Calls inspection | Roof sheets (Place) | Hauls scrap (Carry) |
| 7:00–8:00 | Walks the inspector | Cleanup, fixes | Fixes |

---

# Site sketch: starter-house lot
Built in Studio as a non-scripted gray box: `Workspace.SiteSketch_StarterHouse`. When JobService exists,
it moves to `ServerStorage.Sites`. Units are studs; north is up (−Z).

```
                         N (−Z)
 z=-220 ┌──────────────────────────────────────────────────────────┐
        │ [Equipment yard]                        [Dumpster]       │
        │  excavator, skid steer                                   │
        │                                                          │
        │   (Temp power pole)   ┌───────────────┐   [Crane pad]    │
        │                       │ HOUSE GHOST   │                  │
        │ [Material staging]    │ 40 x 28       │                  │
        │  (Laborer)            └───────┬───────┘                  │
        │                               │driveway  [Concrete truck │
        │ [Truck parking]               │(finish)   / chute pad]   │
 z=-80  └───────────────[Inspector]─────┴──────────────────────────┘
        ════════════════════════ ROAD ═══════════════════════════════
       x=-80                                                     x=80
```
Distances keep every walk under ~10 seconds: staging to the house ≈ 45 studs, parking to staging ≈ 30 studs.
