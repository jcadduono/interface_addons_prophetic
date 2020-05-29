if select(2, UnitClass('player')) ~= 'PRIEST' then
	DisableAddOn('Prophetic')
	return
end

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Prophetic = {}
local Opt -- use this as a local table reference to Prophetic

SLASH_Prophetic1, SLASH_Prophetic2 = '/pro', '/prophetic'
BINDING_HEADER_PROPHETIC = 'Prophetic'

local function InitOpts()
	local function SetDefaults(t, ref)
		local k, v
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Prophetic, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			discipline = false,
			holy = false,
			shadow = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		pot = false,
		trinket = true,
		pws_threshold = 60,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- specialization constants
local SPEC = {
	NONE = 0,
	DISCIPLINE = 1,
	HOLY = 2,
	SHADOW = 3,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	target_mode = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	mana = 0,
	mana_max = 0,
	mana_regen = 0,
	insanity = 0,
	insanity_max = 100,
	insanity_drain = 0,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[165581] = true, -- Crest of Pa'ku (Horde)
		[174044] = true, -- Humming Black Dragonscale (parachute)
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false,
	estimated_range = 30,
}

-- Azerite trait API access
local Azerite = {}

-- base mana for each level
local BaseMana = {
	145,        160,    175,    190,    205,    -- 5
	220,        235,    250,    290,    335,    -- 10
	390,        445,    510,    580,    735,    -- 15
	825,        865,    910,    950,    995,    -- 20
	1060,       1125,   1195,   1405,   1490,   -- 25
	1555,       1620,   1690,   1760,   1830,   -- 30
	2110,       2215,   2320,   2425,   2540,   -- 35
	2615,       2695,   3025,   3110,   3195,   -- 40
	3270,       3345,   3420,   3495,   3870,   -- 45
	3940,       4015,   4090,   4170,   4575,   -- 50
	4660,       4750,   4835,   5280,   5380,   -- 55
	5480,       5585,   5690,   5795,   6300,   -- 60
	6420,       6540,   6660,   6785,   6915,   -- 65
	7045,       7175,   7310,   7915,   8065,   -- 70
	8215,       8370,   8530,   8690,   8855,   -- 75
	9020,       9190,   9360,   10100,  10290,  -- 80
	10485,      10680,  10880,  11085,  11295,  -- 85
	11505,      11725,  12605,  12845,  13085,  -- 90
	13330,      13585,  13840,  14100,  14365,  -- 95
	14635,      15695,  15990,  16290,  16595,  -- 100
	16910,      17230,  17550,  17880,  18220,  -- 105
	18560,      18910,  19265,  19630,  20000,  -- 110
	35985,      42390,  48700,  54545,  59550,  -- 115
	64700,      68505,  72450,  77400,  100000  -- 120
}

local propheticPanel = CreateFrame('Frame', 'propheticPanel', UIParent)
propheticPanel:SetPoint('CENTER', 0, -169)
propheticPanel:SetFrameStrata('BACKGROUND')
propheticPanel:SetSize(64, 64)
propheticPanel:SetMovable(true)
propheticPanel:Hide()
propheticPanel.icon = propheticPanel:CreateTexture(nil, 'BACKGROUND')
propheticPanel.icon:SetAllPoints(propheticPanel)
propheticPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
propheticPanel.border = propheticPanel:CreateTexture(nil, 'ARTWORK')
propheticPanel.border:SetAllPoints(propheticPanel)
propheticPanel.border:SetTexture('Interface\\AddOns\\Prophetic\\border.blp')
propheticPanel.border:Hide()
propheticPanel.dimmer = propheticPanel:CreateTexture(nil, 'BORDER')
propheticPanel.dimmer:SetAllPoints(propheticPanel)
propheticPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
propheticPanel.dimmer:Hide()
propheticPanel.swipe = CreateFrame('Cooldown', nil, propheticPanel, 'CooldownFrameTemplate')
propheticPanel.swipe:SetAllPoints(propheticPanel)
propheticPanel.swipe:SetDrawBling(false)
propheticPanel.text = CreateFrame('Frame', nil, propheticPanel)
propheticPanel.text:SetAllPoints(propheticPanel)
propheticPanel.text.tl = propheticPanel.text:CreateFontString(nil, 'OVERLAY')
propheticPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
propheticPanel.text.tl:SetPoint('TOPLEFT', propheticPanel, 'TOPLEFT', 2.5, -3)
propheticPanel.text.tl:SetJustifyH('LEFT')
propheticPanel.text.tl:SetJustifyV('TOP')
propheticPanel.text.tr = propheticPanel.text:CreateFontString(nil, 'OVERLAY')
propheticPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
propheticPanel.text.tr:SetPoint('TOPRIGHT', propheticPanel, 'TOPRIGHT', -2.5, -3)
propheticPanel.text.tr:SetJustifyH('RIGHT')
propheticPanel.text.tr:SetJustifyV('TOP')
propheticPanel.text.bl = propheticPanel.text:CreateFontString(nil, 'OVERLAY')
propheticPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
propheticPanel.text.bl:SetPoint('BOTTOMLEFT', propheticPanel, 'BOTTOMLEFT', 2.5, 3)
propheticPanel.text.bl:SetJustifyH('LEFT')
propheticPanel.text.bl:SetJustifyV('BOTTOM')
propheticPanel.text.br = propheticPanel.text:CreateFontString(nil, 'OVERLAY')
propheticPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
propheticPanel.text.br:SetPoint('BOTTOMRIGHT', propheticPanel, 'BOTTOMRIGHT', -2.5, 3)
propheticPanel.text.br:SetJustifyH('RIGHT')
propheticPanel.text.br:SetJustifyV('BOTTOM')
propheticPanel.text.center = propheticPanel.text:CreateFontString(nil, 'OVERLAY')
propheticPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 10, 'OUTLINE')
propheticPanel.text.center:SetAllPoints(propheticPanel.text)
propheticPanel.text.center:SetJustifyH('CENTER')
propheticPanel.text.center:SetJustifyV('CENTER')
propheticPanel.button = CreateFrame('Button', nil, propheticPanel)
propheticPanel.button:SetAllPoints(propheticPanel)
propheticPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local propheticPreviousPanel = CreateFrame('Frame', 'propheticPreviousPanel', UIParent)
propheticPreviousPanel:SetFrameStrata('BACKGROUND')
propheticPreviousPanel:SetSize(64, 64)
propheticPreviousPanel:Hide()
propheticPreviousPanel:RegisterForDrag('LeftButton')
propheticPreviousPanel:SetScript('OnDragStart', propheticPreviousPanel.StartMoving)
propheticPreviousPanel:SetScript('OnDragStop', propheticPreviousPanel.StopMovingOrSizing)
propheticPreviousPanel:SetMovable(true)
propheticPreviousPanel.icon = propheticPreviousPanel:CreateTexture(nil, 'BACKGROUND')
propheticPreviousPanel.icon:SetAllPoints(propheticPreviousPanel)
propheticPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
propheticPreviousPanel.border = propheticPreviousPanel:CreateTexture(nil, 'ARTWORK')
propheticPreviousPanel.border:SetAllPoints(propheticPreviousPanel)
propheticPreviousPanel.border:SetTexture('Interface\\AddOns\\Prophetic\\border.blp')
local propheticCooldownPanel = CreateFrame('Frame', 'propheticCooldownPanel', UIParent)
propheticCooldownPanel:SetSize(64, 64)
propheticCooldownPanel:SetFrameStrata('BACKGROUND')
propheticCooldownPanel:Hide()
propheticCooldownPanel:RegisterForDrag('LeftButton')
propheticCooldownPanel:SetScript('OnDragStart', propheticCooldownPanel.StartMoving)
propheticCooldownPanel:SetScript('OnDragStop', propheticCooldownPanel.StopMovingOrSizing)
propheticCooldownPanel:SetMovable(true)
propheticCooldownPanel.icon = propheticCooldownPanel:CreateTexture(nil, 'BACKGROUND')
propheticCooldownPanel.icon:SetAllPoints(propheticCooldownPanel)
propheticCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
propheticCooldownPanel.border = propheticCooldownPanel:CreateTexture(nil, 'ARTWORK')
propheticCooldownPanel.border:SetAllPoints(propheticCooldownPanel)
propheticCooldownPanel.border:SetTexture('Interface\\AddOns\\Prophetic\\border.blp')
propheticCooldownPanel.cd = CreateFrame('Cooldown', nil, propheticCooldownPanel, 'CooldownFrameTemplate')
propheticCooldownPanel.cd:SetAllPoints(propheticCooldownPanel)
local propheticInterruptPanel = CreateFrame('Frame', 'propheticInterruptPanel', UIParent)
propheticInterruptPanel:SetFrameStrata('BACKGROUND')
propheticInterruptPanel:SetSize(64, 64)
propheticInterruptPanel:Hide()
propheticInterruptPanel:RegisterForDrag('LeftButton')
propheticInterruptPanel:SetScript('OnDragStart', propheticInterruptPanel.StartMoving)
propheticInterruptPanel:SetScript('OnDragStop', propheticInterruptPanel.StopMovingOrSizing)
propheticInterruptPanel:SetMovable(true)
propheticInterruptPanel.icon = propheticInterruptPanel:CreateTexture(nil, 'BACKGROUND')
propheticInterruptPanel.icon:SetAllPoints(propheticInterruptPanel)
propheticInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
propheticInterruptPanel.border = propheticInterruptPanel:CreateTexture(nil, 'ARTWORK')
propheticInterruptPanel.border:SetAllPoints(propheticInterruptPanel)
propheticInterruptPanel.border:SetTexture('Interface\\AddOns\\Prophetic\\border.blp')
propheticInterruptPanel.cast = CreateFrame('Cooldown', nil, propheticInterruptPanel, 'CooldownFrameTemplate')
propheticInterruptPanel.cast:SetAllPoints(propheticInterruptPanel)
local propheticExtraPanel = CreateFrame('Frame', 'propheticExtraPanel', UIParent)
propheticExtraPanel:SetFrameStrata('BACKGROUND')
propheticExtraPanel:SetSize(64, 64)
propheticExtraPanel:Hide()
propheticExtraPanel:RegisterForDrag('LeftButton')
propheticExtraPanel:SetScript('OnDragStart', propheticExtraPanel.StartMoving)
propheticExtraPanel:SetScript('OnDragStop', propheticExtraPanel.StopMovingOrSizing)
propheticExtraPanel:SetMovable(true)
propheticExtraPanel.icon = propheticExtraPanel:CreateTexture(nil, 'BACKGROUND')
propheticExtraPanel.icon:SetAllPoints(propheticExtraPanel)
propheticExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
propheticExtraPanel.border = propheticExtraPanel:CreateTexture(nil, 'ARTWORK')
propheticExtraPanel.border:SetAllPoints(propheticExtraPanel)
propheticExtraPanel.border:SetTexture('Interface\\AddOns\\Prophetic\\border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.DISCIPLINE] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.HOLY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.SHADOW] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	}
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	propheticPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function Prophetic_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Prophetic_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Prophetic_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:Purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		mana_cost = 0,
		insanity_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable(seconds)
	if not self.known then
		return false
	end
	if self:Cost() > Player.mana then
		return false
	end
	if Player.spec == SPEC.SHADOW and self:InsanityCost() > Player.insanity then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up()
	return self:Remains() > 0
end

function Ability:Down()
	return not self:Up()
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:Traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self:Casting() then
		if self.requires_charge then
			if self:Charges() == 0 then
				return self.cooldown_duration
			end
		elseif self.cooldown_duration > 0 then
			return self.cooldown_duration
		end
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:Cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana_base) or 0
end

function Ability:InsanityCost()
	return self.insanity_cost or 0
end

function Ability:Charges()
	local charges = (GetSpellCharges(self.spellId)) or 0
	if self:Casting() then
		charges = charges - 1
	end
	return max(0, charges)
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges < max_charges then
		charges = charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
	end
	if self:Casting() then
		charges = charges - 1
	end
	return min(max_charges, max(0, charges))
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return Player.ability_channeling == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:CastRegen()
	return Player.mana_regen * self:CastTime() - self:Cost()
end

function Ability:WontCapMana(reduction)
	return (Player.mana + self:CastRegen()) < (Player.mana_max - (reduction or 5))
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AzeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:Update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Priest Abilities
---- Multiple Specializations
local DesperatePrayer = Ability:Add(19236, true, true)
DesperatePrayer.buff_duration = 10
DesperatePrayer.cooldown_duration = 90
local DispelMagic = Ability:Add(528, false, true)
DispelMagic.mana_cost = 1.6
local Fade = Ability:Add(586, false, true)
Fade.buff_duration = 10
Fade.cooldown_duration = 30
local HolyNova = Ability:Add(132157, false, true, 281265)
HolyNova.mana_cost = 1.6
HolyNova:AutoAoe(true)
local LeapOfFaith = Ability:Add(73325, false, true)
LeapOfFaith.mana_cost = 2.6
LeapOfFaith.cooldown_duration = 90
local Levitate = Ability:Add(1706, true, false, 111759)
Levitate.mana_cost = 0.9
Levitate.buff_duration = 600
local Lightspawn = Ability:Add(254224, false, true)
Lightspawn.cooldown_duration = 180
local MassDispel = Ability:Add(32375, true, true)
MassDispel.mana_cost = 8
MassDispel.cooldown_duration = 45
local MindControl = Ability:Add(605, false, true)
MindControl.mana_cost = 2
MindControl.buff_duration = 30
local PowerWordFortitude = Ability:Add(21562, true, false)
PowerWordFortitude.mana_cost = 4
PowerWordFortitude.buff_duration = 3600
local Purify = Ability:Add(527, true, true)
Purify.mana_cost = 1.3
Purify.cooldown_duration = 8
local Shadowfiend = Ability:Add(34433, false, true)
Shadowfiend.cooldown_duration = 180
local ShadowWordPain = Ability:Add(589, false, true)
ShadowWordPain.mana_cost = 1.8
ShadowWordPain.buff_duration = 16
ShadowWordPain.tick_interval = 2
ShadowWordPain.hasted_ticks = true
ShadowWordPain.insanity_cost = -4
ShadowWordPain:TrackAuras()
local Smite = Ability:Add(585, false, true, 208772)
Smite.mana_cost = 0.5
------ Talents
local DivineStar = Ability:Add(110744, false, true, 110745)
DivineStar.mana_cost = 2
DivineStar.cooldown_duration = 15
DivineStar:AutoAoe()
local Halo = Ability:Add(120517, false, true, 120692)
Halo.mana_cost = 2.7
Halo.cooldown_duration = 40
local ShiningForce = Ability:Add(204263, false, true)
ShiningForce.cooldown_duration = 45
ShiningForce.buff_duration = 3
------ Procs

---- Discipline
local Atonement = Ability:Add(81749, true, true, 194384)
Atonement.buff_duration = 15
local PainSuppression = Ability:Add(33206, true, true)
PainSuppression.mana_cost = 1.6
PainSuppression.buff_duration = 8
PainSuppression.cooldown_duration = 180
local Penance = Ability:Add(47540, false, true, 47666)
Penance.mana_cost = 2
Penance.buff_duration = 2
Penance.cooldown_duration = 9
Penance.hasted_duration = true
Penance.channel_fully = true
local PowerWordBarrier = Ability:Add(62618, true, true, 81782)
PowerWordBarrier.mana_cost = 4
PowerWordBarrier.buff_duration = 10
PowerWordBarrier.cooldown_duration = 180
local PowerWordRadiance = Ability:Add(194509, true, true)
PowerWordRadiance.mana_cost = 6.5
PowerWordRadiance.cooldown_duration = 20
PowerWordRadiance.requires_charge = true
local PowerWordShield = Ability:Add(17, true, true)
PowerWordShield.mana_cost = 2.65
PowerWordShield.buff_duration = 15
local Rapture = Ability:Add(47536, true, true)
Rapture.buff_duration = 10
Rapture.cooldown_duration = 90
local ShadowMend = Ability:Add(186263, false, true)
ShadowMend.buff_duration = 10
local WeakenedSoul = Ability:Add(6788, false, true)
WeakenedSoul.buff_duration = 6
WeakenedSoul.auraTarget = 'player'
------ Talents
local PurgeTheWicked = Ability:Add(204197, false, true, 204213)
PurgeTheWicked.buff_duration = 20
PurgeTheWicked.mana_cost = 1.8
PurgeTheWicked.tick_interval = 2
PurgeTheWicked.hasted_ticks = true
local PowerWordSolace = Ability:Add(129250, false, true)
PowerWordSolace.mana_cost = -1
local Schism = Ability:Add(214621, false, true)
Schism.buff_duration = 9
Schism.cooldown_duration = 24
Schism.mana_cost = 0.5
local SearingLight = Ability:Add(215768, false, true)
local MindbenderDisc = Ability:Add(123040, false, true)
------ Procs
---- Holy
local HolyFire = Ability:Add(14914, false, true)
local HolyWordChastise = Ability:Add(88625, false, true)
local Renew = Ability:Add(139, true, true)
Renew.mana_cost = 1.8
Renew.buff_duration = 15
Renew.tick_interval = 2
Renew.hasted_ticks = true
------ Talents

------ Procs

---- Shadow
local Dispersion = Ability:Add(47585, true, true)
Dispersion.buff_duration = 6
Dispersion.cooldown_duration = 120
local MindBlast = Ability:Add(8092, false, true)
MindBlast.cooldown_duration = 7.5
MindBlast.insanity_cost = -12
MindBlast.hasted_cooldown = true
local MindFlay = Ability:Add(15407, false, true)
local MindSear = Ability:Add(48045, false, true, 49821)
MindSear:AutoAoe(true)
local Shadowform = Ability:Add(232698, true, true)
local Silence = Ability:Add(15487, false, true)
Silence.cooldown_duration = 45
Silence.buff_duration = 4
local VampiricTouch = Ability:Add(34914, false, true)
VampiricTouch.buff_duration = 21
VampiricTouch.tick_interval = 3
VampiricTouch.hasted_ticks = true
VampiricTouch.insanity_cost = -6
VampiricTouch:TrackAuras()
local VoidBolt = Ability:Add(205448, false, true)
VoidBolt.cooldown_duration = 4.5
VoidBolt.insanity_cost = -20
VoidBolt.hasted_cooldown = true
local VoidEruption = Ability:Add(228260, false, true, 228360)
VoidEruption.insanity_cost = 90
VoidEruption:AutoAoe()
local Voidform = Ability:Add(228264, true, true, 194249)
Voidform.insanity_drain_stack = 0
Voidform.insanity_drain_paused = false
------ Talents
local DarkAscension = Ability:Add(280711, false, true)
DarkAscension.cooldown_duration = 60
DarkAscension.insanity_cost = -50
local DarkVoid = Ability:Add(263346, false, true)
DarkVoid.cooldown_duration = 30
DarkVoid.insanity_cost = -30
DarkVoid:AutoAoe()
local LegacyOfTheVoid = Ability:Add(193225, true, true)
local MindbenderShadow = Ability:Add(200174, false, true)
MindbenderShadow.buff_duration = 15
MindbenderShadow.cooldown_duration = 60
local Misery = Ability:Add(238558, false, true)
local ShadowCrash = Ability:Add(205385, false, true, 205386)
ShadowCrash.cooldown_duration = 20
ShadowCrash.insanity_cost = -20
ShadowCrash:AutoAoe()
local ShadowWordDeath = Ability:Add(32379, false, true)
ShadowWordDeath.cooldown_duration = 9
ShadowWordDeath.insanity_cost = -15
ShadowWordDeath.requires_charge = true
local ShadowWordVoid = Ability:Add(205351, false, true)
ShadowWordVoid.cooldown_duration = 9
ShadowWordVoid.insanity_cost = -15
ShadowWordVoid.hasted_cooldown = true
ShadowWordVoid.requires_charge = true
local SurrenderToMadness = Ability:Add(193223, false, true)
SurrenderToMadness.buff_duration = 60
SurrenderToMadness.cooldown_duration = 180
local VoidTorrent = Ability:Add(263165, true, true)
VoidTorrent.buff_duration = 4
VoidTorrent.cooldown_duration = 45
------ Procs

-- Heart of Azeroth
---- Azerite Traits
local ChorusOfInsanity = Ability:Add(278661, true, true, 279572)
ChorusOfInsanity.buff_duration = 120
local DeathThroes = Ability:Add(278659, true, true)
local DepthOfTheShadows = Ability:Add(275541, true, true, 275544)
DepthOfTheShadows.buff_duration = 12
local SearingDialogue = Ability:Add(272788, false, true, 288371)
local SpitefulApparitions = Ability:Add(277682, true, true)
local SuddenRevelation = Ability:Add(287355, true, true, 287360)
SuddenRevelation.buff_duration = 30
local ThoughtHarvester = Ability:Add(288340, true, true, 288343)
ThoughtHarvester.buff_duration = 20
local WhispersOfTheDamned = Ability:Add(275722, true, true)
---- Major Essences
local BloodOfTheEnemy = Ability:Add(298277, false, true)
BloodOfTheEnemy.buff_duration = 10
BloodOfTheEnemy.cooldown_duration = 120
BloodOfTheEnemy.essence_id = 23
BloodOfTheEnemy.essence_major = true
local ConcentratedFlame = Ability:Add(295373, true, true, 295378)
ConcentratedFlame.buff_duration = 180
ConcentratedFlame.cooldown_duration = 30
ConcentratedFlame.requires_charge = true
ConcentratedFlame.essence_id = 12
ConcentratedFlame.essence_major = true
ConcentratedFlame:SetVelocity(40)
ConcentratedFlame.dot = Ability:Add(295368, false, true)
ConcentratedFlame.dot.buff_duration = 6
ConcentratedFlame.dot.tick_interval = 2
ConcentratedFlame.dot.essence_id = 12
ConcentratedFlame.dot.essence_major = true
local GuardianOfAzeroth = Ability:Add(295840, false, true)
GuardianOfAzeroth.cooldown_duration = 180
GuardianOfAzeroth.essence_id = 14
GuardianOfAzeroth.essence_major = true
local FocusedAzeriteBeam = Ability:Add(295258, false, true)
FocusedAzeriteBeam.cooldown_duration = 90
FocusedAzeriteBeam.essence_id = 5
FocusedAzeriteBeam.essence_major = true
local MemoryOfLucidDreams = Ability:Add(298357, true, true)
MemoryOfLucidDreams.buff_duration = 15
MemoryOfLucidDreams.cooldown_duration = 120
MemoryOfLucidDreams.essence_id = 27
MemoryOfLucidDreams.essence_major = true
local PurifyingBlast = Ability:Add(295337, false, true, 295338)
PurifyingBlast.cooldown_duration = 60
PurifyingBlast.essence_id = 6
PurifyingBlast.essence_major = true
PurifyingBlast:AutoAoe(true)
local ReapingFlames = Ability:Add(310690, false, true) -- 311195
ReapingFlames.cooldown_duration = 45
ReapingFlames.essence_id = 35
ReapingFlames.essence_major = true
local RippleInSpace = Ability:Add(302731, true, true)
RippleInSpace.buff_duration = 2
RippleInSpace.cooldown_duration = 60
RippleInSpace.essence_id = 15
RippleInSpace.essence_major = true
local TheUnboundForce = Ability:Add(298452, false, true)
TheUnboundForce.cooldown_duration = 45
TheUnboundForce.essence_id = 28
TheUnboundForce.essence_major = true
local VisionOfPerfection = Ability:Add(299370, true, true, 303345)
VisionOfPerfection.buff_duration = 10
VisionOfPerfection.essence_id = 22
VisionOfPerfection.essence_major = true
local WorldveinResonance = Ability:Add(295186, true, true)
WorldveinResonance.cooldown_duration = 60
WorldveinResonance.essence_id = 4
WorldveinResonance.essence_major = true
---- Minor Essences
local AncientFlame = Ability:Add(295367, false, true)
AncientFlame.buff_duration = 10
AncientFlame.essence_id = 12
local CondensedLifeForce = Ability:Add(295367, false, true)
CondensedLifeForce.essence_id = 14
local FocusedEnergy = Ability:Add(295248, true, true)
FocusedEnergy.buff_duration = 4
FocusedEnergy.essence_id = 5
local Lifeblood = Ability:Add(295137, true, true)
Lifeblood.essence_id = 4
local LucidDreams = Ability:Add(298343, true, true)
LucidDreams.buff_duration = 8
LucidDreams.essence_id = 27
local PurificationProtocol = Ability:Add(295305, false, true)
PurificationProtocol.essence_id = 6
PurificationProtocol:AutoAoe()
local RealityShift = Ability:Add(302952, true, true)
RealityShift.buff_duration = 20
RealityShift.cooldown_duration = 30
RealityShift.essence_id = 15
local RecklessForce = Ability:Add(302932, true, true)
RecklessForce.buff_duration = 3
RecklessForce.essence_id = 28
RecklessForce.counter = Ability:Add(302917, true, true)
RecklessForce.counter.essence_id = 28
local StriveForPerfection = Ability:Add(299369, true, true)
StriveForPerfection.essence_id = 22
-- Racials

-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items
local GreaterFlaskOfEndlessFathoms = InventoryItem:Add(168652)
GreaterFlaskOfEndlessFathoms.buff = Ability:Add(298837, true, true)
local PotionOfUnbridledFury = InventoryItem:Add(169299)
PotionOfUnbridledFury.buff = Ability:Add(300714, true, true)
PotionOfUnbridledFury.buff.triggers_gcd = false
local SuperiorBattlePotionOfIntellect = InventoryItem:Add(168498)
SuperiorBattlePotionOfIntellect.buff = Ability:Add(298152, true, true)
SuperiorBattlePotionOfIntellect.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:Init()
	self.locations = {}
	self.traits = {}
	self.essences = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:Update()
	local _, loc, slot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for pid in next, self.essences do
		self.essences[pid] = nil
	end
	if UnitEffectiveLevel('player') < 110 then
		return -- disable all Azerite/Essences for players scaled under 110
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			for _, slot in next, C_AzeriteEmpoweredItem.GetAllTierInfo(loc) do
				if slot.azeritePowerIDs then
					for _, pid in next, slot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								--print('Azerite found:', pinfo.azeritePowerID, GetSpellInfo(pinfo.spellID))
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
	for _, loc in next, C_AzeriteEssence.GetMilestones() or {} do
		if loc.slot then
			pid = C_AzeriteEssence.GetMilestoneEssence(loc.ID)
			if pid then
				pinfo = C_AzeriteEssence.GetEssenceInfo(pid)
				self.essences[pid] = {
					id = pid,
					rank = pinfo.rank,
					major = loc.slot == 0,
				}
			end
		end
	end
end

-- End Azerite Trait API

-- Start Player API

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:ManaDeficit()
	return self.mana_max - self.mana
end

function Player:ManaPct()
	return self.mana / self.mana_max * 100
end

function Player:ManaTimeToMax()
	local deficit = self.mana_max - self.mana
	if deficit <= 0 then
		return 0
	end
	return deficit / self.mana_regen
end

function Player:UnderAttack()
	return (Player.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateAbilities()
	Player.mana_base = BaseMana[UnitLevel('player')]
	Player.insanity_max = UnitPowerMax('player', 13)

	local _, ability

	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = false
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.spellId2 and C_LevelLink.IsSpellLocked(ability.spellId2)) then
			-- spell is locked, do not mark as known
		elseif IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) then
			ability.known = true
		elseif Azerite.traits[ability.spellId] then
			ability.known = true
		elseif ability.essence_id and Azerite.essences[ability.essence_id] then
			if ability.essence_major then
				ability.known = Azerite.essences[ability.essence_id].major
			else
				ability.known = true
			end
		end
	end

	if ShadowWordVoid.known then
		MindBlast.known = false
	end
	VoidBolt.known = VoidEruption.known
	Lightspawn.known = Shadowfiend.known
	if Player.spec == SPEC.DISCIPLINE then
		Player.swp = PurgeTheWicked.known and PurgeTheWicked or ShadowWordPain
	elseif Player.spec == SPEC.SHADOW then
--[[
actions.precombat+=/variable,name=mind_blast_targets,op=set,value=floor((4.5+azerite.whispers_of_the_damned.rank)%(1+0.27*azerite.searing_dialogue.rank))
actions.precombat+=/variable,name=swp_trait_ranks_check,op=set,value=(1-0.07*azerite.death_throes.rank+0.2*azerite.thought_harvester.rank)*(1-0.09*azerite.thought_harvester.rank*azerite.searing_dialogue.rank)
actions.precombat+=/variable,name=vt_trait_ranks_check,op=set,value=(1-0.04*azerite.thought_harvester.rank-0.05*azerite.spiteful_apparitions.rank)
actions.precombat+=/variable,name=vt_mis_trait_ranks_check,op=set,value=(1-0.07*azerite.death_throes.rank-0.03*azerite.thought_harvester.rank-0.055*azerite.spiteful_apparitions.rank)*(1-0.027*azerite.thought_harvester.rank*azerite.searing_dialogue.rank)
actions.precombat+=/variable,name=vt_mis_sd_check,op=set,value=1-0.014*azerite.searing_dialogue.rank
]]
		Player.mind_blast_targets = floor((4.5 + WhispersOfTheDamned:AzeriteRank()) / (1 + 0.27 * SearingDialogue:AzeriteRank()))
		Player.swp_trait_ranks_check = (1 - 0.07 * DeathThroes:AzeriteRank() + 0.2 * ThoughtHarvester:AzeriteRank()) * (1 - 0.09 * ThoughtHarvester:AzeriteRank() * SearingDialogue:AzeriteRank())
		Player.vt_trait_ranks_check = 1 - 0.04 * ThoughtHarvester:AzeriteRank() - 0.05 * SpitefulApparitions:AzeriteRank()
		Player.vt_mis_trait_ranks_check = (1 - 0.07 * DeathThroes:AzeriteRank() - 0.03 * ThoughtHarvester:AzeriteRank() - 0.055 * SpitefulApparitions:AzeriteRank()) * (1 - 0.027 * ThoughtHarvester:AzeriteRank() * SearingDialogue:AzeriteRank())
		Player.vt_mis_sd_check = 1 - 0.014 * SearingDialogue:AzeriteRank()
	end

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.healthArray, 1)
	self.healthArray[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * (Voidform.known and 15 or 25)
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.healthArray[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.hostile = true
		local i
		for i = 1, 25 do
			self.healthArray[i] = 0
		end
		self:UpdateHealth()
		if Opt.always_on then
			UI:UpdateCombat()
			propheticPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			propheticPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		local i
		for i = 1, 25 do
			self.healthArray[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		propheticPanel:Show()
		return true
	end
end

-- End Target API

-- Start Ability Modifications

function ConcentratedFlame.dot:Remains()
	if ConcentratedFlame:Traveling() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function PowerWordShield:Usable()
	if WeakenedSoul:Up() then
		return false
	end
	return Ability.Usable(self)
end

function Penance:Cooldown()
	local remains = Ability.Cooldown(self)
	if SearingLight.known and Smite:Casting() then
		remains = max(remains - 1, 0)
	end
	return remains
end

function ShadowWordPain:Cost()
	if Voidform.known then
		return 0
	end
	return Ability.Cost(self)
end

function Voidform:InsanityDrain()
	if self.insanity_drain_stack == 0 or self.insanity_drain_paused then
		return 0
	end
	return floor(6.5 + (2/3 * (self.insanity_drain_stack - 1)))
end

function VoidEruption:InsanityCost()
	if LegacyOfTheVoid.known then
		return 60
	end
	return Ability.Cost(self)
end

function VoidEruption:Usable()
	if Voidform:Up() then
		return false
	end
	return Ability.Usable(self)
end

function VoidBolt:Usable(seconds)
	if Voidform:Down() then
		return false
	end
	return Ability.Usable(self, seconds)
end

function ShadowWordPain:Remains()
	if Misery.known and VampiricTouch:Casting() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function Shadowform:Remains()
	if Voidform:Up() then
		return 600
	end
	return Ability.Remains(self)
end

function Voidform:Remains()
	if VoidEruption:Casting() then
		return 600
	end
	return Ability.Remains(self)
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.DISCIPLINE] = {},
	[SPEC.HOLY] = {},
	[SPEC.SHADOW] = {}
}

APL[SPEC.DISCIPLINE].main = function(self)
	if Player:TimeInCombat() == 0 then
		if PowerWordFortitude:Usable() and PowerWordFortitude:Remains() < 300 then
			return PowerWordFortitude
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfEndlessFathoms)
			end
		end
	else
		if PowerWordFortitude:Down() and PowerWordFortitude:Usable() then
			UseExtra(PowerWordFortitude)
		end
	end
	if Player:HealthPct() < 30 and DesperatePrayer:Usable() then
		UseExtra(DesperatePrayer)
	elseif (Player:HealthPct() < Opt.pws_threshold or Atonement:Remains() < Player.gcd) and PowerWordShield:Usable() then
		UseExtra(PowerWordShield)
	end
	if Player:ManaPct() < 95 and PowerWordSolace:Usable() then
		return PowerWordSolace
	end
	if Player.swp:Usable() and Player.swp:Down() and Target.timeToDie > 4 then
		return Player.swp
	end
	if ConcentratedFlame:Usable() and ConcentratedFlame:Charges() > 1.6 and Schism:Down() then
		UseCooldown(ConcentratedFlame)
	end
	if Schism.known and Shadowfiend:Usable() and Schism:Ready(3) and Target.timeToDie > 15 then
		UseCooldown(Shadowfiend)
	end
	if Schism:Usable() and not Player.moving and Target.timeToDie > 4 and Player.swp:Remains() > 10 then
		return Schism
	end
	if Penance:Usable() then
		return Penance
	end
	if PowerWordSolace:Usable(0.2) then
		return PowerWordSolace
	end
	if Player.swp:Usable() and ((Player.swp:Refreshable() and Schism:Down()) or (Schism.known and Schism:Ready(2) and Player.swp:Remains() < 10)) and Target.timeToDie > Player.swp:Remains() + 4 then
		return Player.swp
	end
	if ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() and (Schism:Down() or (Target.boss and Target.timeToDie < 4)) then
		UseCooldown(ConcentratedFlame)
	end
	if DivineStar:Usable() then
		UseCooldown(DivineStar)
	end
	if Shadowfiend:Usable() and Target.timeToDie > 15 then
		UseCooldown(Shadowfiend)
	end
	if Player.moving and Player.swp:Usable() and Player.swp:Refreshable() then
		return Player.swp
	end
	if Schism:Usable() and (Target.boss or Target.timeToDie > 4) then
		return Schism
	end
	if HolyNova:Usable() and (SuddenRevelation:Up() or (Player.enemies >= 4 and Schism:Down())) then
		UseCooldown(HolyNova)
	end
	return Smite
end

APL[SPEC.HOLY].main = function(self)
	if Player:TimeInCombat() == 0 then
		if PowerWordFortitude:Usable() and PowerWordFortitude:Remains() < 300 then
			return PowerWordFortitude
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfEndlessFathoms)
			end
		end
	else
		if PowerWordFortitude:Down() and PowerWordFortitude:Usable() then
			UseExtra(PowerWordFortitude)
		end
	end
end

APL[SPEC.SHADOW].main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/variable,name=mind_blast_targets,op=set,value=floor((4.5+azerite.whispers_of_the_damned.rank)%(1+0.27*azerite.searing_dialogue.rank))
actions.precombat+=/variable,name=swp_trait_ranks_check,op=set,value=(1-0.07*azerite.death_throes.rank+0.2*azerite.thought_harvester.rank)*(1-0.09*azerite.thought_harvester.rank*azerite.searing_dialogue.rank)
actions.precombat+=/variable,name=vt_trait_ranks_check,op=set,value=(1-0.04*azerite.thought_harvester.rank-0.05*azerite.spiteful_apparitions.rank)
actions.precombat+=/variable,name=vt_mis_trait_ranks_check,op=set,value=(1-0.07*azerite.death_throes.rank-0.03*azerite.thought_harvester.rank-0.055*azerite.spiteful_apparitions.rank)*(1-0.027*azerite.thought_harvester.rank*azerite.searing_dialogue.rank)
actions.precombat+=/variable,name=vt_mis_sd_check,op=set,value=1-0.014*azerite.searing_dialogue.rank
actions.precombat+=/shadowform,if=!buff.shadowform.up
actions.precombat+=/use_item,name=azsharas_font_of_power
actions.precombat+=/mind_blast,if=spell_targets.mind_sear<2|azerite.thought_harvester.rank=0
actions.precombat+=/vampiric_touch
]]
		if PowerWordFortitude:Usable() and PowerWordFortitude:Remains() < 300 then
			return PowerWordFortitude
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfEndlessFathoms)
			end
			if Opt.pot and Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if Shadowform:Usable() and Shadowform:Down() then
			return Shadowform
		end
		if MindBlast:Usable() and (Player.enemies < 2 or ThoughtHarvester:AzeriteRank() == 0) then
			return MindBlast
		end
		if VampiricTouch:Usable() and VampiricTouch:Down() then
			return VampiricTouch
		end
	else
		if PowerWordFortitude:Down() and PowerWordFortitude:Usable() then
			UseExtra(PowerWordFortitude)
		end
	end
--[[
actions=potion,if=buff.bloodlust.react|target.time_to_die<=80|target.health.pct<35
actions+=/variable,name=dots_up,op=set,value=dot.shadow_word_pain.ticking&dot.vampiric_touch.ticking
actions+=/run_action_list,name=cleave,if=active_enemies>1
actions+=/run_action_list,name=single,if=active_enemies=1
]]
	if Opt.pot and Target.boss and PotionOfUnbridledFury:Usable() and (Target.timeToDie < 80 or Target.healthPercentage < 35 or Player:BloodlustActive()) then
		UseCooldown(PotionOfUnbridledFury)
	end
	if Player.enemies > 1 then
		return self:cleave()
	end
	return self:single()
end

APL[SPEC.SHADOW].cds = function(self)
--[[
# Use Memory of Lucid Dreams right before you are about to fall out of Voidform
actions.cds=memory_of_lucid_dreams,if=(buff.voidform.stack>20&insanity<=50)|buff.voidform.stack>(26+7*buff.bloodlust.up)|(current_insanity_drain*((gcd.max*2)+action.mind_blast.cast_time))>insanity
actions.cds+=/blood_of_the_enemy
actions.cds+=/guardian_of_azeroth,if=buff.voidform.stack>15
actions.cds+=/use_item,name=manifesto_of_madness,if=spell_targets.mind_sear>=2|raid_event.adds.in>60
actions.cds+=/focused_azerite_beam,if=spell_targets.mind_sear>=2|raid_event.adds.in>60
actions.cds+=/purifying_blast,if=spell_targets.mind_sear>=2|raid_event.adds.in>60
# Wait at least 6s between casting CF. Use the first cast ASAP to get it on CD, then every subsequent cast should be used when Chorus of Insanity is active or it will recharge in the next gcd, or the target is about to die.
actions.cds+=/concentrated_flame,line_cd=6,if=time<=10|(buff.chorus_of_insanity.stack>=15&buff.voidform.up)|full_recharge_time<gcd|target.time_to_die<5
actions.cds+=/ripple_in_space
actions.cds+=/reaping_flames
actions.cds+=/worldvein_resonance
# Use these cooldowns in between your 1st and 2nd Void Bolt in your 2nd Voidform when you have Chorus of Insanity active
actions.cds+=/call_action_list,name=crit_cds,if=(buff.voidform.up&buff.chorus_of_insanity.stack>20)|azerite.chorus_of_insanity.rank=0
# Default fallback for usable items: Use on cooldown.
actions.cds+=/use_items
]]
	if MemoryOfLucidDreams.known then
		if MemoryOfLucidDreams:Usable() and ((Voidform:Stack() > 20 and Player.insanity <= 50) or (Voidform:Stack() > (Player:BloodlustActive() and 33 or 26)) or ((Player.insanity_drain * ((Player.gcd * 2) + MindBlast:CastTime())) > Player.insanity)) then
			return UseCooldown(MemoryOfLucidDreams)
		end
	elseif BloodOfTheEnemy.known then
		if BloodOfTheEnemy:Usable() then
			return UseCooldown(BloodOfTheEnemey)
		end
	elseif GuardianOfAzeroth.known then
		if GuardianOfAzeroth:Usable() and Voidform:Stack() > 15 then
			return UseCooldown(GuardianOfAzeroth)
		end
	elseif FocusedAzeriteBeam.known then
		if FocusedAzeriteBeam:Usable() then
			return UseCooldown(FocusedAzeriteBeam)
		end
	elseif PurifyingBlast.known then
		if PurifyingBlast:Usable() then
			return UseCooldown(PurifyingBlast)
		end
	elseif ConcentratedFlame.known then
		if ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() and (Target.timeToDie < 5 or Player:TimeInCombat() < 10 or (ChorusOfInsanity:Stack() >= 15 and Voidform:Up()) or ConcentratedFlame:FullRechargeTime() < Player.gcd) then
			return UseCooldown(ConcentratedFlame)
		end
	elseif RippleInSpace.known then
		if RippleInSpace:Usable() then
			return UseCooldown(RippleInSpace)
		end
	elseif ReapingFlames.known then
		if ReapingFlames:Usable() then
			return UseCooldown(ReapingFlames)
		end
	elseif WorldveinResonance.known then
		if WorldveinResonance:Usable() and Lifeblood:Stack() < 4 then
			return UseCooldown(WorldveinResonance)
		end
	end
	if not ChorusOfInsanity.known or (Voidform:Up() and ChorusOfInsanity:Stack() > 20) then
		local apl = self:crit_cds()
		if apl then return apl end
	end
	if Opt.trinket then
		if Trinket1:Usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.SHADOW].crit_cds = function(self)
--[[
actions.crit_cds=use_item,name=azsharas_font_of_power
actions.crit_cds+=/use_item,effect_name=cyclotronic_blast
actions.crit_cds+=/the_unbound_force
]]
	if TheUnboundForce:Usable() then
		return UseCooldown(TheUnboundForce)
	end
end

APL[SPEC.SHADOW].cleave = function(self)
--[[
actions.cleave=void_eruption
actions.cleave+=/dark_ascension,if=buff.voidform.down
actions.cleave+=/vampiric_touch,if=!ticking&azerite.thought_harvester.rank>=1
actions.cleave+=/mind_sear,if=buff.harvested_thoughts.up
actions.cleave+=/void_bolt
actions.cleave+=/call_action_list,name=cds
actions.cleave+=/shadow_word_death,target_if=target.time_to_die<3|buff.voidform.down
actions.cleave+=/surrender_to_madness,if=buff.voidform.stack>10+(10*buff.bloodlust.up)
# Use Dark Void on CD unless adds are incoming in 10s or less.
actions.cleave+=/dark_void,if=raid_event.adds.in>10&(dot.shadow_word_pain.refreshable|target.time_to_die>30)
actions.cleave+=/mindbender
actions.cleave+=/mind_blast,target_if=spell_targets.mind_sear<variable.mind_blast_targets
actions.cleave+=/shadow_crash,if=(raid_event.adds.in>5&raid_event.adds.duration<2)|raid_event.adds.duration>2
actions.cleave+=/shadow_word_pain,target_if=refreshable&target.time_to_die>((-1.2+3.3*spell_targets.mind_sear)*variable.swp_trait_ranks_check*(1-0.012*azerite.searing_dialogue.rank*spell_targets.mind_sear)),if=!talent.misery.enabled
actions.cleave+=/vampiric_touch,target_if=refreshable,if=target.time_to_die>((1+3.3*spell_targets.mind_sear)*variable.vt_trait_ranks_check*(1+0.10*azerite.searing_dialogue.rank*spell_targets.mind_sear))
actions.cleave+=/vampiric_touch,target_if=dot.shadow_word_pain.refreshable,if=(talent.misery.enabled&target.time_to_die>((1.0+2.0*spell_targets.mind_sear)*variable.vt_mis_trait_ranks_check*(variable.vt_mis_sd_check*spell_targets.mind_sear)))
actions.cleave+=/void_torrent,if=buff.voidform.up
actions.cleave+=/mind_sear,target_if=spell_targets.mind_sear>1,chain=1,interrupt_immediate=1,interrupt_if=ticks>=2
actions.cleave+=/mind_flay,chain=1,interrupt_immediate=1,interrupt_if=ticks>=2&(cooldown.void_bolt.up|cooldown.mind_blast.up)
actions.cleave+=/shadow_word_pain
]]
	if VoidEruption:Usable() then
		UseCooldown(VoidEruption)
	end
	if DarkAscension:Usable() and Voidform:Down() then
		UseCooldown(DarkAscension)
	end
	if ThoughtHarvester.known and VampiricTouch:Usable() and VampiricTouch:Down() then
		return VampiricTouch
	end
	if MindSear:Usable() and ThoughtHarvester:Up() then
		return MindSear
	end
	if VoidBolt:Usable() then
		return VoidBolt
	end
	self:cds()
	if ShadowWordDeath:Usable() and (Target.timeToDie < 3 or Voidform:Down()) then
		return ShadowWordDeath
	end
	if SurrenderToMadness:Usable() and Voidform:Stack() > (Player:BloodlustActive() and 20 or 10) then
		UseCooldown(SurrenderToMadness)
	end
	if DarkVoid:Usable() and (ShadowWordPain:Refreshable() or Target.timeToDie > 30) then
		UseCooldown(DarkVoid)
	end
	if MindbenderShadow:Usable() then
		UseCooldown(MindbenderShadow)
	end
	if VoidBolt:Usable(Player.channel_remains) then
		return VoidBolt
	end
	if MindBlast:Usable() and Player.enemies < Player.mind_blast_targets then
		return MindBlast
	end
	if ShadowWordVoid:Usable() and Player.enemies < Player.mind_blast_targets then
		return ShadowWordVoid
	end
	if ShadowCrash:Usable() then
		UseCooldown(ShadowCrash)
	end
	if not Misery.known and ShadowWordPain:Usable() and ShadowWordPain:Refreshable() and Target.timeToDie > ((-1.2 + 3.3 * Player.enemies) * Player.swp_trait_ranks_check * (1 - 0.012 * SearingDialogue:AzeriteRank() * Player.enemies)) then
		return ShadowWordPain
	end
	if VampiricTouch:Usable() then
		if VampiricTouch:Refreshable() and Target.timeToDie > ((1 + 3.3 * Player.enemies) * Player.vt_trait_ranks_check * (1 + 0.10 * SearingDialogue:AzeriteRank() * Player.enemies)) then
			return VampiricTouch
		end
		if Misery.known and ShadowWordPain:Refreshable() and Target.timeToDie > ((1 + 2 * Player.enemies) * Player.vt_mis_trait_ranks_check * (Player.vt_mis_sd_check * Player.enemies)) then
			return VampiricTouch
		end
	end
	if VoidTorrent:Usable() and Voidform:Up() then
		UseCooldown(VoidTorrent)
	end
	if Shadowfiend:Usable() then
		UseCooldown(Shadowfiend)
	end
	if MindSear:Usable() then
		return MindSear
	end
	if MindFlay:Usable() then
		return MindFlay
	end
	if ShadowWordPain:Usable() and not Player.ability_channeling then
		return ShadowWordPain
	end
end

APL[SPEC.SHADOW].single = function(self)
--[[
actions.single=void_eruption
actions.single+=/dark_ascension,if=buff.voidform.down
actions.single+=/void_bolt
actions.single+=/call_action_list,name=cds
# Use Mind Sear on ST only if you get a Thought Harvester Proc with at least 1 Searing Dialogue Trait.
actions.single+=/mind_sear,if=buff.harvested_thoughts.up&cooldown.void_bolt.remains>=1.5&azerite.searing_dialogue.rank>=1
# Use SWD before capping charges, or the target is about to die.
actions.single+=/shadow_word_death,if=target.time_to_die<3|cooldown.shadow_word_death.charges=2|(cooldown.shadow_word_death.charges=1&cooldown.shadow_word_death.remains<gcd.max)
actions.single+=/surrender_to_madness,if=buff.voidform.stack>10+(10*buff.bloodlust.up)
# Use Dark Void on CD unless adds are incoming in 10s or less.
actions.single+=/dark_void,if=raid_event.adds.in>10
# Use Mindbender at 19 or more stacks, or if the target will die in less than 15s.
actions.single+=/mindbender,if=talent.mindbender.enabled|(buff.voidform.stack>18|target.time_to_die<15)
actions.single+=/shadow_word_death,if=!buff.voidform.up|(cooldown.shadow_word_death.charges=2&buff.voidform.stack<15)
# Use Shadow Crash on CD unless there are adds incoming.
actions.single+=/shadow_crash,if=raid_event.adds.in>5&raid_event.adds.duration<20
# Bank the Shadow Word: Void charges for a bit to try and avoid overcapping on Insanity.
actions.single+=/mind_blast,if=variable.dots_up&((raid_event.movement.in>cast_time+0.5&raid_event.movement.in<4)|!talent.shadow_word_void.enabled|buff.voidform.down|buff.voidform.stack>14&(insanity<70|charges_fractional>1.33)|buff.voidform.stack<=14&(insanity<60|charges_fractional>1.33))
actions.single+=/void_torrent,if=dot.shadow_word_pain.remains>4&dot.vampiric_touch.remains>4&buff.voidform.up
actions.single+=/shadow_word_pain,if=refreshable&target.time_to_die>4&!talent.misery.enabled&!talent.dark_void.enabled
actions.single+=/vampiric_touch,if=refreshable&target.time_to_die>6|(talent.misery.enabled&dot.shadow_word_pain.refreshable)
actions.single+=/mind_flay,chain=1,interrupt_immediate=1,interrupt_if=ticks>=2&(cooldown.void_bolt.up|cooldown.mind_blast.up)
actions.single+=/shadow_word_pain
]]
	if VoidEruption:Usable() then
		UseCooldown(VoidEruption)
	end
	if DarkAscension:Usable() and Voidform:Down() then
		UseCooldown(DarkAscension)
	end
	if VoidBolt:Usable() then
		return VoidBolt
	end
	self:cds()
	if SearingDialogue.known and ThoughtHarvester.known and MindSear:Usable() and ThoughtHarvester:Up() and not Voidbolt:Ready(1.5) then
		return MindSear
	end
	if ShadowWordDeath:Usable() and (Target.timeToDie < 3 or ShadowWordDeath:FullRechargeTime() < Player.gcd) then
		return ShadowWordDeath
	end
	if SurrenderToMadness:Usable() and Voidform:Stack() > (Player:BloodlustActive() and 20 or 10) then
		UseCooldown(SurrenderToMadness)
	end
	if DarkVoid:Usable() then
		UseCooldown(DarkVoid)
	end
	if MindbenderShadow:Usable() then
		UseCooldown(MindbenderShadow)
	end
	if Shadowfiend:Usable() and (Voidform:Stack() > 18 or Target.timeToDie < 15) then
		UseCooldown(Shadowfiend)
	end
	if ShadowWordDeath:Usable() and Voidform:Down() then
		return ShadowWordDeath
	end
	if ShadowCrash:Usable() then
		UseCooldown(ShadowCrash)
	end
	if ShadowWordPain:Up() and VampiricTouch:Up() then
		if VoidBolt:Usable(Player.channel_remains) then
			return VoidBolt
		end
		if MindBlast:Usable() then
			return MindBlast
		end
		if ShadowWordVoid:Usable() and (Voidform:Down() or ShadowWordVoid:ChargesFractional() > 1.33 or Player.insanity < (Voidform:Stack() > 14 and 70 or 60)) then
			return ShadowWordVoid
		end
	end
	if VoidTorrent:Usable() and Voidform:Up() and ShadowWordPain:Remains() > 4 and VampiricTouch:Remains() > 4 then
		UseCooldown(VoidTorrent)
	end
	if not Misery.known and not DarkVoid.known and ShadowWordPain:Usable() and ShadowWordPain:Refreshable() and Target.timeToDie > 4 then
		return ShadowWordPain
	end
	if VampiricTouch:Usable() and ((VampiricTouch:Refreshable() and Target.timeToDie > 6) or (Misery.known and ShadowWordPain:Refreshable())) then
		return VampiricTouch
	end
	if MindFlay:Usable() then
		return MindFlay
	end
	if ShadowWordPain:Usable() and not Player.ability_channeling then
		return ShadowWordPain
	end
end

APL.Interrupt = function(self)
	if Silence:Usable() then
		return Silence
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon, i
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	propheticPanel:EnableMouse(Opt.aoe or not Opt.locked)
	propheticPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		propheticPanel:SetScript('OnDragStart', nil)
		propheticPanel:SetScript('OnDragStop', nil)
		propheticPanel:RegisterForDrag(nil)
		propheticPreviousPanel:EnableMouse(false)
		propheticCooldownPanel:EnableMouse(false)
		propheticInterruptPanel:EnableMouse(false)
		propheticExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			propheticPanel:SetScript('OnDragStart', propheticPanel.StartMoving)
			propheticPanel:SetScript('OnDragStop', propheticPanel.StopMovingOrSizing)
			propheticPanel:RegisterForDrag('LeftButton')
		end
		propheticPreviousPanel:EnableMouse(true)
		propheticCooldownPanel:EnableMouse(true)
		propheticInterruptPanel:EnableMouse(true)
		propheticExtraPanel:EnableMouse(true)
	end
end

function UI:UpdateAlpha()
	propheticPanel:SetAlpha(Opt.alpha)
	propheticPreviousPanel:SetAlpha(Opt.alpha)
	propheticCooldownPanel:SetAlpha(Opt.alpha)
	propheticInterruptPanel:SetAlpha(Opt.alpha)
	propheticExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	propheticPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	propheticPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	propheticCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	propheticInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	propheticExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	propheticPreviousPanel:ClearAllPoints()
	propheticPreviousPanel:SetPoint('TOPRIGHT', propheticPanel, 'BOTTOMLEFT', -3, 40)
	propheticCooldownPanel:ClearAllPoints()
	propheticCooldownPanel:SetPoint('TOPLEFT', propheticPanel, 'BOTTOMRIGHT', 3, 40)
	propheticInterruptPanel:ClearAllPoints()
	propheticInterruptPanel:SetPoint('BOTTOMLEFT', propheticPanel, 'TOPRIGHT', 3, -21)
	propheticExtraPanel:ClearAllPoints()
	propheticExtraPanel:SetPoint('BOTTOMRIGHT', propheticPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	['blizzard'] = {
		[SPEC.DISCIPLINE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.SHADOW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		}
	},
	['kui'] = {
		[SPEC.DISCIPLINE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.SHADOW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		}
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		propheticPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		propheticPanel:ClearAllPoints()
		propheticPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateManaBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		(Player.spec == SPEC.DISCIPLINE and Opt.hide.discipline) or
		(Player.spec == SPEC.HOLY and Opt.hide.holy) or
		(Player.spec == SPEC.SHADOW and Opt.hide.shadow))
end

function UI:Disappear()
	propheticPanel:Hide()
	propheticPanel.icon:Hide()
	propheticPanel.border:Hide()
	propheticCooldownPanel:Hide()
	propheticInterruptPanel:Hide()
	propheticExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, text_center, text_tl
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Voidform.known then
		text_tl = Player.insanity_drain
	end
	propheticPanel.dimmer:SetShown(dim)
	propheticPanel.text.center:SetText(text_center)
	propheticPanel.text.tl:SetText(text_tl)
	--propheticPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.main =  nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	_, _, _, _, remains, _, _, spellId = UnitChannelInfo('player')
	Player.ability_channeling = abilities.bySpellId[spellId]
	Player.channel_remains = remains and (remains / 1000 - Player.ctime) or 0
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.gcd = 1.5 * Player.haste_factor
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	Player.mana_regen = GetPowerRegen()
	Player.mana = UnitPower('player', 0) + (Player.mana_regen * Player.execute_remains)
	Player.mana_max = UnitPowerMax('player', 0)
	if Player.ability_casting then
		Player.mana = Player.mana - Player.ability_casting:Cost()
	end
	Player.mana = min(max(Player.mana, 0), Player.mana_max)
	if Voidform.known then
		Player.insanity = max(UnitPower('player', 13) - (Player.insanity_drain * Player.execute_remains), 0)
		if Player.ability_casting then
			Player.insanity = Player.insanity - Player.ability_casting:InsanityCost()
		end
		Player.insanity = min(max(Player.insanity, 0), Player.insanity_max)
	end
	Player.moving = GetUnitSpeed('player') ~= 0

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main then
		propheticPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		propheticCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		propheticExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local ends, notInterruptible
		_, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			propheticInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			propheticInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		propheticInterruptPanel.icon:SetShown(Player.interrupt)
		propheticInterruptPanel.border:SetShown(Player.interrupt)
		propheticInterruptPanel:SetShown(start and not notInterruptible)
	end
	propheticPanel.icon:SetShown(Player.main)
	propheticPanel.border:SetShown(Player.main)
	propheticCooldownPanel:SetShown(Player.cd)
	propheticExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == 'Prophetic' then
		Opt = Prophetic
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. name .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Prophetic1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] ' .. name .. ' is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitOpts()
		Azerite:Init()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
		return
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
		end
		if Opt.auto_aoe then
			if dstGUID == Player.guid then
				autoAoe:Add(srcGUID, true)
			elseif srcGUID == Player.guid and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:Add(dstGUID, true)
			end
		end
	end

	local ability = spellId and abilities.bySpellId[spellId]

	if srcGUID ~= Player.guid then
		return
	end

	if not ability then
--[[
		if spellId and type(spellName) == 'string' then
			print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		end
]]
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_HEAL' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_APPLIED_DOSE' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
			ability.last_used = Player.time
			if ability.triggers_gcd then
				Player.previous_gcd[10] = nil
				table.insert(Player.previous_gcd, 1, ability)
			end
			if ability.travel_start then
				ability.travel_start[dstGUID] = Player.time
				if not ability.range_est_start then
					ability.range_est_start = Player.time
				end
			end
			if Opt.previous and propheticPanel:IsVisible() then
				propheticPreviousPanel.ability = ability
				propheticPreviousPanel.border:SetTexture('Interface\\AddOns\\Prophetic\\border.blp')
				propheticPreviousPanel.icon:SetTexture(ability.icon)
				propheticPreviousPanel:Show()
			end
			if Opt.auto_aoe and ability == MindFlay then
				Player:SetTargetMode(1)
			end
		end
		return
	end

	if Voidform.known then
		if ability == Voidform then
			if eventType == 'SPELL_AURA_APPLIED' then
				ability.insanity_drain_stack = 1
			elseif eventType == 'SPELL_AURA_REMOVED' then
				ability.insanity_drain_stack = 0
			elseif eventType == 'SPELL_AURA_APPLIED_DOSE' and not ability.insanity_drain_paused then
				ability.insanity_drain_stack = ability.insanity_drain_stack + 1
			end
			Player.insanity_drain = ability:InsanityDrain()
		elseif ability == VoidTorrent or ability == Dispersion then
			if eventType == 'SPELL_AURA_APPLIED' then
				Voidform.insanity_drain_paused = true
			elseif eventType == 'SPELL_AURA_REMOVED' then
				Voidform.insanity_drain_paused = false
			end
		end
	end

	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if ability.range_est_start then
			Target.estimated_range = floor(ability.velocity * (Player.time - ability.range_est_start))
			ability.range_est_start = nil
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and propheticPanel:IsVisible() and ability == propheticPreviousPanel.ability then
			propheticPreviousPanel.border:SetTexture('Interface\\AddOns\\Prophetic\\misseffect.blp')
		end
	end
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.last_swing_taken = 0
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		propheticPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, i, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	propheticPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			_, _, _, castStart = UnitChannelInfo('player')
			if castStart and Player.main then
				start, duration = GetSpellCooldown(Player.main.spellId)
			else
				start, duration = GetSpellCooldown(61304)
			end
		end
		propheticPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_SPELLCAST_START(srcName, castId, spellId)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:AZERITE_ESSENCE_UPDATE()
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

propheticPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

propheticPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

propheticPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	propheticPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	print('Prophetic -', desc .. ':', opt_view, ...)
end

function SlashCmdList.Prophetic(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				propheticPanel:ClearAllPoints()
			end
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the Prophetic UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use Prophetic for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'd') then
				Opt.hide.discipline = not Opt.hide.discipline
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Discipline specialization', not Opt.hide.discipline)
			end
			if startsWith(msg[2], 'h') then
				Opt.hide.holy = not Opt.hide.holy
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Holy specialization', not Opt.hide.holy)
			end
			if startsWith(msg[2], 's') then
				Opt.hide.shadow = not Opt.hide.shadow
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Shadow specialization', not Opt.hide.shadow)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000discipline|r, |cFFFFD000holy|r, and |cFFFFD000shadow')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if msg[1] == 'pws' then
		if msg[2] then
			Opt.pws_threshold = max(min(tonumber(msg[2]) or 60, 100), 0)
		end
		return Status('Health percentage threshold to show Power Word: Shield reminder', Opt.pws_threshold .. '%')
	end
	if msg[1] == 'reset' then
		propheticPanel:ClearAllPoints()
		propheticPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Prophetic (version: |cFFFFD000' .. GetAddOnMetadata('Prophetic', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Prophetic UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Prophetic UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Prophetic UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Prophetic UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Prophetic UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Prophetic for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000discipline|r/|cFFFFD000holy|r/|cFFFFD000shadow|r - toggle disabling Prophetic for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'pws |cFFFFD000[percent]|r - health percentage threshold to show Power Word: Shield reminder',
		'|cFFFFD000reset|r - reset the location of the Prophetic UI to default',
	} do
		print('  ' .. SLASH_Prophetic1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
