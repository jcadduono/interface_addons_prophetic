local ADDON = 'Prophetic'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_PROPHETIC = ADDON
BINDING_NAME_PROPHETIC_TARGETMORE = "Toggle Targets +"
BINDING_NAME_PROPHETIC_TARGETLESS = "Toggle Targets -"
BINDING_NAME_PROPHETIC_TARGET1 = "Set Targets to 1"
BINDING_NAME_PROPHETIC_TARGET2 = "Set Targets to 2"
BINDING_NAME_PROPHETIC_TARGET3 = "Set Targets to 3"
BINDING_NAME_PROPHETIC_TARGET4 = "Set Targets to 4"
BINDING_NAME_PROPHETIC_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'PRIEST' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetActionInfo = _G.GetActionInfo
local GetBindingKey = _G.GetBindingKey
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetShapeshiftForm = _G.GetShapeshiftForm
local GetSpellCharges = C_Spell.GetSpellCharges
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellInfo = C_Spell.GetSpellInfo
local GetItemCount = C_Item.GetItemCount
local GetItemCooldown = C_Item.GetItemCooldown
local GetInventoryItemCooldown = _G.GetInventoryItemCooldown
local GetItemInfo = C_Item.GetItemInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local IsSpellUsable = C_Spell.IsSpellUsable
local IsItemUsable = C_Item.IsUsableItem
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = C_UnitAuras.GetAuraDataByIndex
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end

local function ToUID(guid)
	local uid = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	return uid and tonumber(uid)
end
-- end useful functions

Prophetic = {}
local Opt -- use this as a local table reference to Prophetic

SLASH_Prophetic1, SLASH_Prophetic2 = '/pro', '/prophetic'

local function InitOpts()
	local function SetDefaults(t, ref)
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
			animation = false,
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
		keybinds = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		cd_ttd = 10,
		pot = false,
		trinket = true,
		heal = 60,
		fiend = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	remains_list = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	tracked = {},
}

-- summoned pet template
local SummonedPet = {}
SummonedPet.__index = SummonedPet

-- classified summoned pets
local SummonedPets = {
	all = {},
	known = {},
	byUnitId = {},
}

-- inventory item template
local InventoryItem, Trinket = {}, {}
InventoryItem.__index = InventoryItem

-- classified inventory items
local InventoryItems = {
	all = {},
	byItemId = {},
}

-- action button template
local Button = {}
Button.__index = Button

-- classified action buttons
local Buttons = {
	all = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- methods for tracking ticking debuffs on targets
local TrackedAuras = {}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	DISCIPLINE = 1,
	HOLY = 2,
	SHADOW = 3,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.DISCIPLINE] = {},
	[SPEC.HOLY] = {},
	[SPEC.SHADOW] = {},
}

-- current player information
local Player = {
	initialized = false,
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	mana = {
		base = 0,
		current = 0,
		max = 100,
		pct = 100,
		regen = 0,
	},
	insanity = {
		current = 0,
		max = 100,
		deficit = 100,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		last_taken = 0,
	},
	set_bonus = {
		t33 = 0, -- Shards of Living Luster
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	fiend_remains = 0,
	fiend_up = false,
}

-- base mana pool max for each level
Player.BaseMana = {
	260,     270,     285,     300,     310,     -- 5
	330,     345,     360,     380,     400,     -- 10
	430,     465,     505,     550,     595,     -- 15
	645,     700,     760,     825,     890,     -- 20
	965,     1050,    1135,    1230,    1335,    -- 25
	1445,    1570,    1700,    1845,    2000,    -- 30
	2165,    2345,    2545,    2755,    2990,    -- 35
	3240,    3510,    3805,    4125,    4470,    -- 40
	4845,    5250,    5690,    6170,    6685,    -- 45
	7245,    7855,    8510,    9225,    10000,   -- 50
	11745,   13795,   16205,   19035,   22360,   -- 55
	26265,   30850,   36235,   42565,   50000,   -- 60
	58730,   68985,   81030,   95180,   111800,  -- 65
	131325,  154255,  181190,  212830,  250000,  -- 70
	293650,  344930,  405160,  475910,  559015,  -- 75
	656630,  771290,  905970,  1064170, 2500000, -- 80
}

-- current pet information (used only to store summoned pets for priests)
local Pet = {}

-- current target information
local Target = {
	boss = false,
	dummy = false,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

-- target dummy unit IDs (count these units as bosses)
Target.Dummies = {
	[189617] = true,
	[189632] = true,
	[194643] = true,
	[194644] = true,
	[194648] = true,
	[194649] = true,
	[197833] = true,
	[198594] = true,
	[219250] = true,
	[225983] = true,
	[225984] = true,
	[225985] = true,
	[225976] = true,
	[225977] = true,
	[225978] = true,
	[225982] = true,
}

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
		{7, '7+'},
		{9, '9+'},
	},
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

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local uid = ToUID(guid)
	if uid and self.ignored_units[uid] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
	local count = 0
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

function AutoAoe:Purge()
	local update
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

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		mana_cost = 0,
		insanity_cost = 0,
		insanity_gain = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		summon_count = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
		keybinds = {},
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
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
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds)
	if not self.known then
		return false
	end
	if self.Available and not self:Available(seconds) then
		return false
	end
	if self:ManaCost() > Player.mana.current then
		return false
	end
	if Player.spec == SPEC.SHADOW and self:InsanityCost() > Player.insanity.current then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			if aura.expirationTime == 0 then
				return 600 -- infinite duration
			end
			return max(0, aura.expirationTime - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:React()
	return self:Remains()
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:HighestRemains()
	local highest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				highest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not highest or remains > highest) then
				highest = remains
			end
		end
	end
	return highest or 0
end

function Ability:LowestRemains()
	local lowest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				lowest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not lowest or remains < lowest) then
				lowest = remains
			end
		end
	end
	return lowest or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	return max(0, cooldown.duration - (Player.ctime - cooldown.startTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	local remains = cooldown.duration - (Player.ctime - cooldown.startTime)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			return (aura.expirationTime == 0 or aura.expirationTime - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and aura.applications or 0
		end
	end
	return 0
end

function Ability:MaxStack()
	return self.max_stack
end

function Ability:Capped(deficit)
	return self:Stack() >= (self:MaxStack() - (deficit or 0))
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.base) or 0
end

function Ability:InsanityCost()
	return self.insanity_cost
end

function Ability:InsanityGain()
	return self.insanity_gain
end

function Ability:Equilibrium()
	return self.equilibrium
end

function Ability:Free()
	return (
		(self.mana_cost > 0 and self:ManaCost() == 0) or
		(Player.spec == SPEC.SHADOW and self.insanity_cost > 0 and self:InsanityCost() == 0)
	)
end

function Ability:ChargesFractional()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return charges
	end
	return charges + ((max(0, Player.ctime - info.cooldownStartTime + (self.off_gcd and 0 or Player.execute_remains))) / info.cooldownDuration)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local info = GetSpellCharges(self.spellId)
	return info and info.maxCharges or 0
end

function Ability:FullRechargeTime()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return info.cooldownDuration
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return 0
	end
	return (info.maxCharges - charges - 1) * info.cooldownDuration + (info.cooldownDuration - (Player.ctime - info.cooldownStartTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local info = GetSpellInfo(self.spellId)
	return info and info.castTime / 1000 or 0
end

function Ability:CastRegen()
	return Player.mana.regen * self:CastTime() - self:ManaCost()
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
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
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.ignore_cast then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		propheticPreviousPanel.ability = self
		propheticPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		propheticPreviousPanel.icon:SetTexture(self.icon)
		propheticPreviousPanel:SetShown(propheticPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and propheticPreviousPanel.ability == self then
		propheticPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

function TrackedAuras:Purge()
	for _, ability in next, Abilities.tracked do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function TrackedAuras:Remove(guid)
	for _, ability in next, Abilities.tracked do
		ability:RemoveAura(guid)
	end
end

function Ability:Track()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid, extend)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	return aura
end

function Ability:RefreshAuraAll(extend)
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFoci()[1]:GetNodeID()
]]

-- Priest Abilities
---- Class
------ Baseline
local DesperatePrayer = Ability:Add(19236, true, true)
DesperatePrayer.buff_duration = 10
DesperatePrayer.cooldown_duration = 90
local Fade = Ability:Add(586, false, true)
Fade.buff_duration = 10
Fade.cooldown_duration = 30
local Levitate = Ability:Add(1706, true, false, 111759)
Levitate.mana_cost = 0.9
Levitate.buff_duration = 600
local Lightspawn = Ability:Add(254224, false, true)
Lightspawn.cooldown_duration = 180
local MindBlast = Ability:Add(8092, false, true)
MindBlast.mana_cost = 0.25
MindBlast.cooldown_duration = 7.5
MindBlast.insanity_gain = 6
MindBlast.summon_count = 1 -- Entropic Rift
MindBlast.hasted_cooldown = true
MindBlast.requires_charge = true
MindBlast.triggers_combat = true
MindBlast.equilibrium = 'shadow'
local PowerInfusion = Ability:Add(10060, true)
PowerInfusion.buff_duration = 20
PowerInfusion.cooldown_duration = 120
local PowerWordFortitude = Ability:Add(21562, true, false)
PowerWordFortitude.mana_cost = 4
PowerWordFortitude.buff_duration = 3600
local PowerWordShield = Ability:Add(17, true, true)
PowerWordShield.mana_cost = 2.65
PowerWordShield.buff_duration = 15
local PsychicScream = Ability:Add(8122, false, true)
PsychicScream.mana_cost = 1.2
PsychicScream.buff_duration = 8
PsychicScream.cooldown_duration = 45
local Purify = Ability:Add(527, true, true)
Purify.mana_cost = 1.3
Purify.cooldown_duration = 8
local Shadowfiend = Ability:Add(34433, false, true)
Shadowfiend.cooldown_duration = 180
Shadowfiend.summon_count = 1
local ShadowWordPain = Ability:Add(589, false, true)
ShadowWordPain.mana_cost = 0.3
ShadowWordPain.buff_duration = 16
ShadowWordPain.tick_interval = 2
ShadowWordPain.insanity_gain = 4
ShadowWordPain.hasted_ticks = true
ShadowWordPain.triggers_combat = true
ShadowWordPain.equilibrium = 'shadow'
ShadowWordPain:AutoAoe(false, 'apply')
ShadowWordPain:Track()
local Smite = Ability:Add(585, false, true, 208772)
Smite.mana_cost = 0.2
Smite.triggers_combat = true
Smite.equilibrium = 'holy'
------ Talents
local CrystallineReflection = Ability:Add(373457, true, true)
CrystallineReflection.talent_node = 82681
local DispelMagic = Ability:Add(528, false, true)
DispelMagic.mana_cost = 1.6
local DivineStar = Ability:Add(110744, false, true, 122128)
DivineStar.mana_cost = 2
DivineStar.cooldown_duration = 15
DivineStar.equilibrium = 'holy'
DivineStar:AutoAoe()
DivineStar.Shadow = Ability:Add(122121, false, true, 390845)
DivineStar.Shadow.mana_cost = 2
DivineStar.Shadow.cooldown_duration = 15
DivineStar.Shadow.insanity_gain = 6
DivineStar.Shadow.triggers_combat = true
DivineStar.Shadow.equilibrium = 'shadow'
DivineStar.Shadow:AutoAoe()
local Halo = Ability:Add(120517, false, true, 120696)
Halo.mana_cost = 2.7
Halo.cooldown_duration = 40
Halo.equilibrium = 'holy'
Halo:AutoAoe()
Halo.Shadow = Ability:Add(120644, false, true, 390964)
Halo.Shadow.mana_cost = 2.7
Halo.Shadow.cooldown_duration = 40
Halo.Shadow.insanity_gain = 10
Halo.Shadow.triggers_combat = true
Halo.Shadow.equilibrium = 'shadow'
Halo.Shadow:AutoAoe()
local HolyNova = Ability:Add(132157, false, true, 281265)
HolyNova.mana_cost = 1.6
HolyNova.equilibrium = 'holy'
HolyNova:AutoAoe(true)
local LeapOfFaith = Ability:Add(73325, true, true)
LeapOfFaith.buff_duration = 1
LeapOfFaith.mana_cost = 2.6
LeapOfFaith.cooldown_duration = 90
local MassDispel = Ability:Add(32375, true, true)
MassDispel.mana_cost = 8
MassDispel.cooldown_duration = 45
local MindControl = Ability:Add(605, false, true)
MindControl.mana_cost = 2
MindControl.buff_duration = 30
MindControl.triggers_combat = true
local PowerWordLife = Ability:Add(373481, true, true)
PowerWordLife.mana_cost = 0.5
PowerWordLife.cooldown_duration = 30
local Renew = Ability:Add(139, true, true)
Renew.mana_cost = 1.8
Renew.buff_duration = 15
Renew.tick_interval = 3
Renew.hasted_ticks = true
local Rhapsody = Ability:Add(390622, true, true, 390636)
Rhapsody.max_stack = 20
local ShadowWordDeath = Ability:Add(32379, false, true)
ShadowWordDeath.mana_cost = 0.5
ShadowWordDeath.cooldown_duration = 20
ShadowWordDeath.insanity_gain = 4
ShadowWordDeath.hasted_cooldown = true
ShadowWordDeath.equilibrium = 'shadow'
local TwistOfFate = Ability:Add(390972, true, true, 390978)
TwistOfFate.buff_duration = 8
local VampiricEmbrace = Ability:Add(15286, true, true)
VampiricEmbrace.buff_duration = 15
VampiricEmbrace.cooldown_duration = 120
------ Procs

---- Discipline
local Atonement = Ability:Add(81749, true, true, 194384)
Atonement.buff_duration = 15
local Penance = Ability:Add(47540, false, true, 47666)
Penance.mana_cost = 1.6
Penance.buff_duration = 2
Penance.cooldown_duration = 9
Penance.hasted_cooldown = true
Penance.hasted_duration = true
Penance.channel_fully = true
Penance.equilibrium = 'holy'
------ Talents
local DarkReprimand = Ability:Add(400169, false, true, 373130)
DarkReprimand.mana_cost = 1.6
DarkReprimand.buff_duration = 2
DarkReprimand.cooldown_duration = 9
DarkReprimand.hasted_cooldown = true
DarkReprimand.hasted_duration = true
DarkReprimand.channel_fully = true
DarkReprimand.equilibrium = 'shadow'
local EncroachingShadows = Ability:Add(472568, false, true)
local Expiation = Ability:Add(390832, true, true)
Expiation.talent_node = 82585
local InescapableTorment = Ability:Add(373427, false, true, 373442)
InescapableTorment:AutoAoe()
local MindbenderDisc = Ability:Add(123040, false, true)
MindbenderDisc.buff_duration = 12
MindbenderDisc.cooldown_duration = 60
MindbenderDisc.summon_count = 1
local PainAndSuffering = Ability:Add(390689, false, true)
PainAndSuffering.talent_node = 82578
local PainSuppression = Ability:Add(33206, true, true)
PainSuppression.mana_cost = 1.6
PainSuppression.buff_duration = 8
PainSuppression.cooldown_duration = 180
local PowerOfTheDarkSide = Ability:Add(198068, true, true, 198069)
PowerOfTheDarkSide.buff_duration = 30
local PowerWordBarrier = Ability:Add(62618, true, true, 81782)
PowerWordBarrier.mana_cost = 4
PowerWordBarrier.buff_duration = 10
PowerWordBarrier.cooldown_duration = 180
local PowerWordRadiance = Ability:Add(194509, true, true)
PowerWordRadiance.mana_cost = 6.5
PowerWordRadiance.cooldown_duration = 20
PowerWordRadiance.requires_charge = true
local Schism = Ability:Add(424509, false, true, 214621)
Schism.buff_duration = 9
local ShadowCovenant = Ability:Add(314867, true, true, 322105)
ShadowCovenant.buff_duration = 12
local TwilightEquilibrium = Ability:Add(390705, true, true)
TwilightEquilibrium.Holy = Ability:Add(390706, true, true)
TwilightEquilibrium.Holy.buff_duration = 6
TwilightEquilibrium.Shadow = Ability:Add(390707, true, true)
TwilightEquilibrium.Shadow.buff_duration = 6
local VoidSummoner = Ability:Add(390770, true, true)
------ Procs

---- Holy
local HolyFire = Ability:Add(14914, false, true)
HolyFire.cooldown_duration = 10
HolyFire.mana_cost = 1
HolyFire.buff_duration = 7
HolyFire.tick_interval = 1
HolyFire.triggers_combat = true
------ Talents
local HolyWordChastise = Ability:Add(88625, false, true)
HolyWordChastise.cooldown_duration = 60
HolyWordChastise.mana_cost = 2
HolyWordChastise.triggers_combat = true
------ Procs

---- Shadow
local MindFlay = Ability:Add(15407, false, true)
MindFlay.buff_duration = 4.5
MindFlay.tick_interval = 0.75
MindFlay.insanity_gain = 2
MindFlay.hasted_duration = true
MindFlay.hasted_ticks = true
local Shadowform = Ability:Add(232698, true, true)
local VampiricTouch = Ability:Add(34914, false, true)
VampiricTouch.buff_duration = 21
VampiricTouch.tick_interval = 3
VampiricTouch.insanity_gain = 5
VampiricTouch.hasted_ticks = true
VampiricTouch.triggers_combat = true
VampiricTouch:Track()
VampiricTouch:AutoAoe(false, 'apply')
------ Talents
local DarkAscension = Ability:Add(391109, true, true)
DarkAscension.buff_duration = 20
DarkAscension.cooldown_duration = 60
DarkAscension.insanity_gain = 30
local Deathspeaker = Ability:Add(392507, true, true, 392511)
Deathspeaker.buff_duration = 15
local DescendingDarkness = Ability:Add(1242666, false, true)
local DevouringPlague = Ability:Add(335467, false, true)
DevouringPlague.buff_duration = 6
DevouringPlague.tick_interval = 3
DevouringPlague.hasted_ticks = true
DevouringPlague.insanity_cost = 50
DevouringPlague:Track()
local Dispersion = Ability:Add(47585, true, true)
Dispersion.buff_duration = 6
Dispersion.cooldown_duration = 120
local DistortedReality = Ability:Add(409044, false, true)
local IdolOfCthun = Ability:Add(377349, false, true)
local IdolOfYoggSaron = Ability:Add(373273, true, true, 373276)
IdolOfYoggSaron.buff_duration = 120
local InsidiousIre = Ability:Add(373212, false, true, 373213)
InsidiousIre.buff_duration = 12
local MindbenderShadow = Ability:Add(200174, false, true)
MindbenderShadow.buff_duration = 15
MindbenderShadow.cooldown_duration = 60
MindbenderShadow.summon_count = 1
local MindDevourer = Ability:Add(373202, true, true, 373204)
MindDevourer.buff_duration = 15
local MindFlayInsanity = Ability:Add(391403, false, true)
MindFlayInsanity.buff_duration = 3
MindFlayInsanity.tick_interval = 0.75
MindFlayInsanity.insanity_gain = 4
MindFlayInsanity.hasted_duration = true
MindFlayInsanity.hasted_ticks = true
MindFlayInsanity.buff = Ability:Add(391401, true, true)
MindFlayInsanity.buff.buff_duration = 15
local MindsEye = Ability:Add(407470, false, true)
local Misery = Ability:Add(238558, false, true)
local PsychicHorror = Ability:Add(64044, false, true)
PsychicHorror.buff_duration = 4
PsychicHorror.cooldown_duration = 45
local PsychicLink = Ability:Add(199484, false, true, 199486)
PsychicLink:AutoAoe()
local ShadowCrash = Ability:Add({205385, 457042}, false, true, 205386)
ShadowCrash.cooldown_duration = 15
ShadowCrash.insanity_gain = 6
ShadowCrash.travel_delay = 1.5
ShadowCrash.triggers_combat = true
ShadowCrash.requires_charge = true
ShadowCrash:AutoAoe()
local ShadowyInsight = Ability:Add(375888, true, true, 375981)
ShadowyInsight.buff_duration = 10
local Silence = Ability:Add(15487, false, true)
Silence.cooldown_duration = 45
Silence.buff_duration = 4
local ShadowyApparitions = Ability:Add(341491, false, true)
local SubservientShadows = Ability:Add(1228516, false, true)
local SurgeOfInsanity = Ability:Add(391399, false, true)
local ThoughtHarvester = Ability:Add(406788, false, true)
local VoidBolt = Ability:Add(205448, false, true)
VoidBolt.cooldown_duration = 6
VoidBolt.insanity_gain = 10
VoidBolt.hasted_cooldown = true
VoidBolt.triggers_combat = true
VoidBolt:SetVelocity(40)
local VoidEruption = Ability:Add(228260, false, true, 228360)
VoidEruption.cooldown_duration = 120
VoidEruption.triggers_combat = true
VoidEruption:AutoAoe(true)
local Voidform = Ability:Add(194249, true, true)
Voidform.buff_duration = 15
local VoidTorrent = Ability:Add(263165, true, true)
VoidTorrent.buff_duration = 3
VoidTorrent.cooldown_duration = 30
VoidTorrent.tick_interval = 1
VoidTorrent.hasted_ticks = true
local VoidVolley = Ability:Add(1242173, false, true)
VoidVolley.insanity_gain = 10
VoidVolley.learn_spellId = 263165
VoidVolley.triggers_combat = true
VoidVolley.buff = Ability:Add(1242171, true, true)
VoidVolley.buff.buff_duration = 20
VoidVolley.damage = Ability:Add(1242189, true, true)
VoidVolley.damage:SetVelocity(50)
VoidVolley.damage:AutoAoe()
------ Procs

-- Hero talents
---- Archon
local EmpoweredSurges = Ability:Add(453799, false, true)
local PerfectedForm = Ability:Add(453917, true, true)
local PowerSurge = Ability:Add(453109, true, true, 453112)
PowerSurge.buff_duration = 10
PowerSurge.Shadow = Ability:Add(453113, true, true)
PowerSurge.Shadow.buff_duration = 10
---- Voidweaver
local DarkeningHorizon = Ability:Add(449912, true, true)
DarkeningHorizon.max_stack = 3
local EntropicRift = Ability:Add(450193, true, true)
EntropicRift.buff_duration = 8
EntropicRift.learn_spellId = 447444
EntropicRift.dot = Ability:Add(447448, false, true)
EntropicRift.dot:AutoAoe()
local InnerQuietus = Ability:Add(448278, false, true)
local VoidBlast = Ability:Add(450215, false, true)
VoidBlast.mana_cost = 0.2
VoidBlast.triggers_combat = true
VoidBlast.equilibrium = 'shadow'
VoidBlast.learn_spellId = 450405
local VoidEmpowerment = Ability:Add(450138, true, true)
VoidEmpowerment.buff = Ability:Add(450150, true, true)
VoidEmpowerment.buff.buff_duration = 15
local VoidInfusion = Ability:Add(450612, true, true)
local Voidwraith = Ability:Add(451235, true, true)
Voidwraith.cooldown_duration = 120
Voidwraith.buff_duration = 15
Voidwraith.learn_spellId = 451234
-- Tier set bonuses

-- Racials

-- PvP talents

-- Trinket effects

-- Class cooldowns

-- End Abilities

-- Start Summoned Pets

function SummonedPets:Purge()
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires <= Player.time then
				pet.active_units[guid] = nil
			end
		end
	end
end

function SummonedPets:Update()
	wipe(self.known)
	wipe(self.byUnitId)
	for _, pet in next, self.all do
		pet.known = pet.learn_spell and pet.learn_spell.known
		if pet.known then
			self.known[#SummonedPets.known + 1] = pet
			self.byUnitId[pet.unitId] = pet
		end
	end
end

function SummonedPets:Count()
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:Count()
	end
	return count
end

function SummonedPets:Clear()
	for _, pet in next, self.known do
		pet:Clear()
	end
end

function SummonedPet:Add(unitId, duration, summonSpell, learnSpell)
	local pet = {
		unitId = unitId,
		duration = duration,
		active_units = {},
		summon_spell = summonSpell,
		learn_spell = learnSpell or summonSpell,
		known = false,
	}
	setmetatable(pet, self)
	SummonedPets.all[#SummonedPets.all + 1] = pet
	return pet
end

function SummonedPet:Remains(initial)
	if self.summon_spell and self.summon_spell.summon_count > 0 and self.summon_spell:Casting() then
		return self:Duration()
	end
	local expires_max = 0
	for guid, unit in next, self.active_units do
		if (not initial or unit.initial) and unit.expires > expires_max then
			expires_max = unit.expires
		end
	end
	return max(0, expires_max - Player.time - Player.execute_remains)
end

function SummonedPet:Up(...)
	return self:Remains(...) > 0
end

function SummonedPet:Down(...)
	return self:Remains(...) <= 0
end

function SummonedPet:Count()
	local count = 0
	if self.summon_spell and self.summon_spell:Casting() then
		count = count + self.summon_spell.summon_count
	end
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time > Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:Duration()
	return self.duration
end

function SummonedPet:Expiring(seconds)
	local count = 0
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time <= (seconds or Player.execute_remains) then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:AddUnit(guid)
	local unit = {
		guid = guid,
		spawn = Player.time,
		expires = Player.time + self:Duration(),
	}
	self.active_units[guid] = unit
	--log(format('%.3f SUMMONED PET ADDED %s EXPIRES %.3f', unit.spawn, guid, unit.expires))
	return unit
end

function SummonedPet:RemoveUnit(guid)
	if self.active_units[guid] then
		--log(format('%.3f SUMMONED PET REMOVED %s AFTER %.3fs EXPECTED %.3fs', Player.time, guid, Player.time - self.active_units[guid], self.active_units[guid].expires))
		self.active_units[guid] = nil
	end
end

function SummonedPet:ExtendAll(seconds)
	for guid, unit in next, self.active_units do
		if unit.expires > Player.time then
			unit.expires = unit.expires + seconds
		end
	end
end

function SummonedPet:Clear()
	for guid in next, self.active_units do
		self.active_units[guid] = nil
	end
end

-- Summoned Pets
Pet.Lightspawn = SummonedPet:Add(128140, 15, Lightspawn)
Pet.Shadowfiend = SummonedPet:Add(19668, 15, Shadowfiend)
Pet.Mindbender = SummonedPet:Add(62982, 15, Mindbender)
Pet.Voidwraith = SummonedPet:Add(224466, 15, Voidwraith)
Pet.EntropicRift = SummonedPet:Add(223273, 8, MindBlast, EntropicRift)

-- End Summoned Pets

-- Start Inventory Items

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
		off_gcd = true,
		keybinds = {},
	}
	setmetatable(item, self)
	InventoryItems.all[#InventoryItems.all + 1] = item
	InventoryItems.byItemId[itemId] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
	end
	return count
end

function InventoryItem:Cooldown()
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
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
local Healthstone = InventoryItem:Add(5512)
Healthstone.max_charges = 3
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Buttons

Buttons.KeybindPatterns = {
	['ALT%-'] = 'a-',
	['CTRL%-'] = 'c-',
	['SHIFT%-'] = 's-',
	['META%-'] = 'm-',
	['NUMPAD'] = 'NP',
	['PLUS'] = '%+',
	['MINUS'] = '%-',
	['MULTIPLY'] = '%*',
	['DIVIDE'] = '%/',
	['BACKSPACE'] = 'BS',
	['BUTTON'] = 'MB',
	['CLEAR'] = 'Clr',
	['DELETE'] = 'Del',
	['END'] = 'End',
	['HOME'] = 'Home',
	['INSERT'] = 'Ins',
	['MOUSEWHEELDOWN'] = 'MwD',
	['MOUSEWHEELUP'] = 'MwU',
	['PAGEDOWN'] = 'PgDn',
	['PAGEUP'] = 'PgUp',
	['CAPSLOCK'] = 'Caps',
	['NUMLOCK'] = 'NumL',
	['SCROLLLOCK'] = 'ScrL',
	['SPACEBAR'] = 'Space',
	['SPACE'] = 'Space',
	['TAB'] = 'Tab',
	['DOWNARROW'] = 'Down',
	['LEFTARROW'] = 'Left',
	['RIGHTARROW'] = 'Right',
	['UPARROW'] = 'Up',
}

function Buttons:Scan()
	if Bartender4 then
		for i = 1, 120 do
			Button:Add(_G['BT4Button' .. i])
		end
		for i = 1, 10 do
			Button:Add(_G['BT4PetButton' .. i])
		end
		return
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				Button:Add(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
		return
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				Button:Add(_G['LUIBarBottom' .. b .. 'Button' .. i])
				Button:Add(_G['LUIBarLeft' .. b .. 'Button' .. i])
				Button:Add(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
		return
	end
	if Dominos then
		for i = 1, 60 do
			Button:Add(_G['DominosActionButton' .. i])
		end
		-- fallthrough because Dominos re-uses Blizzard action buttons
	end
	for i = 1, 12 do
		Button:Add(_G['ActionButton' .. i])
		Button:Add(_G['MultiBarLeftButton' .. i])
		Button:Add(_G['MultiBarRightButton' .. i])
		Button:Add(_G['MultiBarBottomLeftButton' .. i])
		Button:Add(_G['MultiBarBottomRightButton' .. i])
		Button:Add(_G['MultiBar5Button' .. i])
		Button:Add(_G['MultiBar6Button' .. i])
		Button:Add(_G['MultiBar7Button' .. i])
	end
	for i = 1, 10 do
		Button:Add(_G['PetActionButton' .. i])
	end
end

function Button:UpdateGlowDisplay()
	local w, h = self.frame:GetSize()
	self.glow:SetSize(w * 1.4, h * 1.4)
	self.glow:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
	self.glow:SetPoint('BOTTOMRIGHT', self.frame, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
	self.glow.ProcStartFlipbook:SetVertexColor(Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b)
	self.glow.ProcLoopFlipbook:SetVertexColor(Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b)
	self.glow.ProcStartAnim:Play()
	self.glow:Hide()
end

function Button:UpdateActionID()
	self.action_id = (
		(self.frame._state_type == 'action' and self.frame._state_action) or
		(self.frame.CalculateAction and self.frame:CalculateAction()) or
		(self.frame:GetAttribute('action'))
	) or 0
end

function Button:UpdateAction()
	self.action = nil
	if self.action_id <= 0 then
		return
	end
	local actionType, id, subType = GetActionInfo(self.action_id)
	if id and type(id) == 'number' and id > 0 then
		if (actionType == 'item' or (actionType == 'macro' and subType == 'item')) then
			self.action = InventoryItems.byItemId[id]
		elseif (actionType == 'spell' or (actionType == 'macro' and subType == 'spell')) then
			self.action = Abilities.bySpellId[id]
		end
	end
end

function Button:UpdateKeybind()
	self.keybind = nil
	local bind = self.frame.bindingAction or (self.frame.config and self.frame.config.keyBoundTarget)
	if bind then
		local key = GetBindingKey(bind)
		if key then
			key = key:gsub(' ', ''):upper()
			for pattern, short in next, Buttons.KeybindPatterns do
				key = key:gsub(pattern, short)
			end
			self.keybind = key
			return
		end
	end
end

function Button:Add(actionButton)
	if not actionButton then
		return
	end
	local button = {
		frame = actionButton,
		name = actionButton:GetName(),
		action_id = 0,
		glow = CreateFrame('Frame', nil, actionButton, 'ActionButtonSpellAlertTemplate')
	}
	setmetatable(button, self)
	Buttons.all[#Buttons.all + 1] = button
	button:UpdateActionID()
	button:UpdateAction()
	button:UpdateKeybind()
	button:UpdateGlowDisplay()
	return button
end

-- End Buttons

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.tracked)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.tracked[#self.tracked + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:ManaTimeToMax()
	local deficit = self.mana.max - self.mana.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.mana.regen
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 2825 or   -- Bloodlust (Horde Shaman)
			aura.spellId == 32182 or  -- Heroism (Alliance Shaman)
			aura.spellId == 80353 or  -- Time Warp (Mage)
			aura.spellId == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			aura.spellId == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			aura.spellId == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			aura.spellId == 381301 or -- Feral Hide Drums (Leatherworking)
			aura.spellId == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateKnown()
	local info, node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			info = GetSpellInfo(spellId)
			if info then
				ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
			end
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsSpellUsable(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	self.fiend = Shadowfiend
	if MindbenderDisc.known then
		self.fiend = MindbenderDisc
		Pet.Mindbender.duration = self.fiend.buff_duration
		Pet.Mindbender.summon_spell = self.fiend
		Pet.Mindbender.learn_spell = self.fiend
	elseif MindbenderShadow.known then
		self.fiend = MindbenderShadow
		Pet.Mindbender.duration = self.fiend.buff_duration
		Pet.Mindbender.summon_spell = self.fiend
		Pet.Mindbender.learn_spell = self.fiend
	elseif Voidwraith.known then
		self.fiend = Voidwraith
	elseif Lightspawn.known then
		self.fiend = Lightspawn
	end
	Shadowfiend.known = Shadowfiend.known and self.fiend == Shadowfiend
	if ShadowCovenant.known then
		DivineStar.Shadow.known = DivineStar.known
		Halo.Shadow.known = Halo.known
		DarkReprimand.known = Penance.known
	end
	if VoidEruption.known then
		Voidform.known = true
		VoidBolt.known = true
	end
	if VoidVolley.known then
		VoidVolley.buff.known = true
		VoidVolley.damage.known = true
	end
	MindFlayInsanity.known = MindFlay.known and SurgeOfInsanity.known
	PowerSurge.Shadow.known = PowerSurge.known and Shadowform.known

	Abilities:Update()
	SummonedPets:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability then
		if ability == channel.ability then
			channel.chained = true
		end
		channel.interrupt_if = ability.interrupt_if
	else
		channel.interrupt_if = nil
	end
	channel.ability = ability
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, cooldown, start, ends, spellId, speed, max_speed
	self.main = nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	cooldown = GetSpellCooldown(61304)
	self.gcd_remains = cooldown.startTime > 0 and cooldown.duration - (self.ctime - cooldown.startTime) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.current = UnitPower('player', 0) + (self.mana.regen * self.execute_remains)
	if self.cast.ability and self.cast.ability.mana_cost > 0 then
		self.mana.current = self.mana.current - self.cast.ability:ManaCost()
	end
	self.mana.current = clamp(self.mana.current, 0, self.mana.max)
	self.mana.pct = self.mana.current / self.mana.max * 100
	if Shadowform.known then
		self.insanity.current = UnitPower('player', 13)
		if self.cast.ability then
			if self.cast.ability.insanity_cost > 0 then
				self.insanity.current = self.insanity.current - self.cast.ability:InsanityCost()
			end
			if self.cast.ability.insanity_gain > 0 then
				self.insanity.current = self.insanity.current + self.cast.ability:InsanityGain()
			end
		end
		self.insanity.current = clamp(self.insanity.current, 0, self.insanity.max)
		self.insanity.deficit = self.insanity.max - self.insanity.current
	end
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

	SummonedPets:Purge()
	TrackedAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.fiend_remains = self.fiend:Remains()
	self.fiend_up = self.fiend_remains > 0

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if not self.initialized then
		Buttons:Scan()
		UI:DisableOverlayGlows()
		UI:HookResourceFrame()
		self.guid = UnitGUID('player')
		self.name = UnitName('player')
		self.initialized = true
	end
	propheticPreviousPanel.ability = nil
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * (Player.spec == SPEC.SHADOW and 15 or 25)
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.dummy and 600) or
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
		self.boss = false
		self.dummy = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			propheticPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			propheticPreviousPanel:Hide()
		end
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self.uid = ToUID(guid) or 0
		self:UpdateHealth(true)
	end
	self.boss = false
	self.dummy = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.Dummies[self.uid] then
		self.boss = true
		self.dummy = true
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		propheticPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

-- End Target Functions

-- Start Ability Modifications

function Penance:Available(...)
	return not DarkReprimand:Available(...)
end
DivineStar.Available = Penance.Available
Halo.Available = Penance.Available

function Penance:Equilibrium()
	if PowerOfTheDarkSide.known and PowerOfTheDarkSide:Up() then
		return 'shadow'
	end
	return self.equilibrium
end

function DarkReprimand:Available(...)
	return Shadowform.known or (ShadowCovenant.known and ShadowCovenant:Up())
end
DivineStar.Shadow.Available = DarkReprimand.Available
Halo.Shadow.Available = DarkReprimand.Available

function VoidBolt:Available(...)
	return Voidform.known and Voidform:Up()
end

function VoidVolley:Available(...)
	return self.known and self.buff:Up()
end

function VoidTorrent:Available(...)
	return self.known and not VoidVolley:Available()
end

function VoidBolt:CastLanded(...)
	Ability.CastLanded(self, ...)
	ShadowWordPain:RefreshAuraAll(3)
	VampiricTouch:RefreshAuraAll(3)
end

function Voidform:Remains()
	if VoidEruption:Casting() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function Shadowform:Remains()
	if GetShapeshiftForm() == 1 then
		return 600
	end
	return Ability.Remains(self)
end

function ShadowWordPain:Duration()
	local duration = self.buff_duration
	if Misery.known then
		duration = duration + 5
	end
	if PainAndSuffering.known then
		duration = duration + (2 * PainAndSuffering.rank)
	end
	return duration
end

function ShadowWordPain:Remains()
	if (Misery.known and VampiricTouch:Casting()) or (ShadowCrash.known and ShadowCrash:InFlight()) then
		return self:Duration()
	end
	local remains = Ability.Remains(self)
	if Expiation.known and MindBlast:Casting() then
		remains = remains - (3 * Expiation.rank)
	end
	return max(0, remains)
end

function VampiricTouch:Remains()
	if ShadowCrash.known and ShadowCrash:InFlight() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function ShadowCrash:InFlight()
	return (Player.time - self.last_used) < self.travel_delay
end

function Schism:Remains()
	if self.known and MindBlast:Casting() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function Shadowfiend:Remains()
	return Pet.Shadowfiend:Remains()
end

function Lightspawn:Remains()
	return Pet.Lightspawn:Remains()
end

function MindbenderDisc:Remains()
	return max(Pet.Voidwraith:Remains(), Pet.Mindbender:Remains())
end
MindbenderShadow.Remains = MindbenderDisc.Remains

function Voidwraith:Remains()
	return Pet.Voidwraith:Remains()
end

function VoidBlast:Available(...)
	return self.known and Pet.EntropicRift:Up()
end

function Smite:Available(...)
	return not VoidBlast:Available()
end

function DevouringPlague:Duration()
	local duration = self.buff_duration
	if DistortedReality.known then
		duration = duration * 2
	end
	return duration
end

function DevouringPlague:InsanityCost()
	if MindDevourer.known and MindDevourer:Up() then
		return 0
	end
	local cost = Ability.InsanityCost(self)
	if DistortedReality.known then
		cost = cost + 5
	end
	if MindsEye.known then
		cost = cost - 5
	end
	return max(0, cost)
end

function InescapableTorment:Activate()
	if Voidwraith.known then
		Pet.Voidwraith:ExtendAll(0.7)
	elseif MindbenderShadow.known then
		Pet.Mindbender:ExtendAll(0.7)
	else
		Pet.Shadowfiend:ExtendAll(1.0)
	end
end

function MindBlast:CastLanded(...)
	if InescapableTorment.known then
		InescapableTorment:Activate()
	end
	Ability.CastLanded(self, ...)
end

function MindBlast:Free()
	return ShadowyInsight.known and ShadowyInsight:Up()
end

function MindFlay:Available(...)
	return not MindFlayInsanity:Available(...)
end

function MindFlayInsanity:Available(...)
	return self.known and self.buff:Up()
end

function ShadowWordDeath:CastLanded(...)
	if InescapableTorment.known then
		InescapableTorment:Activate()
	end
	Ability.CastLanded(self, ...)
end

function Penance:CastSuccess(...)
	if InescapableTorment.known then
		InescapableTorment:Activate()
	end
	Ability.CastSuccess(self, ...)
end
DarkReprimand.CastSuccess = Penance.CastSuccess

function TwilightEquilibrium.Holy:Remains()
	if self.known and Player.cast.ability then
		if Player.cast.ability:Equilibrium() == 'holy' then
			return 0
		elseif Player.cast.ability:Equilibrium() == 'shadow' then
			return self:Duration()
		end
	end
	return Ability.Remains(self)
end

function TwilightEquilibrium.Shadow:Remains()
	if self.known and Player.cast.ability then
		if Player.cast.ability:Equilibrium() == 'shadow' then
			return 0
		elseif Player.cast.ability:Equilibrium() == 'holy' then
			return self:Duration()
		end
	end
	return Ability.Remains(self)
end

function PsychicScream:Available(...)
	return Target.stunnable
end
PsychicHorror.Usable = PsychicScream.Usable

function TwistOfFate:CanTriggerOnAllyHeal()
	return self.known and Player.health.pct < 35
end

function TwistOfFate:Remains()
	if self.known and Target.health.pct < 35 and Player.cast.ability then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function PowerWordLife:Available(...)
	return Player.health.pct < 35
end

function DarkeningHorizon:Stack()
	local stack = self.stacks
	if VoidBlast:Casting() then
		stack = stack - 1
	end
	return max(0, stack)
end

function DarkeningHorizon:Remains()
	local stack = self:Stack()
	if stack == 0 then
		return 0
	end
	return Pet.EntropicRift:Remains()
end

function PowerSurge:Remains()
	if self.known and (Halo:Casting() or Halo.Shadow:Casting()) then
		return self:Duration()
	end
	return Ability.Remains(self)
end
PowerSurge.Shadow.Remains = PowerSurge.Remains

function VoidBlast:CastLanded(...)
	if DarkeningHorizon.known then
		for guid, unit in next, Pet.EntropicRift.active_units do
			if unit.expires > Player.time and DarkeningHorizon.stacks > 0 then
				unit.expires = unit.expires + 1.0
				DarkeningHorizon.stacks = DarkeningHorizon.stacks - 1
			end
		end
	end
	Ability.CastLanded(self, ...)
end

-- End Ability Modifications

-- Start Summoned Pet Modifications

SubservientShadows.affected = {
	[Pet.Mindbender] = true,
	[Pet.Lightspawn] = true,
	[Pet.Shadowfiend] = true,
	[Pet.Mindbender] = true,
	[Pet.Voidwraith] = true,
	[Pet.EntropicRift] = false,
}

SummonedPet.AddUnit_ = SummonedPet.AddUnit
function SummonedPet:AddUnit(...)
	local pet = SummonedPet.AddUnit_(self, ...)
	if SubservientShadows.known and SubservientShadows.affected[self] then
		pet.expires = pet.expires + (self:Duration() * 0.20)
	end
	return pet
end

function Pet.Mindbender:CastLanded(unit, spellId, dstGUID, event, missType)
	if Opt.auto_aoe and InescapableTorment:Match(spellId) then
		InescapableTorment:RecordTargetHit(dstGUID, event, missType)
	end
end
Pet.Voidwraith.CastLanded = Pet.Mindbender.CastLanded

function Pet.EntropicRift:AddUnit(...)
	local pet = SummonedPet.AddUnit(self, ...)
	if DarkeningHorizon.known then
		DarkeningHorizon.stacks = DarkeningHorizon:MaxStack()
	end
	return pet
end

-- End Summoned Pet Modifications

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

local function WaitFor(ability, wait_time)
	Player.wait_time = wait_time and (Player.ctime + wait_time) or (Player.ctime + ability:Cooldown())
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.DISCIPLINE].Main = function(self)
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
]]
	if Player:TimeInCombat() == 0 then
		if PowerWordFortitude:Usable() and PowerWordFortitude:Remains() < 300 then
			return PowerWordFortitude
		end
	else
		if PowerWordFortitude:Down() and PowerWordFortitude:Usable() then
			UseExtra(PowerWordFortitude)
		end
	end
	self.use_cds = Opt.cooldown and (
		(Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)))) or
		(PowerInfusion.known and PowerInfusion:Remains() > 10) or
		(Player.fiend_remains > 5)
	)
	self.hold_penance = (
		(self.use_cds and InescapableTorment.known and not Player.fiend_up and Player.fiend:Ready((3 - (TwilightEquilibrium.known and 2 or 0)) * Player.haste_factor)) or
		(EncroachingShadows.known and Player.enemies > 1 and ShadowWordPain:Down())
	)
	if PowerWordLife:Usable() then
		UseExtra(PowerWordLife)
	elseif Player.health.pct < 35 and DesperatePrayer:Usable() then
		UseExtra(DesperatePrayer)
	elseif (Player.health.pct < Opt.heal or Atonement:Remains() < Player.gcd) and PowerWordShield:Usable() then
		UseExtra(PowerWordShield)
	elseif self.use_cds and Player.health.pct < Opt.heal and VampiricEmbrace:Usable() then
		UseExtra(VampiricEmbrace)
	end
--[[
actions=shadow_word_death,target_if=target.time_to_die<(2*gcd)
actions+=/call_action_list,name=torment,if=talent.inescapable_torment.enabled&pet.fiend.active&pet.fiend.remains<(3*gcd)
actions+=/shadow_word_pain,if=!remains&(target.time_to_die>(tick_time*2)|(talent.purge_the_wicked.enabled&cooldown.penance.remains<target.time_to_die))
actions+=/use_items,if=cooldown.power_infusion.remains>35|buff.power_infusion.up|fight_remains<25
actions+=/power_infusion
actions+=/call_action_list,name=te_holy,if=talent.twilight_equilibrium.enabled&buff.twilight_equilibrium_holy.up
actions+=/call_action_list,name=te_shadow,if=talent.twilight_equilibrium.enabled&buff.twilight_equilibrium_shadow.up
actions+=/call_action_list,name=torment,if=talent.inescapable_torment.enabled&pet.fiend.active
actions+=/penance
actions+=/dark_reprimand
actions+=/divine_star,if=spell_targets.divine_star>=3|talent.rhapsody.enabled&buff.rhapsody.stack>=18
actions+=/halo,if=spell_targets.halo>=3
]]
	if ShadowWordDeath:Usable() and Target.timeToDie < (2 * Player.gcd) then
		return ShadowWordDeath
	end
	if ShadowWordPain:Usable() and ShadowWordPain:Down() and (Target.timeToDie > (ShadowWordPain:TickTime() * 2) or (EncroachingShadows.known and Penance:Ready(Target.timeToDie))) then
		return ShadowWordPain
	end
	if self.use_cds then
		if Opt.trinket then
			if Opt.trinket and (not PowerInfusion:Ready(35) or PowerInfusion:Up() or (Target.boss and Target.timeToDie < 25)) then
				if Trinket1:Usable() then
					UseCooldown(Trinket1)
				elseif Trinket2:Usable() then
					UseCooldown(Trinket2)
				end
			end
		end
		if PowerInfusion:Usable() then
			UseCooldown(PowerInfusion)
		end
	end
	if DarkeningHorizon.known and VoidBlast:Usable() and Pet.EntropicRift:Remains() < (2 * Player.gcd) and DarkeningHorizon:Up() then
		return VoidBlast
	end
	if InescapableTorment.known and Player.fiend_up then
		local apl = self:torment()
		if apl then return apl end
	end
	local apl
	if TwilightEquilibrium.known then
		if TwilightEquilibrium.Holy:Up() then
			apl = self:te_holy()
			if apl then return apl end
		elseif TwilightEquilibrium.Shadow:Up() then
			apl = self:te_shadow()
			if apl then return apl end
		end
	end
	return self:standard()
end

APL[SPEC.DISCIPLINE].standard = function(self)
	if InescapableTorment.known and Player.fiend_up then
		local apl = self:torment()
		if apl then return apl end
	end
	if DarkReprimand:Usable() and not self.hold_penance then
		return DarkReprimand
	end
	if Penance:Usable() and not self.hold_penance then
		return Penance
	end
	if DarkeningHorizon.known and VoidBlast:Usable() and Pet.EntropicRift:Remains() < (3 * Player.gcd) and DarkeningHorizon:Up() then
		return VoidBlast
	end
	if DivineStar:Usable() and Player.enemies >= 3 then
		UseCooldown(DivineStar)
	end
	if DivineStar.Shadow:Usable() and Player.enemies >= 3 then
		UseCooldown(DivineStar.Shadow)
	end
	if Halo:Usable() and Player.enemies >= 3 then
		UseCooldown(Halo)
	end
	if Halo.Shadow:Usable() and Player.enemies >= 3 then
		UseCooldown(Halo.Shadow)
	end
	if Rhapsody.known and HolyNova:Usable() and (not VoidBlast.known or Pet.EntropicRift:Down()) and Player.enemies >= 3 and Rhapsody:Capped(1) then
		UseCooldown(HolyNova)
	end
	if ShadowWordPain:Usable() and Schism.known and MindBlast:Ready(Player.gcd * 2) and ShadowWordPain:Remains() < 10 and Target.timeToDie > (ShadowWordPain:Remains() + (ShadowWordPain:TickTime() * 3)) then
		return ShadowWordPain
	end
	if self.use_cds and Player.fiend:Usable() and (not InescapableTorment.known or MindBlast:Ready(Player.gcd) or ShadowWordDeath:Ready(Player.gcd)) then
		UseCooldown(Player.fiend)
	end
	if Expiation.known and ShadowWordPain:Usable() and ShadowWordPain:Remains() < (3 * Expiation.rank) and Target.timeToDie > ShadowWordPain:Remains() and (MindBlast:Ready(Player.gcd * 2) or ShadowWordDeath:Ready(Player.gcd * 2)) then
		return ShadowWordPain
	end
	if ShadowWordDeath:Usable() and (
		Target.health.pct < 20 or
		Target:TimeToPct(20) > 8
	) and (
		not InescapableTorment.known or
		Player.fiend_up or
		not Player.fiend:Ready(8)
	) and (
		not Expiation.known or
		ShadowWordPain:Remains() > (3 * Expiation.rank) or
		Target.timeToDie < ShadowWordPain:Remains()
	) then
		return ShadowWordDeath
	end
	if ShadowWordPain:Usable() and ShadowWordPain:Refreshable() and Target.timeToDie > (ShadowWordPain:Remains() + (ShadowWordPain:TickTime() * 3)) then
		return ShadowWordPain
	end
	if VoidBlast:Usable() then
		return VoidBlast
	end
	if DivineStar:Usable() then
		UseCooldown(DivineStar)
	end
	if DivineStar.Shadow:Usable() then
		UseCooldown(DivineStar.Shadow)
	end
	if Halo:Usable() then
		UseCooldown(Halo)
	end
	if Halo.Shadow:Usable() then
		UseCooldown(Halo.Shadow)
	end
	if MindBlast:Usable() and (not InescapableTorment.known or Player.fiend_up or not Player.fiend:Ready(12 * Player.haste_factor)) then
		return MindBlast
	end
	if HolyNova:Usable() and Player.enemies >= 3 and not (TwilightEquilibrium.known and Rhapsody.known) and (not VoidBlast.known or Pet.EntropicRift:Down()) then
		UseCooldown(HolyNova)
	end
	if Smite:Usable() then
		return Smite
	end
	if HolyNova:Usable() and not (TwilightEquilibrium.known and Rhapsody.known) then
		UseCooldown(HolyNova)
	end
	if ShadowWordPain:Usable() then
		return ShadowWordPain
	end
end

APL[SPEC.DISCIPLINE].te_holy = function(self)
	if Penance:Usable() and not self.hold_penance and Penance:Equilibrium() == 'holy' then
		return Penance
	end
	if DivineStar:Usable() and Player.enemies >= 3 then
		UseCooldown(DivineStar)
	end
	if Rhapsody.known and HolyNova:Usable() and Player.enemies >= 3 and Rhapsody:Capped(1) then
		UseCooldown(HolyNova)
	end
	if DivineStar:Usable() then
		UseCooldown(DivineStar)
	end
	if Halo:Usable() then
		UseCooldown(Halo)
	end
	if Rhapsody.known and HolyNova:Usable() and Rhapsody:Capped() then
		UseCooldown(HolyNova)
	end
	if Smite:Usable() then
		return Smite
	end
	if HolyNova:Usable() and Player.enemies >= 3 and (not Rhapsody.known or Rhapsody:Capped(3)) then
		UseCooldown(HolyNova)
	end
end

APL[SPEC.DISCIPLINE].te_shadow = function(self)
	if DarkReprimand:Usable() and not self.hold_penance then
		return DarkReprimand
	end
	if Penance:Usable() and not self.hold_penance and Penance:Equilibrium() == 'shadow' then
		return Penance
	end
	if DarkeningHorizon.known and VoidBlast:Usable() and Pet.EntropicRift:Remains() < (3 * Player.gcd) and DarkeningHorizon:Up() then
		return VoidBlast
	end
	if DivineStar.Shadow:Usable() and Player.enemies >= 3 then
		UseCooldown(DivineStar.Shadow)
	end
	if Halo.Shadow:Usable() and Player.enemies >= 3 then
		UseCooldown(Halo.Shadow)
	end
	if ShadowWordPain:Usable() and Schism.known and MindBlast:Ready(Player.gcd * 2) and ShadowWordPain:Remains() < 10 and Target.timeToDie > (ShadowWordPain:Remains() + (ShadowWordPain:TickTime() * 3)) then
		return ShadowWordPain
	end
	if self.use_cds and Player.fiend:Usable() and (not InescapableTorment.known or MindBlast:Ready(Player.gcd) or ShadowWordDeath:Ready(Player.gcd)) then
		UseCooldown(Player.fiend)
	end
	if Expiation.known and ShadowWordPain:Usable() and ShadowWordPain:Remains() < (3 * Expiation.rank) and Target.timeToDie > ShadowWordPain:Remains() then
		return ShadowWordPain
	end
	if ShadowWordDeath:Usable() and (
		Target.health.pct < 20 or
		Target:TimeToPct(20) > 8
	) and (
		not InescapableTorment.known or
		Player.fiend_up or
		not Player.fiend:Ready(8)
	) and (
		not Expiation.known or
		ShadowWordPain:Remains() > (3 * Expiation.rank) or
		Target.timeToDie < ShadowWordPain:Remains()
	) then
		return ShadowWordDeath
	end
	if VoidBlast:Usable() then
		return VoidBlast
	end
	if DivineStar.Shadow:Usable() then
		UseCooldown(DivineStar.Shadow)
	end
	if Halo.Shadow:Usable() then
		UseCooldown(Halo.Shadow)
	end
	if ShadowWordPain:Usable() and ShadowWordPain:Refreshable() and Target.timeToDie > (ShadowWordPain:Remains() + (ShadowWordPain:TickTime() * 3)) then
		return ShadowWordPain
	end
	if MindBlast:Usable() and (not InescapableTorment.known or Player.fiend_up or not Player.fiend:Ready(12 * Player.haste_factor)) then
		return MindBlast
	end
end

APL[SPEC.DISCIPLINE].torment = function(self)
--[[
actions.torment=mind_blast,if=charges_fractional>1.8&pet.fiend.remains>=execute_time
actions.torment+=/schism,if=pet.fiend.remains>(3*gcd)
actions.torment+=/shadow_word_death,target_if=min:target.time_to_die,if=target.health.pct<20
actions.torment+=/mind_blast,if=charges_fractional>1.5&pet.fiend.remains>=execute_time
actions.torment+=/shadow_word_death,target_if=min:target.time_to_die,if=target.time_to_pct_20>(pet.fiend.remains-gcd)
actions.torment+=/mind_blast,if=pet.fiend.remains>=execute_time
]]
	if ShadowWordDeath:Usable() and Player.fiend_remains < (Player.gcd * 2) then
		return ShadowWordDeath
	end
	if Expiation.known and ShadowWordPain:Usable() and ShadowWordPain:Remains() < (3 * Expiation.rank) and Target.timeToDie > ShadowWordPain:Remains() then
		return ShadowWordPain
	end
	if Schism.known and MindBlast:Usable() and Schism:Down() and Player.fiend_remains > MindBlast:CastTime()  then
		return MindBlast
	end
	if DarkReprimand:Usable() and not self.hold_penance then
		return DarkReprimand
	end
	if Penance:Usable() and not self.hold_penance then
		return Penance
	end
	if DarkeningHorizon.known and VoidBlast:Usable() and Pet.EntropicRift:Remains() < (3 * Player.gcd) and DarkeningHorizon:Up() then
		return VoidBlast
	end
	if ShadowWordDeath:Usable() and (
		Target.health.pct < 20 or
		Target:TimeToPct(20) > 8
	) and (
		not Expiation.known or
		ShadowWordPain:Remains() > (3 * Expiation.rank) or
		Target.timeToDie < ShadowWordPain:Remains()
	) then
		return ShadowWordDeath
	end
	if MindBlast:Usable() and Player.fiend_remains > MindBlast:CastTime() then
		return MindBlast
	end
end

APL[SPEC.HOLY].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if PowerWordFortitude:Usable() and PowerWordFortitude:Remains() < 300 then
			return PowerWordFortitude
		end
	else
		if PowerWordFortitude:Down() and PowerWordFortitude:Usable() then
			UseExtra(PowerWordFortitude)
		end
	end
	if PowerWordLife:Usable() then
		UseExtra(PowerWordLife)
	elseif Player.health.pct < 35 and DesperatePrayer:Usable() then
		UseExtra(DesperatePrayer)
	elseif (Player.health.pct < Opt.heal or Atonement:Remains() < Player.gcd) and PowerWordShield:Usable() then
		UseExtra(PowerWordShield)
	elseif self.use_cds and Player.health.pct < Opt.heal and VampiricEmbrace:Usable() then
		UseExtra(VampiricEmbrace)
	end
end

APL[SPEC.SHADOW].Main = function(self)
	self.use_cds = Opt.cooldown and (
		(Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)))) or
		(PowerSurge.known and Halo.Shadow.known and PowerSurge.Shadow:Remains() > 5) or
		(PowerInfusion.known and PowerInfusion:Remains() > 8) or
		(DarkAscension.known and DarkAscension:Remains() > 8) or
		(VoidEruption.known and Voidform:Remains() > 8) or
		(Player.fiend_remains > 8)
	)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=snapshot_stats
actions.precombat+=/shadowform,if=!buff.shadowform.up
actions.precombat+=/variable,name=trinket_1_buffs,value=(trinket.1.has_buff.intellect|trinket.1.has_buff.mastery|trinket.1.has_buff.versatility|trinket.1.has_buff.haste|trinket.1.has_buff.crit|trinket.1.is.signet_of_the_priory)&(trinket.1.cooldown.duration>=20)
actions.precombat+=/variable,name=trinket_2_buffs,value=(trinket.2.has_buff.intellect|trinket.2.has_buff.mastery|trinket.2.has_buff.versatility|trinket.2.has_buff.haste|trinket.2.has_buff.crit|trinket.2.is.signet_of_the_priory)&(trinket.2.cooldown.duration>=20)
actions.precombat+=/variable,name=dr_force_prio,default=1,op=reset
actions.precombat+=/variable,name=me_force_prio,default=1,op=reset
actions.precombat+=/variable,name=max_vts,default=12,op=reset
actions.precombat+=/variable,name=is_vt_possible,default=0,op=reset
actions.precombat+=/use_item,name=ingenious_mana_battery
actions.precombat+=/arcane_torrent
actions.precombat+=/use_item,name=aberrant_spellforge
actions.precombat+=/halo,if=!fight_style.dungeonroute&!fight_style.dungeonslice&active_enemies<=4&(fight_remains>=120|active_enemies<=2)&!talent.power_surge
actions.precombat+=/shadow_crash,if=raid_event.adds.in>=25&spell_targets.shadow_crash<=12&!fight_style.dungeonslice
actions.precombat+=/vampiric_touch,if=!action.shadow_crash.enabled|raid_event.adds.in<25|spell_targets.shadow_crash>8|fight_style.dungeonslice
]]
		if PowerWordFortitude:Usable() and PowerWordFortitude:Remains() < 300 then
			return PowerWordFortitude
		end
		if Shadowform:Usable() and Shadowform:Down() then
			return Shadowform
		end
		if ShadowCrash:Usable() and not ShadowCrash:InFlight() then
			UseCooldown(ShadowCrash)
		end
		if VampiricTouch:Usable() and VampiricTouch:Down() and not (ShadowCrash.known and (ShadowCrash:Ready() or ShadowCrash:InFlight())) then
			return VampiricTouch
		end
	else
		if PowerWordFortitude:Down() and PowerWordFortitude:Usable() then
			UseExtra(PowerWordFortitude)
		end
	end
	if PowerWordLife:Usable() then
		UseExtra(PowerWordLife)
	elseif Player.health.pct < 35 and DesperatePrayer:Usable() then
		UseExtra(DesperatePrayer)
	elseif (Player.health.pct < Opt.heal or Player:UnderMeleeAttack()) and PowerWordShield:Usable() then
		UseExtra(PowerWordShield)
	elseif self.use_cds and Player.health.pct < Opt.heal and VampiricEmbrace:Usable() then
		UseExtra(VampiricEmbrace)
	end
--[[
actions=variable,name=holding_crash,op=set,value=raid_event.adds.in<15
actions+=/call_action_list,name=aoe,if=active_enemies>2
actions+=/run_action_list,name=main
]]
	self.holding_crash = false
	self.max_vts = 0
	if Player.enemies > 2 then
		local apl = self:aoe()
		if apl then return apl end
	end
	return self:main()
end

APL[SPEC.SHADOW].precombat_variables = function(self)
	-- default channel interrupts if casted outside window of APL recommendation
	MindFlay.interrupt_if = self.channel_interrupt[1]
	MindFlayInsanity.interrupt_if = nil
	VoidTorrent.interrupt_if = nil
end

APL[SPEC.SHADOW].aoe = function(self)
--[[
actions.aoe=call_action_list,name=aoe_variables
actions.aoe+=/vampiric_touch,if=(variable.max_vts>0&!variable.manual_vts_applied&!action.shadow_crash.in_flight)&!buff.entropic_rift.up
actions.aoe+=/shadow_crash,if=!variable.holding_crash,target_if=dot.vampiric_touch.refreshable|dot.vampiric_touch.remains<=target.time_to_die&!buff.voidform.up&(raid_event.adds.in-dot.vampiric_touch.remains)<15
]]
	self:aoe_variables()
	if VampiricTouch:Usable() and VampiricTouch:Refreshable() and Target.timeToDie > (VampiricTouch:Remains() + (VampiricTouch:TickTime() * 4)) and (self.max_vts > 0 and not self.manual_vts_applied and not ShadowCrash:InFlight()) and (not EntropicRift.known or Pet.EntropicRift:Down()) then
		return VampiricTouch
	end
	if ShadowCrash:Usable() and not self.holding_crash and not ShadowCrash:InFlight() and VampiricTouch:Refreshable() and ShadowCrash:ChargesFractional() > 1.5 then
		UseCooldown(ShadowCrash)
	end
end

APL[SPEC.SHADOW].aoe_variables = function(self)
--[[
actions.aoe_variables=variable,name=max_vts,op=set,default=12,value=spell_targets.vampiric_touch>?12
actions.aoe_variables+=/variable,name=is_vt_possible,op=set,value=0,default=1
actions.aoe_variables+=/variable,name=is_vt_possible,op=set,value=1,if=target.time_to_die>=18
actions.aoe_variables+=/variable,name=dots_up,op=set,value=(active_dot.vampiric_touch+8*(action.shadow_crash.in_flight&action.shadow_crash.enabled))>=variable.max_vts|!variable.is_vt_possible
actions.aoe_variables+=/variable,name=holding_crash,op=set,value=(variable.max_vts-active_dot.vampiric_touch)<4&raid_event.adds.in>15|raid_event.adds.in<10&raid_event.adds.count>(variable.max_vts-active_dot.vampiric_touch),if=variable.holding_crash&action.shadow_crash.enabled&raid_event.adds.exists
actions.aoe_variables+=/variable,name=manual_vts_applied,op=set,value=(active_dot.vampiric_touch+8*!variable.holding_crash)>=variable.max_vts|!variable.is_vt_possible
]]
	self.max_vts = min(12, Player.enemies)
	self.is_vt_possible = Target.timeToDie >= (VampiricTouch:Remains() + (VampiricTouch:TickTime() * 4))
	self.dots_up = (not self.is_vt_possible) or (VampiricTouch:Ticking() + (ShadowCrash.known and ShadowCrash:InFlight() and 8 or 0)) >= self.max_vts
	self.manual_vts_applied = (not self.is_vt_possible) or (VampiricTouch:Ticking() + (not self.holding_crash and 8 or 0)) >= self.max_vts
end

APL[SPEC.SHADOW].cds = function(self)
--[[
actions.cds=potion,if=(buff.voidform.up|buff.power_infusion.up|buff.dark_ascension.up&(fight_remains<=cooldown.power_infusion.remains+15))&(fight_remains>=320|time_to_bloodlust>=320|buff.bloodlust.react)|fight_remains<=30
actions.cds+=/fireblood,if=buff.power_infusion.up|fight_remains<=8
actions.cds+=/berserking,if=buff.power_infusion.up|fight_remains<=12
actions.cds+=/blood_fury,if=buff.power_infusion.up|fight_remains<=15
actions.cds+=/ancestral_call,if=buff.power_infusion.up|fight_remains<=15
actions.cds+=/power_infusion,if=(buff.voidform.up|buff.dark_ascension.up&(fight_remains<=80|fight_remains>=140)|active_allied_augmentations)
actions.cds+=/invoke_external_buff,name=power_infusion,if=(buff.voidform.up|buff.dark_ascension.up)&!buff.power_infusion.up
actions.cds+=/invoke_external_buff,name=bloodlust,if=buff.power_infusion.up&fight_remains<120|fight_remains<=40
actions.cds+=/halo,if=talent.power_surge&(pet.fiend.active&cooldown.fiend.remains>=4&talent.mindbender|!talent.mindbender&!cooldown.fiend.up|active_enemies>2&!talent.inescapable_torment|!talent.dark_ascension)&(cooldown.mind_blast.charges=0|!talent.void_eruption|cooldown.void_eruption.remains>=gcd.max*4)
actions.cds+=/void_eruption,if=(pet.fiend.active&cooldown.fiend.remains>=4|!talent.mindbender&!cooldown.fiend.up|active_enemies>2&!talent.inescapable_torment)&(cooldown.mind_blast.charges=0|time>15)
actions.cds+=/dark_ascension,if=(pet.fiend.active&cooldown.fiend.remains>=4|!talent.mindbender&!cooldown.fiend.up|active_enemies>2&!talent.inescapable_torment)&(active_dot.devouring_plague>=1|insanity>=(15+5*!talent.minds_eye+5*talent.distorted_reality-pet.fiend.active*6))
actions.cds+=/call_action_list,name=trinkets
actions.cds+=/desperate_prayer,if=health.pct<=75
]]
	if PowerInfusion:Usable() and (
		(Player.fiend_up and not (VoidEruption.known or DarkAscension.known)) or
		(VoidEruption.known and Voidform:Up()) or
		(DarkAscension.known and DarkAscension:Up()) or
		(Target.boss and Target.timeToDie < 20)
	) then
		return UseCooldown(PowerInfusion)
	end
	self.cd_condition = (
		(Player.fiend_up and not Player.fiend:Ready(4)) or
		(Player.insanity.deficit < 40 and Player.fiend:Ready(4)) or
		(not MindbenderShadow.known and not Player.fiend:Ready()) or
		(Player.enemies > 2 and not InescapableTorment.known)
	)
	if PowerSurge.known and Halo.Shadow:Usable() and (
		self.cd_condition or
		not DarkAscension.known
	) and (
		not VoidEruption.known or
		MindBlast:Charges() == 0 or
		not VoidEruption:Ready(Player.gcd * 4)
	) then
		return UseCooldown(Halo.Shadow)
	end
	if self.cd_condition and VoidEruption:Usable() and (
		Player.insanity.deficit < 40 or
		MindBlast:Charges() == 0 or
		Player:TimeInCombat() > 15
	) then
		return UseCooldown(VoidEruption)
	end
	if self.cd_condition and DarkAscension:Usable() and (
		DevouringPlague:Ticking() >= 1 or
		Player.insanity.current >= (15 + (MindsEye.known and 0 or 5) + (DistortedReality.known and 5 or 0) - (Player.fiend_up and 6 or 0))
	) then
		return UseCooldown(DarkAscension)
	end
	if Opt.trinket then
		self:trinkets()
	end
	if Player.fiend:Usable() and Player.insanity.deficit >= 16 and (
		(ShadowWordPain:Up() and self.dots_up) or
		(ShadowCrash.known and ShadowCrash:InFlight())
	) and (
		not PowerSurge.known or
		PowerSurge.Shadow:Up() or
		(Halo.Shadow.known and Halo.Shadow:Ready())
	) and (
		Target.timeToDie < 15 or
		(DarkAscension.known and DarkAscension:Ready(Player.gcd)) or
		(VoidEruption.known and (VoidEruption:Ready(Player.gcd) or (MindbenderShadow.known and not VoidEruption:Ready(50)))) or
		not (DarkAscension.known or VoidEruption.known)
	) then
		return UseCooldown(Player.fiend)
	end
end

APL[SPEC.SHADOW].trinkets = function(self)
--[[
actions.trinkets=use_item,use_off_gcd=1,name=hyperthread_wristwraps,if=talent.void_blast&hyperthread_wristwraps.void_blast.count>=2&!cooldown.mind_blast.up|!talent.void_blast&((hyperthread_wristwraps.void_bolt.count>=1|!talent.void_eruption)&hyperthread_wristwraps.void_torrent.count>=1)
actions.trinkets+=/use_item,use_off_gcd=1,name=aberrant_spellforge,if=gcd.remains>0&buff.aberrant_spellforge.stack<=4
actions.trinkets+=/use_item,use_off_gcd=1,name=neural_synapse_enhancer,if=(buff.power_surge.up|buff.entropic_rift.up|variable.trinket_1_buffs|variable.trinket_2_buffs)&(buff.voidform.up|cooldown.void_eruption.remains>=40|buff.dark_ascension.up)
actions.trinkets+=/use_item,use_off_gcd=1,name=flarendos_pilot_light,if=gcd.remains>0&(buff.voidform.up|buff.power_infusion.remains>=10|buff.dark_ascension.up)|fight_remains<20
actions.trinkets+=/use_item,use_off_gcd=1,name=geargrinders_spare_keys,if=gcd.remains>0
actions.trinkets+=/use_item,name=spymasters_web,if=(buff.power_infusion.remains>=10&buff.spymasters_report.stack>=36&fight_remains>240)&(buff.voidform.up|buff.dark_ascension.up|!talent.dark_ascension&!talent.void_eruption)|((buff.power_infusion.remains>=10&buff.bloodlust.up&buff.spymasters_report.stack>=10)|buff.power_infusion.remains>=10&(fight_remains<120))&(buff.voidform.up|buff.dark_ascension.up|!talent.dark_ascension&!talent.void_eruption)|(fight_remains<=20|buff.dark_ascension.up&fight_remains<=60|buff.entropic_rift.up&talent.entropic_rift&fight_remains<=30)&!buff.spymasters_web.up
actions.trinkets+=/use_item,name=prized_gladiators_badge_of_ferocity,if=(buff.voidform.up|buff.power_infusion.remains>=10|buff.dark_ascension.up|(talent.void_eruption&cooldown.void_eruption.remains>10)|equipped.neural_synapse_enhancer&buff.entropic_rift.up)|fight_remains<20
actions.trinkets+=/use_item,name=astral_gladiators_badge_of_ferocity,if=(buff.voidform.up|buff.power_infusion.remains>=10|buff.dark_ascension.up|(talent.void_eruption&cooldown.void_eruption.remains>10)|equipped.neural_synapse_enhancer&buff.entropic_rift.up)|fight_remains<20
actions.trinkets+=/use_item,use_off_gcd=1,name=perfidious_projector,if=gcd.remains>0&(!talent.voidheart|buff.voidheart.up|fight_remains<20)
actions.trinkets+=/use_items,if=(buff.voidform.up|buff.power_infusion.remains>=10|buff.dark_ascension.up|equipped.neural_synapse_enhancer&buff.entropic_rift.up)|fight_remains<20
]]
	if Trinket1:Usable() and (Voidform:Up() or PowerInfusion:Up() or DarkAscension:Up() or (Target.boss and Target.timeToDie < 20)) then
		return UseCooldown(Trinket1)
	end
	if Trinket2:Usable() and (Voidform:Up() or PowerInfusion:Up() or DarkAscension:Up() or (Target.boss and Target.timeToDie < 20)) then
		return UseCooldown(Trinket2)
	end
end

APL[SPEC.SHADOW].main = function(self)
--[[
actions.main=variable,name=dots_up,op=set,value=active_dot.vampiric_touch=active_enemies|action.shadow_crash.in_flight,if=active_enemies<3
actions.main+=/call_action_list,name=cds,if=fight_remains<30|target.time_to_die>15&(!variable.holding_crash|active_enemies>2)
actions.main+=/mindbender,if=(dot.shadow_word_pain.ticking&variable.dots_up|action.shadow_crash.in_flight)&(!cooldown.halo.up|!talent.power_surge.enabled)&(fight_remains<30|target.time_to_die>15)&(!talent.dark_ascension|cooldown.dark_ascension.remains<gcd.max|fight_remains<15)
actions.main+=/shadow_word_death,if=priest.force_devour_matter&talent.devour_matter
actions.main+=/void_blast,if=(dot.devouring_plague.remains>=execute_time|buff.entropic_rift.remains<=gcd.max|action.void_torrent.channeling&talent.void_empowerment)&(insanity.deficit>=16|cooldown.mind_blast.full_recharge_time<=gcd.max|buff.entropic_rift.remains<=gcd.max)
actions.main+=/devouring_plague,if=buff.voidform.up&talent.perfected_form&buff.voidform.remains<=gcd.max&talent.void_eruption
actions.main+=/void_bolt,if=insanity.deficit>16&cooldown.void_bolt.remains%gcd.max<=0.1
actions.main+=/devouring_plague,if=active_dot.devouring_plague<=1&dot.devouring_plague.remains<=gcd.max&(!talent.void_eruption|cooldown.void_eruption.remains>=gcd.max*3)|insanity.deficit<=35|buff.mind_devourer.up|buff.entropic_rift.up|buff.power_surge.up&buff.tww3_archon_4pc_helper.stack<4&buff.ascension.up
actions.main+=/void_torrent,if=!variable.holding_crash&(dot.devouring_plague.remains>=2.5&(cooldown.dark_ascension.remains>=12|!talent.dark_ascension|!talent.void_blast)|cooldown.void_eruption.remains<=3&talent.void_eruption),interrupt_if=!talent.entropic_rift,interrupt_immediate=1
actions.main+=/void_volley,if=buff.void_volley.remains<=5|buff.entropic_rift.up&action.void_blast.usable_in>buff.entropic_rift.remains|target.time_to_die<=5
actions.main+=/mind_flay_insanity,target_if=max:dot.devouring_plague.remains
actions.main+=/shadow_crash,if=!variable.holding_crash&!action.shadow_crash.in_flight
actions.main+=/vampiric_touch,if=refreshable&target.time_to_die>12&(dot.vampiric_touch.ticking|!variable.dots_up)&(variable.max_vts>0|active_enemies=1)&(action.shadow_crash.usable_in>=dot.vampiric_touch.remains|variable.holding_crash|!action.shadow_crash.enabled)&(!action.shadow_crash.in_flight)
actions.main+=/mind_blast,if=(!buff.mind_devourer.react|!talent.mind_devourer|cooldown.void_eruption.up&talent.void_eruption)
actions.main+=/void_volley
actions.main+=/devouring_plague,if=buff.voidform.up&talent.void_eruption|buff.power_surge.up|talent.distorted_reality
actions.main+=/halo,if=spell_targets>1
actions.main+=/call_action_list,name=heal_for_tof,if=!buff.twist_of_fate.up&buff.twist_of_fate_can_trigger_on_ally_heal.up&(talent.rhapsody|talent.divine_star|talent.halo)
actions.main+=/shadow_crash,if=!variable.holding_crash&raid_event.adds.in>=30&talent.descending_darkness&raid_event.movement.in>=30
actions.main+=/shadow_word_death,target_if=target.health.pct<(20+15*talent.deathspeaker)
actions.main+=/shadow_word_death,if=talent.inescapable_torment&pet.fiend.active
actions.main+=/mind_flay,chain=1,interrupt_immediate=1,interrupt_if=ticks>=2,interrupt_global=1
actions.main+=/divine_star
actions.main+=/shadow_crash,if=raid_event.adds.in>20
actions.main+=/shadow_word_death,target_if=target.health.pct<20
actions.main+=/shadow_word_death,target_if=max:dot.devouring_plague.remains
actions.main+=/shadow_word_pain,target_if=min:remains
]]
	self.dots_up = VampiricTouch:Ticking() >= min(6, Player.enemies) or (ShadowCrash.known and ShadowCrash:InFlight())
	if self.use_cds then
		self:cds()
	end
	if VoidBlast:Usable() and (
		Pet.EntropicRift:Remains() <= Player.gcd or
		(
			DevouringPlague:Remains() >= VoidBlast:CastTime() or
			Pet.EntropicRift:Remains() <= Player.gcd or
			(VoidEmpowerment.known and VoidTorrent:Channeling())
		) and (
			Player.insanity.deficit >= 16 or
			MindBlast:FullRechargeTime() <= Player.gcd
		)
	) then
		return VoidBlast
	end
	if DevouringPlague:Usable() and (
		Player.insanity.deficit <= 16 or
		(VoidEruption.known and PerfectedForm.known and Voidform:Up() and Voidform:Remains() <= Player.gcd * 2)
	) then
		return DevouringPlague
	end
	if VoidBolt:Usable() and Player.insanity.deficit > 16 then
		return VoidBolt
	end
	if DevouringPlague:Usable() and Player.insanity.deficit <= 16 then
		return DevouringPlague
	end
	if DevouringPlague:Usable() and DevouringPlague:Ticking() <= 1 and DevouringPlague:Remains() <= Player.gcd and (
		not VoidEruption.known or
		not VoidEruption:Ready(Player.gcd * 3) or
		Player.insanity.deficit <= 35 or
		(MindDevourer.known and MindDevourer:Up()) or
		(EntropicRift.known and Pet.EntropicRift:Up())
		--(PowerSurge.known and PowerSurge.Shadow:Up() and Ascension:Up())
	) then
		return DevouringPlague
	end
	if VoidTorrent:Usable() and not self.holding_crash and (
		(DevouringPlague:Remains() >= 2.5 and (not DarkAscension.known or not VoidBlast.known or not DarkAscension:Ready(12))) or
		(VoidEruption.known and VoidEruption:Ready(3))
	) then
		VoidTorrent.interrupt_if = self.channel_interrupt[2]
		UseCooldown(VoidTorrent)
	end
	if VoidVolley:Usable() and (
		VoidVolley.buff:Remains() <= 5 or
		(EntropicRift.known and Pet.EntropicRift:Up() and VoidBlast:Cooldown() < Pet.EntropicRift:Remains()) or
		Target.timeToDie <= 5
	) then
		UseCooldown(VoidVolley)
	end
	if MindFlayInsanity:Usable() then
		MindFlayInsanity.interrupt_if = nil
		return MindFlayInsanity
	end
	if ShadowCrash:Usable() and not self.holding_crash and not ShadowCrash:InFlight() and (
		VampiricTouch:Refreshable() or
		ShadowCrash:ChargesFractional() > 1.8
	) then
		UseCooldown(ShadowCrash)
	end
	if VampiricTouch:Usable() and VampiricTouch:Refreshable() and Target.timeToDie > (VampiricTouch:Remains() + (VampiricTouch:TickTime() * 3)) and not ShadowCrash:InFlight() and (VampiricTouch:Up() or not self.dots_up) and (self.max_vts > 0 or Player.enemies == 1) and (not ShadowCrash.known or self.holding_crash or ShadowCrash:Cooldown() > VampiricTouch:Remains()) then
		return VampiricTouch
	end
	if MindBlast:Usable() and (
		not MindDevourer.known or
		MindDevourer:Down() or
		(self.use_cds and VoidEruption.known and VoidEruption:Ready(MindBlast:Charges() * MindBlast:CastTime()))
	) then
		return MindBlast
	end
	if VoidVolley:Usable() then
		UseCooldown(VoidVolley)
	end
	if DevouringPlague:Usable() and (
		DistortedReality.known or
		(VoidEruption.known and Voidform:Up()) or
		(PowerSurge.known and PowerSurge.Shadow:Up())
	) then
		return DevouringPlague
	end
	if (self.use_cds or not PowerSurge.known) and Halo.Shadow:Usable() and Player.enemies > 1 then
		UseCooldown(Halo.Shadow)
	end
	if TwistOfFate.known and TwistOfFate:Down() and TwistOfFate:CanTriggerOnAllyHeal() then
		self:heal_for_tof()
	end
	if DescendingDarkness.known and ShadowCrash:Usable() and not ShadowCrash:InFlight() and ShadowCrash:ChargesFractional() > 1.5 then
		UseCooldown(ShadowCrash)
	end
	if ShadowWordDeath:Usable() and (
		Target.health.pct < (20 + (Deathspeaker.known and 15 or 0)) or
		(InescapableTorment.known and Player.fiend_up)
	) then
		return ShadowWordDeath
	end
	if not Player.moving and MindFlay:Usable() then
		MindFlay.interrupt_if = self.channel_interrupt[1]
		return MindFlay
	end
	if DivineStar.Shadow:Usable() then
		UseCooldown(DivineStar.Shadow)
	end
	if ShadowCrash:Usable() and not self.holding_crash and not ShadowCrash:InFlight() and ShadowCrash:ChargesFractional() > 1.5 then
		UseCooldown(ShadowCrash)
	end
	if ShadowWordDeath:Usable() then
		return ShadowWordDeath
	end
	if ShadowWordPain:Usable() then
		return ShadowWordPain
	end
end

APL[SPEC.SHADOW].heal_for_tof = function(self)
--[[
actions.heal_for_tof=halo
actions.heal_for_tof+=/divine_star
actions.heal_for_tof+=/holy_nova,if=buff.rhapsody.stack=20&talent.rhapsody
]]
	if not PowerSurge.known and Halo.Shadow:Usable() then
		UseExtra(Halo.Shadow)
	elseif DivineStar.Shadow:Usable() then
		UseExtra(DivineStar.Shadow)
	elseif Rhapsody.known and HolyNova:Usable() and Rhapsody:Capped() then
		UseExtra(HolyNova)
	end
end

APL[SPEC.SHADOW].channel_interrupt = {
	[1] = function() -- Mind Flay
		return Player.channel.ticks >= 2
	end,
	[2] = function() -- Void Torrent
		return not EntropicRift.known
	end,
}

APL.Interrupt = function(self)
	if Silence:Usable() then
		return Silence
	end
	if PsychicHorror:Usable() then
		return PsychicHorror
	end
	if PsychicScream:Usable() then
		return PsychicScream
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI:DisableOverlayGlows()
	if not Opt.glow.blizzard then
		SetCVar('assistedCombatHighlight', 0)
	end
	if Opt.glow.blizzard or not LibStub then
		return
	end
	local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
	if lib then
		lib.ShowOverlayGlow = function(...)
			return lib.HideOverlayGlow(...)
		end
	end
end

function UI:UpdateGlows()
	for _, button in next, Buttons.all do
		if button.action and button.frame:IsVisible() and (
			(Opt.glow.main and button.action == Player.main) or
			(Opt.glow.cooldown and button.action == Player.cd) or
			(Opt.glow.interrupt and button.action == Player.interrupt) or
			(Opt.glow.extra and button.action == Player.extra)
		) then
			if not button.glow:IsVisible() then
				button.glow:Show()
				if Opt.glow.animation then
					button.glow.ProcStartAnim:Play()
				else
					button.glow.ProcLoop:Play()
				end
			end
		elseif button.glow:IsVisible() then
			if button.glow.ProcStartAnim:IsPlaying() then
				button.glow.ProcStartAnim:Stop()
			end
			if button.glow.ProcLoop:IsPlaying() then
				button.glow.ProcLoop:Stop()
			end
			button.glow:Hide()
		end
	end
end

function UI:UpdateBindings()
	for _, item in next, InventoryItems.all do
		wipe(item.keybinds)
	end
	for _, ability in next, Abilities.all do
		wipe(ability.keybinds)
	end
	for _, button in next, Buttons.all do
		if button.action and button.keybind then
			button.action.keybinds[#button.action.keybinds + 1] = button.keybind
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	propheticPanel:SetMovable(not Opt.snap)
	propheticPreviousPanel:SetMovable(not Opt.snap)
	propheticCooldownPanel:SetMovable(not Opt.snap)
	propheticInterruptPanel:SetMovable(not Opt.snap)
	propheticExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		propheticPanel:SetUserPlaced(true)
		propheticPreviousPanel:SetUserPlaced(true)
		propheticCooldownPanel:SetUserPlaced(true)
		propheticInterruptPanel:SetUserPlaced(true)
		propheticExtraPanel:SetUserPlaced(true)
	end
	propheticPanel:EnableMouse(draggable or Opt.aoe)
	propheticPanel.button:SetShown(Opt.aoe)
	propheticPreviousPanel:EnableMouse(draggable)
	propheticCooldownPanel:EnableMouse(draggable)
	propheticInterruptPanel:EnableMouse(draggable)
	propheticExtraPanel:EnableMouse(draggable)
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
	propheticPanel.text:SetScale(Opt.scale.main)
	propheticPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	propheticCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	propheticCooldownPanel.text:SetScale(Opt.scale.cooldown)
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
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.DISCIPLINE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 },
		},
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 },
		},
		[SPEC.SHADOW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 },
		}
	},
	kui = { -- Kui Nameplates
		[SPEC.DISCIPLINE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.SHADOW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		propheticPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
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
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
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
	self:UpdateGlows()
end

function UI:Reset()
	propheticPanel:ClearAllPoints()
	propheticPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_center, text_tr, text_bl, text_cd_center, text_cd_tr
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsSpellUsable(Player.main.spellId)) or
		           (Player.main.itemId and IsItemUsable(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsSpellUsable(Player.cd.spellId)) or
		           (Player.cd.itemId and IsItemUsable(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
		if Opt.keybinds then
			for _, bind in next, Player.main.keybinds do
				text_tr = bind
				break
			end
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd_center = format('%.1f', react)
			end
		end
		if Opt.keybinds then
			for _, bind in next, Player.cd.keybinds do
				text_cd_tr = bind
				break
			end
		end
	end
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT\n%.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	if channel.ability and not channel.ability.ignore_channel and channel.tick_count > 0 then
		dim = Opt.dimmer
		if channel.tick_count > 1 then
			local ctime = GetTime()
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = '|cFF00FF00CHAIN'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if Opt.fiend then
		local remains
		for _, unit in next, Pet.Shadowfiend.active_units do
			remains = unit.expires - Player.time
			if remains > 0 then
				self.remains_list[#self.remains_list + 1] = remains
			end
		end
		for _, unit in next, Pet.Lightspawn.active_units do
			remains = unit.expires - Player.time
			if remains > 0 then
				self.remains_list[#self.remains_list + 1] = remains
			end
		end
		for _, unit in next, Pet.Mindbender.active_units do
			remains = unit.expires - Player.time
			if remains > 0 then
				self.remains_list[#self.remains_list + 1] = remains
			end
		end
		for _, unit in next, Pet.Voidwraith.active_units do
			remains = unit.expires - Player.time
			if remains > 0 then
				self.remains_list[#self.remains_list + 1] = remains
			end
		end
	end
	if #self.remains_list > 0 then
		table.sort(self.remains_list)
		for i = #self.remains_list, 1, -1 do
			text_bl = format('%.1fs\n%s', self.remains_list[i], text_bl or '')
			self.remains_list[i] = nil
		end
	end
	if border ~= propheticPanel.border.overlay then
		propheticPanel.border.overlay = border
		propheticPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	propheticPanel.dimmer:SetShown(dim)
	propheticPanel.text.center:SetText(text_center)
	propheticPanel.text.tr:SetText(text_tr)
	propheticPanel.text.bl:SetText(text_bl)
	propheticCooldownPanel.dimmer:SetShown(dim_cd)
	propheticCooldownPanel.text.center:SetText(text_cd_center)
	propheticCooldownPanel.text.tr:SetText(text_cd_tr)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		propheticPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = Player.main:Free()
	end
	if Player.cd then
		propheticCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local cooldown = GetSpellCooldown(Player.cd.spellId)
			propheticCooldownPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
		end
	end
	if Player.extra then
		propheticExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			propheticInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			propheticInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		propheticInterruptPanel.icon:SetShown(Player.interrupt)
		propheticInterruptPanel.border:SetShown(Player.interrupt)
		propheticInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and propheticPreviousPanel.ability then
		if (Player.time - propheticPreviousPanel.ability.last_used) > 10 then
			propheticPreviousPanel.ability = nil
			propheticPreviousPanel:Hide()
		end
	end

	propheticPanel.icon:SetShown(Player.main)
	propheticPanel.border:SetShown(Player.main)
	propheticCooldownPanel:SetShown(Player.cd)
	propheticExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Prophetic
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_Prophetic1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			log('[|cFFFFD000Warning|r]', ADDON, 'is not designed for players under level 10, and almost certainly will not operate properly!')
		end
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ABSORBED' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	local uid = ToUID(dstGUID)
	if not uid or Target.Dummies[uid] then
		return
	end
	TrackedAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
	local pet = SummonedPets.byUnitId[uid]
	if pet then
		pet:RemoveUnit(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL_SUMMON = function(event, srcGUID, dstGUID)
	if srcGUID ~= Player.guid then
		return
	end
	local uid = ToUID(dstGUID)
	if not uid then
		return
	end
	local pet = SummonedPets.byUnitId[uid]
	if pet then
		pet:AddUnit(dstGUID)
	end
end

--local UnknownSpell = {}

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		local uid = ToUID(srcGUID)
		if uid then
			local pet = SummonedPets.byUnitId[uid]
			if pet then
				local unit = pet.active_units[srcGUID]
				if unit then
					if event == 'SPELL_CAST_SUCCESS' and pet.CastSuccess then
						pet:CastSuccess(unit, spellId, dstGUID)
					elseif event == 'SPELL_CAST_START' and pet.CastStart then
						pet:CastStart(unit, spellId, dstGUID)
					elseif event == 'SPELL_CAST_FAILED' and pet.CastFailed then
						pet:CastFailed(unit, spellId, dstGUID, missType)
					elseif (event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH') and pet.CastLanded then
						pet:CastLanded(unit, spellId, dstGUID, event, missType)
					end
					--log(format('%.3f PET %d EVENT %s SPELL %s ID %d', Player.time, pet.unitId, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
				end
			end
		end
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
--[[
		if not UnknownSpell[event] then
			UnknownSpell[event] = {}
		end
		if not UnknownSpell[event][spellId] then
			UnknownSpell[event][spellId] = true
			log(format('%.3f EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d FROM %s ON %s', Player.time, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0, srcGUID, dstGUID))
		end
]]
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth(unitId)
		Player.health.max = UnitHealthMax(unitId)
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitEffectiveLevel(unitId)
		Player.mana.base = Player.BaseMana[Player.level]
		Player.mana.max = UnitPowerMax(unitId, 0)
		Player.insanity.max = UnitPowerMax(unitId, 13)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		propheticPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
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
	for _, i in next, InventoryItems.all do
		i.name, _, _, _, _, _, _, _, equipType, i.icon = GetItemInfo(i.itemId or 0)
		i.can_use = i.name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, i.equip_slot = Player:Equipped(i.itemId)
			if i.equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', i.equip_slot)
			end
			i.can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[i.itemId] then
			i.can_use = false
		end
	end

	Player.set_bonus.t33 = (Player:Equipped(212081) and 1 or 0) + (Player:Equipped(212082) and 1 or 0) + (Player:Equipped(212083) and 1 or 0) + (Player:Equipped(212084) and 1 or 0) + (Player:Equipped(212086) and 1 or 0)

	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	propheticPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	Events:UNIT_MAXPOWER('player')
	Events:UPDATE_BINDINGS()
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, cooldown, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			cooldown = {
				startTime = castStart / 1000,
				duration = (castEnd - castStart) / 1000
			}
		else
			cooldown = GetSpellCooldown(61304)
		end
		propheticPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED(slot)
	for _, button in next, Buttons.all do
		if not slot or button.action_id == slot then
			button:UpdateAction()
		end
	end
	UI:UpdateBindings()
	UI:UpdateGlows()
end

function Events:ACTIONBAR_PAGE_CHANGED()
	C_Timer.After(0, function()
		Events:ACTIONBAR_SLOT_CHANGED(0)
	end)
end
Events.UPDATE_BONUS_ACTIONBAR = Events.ACTIONBAR_PAGE_CHANGED

function Events:UPDATE_BINDINGS()
	UI:UpdateBindings()
end
Events.GAME_PAD_ACTIVE_CHANGED = Events.UPDATE_BINDINGS

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
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
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

propheticPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	propheticPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
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
	log(desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				UI:Reset()
			end
			UI:UpdateDraggable()
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
				for _, button in next, Buttons.all do
					button:UpdateGlowDisplay()
				end
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
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
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				for _, button in next, Buttons.all do
					button:UpdateGlowDisplay()
				end
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
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
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'key') or startsWith(msg[1], 'bind') then
		if msg[2] then
			Opt.keybinds = msg[2] == 'on'
		end
		return Status('Show keybinding text on main ability icon (topright)', Opt.keybinds)
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
	if startsWith(msg[1], 'hide') or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'd') then
				Opt.hide.discipline = not Opt.hide.discipline
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Discipline specialization', not Opt.hide.discipline)
			end
			if startsWith(msg[2], 'h') then
				Opt.hide.holy = not Opt.hide.holy
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Holy specialization', not Opt.hide.holy)
			end
			if startsWith(msg[2], 's') then
				Opt.hide.shadow = not Opt.hide.shadow
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Shadow specialization', not Opt.hide.shadow)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000discipline|r/|cFFFFD000holy|r/|cFFFFD000shadow|r')
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
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 10
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
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
	if startsWith(msg[1], 'he') then
		if msg[2] then
			Opt.heal = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend self healing spells', Opt.heal .. '%')
	end
	if startsWith(msg[1], 'fi') then
		if msg[2] then
			Opt.fiend = msg[2] == 'on'
		end
		return Status('Show Shadowfiend/Mindbender/Voidwraith remaining time (bottomleft)', Opt.fiend)
	end
	if msg[1] == 'reset' then
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. C_AddOns.GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'keybind |cFF00C000on|r/|cFFC00000off|r - show keybinding text on main ability icon (topright)',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000discipline|r/|cFFFFD000holy|r/|cFFFFD000shadow|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'heal |cFFFFD000[percent]|r - health percentage threshold to recommend self healing spells (default is 60%, 0 to disable)',
		'fiend |cFF00C000on|r/|cFFC00000off|r - show Shadowfiend/Mindbender/Voidwraith remaining time (bottomleft)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Prophetic1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
