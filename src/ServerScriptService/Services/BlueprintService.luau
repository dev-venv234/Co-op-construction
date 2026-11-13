--!strict
-- Builds a job site from blueprint data: ghost slots (locked / open / done), material piles, and prompts.
-- Prompts carry attributes (SlotId, Role, Open, PileItem) so the client can show only the ones that matter;
-- the server still re-checks everything when a prompt fires.
local Blueprint = {}

export type Slot = {
	def: any,
	part: BasePart,
	prompt: ProximityPrompt,
	done: boolean,
	open: boolean,
	busyBy: Player?,
}

local LOCKED = Color3.fromRGB(90, 110, 140)

-- Enum lookups throw on unknown names, so fall back safely.
local function material(name: string?): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and m then m else Enum.Material.SmoothPlastic
end
local OPEN = Color3.fromRGB(80, 220, 255)

local function makePrompt(parent: Instance, action: string, object: string, reach: number): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = reach
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.GamepadKeyCode = Enum.KeyCode.ButtonX
	pp.Parent = parent
	return pp
end

function Blueprint.SetVisual(slot: Slot, mode: string)
	local p = slot.part
	if mode == "done" then
		local d = slot.def.Done
		p.Color = d.Color
		p.Material = material(d.Material)
		p.Transparency = d.Transparency or 0
		p.CanCollide = slot.def.Collide ~= false
	elseif mode == "open" then
		p.Color = OPEN
		p.Material = Enum.Material.Neon
		p.Transparency = 0.55
		p.CanCollide = false
	else
		p.Color = LOCKED
		p.Material = Enum.Material.Glass
		p.Transparency = 0.88
		p.CanCollide = false
	end
end

function Blueprint.AddPile(site: Instance, item: string, itemDef: any, worldPos: Vector3): ProximityPrompt
	local pile = Instance.new("Part")
	pile.Name = "Pile_" .. item
	pile.Anchored = true
	pile.Size = Vector3.new(3, 2, 3)
	pile.Position = worldPos + Vector3.new(0, 1, 0)
	pile.Color = itemDef.Color
	pile.Material = material(itemDef.Material)
	pile.Parent = site
	local pp = makePrompt(pile, "Pick up " .. item, "Pile", 10)
	pp:SetAttribute("PileItem", item)

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 30)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.MaxDistance = 80
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 0.4
	t.BackgroundColor3 = Color3.new(0, 0, 0)
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.Text = item .. "s"
	t.Parent = bb
	bb.Parent = pile
	return pp
end

-- One ghost slot (locked to start). Build uses it for the blueprint; JobService.AddSlot for rework tasks.
function Blueprint.AddSlot(site: Instance, def: any, cf: CFrame): Slot
	local part = Instance.new("Part")
	part.Name = "Slot_" .. def.Id
	part.Anchored = true
	part.CastShadow = false
	part.Size = def.Size
	part.CFrame = cf
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = site
	local pp = makePrompt(part, def.Label, def.Role, def.Reach or 12)
	pp:SetAttribute("SlotId", def.Id)
	pp:SetAttribute("Role", def.Role)
	pp:SetAttribute("Open", false)
	-- Read by the client guide (GuideController) to point at the next step. Display only.
	pp:SetAttribute("Kind", def.Kind)
	pp:SetAttribute("Item", def.Item)
	pp:SetAttribute("Equipment", def.Equipment)
	local slot: Slot = { def = def, part = part, prompt = pp, done = false, open = false }
	Blueprint.SetVisual(slot, "locked")
	return slot
end

-- originCF places the blueprint on a site: its position is the lot center, its rotation turns the
-- blueprint's front (local -Z) toward the site's road gate. skipPiles: items that arrive later by truck.
function Blueprint.Build(bp: any, parent: Instance, originCF: CFrame, skipPiles: { [string]: boolean }?): (Model, { [string]: Slot }, { [string]: ProximityPrompt })
	local site = Instance.new("Model")
	site.Name = "JobSite_" .. bp.Id

	local slots: { [string]: Slot } = {}
	for _, def in bp.Slots do
		slots[def.Id] = Blueprint.AddSlot(site, def, originCF * CFrame.new(def.Pos))
	end

	local piles: { [string]: ProximityPrompt } = {}
	for _, pile in bp.Piles do
		if skipPiles and skipPiles[pile.Item] then
			continue
		end
		piles[pile.Item] = Blueprint.AddPile(site, pile.Item, bp.Items[pile.Item], originCF:PointToWorldSpace(pile.Pos))
	end

	site.Parent = parent
	return site, slots, piles
end

return Blueprint
