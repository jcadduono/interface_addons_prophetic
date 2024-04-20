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
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetShapeshiftForm = _G.GetShapeshiftForm
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAura = _G.UnitAura
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
	glows = {},
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
	trackAuras = {},
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

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

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
		regen = 0,
	},
	insanity = {
		current = 0,
		max = 100,
		drain = 0,
		generation = 0,
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
		t29 = 0, -- Draconic Hierophant's Finery
		t30 = 0, -- The Furnace Seraph's Verdict
		t31 = 0, -- Blessings of Lunar Communion
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

-- current pet information (used only to store summoned pets for priests)
local Pet = {}

-- current target information
local Target = {
	boss = false,
	guid = 0,
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

-- base mana pool max for each level
local BaseMana = {
	260,	270,	285,	300,	310,	--  5
	330,	345,	360,	380,	400,	-- 10
	430,	465,	505,	550,	595,	-- 15
	645,	700,	760,	825,	890,	-- 20
	965,	1050,	1135,	1230,	1335,	-- 25
	1445,	1570,	1700,	1845,	2000,	-- 30
	2165,	2345,	2545,	2755,	2990,	-- 35
	3240,	3510,	3805,	4125,	4470,	-- 40
	4845,	5250,	5690,	6170,	6685,	-- 45
	7245,	7855,	8510,	9225,	10000,	-- 50
	11745,	13795,	16205,	19035,	22360,	-- 55
	26265,	30850,	36235,	42565,	50000,	-- 60
	58730,	68985,	81030,	95180,	111800,	-- 65
	131325,	154255,	181190,	212830,	250000,	-- 70
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
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
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

function Ability:Usable(seconds, pool)
	if not self.known then
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
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
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
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	local remains = duration - (Player.ctime - start)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and count or 0
		end
	end
	return 0
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

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + (self.off_gcd and 0 or Player.execute_remains))) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - (self.off_gcd and 0 or Player.execute_remains))
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
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return 0
	end
	return castTime / 1000
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
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
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

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, Abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, Abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
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

function Ability:RefreshAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	return aura
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
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
/dump GetMouseFocus():GetNodeID()
]]

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
HolyNova.equilibrium = 'holy'
HolyNova:AutoAoe(true)
local LeapOfFaith = Ability:Add(73325, true, true)
LeapOfFaith.buff_duration = 1
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
local PowerInfusion = Ability:Add(10060, true)
PowerInfusion.buff_duration = 20
PowerInfusion.cooldown_duration = 120
local PowerWordFortitude = Ability:Add(21562, true, false)
PowerWordFortitude.mana_cost = 4
PowerWordFortitude.buff_duration = 3600
local Purify = Ability:Add(527, true, true)
Purify.mana_cost = 1.3
Purify.cooldown_duration = 8
local Shadowfiend = Ability:Add(34433, false, true)
Shadowfiend.cooldown_duration = 180
local ShadowWordPain = Ability:Add(589, false, true)
ShadowWordPain.mana_cost = 0.3
ShadowWordPain.buff_duration = 16
ShadowWordPain.tick_interval = 2
ShadowWordPain.hasted_ticks = true
ShadowWordPain.insanity_gain = 4
ShadowWordPain.equilibrium = 'shadow'
ShadowWordPain:AutoAoe(false, 'apply')
ShadowWordPain:TrackAuras()
local Smite = Ability:Add(585, false, true, 208772)
Smite.mana_cost = 0.2
Smite.equilibrium = 'holy'
------ Talents
local DivineStar = Ability:Add(110744, false, true, 122128)
DivineStar.mana_cost = 2
DivineStar.cooldown_duration = 15
DivineStar.equilibrium = 'holy'
DivineStar:AutoAoe()
DivineStar.Shadow = Ability:Add(122121, false, true, 390845)
DivineStar.Shadow.mana_cost = 2
DivineStar.Shadow.cooldown_duration = 15
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
Halo.Shadow.equilibrium = 'shadow'
Halo.Shadow:AutoAoe()
local Mindgames = Ability:Add(375901, false, true)
Mindgames.buff_duration = 5
Mindgames.cooldown_duration = 45
Mindgames.equilibrium = 'shadow'
local PowerWordLife = Ability:Add(373481, true, true)
PowerWordLife.mana_cost = 0.5
PowerWordLife.cooldown_duration = 30
local Rhapsody = Ability:Add(390622, true, true, 390636)
local VampiricEmbrace = Ability:Add(15286, true, true)
VampiricEmbrace.buff_duration = 15
VampiricEmbrace.cooldown_duration = 120
------ Procs

------ Tier Bonuses

---- Discipline
local Atonement = Ability:Add(81749, true, true, 194384)
Atonement.buff_duration = 15
local PainSuppression = Ability:Add(33206, true, true)
PainSuppression.mana_cost = 1.6
PainSuppression.buff_duration = 8
PainSuppression.cooldown_duration = 180
local Penance = Ability:Add(47540, false, true, 47666)
Penance.mana_cost = 1.6
Penance.buff_duration = 2
Penance.cooldown_duration = 9
Penance.hasted_duration = true
Penance.channel_fully = true
Penance.equilibrium = 'holy'
local DarkReprimand = Ability:Add(400169, false, true, 373130)
DarkReprimand.mana_cost = 1.6
DarkReprimand.buff_duration = 2
DarkReprimand.cooldown_duration = 9
DarkReprimand.hasted_duration = true
DarkReprimand.channel_fully = true
DarkReprimand.equilibrium = 'shadow'
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
Rapture.mana_cost = 3.1
Rapture.buff_duration = 8
Rapture.cooldown_duration = 90
------ Talents
local Expiation = Ability:Add(390832, true, true)
Expiation.talent_node = 82585
local InescapableTorment = Ability:Add(373427, false, true, 373442)
InescapableTorment:AutoAoe()
local MindbenderDisc = Ability:Add(123040, false, true)
MindbenderDisc.buff_duration = 12
MindbenderDisc.cooldown_duration = 60
local PurgeTheWicked = Ability:Add(204197, false, true, 204213)
PurgeTheWicked.buff_duration = 20
PurgeTheWicked.mana_cost = 1.8
PurgeTheWicked.tick_interval = 2
PurgeTheWicked.hasted_ticks = true
PurgeTheWicked.equilibrium = 'holy'
PurgeTheWicked:AutoAoe(false, 'apply')
local Schism = Ability:Add(424509, false, true, 214621)
Schism.buff_duration = 9
local ShadowCovenant = Ability:Add(314867, true, true, 322105)
ShadowCovenant.buff_duration = 12
local TrainOfThought = Ability:Add(390693, false, true)
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
local HolyWordChastise = Ability:Add(88625, false, true)
HolyWordChastise.cooldown_duration = 60
HolyWordChastise.mana_cost = 2
local Renew = Ability:Add(139, true, true)
Renew.mana_cost = 1.8
Renew.buff_duration = 15
Renew.tick_interval = 3
Renew.hasted_ticks = true
------ Talents

------ Procs

------ Tier Bonuses

---- Shadow
local DevouringPlague = Ability:Add(335467, false, true)
DevouringPlague.buff_duration = 6
DevouringPlague.tick_interval = 3
DevouringPlague.hasted_ticks = true
DevouringPlague.insanity_cost = 50
DevouringPlague:TrackAuras()
local Dispersion = Ability:Add(47585, true, true)
Dispersion.buff_duration = 6
Dispersion.cooldown_duration = 120
local MindBlast = Ability:Add(8092, false, true)
MindBlast.mana_cost = 0.25
MindBlast.cooldown_duration = 7.5
MindBlast.insanity_gain = 9
MindBlast.hasted_cooldown = true
MindBlast.requires_charge = true
MindBlast.equilibrium = 'shadow'
local MindFlay = Ability:Add(15407, false, true)
MindFlay.buff_duration = 4.5
MindFlay.tick_interval = 0.75
MindFlay.hasted_duration = true
MindFlay.hasted_ticks = true
local MindSear = Ability:Add(48045, false, true)
MindSear.buff_duration = 4.5
MindSear.tick_interval = 0.75
MindSear.hasted_duration = true
MindSear.hasted_ticks = true
MindSear.damage = Ability:Add(49821, false, true)
MindSear.damage:AutoAoe(true)
local Shadowform = Ability:Add(232698, true, true)
local ShadowWordDeath = Ability:Add(32379, false, true)
ShadowWordDeath.mana_cost = 0.5
ShadowWordDeath.cooldown_duration = 20
ShadowWordDeath.hasted_cooldown = true
ShadowWordDeath.equilibrium = 'shadow'
local Silence = Ability:Add(15487, false, true)
Silence.cooldown_duration = 45
Silence.buff_duration = 4
local VampiricTouch = Ability:Add(34914, false, true)
VampiricTouch.buff_duration = 21
VampiricTouch.tick_interval = 3
VampiricTouch.hasted_ticks = true
VampiricTouch.insanity_gain = 5
VampiricTouch:TrackAuras()
VampiricTouch:AutoAoe(false, 'apply')
local VoidBolt = Ability:Add(205448, false, true)
VoidBolt.cooldown_duration = 4.5
VoidBolt.insanity_gain = 12
VoidBolt.hasted_cooldown = true
local VoidEruption = Ability:Add(228260, false, true, 228360)
VoidEruption.cooldown_duration = 90
VoidEruption:AutoAoe(true)
local Voidform = Ability:Add(194249, true, true)
Voidform.buff_duration = 15
------ Talents
local Damnation = Ability:Add(341374, false, true)
Damnation.cooldown_duration = 45
local HungeringVoid = Ability:Add(345218, false, true, 345219)
HungeringVoid.buff_duration = 6
local MindbenderShadow = Ability:Add(200174, false, true)
MindbenderShadow.buff_duration = 15
MindbenderShadow.cooldown_duration = 60
local MindDevourer = Ability:Add(373202, true, true, 373204)
MindDevourer.buff_duration = 15
local Misery = Ability:Add(238558, false, true)
local PsychicLink = Ability:Add(199484, false, true, 199486)
local ShadowCrash = Ability:Add(205385, false, true, 205386)
ShadowCrash.cooldown_duration = 30
ShadowCrash.insanity_gain = 15
ShadowCrash.hasted_cooldown = true
ShadowCrash:AutoAoe()
local SurrenderToMadness = Ability:Add(193223, false, true)
SurrenderToMadness.buff_duration = 30
SurrenderToMadness.cooldown_duration = 90
local UnfurlingDarkness = Ability:Add(341273, true, true, 341282)
UnfurlingDarkness.buff_duration = 8
local VoidTorrent = Ability:Add(263165, true, true)
VoidTorrent.buff_duration = 3
VoidTorrent.cooldown_duration = 30
------ Procs
local DarkThought = Ability:Add(341205, true, true, 341207)
DarkThought.buff_duration = 10
-- Tier set bonuses

-- Racials

-- PvP talents

-- Trinket Effects
local SolarMaelstrom = Ability:Add(422146, false, true) -- Belor'relos
SolarMaelstrom:AutoAoe()
-- Class cooldowns

-- End Abilities

-- Start Summoned Pets

function SummonedPets:Find(guid)
	local unitId = guid:match('^Creature%-0%-%d+%-%d+%-%d+%-(%d+)')
	return unitId and self.byUnitId[tonumber(unitId)]
end

function SummonedPets:Purge()
	local _, pet, guid, unit
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
		pet.known = pet.summon_spell and pet.summon_spell.known
		if pet.known then
			self.known[#SummonedPets.known + 1] = pet
			self.byUnitId[pet.unitId] = pet
		end
	end
end

function SummonedPets:Count()
	local _, pet, guid, unit
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:Count()
	end
	return count
end

function SummonedPet:Add(unitId, duration, summonSpell)
	local pet = {
		unitId = unitId,
		duration = duration,
		active_units = {},
		summon_spell = summonSpell,
		known = false,
	}
	setmetatable(pet, self)
	SummonedPets.all[#SummonedPets.all + 1] = pet
	return pet
end

function SummonedPet:Remains(initial)
	local expires_max, guid, unit = 0
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
	local count, guid, unit = 0
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time > Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:Expiring(seconds)
	local count, guid, unit = 0
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
		expires = Player.time + self.duration,
	}
	self.active_units[guid] = unit
	return unit
end

function SummonedPet:RemoveUnit(guid)
	if self.active_units[guid] then
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

-- Summoned Pets
Pet.Lightspawn = SummonedPet:Add(128140, 15, Lightspawn)
Pet.Shadowfiend = SummonedPet:Add(19668, 15, Shadowfiend)
Pet.Mindbender = SummonedPet:Add(62982)

-- End Summoned Pets

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
		off_gcd = true,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
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
Trinket.BelorrelosTheSuncaller = InventoryItem:Add(207172)
Trinket.BelorrelosTheSuncaller.cast_spell = SolarMaelstrom
Trinket.BelorrelosTheSuncaller.cooldown_duration = 120
Trinket.BelorrelosTheSuncaller.off_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.trackAuras)
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
				self.trackAuras[#self.trackAuras + 1] = ability
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
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 381301 or -- Feral Hide Drums (Leatherworking)
			id == 390386    -- Fury of the Aspects (Evoker)
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
	self.mana.base = BaseMana[self.level]
	self.mana.max = UnitPowerMax('player', 0)
	self.insanity.max = UnitPowerMax('player', 13)

	local node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
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
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsUsableSpell(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	self.swp = ShadowWordPain
	if PurgeTheWicked.known then
		ShadowWordPain.known = false
		self.swp = PurgeTheWicked
	end
	self.fiend = Shadowfiend
	if MindbenderDisc.known then
		self.fiend = MindbenderDisc
		Pet.Mindbender.duration = self.fiend.buff_duration
		Pet.Mindbender.summon_spell = self.fiend
	elseif MindbenderShadow.known then
		self.fiend = MindbenderShadow
		Pet.Mindbender.duration = self.fiend.buff_duration
		Pet.Mindbender.summon_spell = self.fiend
	elseif Lightspawn.known then
		self.fiend = Lightspawn
	end
	Shadowfiend.known = Shadowfiend.known and self.fiend == Shadowfiend
	if ShadowCovenant.known then
		DivineStar.Shadow.known = DivineStar.known
		Halo.Shadow.known = Halo.known
		DarkReprimand.known = Penance.known
	end
	MindSear.damage.known = MindSear.known
	Voidform.known = VoidEruption.known
	VoidBolt.known = VoidEruption.known
	SolarMaelstrom.known = Trinket.BelorrelosTheSuncaller:Equipped()

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
	if ability and ability == channel.ability then
		channel.chained = true
	else
		channel.ability = ability
	end
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
	local _, start, ends, duration, spellId, speed, max_speed
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
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
	if self.cast.ability then
		self.mana.current = self.mana.current - self.cast.ability:ManaCost()
	end
	self.mana.current = clamp(self.mana.current, 0, self.mana.max)
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
	end
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

	SummonedPets:Purge()
	trackAuras:Purge()
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
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	propheticPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
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
	self.timeToDieMax = self.health.current / Player.health.max * (Player.spec == SPEC.SHADOW and 10 or 20)
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
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
		self:UpdateHealth(true)
	end
	self.boss = false
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

function Penance:Cooldown()
	local remains = Ability.Cooldown(self)
	if TrainOfThought.known and Smite:Casting() then
		remains = remains - 0.5
	end
	return max(0, remains)
end
DarkReprimand.Cooldown = Penance.Cooldown

function Penance:Usable()
	if ShadowCovenant.known and ShadowCovenant:Up() then
		return false
	end
	return Ability.Usable(self)
end
DivineStar.Usable = Penance.Usable
Halo.Usable = Penance.Usable

function DarkReprimand:Usable()
	return ShadowCovenant.known and Ability.Usable(self) and ShadowCovenant:Up() and ShadowCovenant:Remains() >= self:CastTime()
end
DivineStar.Shadow.Usable = DarkReprimand.Usable
Halo.Shadow.Usable = DarkReprimand.Usable

function VoidBolt:Usable(...)
	return Voidform:Up() and Ability.Usable(self, ...)
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

function ShadowWordPain:Remains()
	if Misery.known and VampiricTouch:Casting() then
		return self:Duration()
	end
	local remains = Ability.Remains(self)
	if Expiation.known and MindBlast:Casting() then
		remains = remains - (3 * Expiation.rank)
	end
	return max(0, remains)
end
PurgeTheWicked.Remains = ShadowWordPain.Remains

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
	return Pet.Mindbender:Remains()
end
MindbenderShadow.Remains = MindbenderDisc.Remains

function MindbenderDisc:Cooldown()
	local remains = Ability.Cooldown(self)
	if VoidSummoner.known and (Smite:Casting() or MindBlast:Casting()) then
		remains = remains - 2
	end
	return max(0, remains)
end

function DevouringPlague:InsanityCost()
	if MindDevourer.known and MindDevourer:Up() then
		return 0
	end
	return Ability.InsanityCost(self)
end

function MindBlast:CastWhileChanneling()
	return (MindFlay:Channeling() or MindSear:Channeling()) and DarkThought:Up()
end

function MindBlast:Free()
	return DarkThought:Up()
end

function MindBlast:CastLanded(...)
	if InescapableTorment.known then
		Pet.Mindbender:ExtendAll(1.0)
	end
	Ability.CastLanded(self, ...)
end

function ShadowWordDeath:CastLanded(...)
	if InescapableTorment.known then
		Pet.Mindbender:ExtendAll(1.0)
	end
	Ability.CastLanded(self, ...)
end

function Penance:CastSuccess(...)
	if InescapableTorment.known then
		Pet.Mindbender:ExtendAll(1.0)
	end
	Ability.CastSuccess(self, ...)
end
DarkReprimand.CastSuccess = Penance.CastSuccess

function TwilightEquilibrium.Holy:Remains()
	if Player.cast.ability then
		if Player.cast.ability.equilibrium == 'holy' then
			return 0
		elseif Player.cast.ability.equilibrium == 'shadow' then
			return self:Duration()
		end
	end
	return Ability.Remains(self)
end

function TwilightEquilibrium.Shadow:Remains()
	if Player.cast.ability then
		if Player.cast.ability.equilibrium == 'shadow' then
			return 0
		elseif Player.cast.ability.equilibrium == 'holy' then
			return self:Duration()
		end
	end
	return Ability.Remains(self)
end

-- End Ability Modifications

-- Start Summoned Pet Modifications

function Pet.Mindbender:CastLanded(unit, spellId, dstGUID, event, missType)
	if Opt.auto_aoe and InescapableTorment:Match(spellId) then
		InescapableTorment:RecordTargetHit(dstGUID, event, missType)
	end
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
	self.hold_penance = self.use_cds and InescapableTorment.known and not Player.fiend_up and Player.fiend:Ready((6 - (TrainOfThought.known and 3 or 0) - (TwilightEquilibrium.known and 2 or 0)) * Player.haste_factor)
	if Player.health.pct < 35 and PowerWordLife:Usable() then
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
	if InescapableTorment.known and Player.fiend_up and Player.fiend_remains < (3 * Player.gcd) then
		local apl = self:torment()
		if apl then return apl end
	end
	if Player.swp:Usable() and Player.swp:Down() and (Target.timeToDie > (Player.swp:TickTime() * 2) or (PurgeTheWicked.known and Penance:Ready(Target.timeToDie))) then
		return Player.swp
	end
	if self.use_cds then
		if Opt.trinket then
			if Trinket.BelorrelosTheSuncaller:Usable() and Player.fiend_remains == 0 then
				UseCooldown(Trinket.BelorrelosTheSuncaller)
			end
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
	local apl
	if TwilightEquilibrium.known then
		if TwilightEquilibrium.Holy:Up() then
			apl = self:te_holy()
			if apl then return apl end
		elseif TwilightEquilibrium.Shadow:Up() then
			apl = self:te_shadow()
			if apl then return apl end
		end
	else
		apl = self:standard()
		if apl then return apl end
	end
	return self:filler()
end

APL[SPEC.DISCIPLINE].standard = function(self)
	if InescapableTorment.known and Player.fiend_up then
		local apl = self:torment()
		if apl then return apl end
	end
	if Penance:Usable() and not self.hold_penance then
		return Penance
	end
	if DarkReprimand:Usable() and not self.hold_penance then
		return DarkReprimand
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
	if Rhapsody.known and HolyNova:Usable() and Player.enemies >= 3 and Rhapsody:Stack() >= (20 - Player.enemies) then
		UseCooldown(HolyNova)
	end
	if Player.swp:Usable() and Schism.known and MindBlast:Ready(Player.gcd * 2) and Player.swp:Remains() < 10 and Target.timeToDie > (Player.swp:Remains() + (Player.swp:TickTime() * 3)) then
		return Player.swp
	end
	if self.use_cds and Player.fiend:Usable() and (not InescapableTorment.known or MindBlast:Ready(Player.gcd) or ShadowWordDeath:Ready(Player.gcd)) then
		UseCooldown(Player.fiend)
	end
	if Player.swp:Usable() and Player.swp:Refreshable() and Target.timeToDie > (Player.swp:Remains() + (Player.swp:TickTime() * 3)) then
		return Player.swp
	end
	if ShadowWordDeath:Usable() and Target.health.pct < 20 and (not InescapableTorment.known or Player.fiend_up or Target.timeToDie < (Player.fiend:Cooldown() / 2) or not Player.fiend:Ready(14 * Player.haste_factor)) then
		return ShadowWordDeath
	end
	if ShadowWordDeath:Usable() and Target:TimeToPct(20) > 10 and (not InescapableTorment.known or Player.fiend_up or not Player.fiend:Ready(14 * Player.haste_factor)) then
		return ShadowWordDeath
	end
	if Mindgames:Usable() and Target.timeToDie > 6 and (not ShadowCovenant.known or not Player.fiend:Ready(Player.gcd * 4)) then
		UseCooldown(Mindgames)
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
end

APL[SPEC.DISCIPLINE].filler = function(self)
	if Player.swp:Usable() and Player.swp:Refreshable() and Target.timeToDie > (Player.swp:Remains() + (Player.swp:TickTime() * 3)) then
		return Player.swp
	end
	if MindBlast:Usable() and (not InescapableTorment.known or Player.fiend_up or not Player.fiend:Ready(12 * Player.haste_factor)) then
		return MindBlast
	end
	if HolyNova:Usable() and not (TwilightEquilibrium.known and Rhapsody.known) and ((Player.enemies >= 3 and not VoidSummoner.known) or (Rhapsody.known and Rhapsody:Stack() >= (20 - Player.enemies))) then
		UseCooldown(HolyNova)
	end
	if Penance:Usable() and not self.hold_penance then
		return Penance
	end
	if Smite:Usable() then
		return Smite
	end
	if HolyNova:Usable() and not (TwilightEquilibrium.known and Rhapsody.known) then
		UseCooldown(HolyNova)
	end
	if Player.swp:Usable() then
		return Player.swp
	end
end

APL[SPEC.DISCIPLINE].te_holy = function(self)
	if Penance:Usable() and not self.hold_penance then
		return Penance
	end
	if DivineStar:Usable() and Player.enemies >= 3 then
		UseCooldown(DivineStar)
	end
	if Rhapsody.known and HolyNova:Usable() and Player.enemies >= 3 and Rhapsody:Stack() >= (20 - Player.enemies) then
		UseCooldown(HolyNova)
	end
	if PurgeTheWicked:Usable() and Schism.known and MindBlast:Ready(Player.gcd * 2) and PurgeTheWicked:Remains() < 10 and Target.timeToDie > (PurgeTheWicked:Remains() + (PurgeTheWicked:TickTime() * 3)) then
		return PurgeTheWicked
	end
	if DivineStar:Usable() then
		UseCooldown(DivineStar)
	end
	if Halo:Usable() then
		UseCooldown(Halo)
	end
	if PurgeTheWicked:Usable() and PurgeTheWicked:Refreshable() and Target.timeToDie > (PurgeTheWicked:Remains() + (PurgeTheWicked:TickTime() * 3)) then
		return PurgeTheWicked
	end
	if HolyNova:Usable() and ((Player.enemies >= 3 and not VoidSummoner.known) or (Rhapsody.known and Rhapsody:Stack() >= (20 - Player.enemies))) then
		UseCooldown(HolyNova)
	end
	if Smite:Usable() then
		return Smite
	end
end

APL[SPEC.DISCIPLINE].te_shadow = function(self)
	if InescapableTorment.known and Player.fiend_up then
		local apl = self:torment()
		if apl then return apl end
	end
	if DarkReprimand:Usable() and not self.hold_penance then
		return DarkReprimand
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
	if ShadowWordDeath:Usable() and Target.health.pct < 20 and (not InescapableTorment.known or Player.fiend_up or Target.timeToDie < (Player.fiend:Cooldown() / 2) or not Player.fiend:Ready(14 * Player.haste_factor)) then
		return ShadowWordDeath
	end
	if ShadowWordDeath:Usable() and Target:TimeToPct(20) > 10 and (not InescapableTorment.known or Player.fiend_up or not Player.fiend:Ready(14 * Player.haste_factor)) then
		return ShadowWordDeath
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
	if Mindgames:Usable() and Target.timeToDie > 6 and (not Player.fiend_up or not (DarkReprimand:Ready(Player.gcd * 2) or ShadowWordDeath:Ready(Player.gcd * 2) or MindBlast:Ready(Player.gcd * 2))) then
		UseCooldown(Mindgames)
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
	if Schism.known and MindBlast:Usable() and Schism:Down() and Player.fiend_remains > MindBlast:CastTime()  then
		return MindBlast
	end
	if ShadowWordDeath:Usable() and (
		Target.health.pct < 20 or
		Target:TimeToPct(20) > (Player.fiend_remains - Player.gcd)
	) then
		return ShadowWordDeath
	end
	if MindBlast:Usable() and Player.fiend_remains > MindBlast:CastTime() then
		return MindBlast
	end
	if DarkReprimand:Usable() then
		return DarkReprimand
	end
	if Penance:Usable() then
		return Penance
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
	if Player.health.pct < 35 and PowerWordLife:Usable() then
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
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/snapshot_stats
actions.precombat+=/shadowform,if=!buff.shadowform.up
actions.precombat+=/arcane_torrent
actions.precombat+=/variable,name=mind_sear_cutoff,op=set,value=2
actions.precombat+=/vampiric_touch,if=!talent.damnation.enabled
actions.precombat+=/mind_blast,if=talent.damnation.enabled
]]
		if PowerWordFortitude:Usable() and PowerWordFortitude:Remains() < 300 then
			return PowerWordFortitude
		end
		if Shadowform:Usable() and Shadowform:Down() then
			return Shadowform
		end
		if VampiricTouch:Usable() and VampiricTouch:Down() and not Damnation.known then
			return VampiricTouch
		end
		if MindBlast:Usable() and Damnation.known then
			return MindBlast
		end
	else
		if PowerWordFortitude:Down() and PowerWordFortitude:Usable() then
			UseExtra(PowerWordFortitude)
		end
	end
	if Player.health.pct < 35 and PowerWordLife:Usable() then
		UseExtra(PowerWordLife)
	elseif Player.health.pct < 35 and DesperatePrayer:Usable() then
		UseExtra(DesperatePrayer)
	elseif (Player.health.pct < Opt.heal or Atonement:Remains() < Player.gcd) and PowerWordShield:Usable() then
		UseExtra(PowerWordShield)
	elseif self.use_cds and Player.health.pct < Opt.heal and VampiricEmbrace:Usable() then
		UseExtra(VampiricEmbrace)
	end
--[[
actions=potion,if=buff.power_infusion.up&(buff.bloodlust.up|(time+fight_remains)>=320)
actions+=/antumbra_swap,if=buff.singularity_supreme_lockout.up&!buff.power_infusion.up&!buff.voidform.up&!pet.fiend.active&!buff.singularity_supreme.up&!buff.swap_stat_compensation.up&!buff.bloodlust.up&!((fight_remains+time)>=330&time<=200|(fight_remains+time)<=250&(fight_remains+time)>=200)
actions+=/antumbra_swap,if=buff.swap_stat_compensation.up&!buff.singularity_supreme_lockout.up&(cooldown.power_infusion.remains<=30&cooldown.void_eruption.remains<=30&!((time>80&time<100)&((fight_remains+time)>=330&time<=200|(fight_remains+time)<=250&(fight_remains+time)>=200))|fight_remains<=40)
actions+=/variable,name=dots_up,op=set,value=dot.shadow_word_pain.ticking&dot.vampiric_touch.ticking
actions+=/variable,name=all_dots_up,op=set,value=dot.shadow_word_pain.ticking&dot.vampiric_touch.ticking&dot.devouring_plague.ticking
actions+=/variable,name=five_minutes_viable,op=set,value=(fight_remains+time)>=60*5+20
actions+=/variable,name=four_minutes_viable,op=set,value=!variable.five_minutes_viable&(fight_remains+time)>=60*4+20
actions+=/variable,name=do_three_mins,op=set,value=(variable.five_minutes_viable|!variable.five_minutes_viable&!variable.four_minutes_viable)&time<=200
actions+=/variable,name=cd_management,op=set,value=variable.do_three_mins|(variable.four_minutes_viable&cooldown.power_infusion.remains<=gcd.max*3|variable.five_minutes_viable&time>300)|fight_remains<=25,default=0
actions+=/variable,name=max_vts,op=set,default=1,value=spell_targets.vampiric_touch
actions+=/variable,name=max_vts,op=set,value=(spell_targets.mind_sear<=5)*spell_targets.mind_sear,if=buff.voidform.up
actions+=/variable,name=is_vt_possible,op=set,value=0,default=1
actions+=/variable,name=is_vt_possible,op=set,value=1,target_if=max:(target.time_to_die*dot.vampiric_touch.refreshable),if=target.time_to_die>=18
actions+=/variable,name=vts_applied,op=set,value=active_dot.vampiric_touch>=variable.max_vts|!variable.is_vt_possible
actions+=/variable,name=pool_for_cds,op=set,value=cooldown.void_eruption.up&variable.cd_management
actions+=/variable,name=on_use_trinket,value=equipped.shadowed_orb_of_torment+equipped.moonlit_prism+equipped.neural_synapse_enhancer+equipped.fleshrenders_meathook+equipped.scars_of_fraternal_strife+equipped.the_first_sigil+equipped.soulletting_ruby+equipped.inscrutable_quantum_device
actions+=/blood_fury,if=buff.power_infusion.up
actions+=/fireblood,if=buff.power_infusion.up
actions+=/berserking,if=buff.power_infusion.up
actions+=/lights_judgment,if=spell_targets.lights_judgment>=2|(!raid_event.adds.exists|raid_event.adds.in>75)
actions+=/ancestral_call,if=buff.power_infusion.up
actions+=/use_item,name=hyperthread_wristwraps,if=0
actions+=/use_item,name=ring_of_collapsing_futures,if=(buff.temptation.stack<1&target.time_to_die>60)|target.time_to_die<60
actions+=/call_action_list,name=cwc
actions+=/run_action_list,name=main
]]
	self.dots_up = ShadowWordPain:Up() and VampiricTouch:Up()
	self.all_dots_up = self.dots_up and DevouringPlague:Up()
	self.mind_sear_cutoff = 2
	self.five_minutes_viable = (Target.timeToDie + Player:TimeInCombat()) >= (60 * 5 + 20)
	self.four_minutes_viable = not self.five_minutes_viable and (Target.timeToDie + Player:TimeInCombat()) >= (60 * 4 + 20)
	self.do_three_mins = (self.five_minutes_viable or not self.four_minutes_viable) and Player:TimeInCombat() <= 200
	self.cd_management = self.do_three_mins or (self.four_minutes_viable and PowerInfusion:Ready(Player.gcd * 3)) or (self.five_minutes_viable and Player:TimeInCombat() > 300) or Target.timeToDie <= 25
	self.max_vts = Player.enemies
	if Voidform:Up() then
		self.max_vts = Player.enemies <= 5 and Player.enemies or 0
	end
	self.vts_applied = Target.timeToDie < 18 or VampiricTouch:Ticking() >= self.max_vts
	self.pool_for_cds = VoidEruption:Ready() and self.cd_management
	self.on_use_trinket = Trinket1.can_use or Trinket2.can_use
	if MindFlay:Channeling() or MindSear:Channeling() then
		local apl = self:cwc()
		if apl then return apl end
	end
	return self:main()
end

APL[SPEC.SHADOW].cds = function(self)
--[[
actions.cds=power_infusion,if=buff.voidform.up&(!variable.five_minutes_viable|time>300|time<235)|fight_remains<=25
actions.cds+=/call_action_list,name=trinkets
actions.cds+=/mindbender,if=dot.shadow_word_pain.ticking&variable.vts_applied
actions.cds+=/desperate_prayer,if=health.pct<=75
]]
	if PowerInfusion:Usable() and ((Voidform:Up() and (not self.five_minutes_viable or not between(Player:TimeInCombat(), 235, 300))) or (Target.boss and Target.timeToDie <= 25)) then
		return UseCooldown(PowerInfusion)
	end
	if MindbenderShadow:Usable() and self.vts_applied and ShadowWordPain:Up() then
		return UseCooldown(MindbenderShadow)
	end
	if Opt.trinket then
		self:trinkets()
	end
end

APL[SPEC.SHADOW].trinkets = function(self)
--[[
actions.trinkets=use_item,name=scars_of_fraternal_strife,if=!buff.scars_of_fraternal_strife_4.up
actions.trinkets+=/use_item,name=empyreal_ordnance,if=cooldown.void_eruption.remains<=12|cooldown.void_eruption.remains>27
actions.trinkets+=/use_item,name=inscrutable_quantum_device,if=buff.voidform.up&buff.power_infusion.up|fight_remains<=20|buff.power_infusion.up&cooldown.void_eruption.remains+15>fight_remains|buff.voidform.up&cooldown.power_infusion.remains+15>fight_remains|(cooldown.power_infusion.remains>=10&cooldown.void_eruption.remains>=10)&fight_remains>=190
actions.trinkets+=/use_item,name=macabre_sheet_music,if=cooldown.void_eruption.remains>10
actions.trinkets+=/use_item,name=soulletting_ruby,if=buff.power_infusion.up|!priest.self_power_infusion|equipped.shadowed_orb_of_torment,target_if=min:target.health.pct
actions.trinkets+=/use_item,name=the_first_sigil,if=buff.voidform.up|buff.power_infusion.up|!priest.self_power_infusion|cooldown.void_eruption.remains>10|(equipped.soulletting_ruby&!trinket.soulletting_ruby.cooldown.up)|fight_remains<20
actions.trinkets+=/use_item,name=scars_of_fraternal_strife,if=buff.scars_of_fraternal_strife_4.up&((variable.on_use_trinket>=2&!equipped.shadowed_orb_of_torment)&cooldown.power_infusion.remains<=20&cooldown.void_eruption.remains<=(20-5*talent.ancient_madness)|buff.voidform.up&buff.power_infusion.up&(equipped.shadowed_orb_of_torment|variable.on_use_trinket<=1))&fight_remains<=80|fight_remains<=30
actions.trinkets+=/use_item,name=neural_synapse_enhancer,if=buff.voidform.up&buff.power_infusion.up|pet.fiend.active&cooldown.power_infusion.remains>=10*gcd.max
actions.trinkets+=/use_item,name=sinful_gladiators_badge_of_ferocity,if=cooldown.void_eruption.remains>=10
actions.trinkets+=/use_item,name=shadowed_orb_of_torment,if=cooldown.power_infusion.remains<=10&cooldown.void_eruption.remains<=10|covenant.night_fae&(!buff.voidform.up|prev_gcd.1.void_bolt)|fight_remains<=40
actions.trinkets+=/use_item,name=architects_ingenuity_core
actions.trinkets+=/use_items,if=buff.voidform.up|buff.power_infusion.up|cooldown.void_eruption.remains>10
]]
	if Trinket1:Usable() and (Voidform:Up() or PowerInfusion:Up() or not VoidEruption:Ready(10)) then
		return UseCooldown(Trinket1)
	end
	if Trinket2:Usable() and (Voidform:Up() or PowerInfusion:Up() or not VoidEruption:Ready(10)) then
		return UseCooldown(Trinket2)
	end
end

APL[SPEC.SHADOW].cwc = function(self)
--[[
actions.cwc+=/mind_blast,only_cwc=1
]]
	if MindBlast:Usable() and MindBlast:CastWhileChanneling() then
		return MindBlast
	end
end

APL[SPEC.SHADOW].main = function(self)
--[[
actions.main+=/call_action_list,name=cds
actions.main+=/damnation,target_if=(dot.vampiric_touch.refreshable|dot.shadow_word_pain.refreshable|(!buff.mind_devourer.up&insanity<50))
actions.main+=/mind_blast,if=(cooldown.mind_blast.full_recharge_time<=gcd.max*2&(debuff.hungering_void.up|!talent.hungering_void.enabled)
actions.main+=/mindgames,target_if=insanity<90&((variable.all_dots_up&(!cooldown.void_eruption.up|!variable.cd_management))|buff.voidform.up)&(!talent.hungering_void.enabled|debuff.hungering_void.remains>cast_time|!buff.voidform.up)
actions.main+=/void_bolt,if=talent.hungering_void
actions.main+=/devouring_plague,if=(refreshable|insanity>75|talent.void_torrent.enabled&cooldown.void_torrent.remains<=3*gcd&!buff.voidform.up|buff.voidform.up&(cooldown.mind_blast.charges_fractional<2|buff.mind_devourer.up))&(!variable.pool_for_cds|insanity>=85)
actions.main+=/void_bolt,if=talent.hungering_void.enabled
actions.main+=/shadow_word_death,target_if=target.health.pct<20&spell_targets.mind_sear<4)
actions.main+=/surrender_to_madness,target_if=target.time_to_die<25&buff.voidform.down
actions.main+=/void_torrent,target_if=variable.dots_up&(buff.voidform.down|buff.voidform.remains<cooldown.void_bolt.remains|prev_gcd.1.void_bolt&!buff.bloodlust.react&spell_targets.mind_sear<3)&variable.vts_applied&spell_targets.mind_sear<(5+(6*talent.twist_of_fate.enabled))
actions.main+=/shadow_crash,if=raid_event.adds.in>10
actions.main+=/mind_sear,target_if=spell_targets.mind_sear>variable.mind_sear_cutoff&buff.dark_thought.up,chain=1,interrupt_immediate=1,interrupt_if=ticks>=4
actions.main+=/mind_flay,if=buff.dark_thought.up&variable.dots_up&!buff.voidform.up&!variable.pool_for_cds&cooldown.mind_blast.full_recharge_time>=gcd.max,chain=1,interrupt_immediate=1,interrupt_if=ticks>=4&!buff.dark_thought.up
actions.main+=/void_bolt,if=variable.dots_up
actions.main+=/vampiric_touch,target_if=refreshable&target.time_to_die>=18&(dot.vampiric_touch.ticking|!variable.vts_applied)&variable.max_vts>0|(talent.misery.enabled&dot.shadow_word_pain.refreshable)|buff.unfurling_darkness.up
actions.main+=/shadow_word_pain,if=refreshable&target.time_to_die>4&!talent.misery.enabled&talent.psychic_link.enabled&spell_targets.mind_sear>2
actions.main+=/shadow_word_pain,target_if=refreshable&target.time_to_die>4&!talent.misery.enabled&(!talent.psychic_link.enabled|(talent.psychic_link.enabled&spell_targets.mind_sear<=2))
actions.main+=/mind_sear,target_if=spell_targets.mind_sear>variable.mind_sear_cutoff,chain=1,interrupt_immediate=1,interrupt_if=ticks>=2
actions.main+=/mind_flay,chain=1,interrupt_immediate=1,interrupt_if=ticks>=2&(!buff.dark_thought.up|cooldown.void_bolt.up&buff.voidform.up)
actions.main+=/shadow_word_death
actions.main+=/shadow_word_pain
]]
	self:cds()
	if Damnation:Usable() and (VampiricTouch:Refreshable() or ShadowWordPain:Refreshable() or (MindDevourer:Down() and Player.insanity.current < 50)) then
		return Damnation
	end
	if HungeringVoid.known and VoidBolt:Usable() then
		return VoidBolt
	end
	if DevouringPlague:Usable() and (
		((not self.pool_for_cds or Player.insanity.current >= 85) and (DevouringPlague:Refreshable() or Player.insanity.current > 75 or (VoidTorrent.known and VoidTorrent:Ready(Player.gcd * 3) and Voidform:Down()) or (Voidform:Up() and (MindBlast:ChargesFractional() < 2 or MindDevourer:Up()))))
	) then
		return DevouringPlague
	end
	if HungeringVoid.known and VoidBolt:Usable() then
		return VoidBolt
	end
	if ShadowWordDeath:Usable() and Target.health.pct < 20 and Player.enemies < 4 then
		return ShadowWordDeath
	end
	if SurrenderToMadness:Usable() and Target.timeToDie < 25 and Voidform:Down() then
		UseCooldown(SurrenderToMadness)
	end
	if VoidTorrent:Usable() and self.dots_up and self.vts_applied and Player.enemies < (5 + (TwistOfFate.known and 6 or 0)) and (Voidform:Down() or Voidform:Remains() < VoidBolt:Cooldown() or (VoidBolt:Previous() and not Player:BloodlustActive() and Player.enemies < 3)) then
		UseCooldown(VoidTorrent)
	end
	if ShadowCrash:Usable() then
		UseCooldown(ShadowCrash)
	end
	if MindSear:Usable() and Player.enemies > self.mind_sear_cutoff and DarkThought:Up() then
		Player.channel.interrupt_if = self.channel_interrupt[1]
		if MindSear:Remains() > 1 then
			return
		end
		return MindSear
	end
	if MindFlay:Usable() and DarkThought:Up() and self.dots_up and Voidform:Down() and not self.pool_for_cds and MindBlast:FullRechargeTime() >= Player.gcd then
		Player.channel.interrupt_if = self.channel_interrupt[2]
		if MindFlay:Remains() > 1 then
			return
		end
		return MindFlay
	end
	if MindBlast:Usable() and self.dots_up and Target.timeToDie > MindBlast:CastTime() and Player.enemies < (4 + (Misery.known and 2 or 0) + (PsychicLink.known and VampiricTouch:Ticking() or 0)) then
		return MindBlast
	end
	if VoidBolt:Usable() and self.dots_up then
		return VoidBolt
	end
	if VampiricTouch:Usable() and (
		(VampiricTouch:Refreshable() and Target.timeToDie >= 18 and (VampiricTouch:Up() or not self.vts_applied) and self.max_vts > 0) or
		(Misery.known and ShadowWordPain:Refreshable()) or UnfurlingDarkness:Up()
	) then
		return VampiricTouch
	end
	if ShadowWordPain:Usable() and not Misery.known and Target.timeToDie > 4 and ShadowWordPain:Refreshable() and (
		(PsychicLink.known and Player.enemies > 2) or
		(not PsychicLink.known or (PsychicLink.known and Player.enemies <= 2))
	) then
		return ShadowWordPain
	end
	if Player.moving then
		if ShadowWordDeath:Usable() then
			UseCooldown(ShadowWordDeath)
		end
		if ShadowWordPain:Usable() then
			UseCooldown(ShadowWordPain)
		end
	end
	if MindSear:Usable() and Player.enemies > self.mind_sear_cutoff then
		Player.channel.interrupt_if = self.channel_interrupt[3]
		if MindSear:Remains() > 1 then
			return
		end
		return MindSear
	end
	if MindFlay:Usable() then
		Player.channel.interrupt_if = self.channel_interrupt[4]
		if MindFlay:Remains() > 1 then
			return
		end
		return MindFlay
	end
	if ShadowWordDeath:Usable() then
		return ShadowWordDeath
	end
	if ShadowWordPain:Usable() then
		return ShadowWordPain
	end
end

APL[SPEC.SHADOW].channel_interrupt = {
	[1] = function() -- Mind Sear
		return Player.channel.ticks >= 4
	end,
	[2] = function() -- Mind Flay
		return Player.channel.ticks >= 4 and DarkThought:Down()
	end,
	[3] = function() -- Mind Sear
		return Player.channel.ticks >= 2
	end,
	[4] = function() -- Mind Flay
		return Player.channel.ticks >= 2 and (DarkThought:Down() or (not VoidBolt:Ready() and Voidform:Up()))
	end,
}

APL.Interrupt = function(self)
	if Silence:Usable() then
		return Silence
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
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
	self:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon
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
				glow:Show()
				if Opt.glow.animation then
					glow.ProcStartAnim:Play()
				else
					glow.ProcLoop:Play()
				end
			end
		elseif glow:IsVisible() then
			if glow.ProcStartAnim:IsPlaying() then
				glow.ProcStartAnim:Stop()
			end
			if glow.ProcLoop:IsPlaying() then
				glow.ProcLoop:Stop()
			end
			glow:Hide()
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
			['below'] = { 'TOP', 'BOTTOM', 0, -2 },
		},
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 },
		},
		[SPEC.SHADOW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 },
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
	UI:UpdateGlows()
end

function UI:Reset()
	propheticPanel:ClearAllPoints()
	propheticPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, border, text_center, text_tr, text_cd
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
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
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd = format('%.1f', react)
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
		if Player.main and Player.main.cwc then
			dim = false
		end
	end
	if Opt.fiend then
		local remains
		text_tr = ''
		for _, unit in next, Pet.Shadowfiend.active_units do
			remains = unit.expires - Player.time
			if remains > 0 then
				text_tr = format('%s%.1fs\n', text_tr, remains)
			end
		end
		for _, unit in next, Pet.Lightspawn.active_units do
			remains = unit.expires - Player.time
			if remains > 0 then
				text_tr = format('%s%.1fs\n', text_tr, remains)
			end
		end
		for _, unit in next, Pet.Mindbender.active_units do
			remains = unit.expires - Player.time
			if remains > 0 then
				text_tr = format('%s%.1fs\n', text_tr, remains)
			end
		end
	end
	if border ~= propheticPanel.border.overlay then
		propheticPanel.border.overlay = border
		propheticPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	propheticPanel.dimmer:SetShown(dim)
	propheticPanel.text.center:SetText(text_center)
	--propheticPanel.text.tl:SetText(text_tl)
	propheticPanel.text.tr:SetText(text_tr)
	--propheticPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	propheticCooldownPanel.text:SetText(text_cd)
	propheticCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		propheticPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.mana_cost > 0 and Player.main:ManaCost() == 0) or (Shadowform.known and Player.main.insanity_cost > 0 and Player.main:InsanityCost() == 0) or (Player.main.Free and Player.main.Free())
	end
	if Player.cd then
		propheticCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			propheticCooldownPanel.swipe:SetCooldown(start, duration)
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
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
	local pet = SummonedPets:Find(dstGUID)
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
	local pet = SummonedPets:Find(dstGUID)
	if pet then
		pet:AddUnit(dstGUID)
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		local pet = SummonedPets:Find(srcGUID)
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
				--log(format('PET %d EVENT %s SPELL %s ID %d', pet.unitId, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
			end
		end
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
		--log(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
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
		Player.health.current = UnitHealth('player')
		Player.health.max = UnitHealthMax('player')
		Player.health.pct = Player.health.current / Player.health.max * 100
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

	Player.set_bonus.t29 = (Player:Equipped(200324) and 1 or 0) + (Player:Equipped(200326) and 1 or 0) + (Player:Equipped(200327) and 1 or 0) + (Player:Equipped(200328) and 1 or 0) + (Player:Equipped(200329) and 1 or 0)
	Player.set_bonus.t30 = (Player:Equipped(202540) and 1 or 0) + (Player:Equipped(202541) and 1 or 0) + (Player:Equipped(202542) and 1 or 0) + (Player:Equipped(202543) and 1 or 0) + (Player:Equipped(202545) and 1 or 0)
	Player.set_bonus.t31 = (Player:Equipped(207279) and 1 or 0) + (Player:Equipped(207280) and 1 or 0) + (Player:Equipped(207281) and 1 or 0) + (Player:Equipped(207282) and 1 or 0) + (Player:Equipped(207284) and 1 or 0)

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
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		propheticPanel.swipe:SetCooldown(start, duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

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
				UI:UpdateGlowColorAndScale()
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
				UI:UpdateGlowColorAndScale()
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
			Opt.heal_threshold = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend self healing spells', Opt.heal_threshold .. '%')
	end
	if startsWith(msg[1], 'fi') then
		if msg[2] then
			Opt.fiend = msg[2] == 'on'
		end
		return Status('Show Shadowfiend/Mindbender remaining time (top right)', Opt.fiend)
	end
	if msg[1] == 'reset' then
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
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
		'fiend |cFF00C000on|r/|cFFC00000off|r - show Shadowfiend/Mindbender remaining time (top right)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Prophetic1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
