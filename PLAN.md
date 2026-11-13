# Construction Crew - Roblox Game Plan (source: PDF, extracted text)

> Raw text extracted from "Construction Crew — Roblox Game Plan.pdf" (Nov 7, 2026). Tables are flattened; see the PDF for layout.

<!-- page 1 -->
Construction Crew — Roblox Game Plan
Nov 7, 2026  ·  @gianni
Concept and hook
A co-op job-site game: a crew of 2–6 players, each in a real trade, races to finish a house
before the deadline while things go wrong.
Pitch: "Lethal Company, but you're a construction crew." You show up in your beat-up
truck, pick your trade, and your crew has to frame, wire, plumb, and finish a house on time
to get paid.
Why it can win: the construction games already on Roblox (House Construction Tycoon,
Construction Simulator) are solo tycoons where you manage workers from above. Nobody
has a game where players are the crew, depend on each other, and fail in funny ways
together. Authenticity is the edge: the trade order, the waiting on subs, the inspector
showing up — that comes from how a real GC site runs.
Working title ideas: Job Site, Crew, Built Different, Punch List.
Core loop
One loop, repeated with bigger jobs: show up, pick a trade, build together, get paid,
upgrade.
1. Drop new players straight into a job. First-timers skip the hub and spawn on a live
starter job with a crew (bots fill the gaps), so they're working within 30 seconds.
Roblox decides whether to keep showing a game based on these first minutes. The
hub, truck dealer, and job board unlock after the first payout.
2. Get your truck. Everyone starts with a rusty single-cab. The truck carries tools and
materials, so a better truck matters on the job.
3. Quick Join a crew. One button matches you to any crew that needs your trade. Or
form your own and pick the job tier as Foreman.
4. Pick your trade. Foreman, Laborer, Concrete, Operator, Electrician, Plumber. Empty
slots get bot workers that are slower and make mistakes.
5. Drive to the site. Keep drives under 60 seconds. Driving is fun once; after that it's
dead time.
Construction Crew — Roblox Game Plan
Page 1 of 12

<!-- page 2 -->
6. Build in phases on a ghost blueprint. The house appears as glowing outlines; players
fill them in (see Build system). Every phase gives every trade something to do.
7. Pass inspection, get paid. Payout depends on time, quality score, and damage, with a
bonus for beating the deadline.
8. Upgrade and go bigger. Better trucks, tools, and trade levels unlock bigger jobs that
pay more but take longer.
Roles
Six trades, each with its own minigame and its own reason the crew needs it. Launch with
four (Foreman, Laborer, Operator, Electrician) and add the rest once the loop works.
Each trade levels up separately, so players have a reason to master one trade and also try
others.
Trade Main job on site Minigame Why the crew needs
them
Foreman Reads plans, assigns
tasks, calls
inspections
Blueprint view; marks
mistakes; places task
pings
Only one who sees the
full plan; catches errors
before inspection
Laborer Hauls and stages
materials, cleanup,
demo
Carrying with weight
limits; wheelbarrow; nail
gun framing
Everyone else runs out
of materials without
them
Concrete Forms, pours, finishes
footings and slab
Pour timing; screeding
and leveling before it sets
A bad slab ruins every
phase after it
Operator Excavator, skid steer,
lift, crane
Driving and precision
placement with physics
Only one who can dig,
lift trusses, and move
heavy loads
Electrician Rough-in and finish
wiring, panel
Circuit puzzles; running
wire through studs
House fails inspection
without power
Plumber Supply and drain lines,
fixtures
Pipe-routing puzzle with
slope and pressure
Leaks show up later and
cost the crew money
Construction Crew — Roblox Game Plan
Page 2 of 12

<!-- page 3 -->
Build system
Build one task engine and reskin it for each trade. Six fully custom minigames would take
months; four shared task types take weeks.
Ghost blueprints: the house shows as outlines, so players always know what to build
next. No freeform building means no griefed or broken houses, and quality scoring is
easy.
Mobile first: most Roblox players are on phones. Every task must work with taps and
on-screen prompts; test on a phone every week.
Server-side checks: the server confirms every placement and payout, which blocks
the money exploits that kill economy games.
Bots use the same tasks: a bot worker is just a slower, error-prone player running the
same task engine.
Feature list
35 features at launch and 14 more added in updates after. If it isn't marked Launch, it
waits.
Task
type
How it plays Used by
Carry Pick up, haul, drop in a marked zone;
weight slows you
Laborer, everyone
Place Snap a part into a glowing ghost
outline on the blueprint
Laborer (framing), Operator (trusses),
Plumber (fixtures)
Timing Hold or tap in a moving window; miss
and quality drops
Concrete (pour, screed), Laborer (nail
gun)
Connect Short route puzzle from A to B Electrician (wire), Plumber (pipes)
Area Feature What it does Release
Onboarding Drop-in first job New players spawn on a live
starter job within 30 seconds
Launch
Construction Crew — Roblox Game Plan
Page 3 of 12

<!-- page 4 -->
Area Feature What it does Release
Onboarding Guided first job On-screen arrows and tips
through each phase, once
Launch
Onboarding Hub unlock Yard, dealer, and job board
open after the first payout
Launch
Crews Quick Join Matches you to any crew that
needs your trade
Launch
Crews Form a crew Foreman picks the job tier and
invites friends
Launch
Crews Bot workers Fill empty slots; slower and
make mistakes
Launch
Crews Crew chat pings Tap to mark a spot or call for
help, no typing needed
Launch
Crews Kick vote Crew removes griefers Launch
Roles Foreman Blueprint view, task pings,
calls inspection
Launch
Roles Laborer Carrying, staging, nail-gun
framing, cleanup
Launch
Roles Operator Excavator, skid steer, crane Launch
Roles Electrician Panel, wire routing, fixtures Launch
Roles Plumber Pipe routing with slope and
pressure
Update
Roles Concrete Forms, pours, screeding Update
Building Task engine Carry, place, timing, and
connect tasks shared by all
trades
Launch
Building Ghost blueprints Glowing outlines show what
to build next
Launch
Building Quality score Every task's accuracy adds up
to a job grade
Launch
Construction Crew — Roblox Game Plan
Page 4 of 12

<!-- page 5 -->
Area Feature What it does Release
Building Inspection Inspector walks the house;
mistakes cost pay
Launch
Building Collapse physics Skipped steps make parts of
the house fail at inspection
Launch
Jobs Shed job (Tier 1) 8-minute starter job Launch
Jobs Starter house (Tier 2) 15-minute house Launch
Jobs Two-story home (Tier 3) 25 minutes, adds drywall and
HVAC
Update
Jobs Luxury custom home (Tier 4) 35 minutes, pool and garage Update
Jobs Commercial (Tier 5) Strip mall, warehouse Update
Jobs Oil rig jobs Survey, build the rig, drill Later
Chaos Surprise inspector Shows up mid-phase Launch
Chaos Rain delay No pouring; mud slows
vehicles
Launch
Chaos Crane mishap Badly rigged load drops Launch
Chaos No-show sub, wrong delivery,
rock ledge, neighbor complaint
More random events Update
Vehicles Starter truck Rusty single-cab Launch
Vehicles Work pickup First upgrade, more cargo Launch
Vehicles Heavy-duty dually and custom
trucks
Late-game and premium
trucks
Update
Vehicles Truck customization Wraps, wheels, light bars Update
Progression Cash and payouts Pay by time, quality, and
damage
Launch
Progression Trade levels Each trade levels separately
and unlocks bigger jobs
Launch
Progression Tool upgrades Laser level, better nail gun,
pipe bender
Update
Construction Crew — Roblox Game Plan
Page 5 of 12

<!-- page 6 -->
Sample job: starter house, about 15 minutes
The rule for every phase: no trade sits idle for more than a minute. When one trade leads,
the others prep the next phase.
Area Feature What it does Release
Progression Own Your Company Hire bot crews, take contracts
under your name
Update
Economy Saving (DataStore) Cash, trucks, and levels
persist
Launch
Economy Server-side checks Server confirms every
placement and payout
Launch
Monetization Rush delivery, hire a pro, retry
inspection
Repeatable crew-helping
purchases
Launch
Monetization 2× pay pass, cash packs Core passes and products Launch
Monetization Premium trucks, cosmetics,
Own Your Company pass
Status and late-game passes Update
Retention Daily contract One bonus job a day; streaks
raise the bonus
Launch
Retention Codes Released at like milestones
and updates
Launch
Retention Group reward Cash bonus for joining the
Roblox group
Launch
Retention Crew leaderboards Fastest build, most jobs, best
quality; weekly reset
Update
Retention Invite bonus Extra pay for finishing a job
with a friend you brought
Update
Platform Mobile controls Tap-based tasks and on-
screen prompts
Launch
Platform Settings Graphics quality, sound,
control layout
Launch
Construction Crew — Roblox Game Plan
Page 6 of 12

<!-- page 7 -->
Bigger jobs add phases (drywall, HVAC, second floor) and stretch to 25–40 minutes.
Chaos events
Chaos is how the game spreads: funny failures get clipped and posted to TikTok and
YouTube. Plan for one or two random events per job, more on harder tiers.
Surprise inspector: shows up mid-phase; every visible mistake costs money.
Rain delay: concrete can't be poured; mud slows trucks and the crane.
Crane mishap: a badly rigged load swings and drops; physics does the rest.
No-show sub: one bot worker doesn't show up; someone has to cover two trades.
Wrong delivery: the lumber truck brings the wrong order; the Laborer drives back to
the yard.
Hidden problem: a rock ledge or old pipe when digging the footings.
Neighbor complaint: noise warning; a timer to finish loud work.
Structural fail: skip steps and the house can partly collapse at inspection. This is the
main clip moment, and the bridge game's collapse physics can be reused here.
Time Phase Foreman Laborer Concrete Operator Electrician Plumber
0–2
min
Site prep Lays out the
stakes from
the plan
Unloads
and stages
materials
Builds
forms
Digs
footings
Sets the
temporary
power pole
Lays the
drain lines
under the
slab
2–5
min
Foundation Checks
levels
Moves
rebar
Pours and
finishes
the slab
Runs the
concrete
truck chute
Grounding
rod
Caps lines,
pressure
test
5–9
min
Framing Calls
mistakes
Nail-gun
walls
Helps
frame
Lifts
trusses
with the
crane
Pre-drills
studs
Pre-drills
studs
9–12
min
Rough-in Schedules
inspection
Hangs
sheathing
and roofing
Pours
porch and
walkway
Lifts
roofing
pallets
Runs wire,
sets the
panel
Runs
supply
lines
12–15
min
Finish and
inspection
Walks the
inspector
Cleanup Driveway Hauls the
dumpster
Outlets,
fixtures,
power on
Fixtures,
water on
Construction Crew — Roblox Game Plan
Page 7 of 12

<!-- page 8 -->
Progression and economy
Pay rises faster than job length, so bigger jobs are always worth it. A new player should
afford their first truck upgrade within 2–3 jobs. All dollar amounts are starting numbers to
tune in playtests.
Payout modifiers: finish early +25%; quality score from 0.5× to 1.5×; damage and rework
subtract.
What players spend on:
Trucks: rusty single-cab → work pickup → heavy-duty dually → custom trucks. Bigger
trucks carry more materials, so fewer trips back to the yard.
Tools: better nail gun, laser level, pipe bender. Faster or more accurate work, not raw
power.
Trade levels: unlock harder tasks and bigger jobs.
Late game: buy a company, hire bot crews, and take contracts from the job board
under your own name.
Monetization
You keep about $0.0027 per Robux a player spends: Roblox takes 30%, then DevEx pays
$0.0038 per earned Robux. So the money comes from volume and repeat purchases, not
price. Sell speed, style, and status, never a way to skip the crew. (rates)
The best angle: buys that help the whole crew. When one player buys rush delivery,
everyone on site benefits and sees their name pop up. Spending becomes status, and the
whole server sees what's for sale.
Tier Job Length Crew
size
Base pay per
player
Unlock
1 Shed / garage 8 min 2–3 $500 Start
2 Starter house 15 min 3–5 $1,500 Trade level 3
3 Two-story family home 25 min 4–6 $4,000 Trade level 8 + mid
truck
4 Luxury custom home 35 min 5–6 $10,000 Trade level 15
5 Commercial (strip mall,
warehouse)
45 min 6 $25,000 Company license
Construction Crew — Roblox Game Plan
Page 8 of 12

<!-- page 9 -->
Never sell: auto-build, skip-phase, or anything that finishes a job without the crew.
Rough earnings at 3% buying 200 R$ a month (my assumptions, not benchmarks): 1,000
daily players ≈ $480/month; 10,000 ≈ $4,800; 50,000 ≈ $24,000. Retention and player count
matter far more than prices.
New-player bonus: Roblox's Audience Expansion Rewards pay 35% of a brand-new user's
first $100 in purchases anywhere on Roblox for 60 days. TikTok clips that bring new users
to Roblox pay twice. (source)
Free growth levers (cheap to build, and they keep players coming back):
Daily contract: one bonus job a day for extra pay; streaks raise the bonus.
Like and group rewards: codes at like milestones; a cash bonus for joining the Roblox
group, which lets you message players about updates.
Item Type Price Notes
Rush delivery Developer product,
repeatable
25–49 R$ Materials arrive instantly for the
whole crew
Hire a pro Developer product,
repeatable
49–99 R$ Skilled bot fills an empty slot for
one job
Retry
inspection
Developer product,
repeatable
35 R$ Keep the job instead of taking
the penalty
Cash packs Developer product,
repeatable
49–499 R$ Faster upgrades
Premium trucks Robux, one-time 199–799 R$ Visible flex, slightly more cargo;
best truck still earnable by
grinding
2× pay Game pass 299 R$ Applies to the buyer only
Own Your
Company
Game pass 499 R$ Bot crews, private job board,
company logo
Cosmetics Robux 25–150 R$ Hard hats, vests, boots, crew
logos, truck wraps
Private servers Roblox built-in 100
R$/month
For crews that play together
Construction Crew — Roblox Game Plan
Page 9 of 12

<!-- page 10 -->
Crew leaderboards: fastest starter house, most jobs, highest quality score, reset
weekly.
Invite bonus: extra pay when you finish a job with a friend you brought in.
Build roadmap
Soft launch in 8 weeks at about 8–10 hours a week, then ship an update every week. On
Roblox, live player data beats more polish, so get real players in early. Each phase ends
with a gate; don't move on until you pass it.
Each dashed line is a gate. Don't start the next phase until you pass it; the details are in
the list below.
1. Week 1: Paper design. Write the starter-house job minute by minute for each role.
Sketch one site.
Gate: no role idle for more than a minute on paper.
2. Weeks 2–4: Gray box. Task engine (carry, place, timing, connect), ghost blueprints,
one truck, a shed job with Laborer, Operator, and Foreman.
Gate: you and 2 friends play it 3 times and want a 4th run.
3. Weeks 5–7: Vertical slice. Starter house with all 4 launch roles, drop-in onboarding,
bot workers, saving, pay, 2 trucks, 3 chaos events, 2× pay pass.
Gate: a stranger on a phone finishes a job without help.
build timeline · 8 weeks, 3 gates
Construction Crew — Roblox Game Plan
Page 10 of 12

<!-- page 11 -->
4. Week 8: Soft launch. Go public with a strong icon and thumbnail. Post 1–2 clips a day
on TikTok, YouTube Shorts, and Reels.
5. Weekly updates after launch. Every week: a new truck, chaos event, or cosmetic, plus
a code. Every 3–4 weeks: a new role or job tier (Plumber, Concrete, two-story homes,
then commercial). Oil rigs come later as a new job type that reuses trucks, roles, and
chaos.
Risks, metrics, and next steps
Biggest risks:
Metrics to watch after launch: day-1 retention (aim for 20%+), average session length
(15+ minutes), share of players who finish their first job (60%+), and how many clips
players post.
This week:
Risk What it looks like Fix
Slow first
minutes
New players land in a hub, get
bored, and leave
Drop them straight into a live job;
hub unlocks after the first payout
Idle roles Players stand around waiting for the
slab to set
Every phase gives every role a task;
prep work for the next phase
Clunky on
phones
Minigames need a mouse; most
players are on mobile
Tap-based tasks; test on a phone
every week
Empty
servers
Solo players can't find a crew Quick Join, bot workers in any slot,
solo shed jobs
Griefers Someone wrecks the house or
steals the truck
Ghost blueprints only; Foreman can
kick; no pay for whoever causes
damage
Money
exploits
Exploiters spawn cash and wreck
the economy
Server checks every placement and
payout
Scope creep Six roles, oil, and commercial jobs
before launch
Launch with 4 roles and 2 job tiers;
add the rest as weekly updates
Too many
projects
Bridge game and this split your time Pick this one; reuse the bridge
collapse physics here
Construction Crew — Roblox Game Plan
Page 11 of 12

<!-- page 12 -->
Write the minute-by-minute starter-house job on paper
Play House Construction Tycoon and Construction Simulator for 20 minutes each;
note what's missing
Gray-box the site and get one truck driving in Roblox Studio
Line up 2 friends for the first playtest
Construction Crew — Roblox Game Plan
Page 12 of 12
