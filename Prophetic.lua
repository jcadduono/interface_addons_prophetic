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
local GetCombatRatingBonus = _G.GetCombatRatingBonus
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
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

PropheticConfig = {}
local Opt -- use this as a local table reference to PropheticConfig

SLASH_Prophetic1, SLASH_Prophetic2 = '/prophetic', '/pro'
BINDING_HEADER_PROPHETIC = ADDON

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
	SetDefaults(PropheticConfig, { -- defaults
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
		cd_ttd = 8,
		pot = false,
		trinket = true,
	})
end

-- UI related functions container
local UI = {}

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

-- action priority list container
local APL = {}

-- current player information
local Player = {
	initialized = false,
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
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
		tick_mana = 0,
		tick_interval = 2,
		next_tick = 0,
		per_tick = 0,
		time_until_tick = 0,
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
		last_taken_physical = 0,
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
	main_freecast = false,
}

-- current target information
local Target = {
	boss = false,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
	npc_swing_types = { -- [npcId] = type
	},
}

-- Start AoE

Player.target_modes = {
	{1, ''},
	{2, '2'},
	{3, '3'},
	{4, '4'},
	{5, '5+'},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes)
	self.enemies = self.target_modes[self.target_mode][1]
	propheticPanel.text.br:SetText(self.target_modes[self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes or mode)
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
	for i = #Player.target_modes, 1, -1 do
		if count >= Player.target_modes[i][1] then
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

function Ability:Add(spellId, buff, player)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		name = false,
		icon = false,
		requires_charge = false,
		triggers_combat = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		mana_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 30,
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
		if spell == self.spellId then
			return true
		end
		for _, id in next, self.spellIds do
			if spell == id then
				return true
			end
		end
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

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if self.Available and not self:Available(seconds) then
		return false
	end
	if not pool then
		if self:ManaCost() > Player.mana.current then
			return false
		end
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains(mine, offGCD)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter .. (mine and '|PLAYER' or ''))
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			if aura.expirationTime == 0 then
				return 600 -- infinite duration
			end
			return max(0, aura.expirationTime - Player.ctime - (offGCD and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
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
	return self.mana_cost
end

function Ability:Free()
	return self.mana_cost > 0 and self:ManaCost() == 0
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

-- Start DoT Tracking

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

function Ability:RefreshAura(guid)
	return self:ApplyAura(guid)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT Tracking

-- Priest Abilities
---- General
local Shoot = Ability:Add({5019}, false, true)
---- Discipline
local PowerWordFortitude = Ability:Add({1243, 1244, 1245, 2791, 10937, 10938, 25389}, true)
PowerWordFortitude.buff_duration = 1800
PowerWordFortitude.mana_costs = {20, 70, 200, 300, 450, 600, 700}
local PowerWordShield = Ability:Add({17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901, 25217, 25218}, true)
PowerWordShield.buff_duration = 30
PowerWordShield.cooldown_duration = 4
PowerWordShield.mana_costs = {45, 80, 130, 175, 210, 250, 300, 355, 425, 500, 540, 600}
local PrayerOfFortitude = Ability:Add({21562, 21564, 25392}, true)
PrayerOfFortitude.buff_duration = 3600
PrayerOfFortitude.mana_costs = {1200, 1500, 1800}
local InnerFire = Ability:Add({588, 7128, 602, 1006, 10951, 10952, 25431}, true, true)
InnerFire.buff_duration = 600
InnerFire.mana_costs = {30, 65, 105, 165, 235, 315, 375}
local WeakenedSoul = Ability:Add(6788) -- Debuff applied by Power Word: Shield
WeakenedSoul.aura_target = 'player'
WeakenedSoul.buff_duration = 15
------ Talents
local InnerFocus = Ability:Add({14751}, true, true)
InnerFocus.buff_duration = 600
------ Procs

---- Holy
local HolyFire = Ability:Add({14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261, 25384}, false, true)
HolyFire.buff_duration = 10
HolyFire.tick_interval = 2
HolyFire.mana_costs = {85, 95, 125, 145, 170, 200, 230, 255, 290}
HolyFire.damage_min = {84, 106, 144, 178, 219, 271, 323, 375, 426}
HolyFire.damage_max = {104, 131, 178, 223, 273, 340, 406, 470, 537}
HolyFire.sp_coefficient = {0.857, 0.857, 0.857, 0.857, 0.857, 0.857, 0.857, 0.857, 0.857}
HolyFire.sp_school = 2
HolyFire.triggers_combat = true
local PrayerOfMending = Ability:Add({33076}, true, true)
PrayerOfMending.mana_costs = {390}
PrayerOfMending.buff = Ability:Add({41635}, true)
PrayerOfMending.buff.buff_duration = 30
local Smite = Ability:Add({585, 591, 598, 984, 1004, 6060, 10933, 10934, 25363, 25364}, false, true)
Smite.mana_costs = {20, 30, 60, 95, 140, 185, 230, 280, 300, 385}
Smite.damage_min = {15, 28, 58, 97, 158, 222, 298, 384, 422, 549}
Smite.damage_max = {20, 34, 67, 112, 178, 250, 335, 429, 470, 616}
Smite.sp_coefficient = {0.123, 0.271, 0.554, 0.714, 0.714, 0.714, 0.714, 0.714, 0.714, 0.714}
Smite.sp_school = 2
Smite.triggers_combat = true
------ Talents
local SearingLight = Ability:Add({14909, 15017}, false, true)
local SurgeOfLight = Ability:Add({33150, 33154}, true, true)
SurgeOfLight.buff = Ability:Add({33151}, true, true)
SurgeOfLight.buff.buff_duration = 10
------ Procs

---- Shadow
local MindBlast = Ability:Add({8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947, 25372, 25375}, false, true)
MindBlast.cooldown_duration = 8
MindBlast.mana_costs = {50, 80, 110, 150, 185, 225, 265, 310, 350, 380, 450}
MindBlast.damage_min = {42, 76, 117, 174, 225, 288, 356, 437, 516, 571, 711}
MindBlast.damage_max = {46, 83, 126, 184, 239, 307, 377, 461, 544, 602, 752}
MindBlast.sp_coefficient = {0.268, 0.364, 0.429, 0.429, 0.429, 0.429, 0.429, 0.429, 0.429, 0.429, 0.429}
MindBlast.sp_school = 6
MindBlast.triggers_combat = true
local Shadowfiend = Ability:Add({34433}, false, true)
Shadowfiend.buff_duration = 15
Shadowfiend.cooldown_duration = 300
Shadowfiend.mana_cost_pct = 6
local ShadowWordDeath = Ability:Add({32379, 32996}, false, true)
ShadowWordDeath.cooldown_duration = 12
ShadowWordDeath.mana_costs = {243, 309}
ShadowWordDeath.damage_min = {450, 572}
ShadowWordDeath.damage_max = {522, 664}
ShadowWordDeath.sp_coefficient = {0.429, 0.429}
ShadowWordDeath.sp_school = 6
ShadowWordDeath.triggers_combat = true
local ShadowWordPain = Ability:Add({589, 594, 970, 992, 2767, 10892, 10893, 10894, 25367, 25368}, false, true)
ShadowWordPain.buff_duration = 18
ShadowWordPain.tick_interval = 3
ShadowWordPain.mana_costs = {25, 50, 95, 155, 230, 305, 385, 470, 510, 575}
ShadowWordPain.triggers_combat = true
------ Talents
local Darkness = Ability:Add({15259, 15307, 15308, 15309, 15310}, true, true)
local MindFlay = Ability:Add({15407, 17311, 17312, 17313, 17314, 18807, 25387}, false, true)
MindFlay.mana_costs = {45, 70, 100, 135, 165, 205, 230}
MindFlay.tick_interval = 1
MindFlay.sp_school = 6
MindFlay.triggers_combat = true
local Misery = Ability:Add({33191, 33192, 33193, 33194, 33195}, false, true)
Misery.debuff = Ability:Add({33196, 33197, 33198, 33199, 33200})
Misery.debuff.buff_duration = 24
local Shadowform = Ability:Add({15473}, true, true)
Shadowform.mana_cost_pct = 32
local Silence = Ability:Add(15487)
Silence.mana_cost = 225
Silence.max_range = 20
Silence.buff_duration = 5
Silence.cooldown_duration = 45
Silence.triggers_combat = true
local SpiritTap = Ability:Add({15270, 15335, 15336, 15337, 15338}, true, true)
SpiritTap.buff_duration = 15
local VampiricEmbrace = Ability:Add({15286}, false, true)
VampiricEmbrace.buff_duration = 60
VampiricEmbrace.cooldown_duration = 10
VampiricEmbrace.mana_cost_pct = 2
local VampiricTouch = Ability:Add({34914, 34916, 34917}, false, true)
VampiricTouch.mana_costs = {325, 400, 425}
VampiricTouch.buff_duration = 15
VampiricTouch.tick_interval = 3
VampiricTouch.sp_school = 6
VampiricTouch.triggers_combat = true
------ Procs

-- Racials

-- Class Debuffs
local CurseOfTheElements = Ability:Add({27228})
CurseOfTheElements.buff_duration = 300
local ShadowVulnerabilityWarlock = Ability:Add({17800}) -- Destruction Warlock Improved Shadow Bolt talent
ShadowVulnerabilityWarlock.buff_duration = 12
local ShadowVulnerabilityPriest = Ability:Add(15258) -- Shadow Priest Shadow Weaving talent
ShadowVulnerabilityPriest.buff_duration = 15
-- Trinket Effects

-- End Abilities

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
			for i, spellId in next, ability.spellIds do
				self.bySpellId[spellId] = ability
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

function Player:ManaTick(timerTrigger)
	local time = GetTime()
	local mana = UnitPower('player', 0)
	if (
		(not timerTrigger and mana > self.mana.tick_mana) or
		(timerTrigger and mana >= self.mana.max)
	) then
		self.mana.next_tick = time + self.mana.tick_interval
		if mana >= self.mana.max then
			C_Timer.After(self.mana.tick_interval, function() Player:ManaTick(true) end)
		end
	end
	self.mana.tick_mana = mana
end

function Player:UnderMeleeAttack(physical)
	return (self.time - (physical and self.swing.last_taken_physical or self.swing.last_taken)) < 3
end

function Player:UnderAttack()
	return self.threat >= 3 or self:UnderMeleeAttack()
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
	local info
	-- Update spell ranks first
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.spellId = ability.spellIds[1]
		ability.rank = 1
		for i, spellId in next, ability.spellIds do
			if IsPlayerSpell(spellId) then
				ability.known = true
				ability.spellId = spellId -- update spellId to current rank
				ability.rank = i
				if ability.mana_costs then
					ability.mana_cost = ability.mana_costs[i] -- update mana_cost to current rank
				end
				if ability.mana_cost_pct then
					ability.mana_cost = floor(self.mana.base * (ability.mana_cost_pct / 100))
				end
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		info = GetSpellInfo(ability.spellId)
		if info then
			ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
		end
	end

	PrayerOfMending.buff.known = PrayerOfMending.known

	Abilities:Update()
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
	self.clip_flay_early = false
	self:UpdateTime()
	self.haste_factor = 1 / (1 + GetCombatRatingBonus(CR_HASTE_SPELL) / 100)
	self.gcd = 1.5 * self.haste_factor
	cooldown = GetSpellCooldown(47524)
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
	if MindFlay.known and MindFlay:Channeling() then
		self.execute_remains = max(self.gcd_remains, self.channel.ends - self.channel.tick_interval - self.ctime)
	end
	self.mana.current = UnitPower('player', 0)
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.per_tick = floor(self.mana.regen * self.mana.tick_interval)
	self.mana.time_until_tick = max(0, self.mana.next_tick - self.ctime)
	if self.cast.ability then
		self.mana.current = self.mana.current - self.cast.ability:ManaCost()
	end
	if self.execute_remains > self.mana.time_until_tick then
		self.mana.current = self.mana.current + self.mana.per_tick
	end
	self.mana.current = clamp(self.mana.current, 0, self.mana.max)
	self.mana.pct = self.mana.current / self.mana.max * 100
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

	TrackedAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.main = APL:Main()

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
		self.guid = UnitGUID('player')
		self.name = UnitName('player')
		self.initialized = true
	end
	propheticPreviousPanel.ability = nil
	_, self.instance = IsInInstance()
	self:SetTargetMode(1)
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	Events:UNIT_MAXPOWER('player')
	Events:ACTIONBAR_PAGE_CHANGED()
	Target:Update()
	Player:Update()
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
	self.timeToDieMax = self.health.current / Player.health.max * 15
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
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
		self.uid = ToUID(guid) or 0
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

function Target:Health()
	local health = self.health.current
	if Player.cast.ability then
		health = health - Player.cast.ability:MinDamage()
	end
	return max(0, health)
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self:Health() - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

-- End Target Functions

-- Start Ability Modifications

function Ability:ManaCost()
	if InnerFocus.known and InnerFocus:Up() then
		return 0
	end
	return self.mana_cost
end

function Ability:CalculateBonusDamage(base)
	local damage = base
	if self.sp_coefficient then
		damage = damage + (GetSpellBonusDamage(self.sp_school or 2) * self.sp_coefficient[self.rank])
	end
	if self.sp_school == 6 then
		if Darkness.known then
			damage = damage * (1 + (0.02 * Darkness.rank))
		end
		if Shadowform:Up() then
			damage = damage * 1.15
		end
		if ShadowVulnerabilityPriest:Up() then
			damage = damage * (1 + (0.02 * ShadowVulnerabilityPriest:Stack()))
		end
		if ShadowVulnerabilityWarlock:Up() then
			damage = damage * 1.20
		end
		if CurseOfTheElements:Up() then
			damage = damage * 1.10
		end
	end
	if Misery.debuff:Up() then
		damage = damage * (1 + (0.01 * Misery.rank))
	end
	return damage
end

function Ability:MinDamage()
	return self.damage_min and self:CalculateBonusDamage(self.damage_min[self.rank]) or 0
end

function Ability:MaxDamage()
	return self.damage_max and self:CalculateBonusDamage(self.damage_max[self.rank]) or 0
end

function PowerWordShield:Available()
	return WeakenedSoul:Down()
end

function InnerFocus:Available()
	return Ability.Remains(self) <= 0
end

function InnerFocus:Remains()
	if Player.cast.ability and Player.cast.ability.mana_cost > 0 then
		return 0
	end
	return Ability.Remains(self)
end

function Smite:ManaCost()
	if SurgeOfLight.known and SurgeOfLight.buff:Up() then
		return 0
	end
	return self.mana_cost
end

function Shoot:Available()
	return HasWandEquipped()
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

APL.Main = function(self)
	if Player:TimeInCombat() == 0 then
		local apl = self:Buffs(Target.boss and 180 or 30)
		if apl then return apl end
		if PowerWordShield:Usable() and PowerWordShield:Remains() < 10 then
			UseCooldown(PowerWordShield)
		end
	else
		local apl = self:Buffs(10)
		if apl then UseExtra(apl) end
	end
	if MindFlay.known then
		return self:Shadow()
	end
	return self:HolyDisc()
end

APL.HolyDisc = function(self)
	if Player:TimeInCombat() == 0 then
		if SurgeOfLight.known and Smite:Usable() and SurgeOfLight.buff:Up() and SurgeOfLight.buff:Remains() < 5 then
			return Smite
		end
		if HolyFire:Usable() and HolyFire:Down() then
			return HolyFire
		end
	end
	if PowerWordShield:Usable() and Player:UnderAttack() and PowerWordShield:Remains() < Smite:CastTime() then
		UseExtra(PowerWordShield)
	end
	if Shadowfiend:Usable() and Player:ManaPct() < 30 and (Target.timeToDie > 15 or Player.enemies > 1) then
		UseCooldown(Shadowfiend)
	end
	if SurgeOfLight.known and Smite:Usable() and SurgeOfLight.buff:Up() then
		return Smite
	end
	if ShadowWordDeath:Usable() and (Target.timeToDie < 1 or Target:Health() < ShadowWordDeath:MinDamage() or (Player.group_size > 1 and PrayerOfMending.buff:Up() and not Player:UnderAttack())) then
		return ShadowWordDeath
	end
	if ShadowWordPain:Usable() and ShadowWordPain:Down() and Target.timeToDie > (ShadowWordPain:TickTime() * 4) then
		if InnerFocus:Usable() then
			UseCooldown(InnerFocus)
		end
		return ShadowWordPain
	end
	if MindBlast:Usable() and SearingLight.rank < 2 and Target.timeToDie > MindBlast:CastTime() then
		return MindBlast
	end
	if HolyFire:Usable() and HolyFire:Remains() < HolyFire:CastTime() and Target.timeToDie > (HolyFire:CastTime() + (HolyFire:TickTime() * 4)) and (not Player:UnderMeleeAttack() or PowerWordShield:Remains() > HolyFire:CastTime()) then
		return HolyFire
	end
	if Smite:Usable() and Target.timeToDie > Smite:CastTime() and (not Player:UnderMeleeAttack() or PowerWordShield:Remains() > Smite:CastTime()) then
		return Smite
	end
	if MindBlast:Usable() and Target.timeToDie > Smite:CastTime() and (not Player:UnderMeleeAttack() or PowerWordShield:Remains() > Smite:CastTime()) then
		return MindBlast
	end
	if Shoot:Usable() then
		return Shoot
	end
end

APL.Shadow = function(self)
	if Player:TimeInCombat() == 0 then
		if Shadowform:Down() then
			return Shadowform
		end
	else
		if Shadowform:Down() then
			UseCooldown(Shadowform)
		end
	end
	if PowerWordShield:Usable() and Player:UnderAttack() and PowerWordShield:Remains() < Smite:CastTime() then
		UseExtra(PowerWordShield)
	end
	if Shadowfiend:Usable() and Player:ManaPct() < 30 and (Target.timeToDie > 15 or Player.enemies > 1) then
		UseCooldown(Shadowfiend)
	end
	if ShadowWordDeath:Usable(0.5 * Player.haste_factor) and (Target.timeToDie < 1 or Target:Health() < ShadowWordDeath:MinDamage()) then
		Player.clip_flay_early = true
		return ShadowWordDeath
	end
	if MindBlast:Usable(0.5 * Player.haste_factor) and Target.timeToDie > MindBlast:CastTime() and ShadowVulnerabilityPriest:Stack() >= 5 and ShadowVulnerabilityPriest:Remains() > MindBlast:CastTime() then
		if InnerFocus:Usable() and Target.timeToDie < (ShadowWordPain:Remains() + ShadowWordPain:TickTime() * 4) then
			UseCooldown(InnerFocus)
		end
		return MindBlast
	end
	if VampiricTouch:Usable() and VampiricTouch:Remains() < VampiricTouch:CastTime() and Target.timeToDie > (VampiricTouch:TickTime() * 2) then
		return VampiricTouch
	end
	if ShadowWordPain:Usable() and ShadowWordPain:Down() and Target.timeToDie > (ShadowWordPain:TickTime() * 2) then
		if InnerFocus:Usable() then
			UseCooldown(InnerFocus)
		end
		return ShadowWordPain
	end
	if MindBlast:Usable(0.5 * Player.haste_factor) and Target.timeToDie > MindBlast:CastTime() then
		return MindBlast
	end
	if ShadowWordDeath:Usable(0.5 * Player.haste_factor) and Player.health.current > ShadowWordDeath:MaxDamage() * 2 and not Player:UnderAttack() then
		return ShadowWordDeath
	end
	if VampiricEmbrace:Usable() and (Target.boss or Target.timeToDie > 30) and VampiricEmbrace:Remains() < 4 then
		UseExtra(VampiricEmbrace)
	end
	if MindFlay:Usable() then
		return MindFlay
	end
	if Shoot:Usable() then
		return Shoot
	end
end

APL.Buffs = function(self, remains)
	if PowerWordFortitude:Usable() and PowerWordFortitude:Remains() < remains and PrayerOfFortitude:Remains() < remains then
		return PowerWordFortitude
	end
	if InnerFire:Usable() and InnerFire:Remains() < remains then
		return InnerFire
	end
end

APL.Interrupt = function(self)
	if Silence:Usable() then
		return Silence
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
	local border, dim, dim_cd, text_center, text_tl, text_tr, text_cd_tr
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
		if Opt.keybinds then
			for _, bind in next, Player.cd.keybinds do
				text_cd_tr = bind
				break
			end
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
			elseif MindFlay:Channeling() and not Player.clip_flay_early then
				local clip = channel.ends - channel.tick_interval - ctime
				if clip > 0 then
					text_center = format('|cFFFFFD00CLIP\n%.1fs', clip)
					dim = Opt.dimmer
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if border ~= propheticPanel.border.overlay then
		propheticPanel.border.overlay = border
		propheticPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	propheticPanel.dimmer:SetShown(dim)
	propheticPanel.text.center:SetText(text_center)
	propheticPanel.text.tl:SetText(text_tl)
	propheticPanel.text.tr:SetText(text_tr)
	--propheticPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	propheticCooldownPanel.dimmer:SetShown(dim_cd)
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
		Opt = PropheticConfig
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
	if not uid then
		return
	end
	TrackedAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		local uid = ToUID(srcGUID)
		if uid > 0 then
			if spellSchool then
				if spellSchool > 1 and Target.npc_swing_types[uid] ~= spellSchool then
					Target.npc_swing_types[npcId] = spellSchool
				end
			elseif Target.npc_swing_types[npcId] then
				spellSchool = Target.npc_swing_types[uid]
			end
		end
		if not spellSchool or bit.band(spellSchool, 1) > 0 then
			Player.swing.last_taken_physical = Player.time
		end
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

--local UnknownSpell = {}

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
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

function Events:UNIT_POWER_FREQUENT(unitId, powerType)
	if unitId == 'player' and powerType == 'MANA' then
		Player:ManaTick()
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitEffectiveLevel(unitId)
		local int = UnitStat(unitId, 4)
		Player.mana.max = UnitPowerMax(unitId, 0)
		Player.mana.base = Player.mana.max - (min(20, int) + 15 * (int - min(20, int)))
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
	Player.swing.last_taken_physical = 0
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

	Player:UpdateKnown()
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
			cooldown = GetSpellCooldown(47524)
		end
		propheticPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
	end
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
		Events:ACTIONBAR_SLOT_CHANGED()
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
		return Status('Locked', Opt.locked)
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
			Opt.cd_ttd = tonumber(msg[2]) or 8
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
	if msg[1] == 'reset' then
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. C_AddOns.GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
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
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Prophetic1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
