local ADDON = 'Prophetic'
if select(2, UnitClass('player')) ~= 'PRIEST' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
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
-- end reference global functions

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
		cd_ttd = 8,
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

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local events = {}

local timer = {
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
	cast_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	health = {
		current = 0,
		max = 100,
	},
	mana = {
		current = 0,
		base = 100,
		max = 100,
		regen = 0,
	},
	insanity = {
		current = 0,
		max = 100,
		drain = 0,
		generation = 0,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	set_bonus = {
		t28 = 0,
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
	main_freecast = false,
	use_cds = false,
}

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

-- base mana for each level
local BaseMana = {
	52,   54,   57,   60,   62,   66,   69,   72,   76,   80,    -- 10
	86,   93,   101,  110,  119,  129,  140,  152,  165,  178,   -- 20
	193,  210,  227,  246,  267,  289,  314,  340,  369,  400,   -- 30
	433,  469,  509,  551,  598,  648,  702,  761,  825,  894,   -- 40
	969,  1050, 1138, 1234, 1337, 1449, 1571, 1702, 1845, 2000,  -- 50
	2349, 2759, 3241, 3807, 4472, 5253, 6170, 7247, 8513, 10000, -- 60
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
propheticPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
propheticPanel.border:Hide()
propheticPanel.dimmer = propheticPanel:CreateTexture(nil, 'BORDER')
propheticPanel.dimmer:SetAllPoints(propheticPanel)
propheticPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
propheticPanel.dimmer:Hide()
propheticPanel.swipe = CreateFrame('Cooldown', nil, propheticPanel, 'CooldownFrameTemplate')
propheticPanel.swipe:SetAllPoints(propheticPanel)
propheticPanel.swipe:SetDrawBling(false)
propheticPanel.swipe:SetDrawEdge(false)
propheticPanel.text = CreateFrame('Frame', nil, propheticPanel)
propheticPanel.text:SetAllPoints(propheticPanel)
propheticPanel.text.tl = propheticPanel.text:CreateFontString(nil, 'OVERLAY')
propheticPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
propheticPanel.text.tl:SetPoint('TOPLEFT', propheticPanel, 'TOPLEFT', 2.5, -3)
propheticPanel.text.tl:SetJustifyH('LEFT')
propheticPanel.text.tr = propheticPanel.text:CreateFontString(nil, 'OVERLAY')
propheticPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
propheticPanel.text.tr:SetPoint('TOPRIGHT', propheticPanel, 'TOPRIGHT', -2.5, -3)
propheticPanel.text.tr:SetJustifyH('RIGHT')
propheticPanel.text.bl = propheticPanel.text:CreateFontString(nil, 'OVERLAY')
propheticPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
propheticPanel.text.bl:SetPoint('BOTTOMLEFT', propheticPanel, 'BOTTOMLEFT', 2.5, 3)
propheticPanel.text.bl:SetJustifyH('LEFT')
propheticPanel.text.br = propheticPanel.text:CreateFontString(nil, 'OVERLAY')
propheticPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
propheticPanel.text.br:SetPoint('BOTTOMRIGHT', propheticPanel, 'BOTTOMRIGHT', -2.5, 3)
propheticPanel.text.br:SetJustifyH('RIGHT')
propheticPanel.text.center = propheticPanel.text:CreateFontString(nil, 'OVERLAY')
propheticPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 9, 'OUTLINE')
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
propheticPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
propheticCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
propheticCooldownPanel.dimmer = propheticCooldownPanel:CreateTexture(nil, 'BORDER')
propheticCooldownPanel.dimmer:SetAllPoints(propheticCooldownPanel)
propheticCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
propheticCooldownPanel.dimmer:Hide()
propheticCooldownPanel.swipe = CreateFrame('Cooldown', nil, propheticCooldownPanel, 'CooldownFrameTemplate')
propheticCooldownPanel.swipe:SetAllPoints(propheticCooldownPanel)
propheticCooldownPanel.swipe:SetDrawBling(false)
propheticCooldownPanel.swipe:SetDrawEdge(false)
propheticCooldownPanel.text = propheticCooldownPanel:CreateFontString(nil, 'OVERLAY')
propheticCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
propheticCooldownPanel.text:SetAllPoints(propheticCooldownPanel)
propheticCooldownPanel.text:SetJustifyH('CENTER')
propheticCooldownPanel.text:SetJustifyV('CENTER')
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
propheticInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
propheticInterruptPanel.swipe = CreateFrame('Cooldown', nil, propheticInterruptPanel, 'CooldownFrameTemplate')
propheticInterruptPanel.swipe:SetAllPoints(propheticInterruptPanel)
propheticInterruptPanel.swipe:SetDrawBling(false)
propheticInterruptPanel.swipe:SetDrawEdge(false)
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
propheticExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

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
	local npcId = guid:match('^%a+%-0%-%d+%-%d+%-%d+%-(%d+)')
	if not npcId or self.ignored_units[tonumber(npcId)] then
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
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
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

function autoAoe:Purge()
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

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

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
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
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
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds)
	if not self.known then
		return false
	end
	if self.mana_cost > 0 and self:Cost() > Player.mana.current then
		return false
	end
	if Player.spec == SPEC.SHADOW and self.insanity_cost > 0 and self:InsanityCost() > Player.insanity.current then
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
			return max(0, expires - Player.ctime - Player.execute_remains)
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
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
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
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:Cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * (Player.mana.base * 5)) or 0
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
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
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
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return Player.ability_channeling == self
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
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
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
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		self.auto_aoe.target_count = 0
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastFailed(dstGUID, missType)

end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		autoAoe:Add(dstGUID, true)
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
			if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, Player.time - oldest.start)))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(max(5, min(self.max_range, self.velocity * (Player.time - self.range_est_start))))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and propheticPreviousPanel.ability == self then
		propheticPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
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

function Ability:RefreshAura(guid, seconds)
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + (seconds or duration))
end

function Ability:RefreshAuraAll(seconds)
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + (seconds or duration))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

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
ShadowWordPain:AutoAoe(false, 'apply')
ShadowWordPain:TrackAuras()
local Smite = Ability:Add(585, false, true, 208772)
Smite.mana_cost = 0.2
------ Talents
local DivineStar = Ability:Add(110744, false, true, 110745)
DivineStar.mana_cost = 2
DivineStar.cooldown_duration = 15
DivineStar:AutoAoe()
local Halo = Ability:Add(120517, false, true, 120692)
Halo.mana_cost = 2.7
Halo.cooldown_duration = 40
local ShiningForce = Ability:Add(204263, false, true)
ShiningForce.mana_cost = 2.5
ShiningForce.cooldown_duration = 45
ShiningForce.buff_duration = 3
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
local ShadowMend = Ability:Add(186263, false, true)
ShadowMend.mana_cost = 3.5
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
PurgeTheWicked:AutoAoe(false, 'apply')
local PowerWordSolace = Ability:Add(129250, false, true)
local Schism = Ability:Add(214621, false, true)
Schism.buff_duration = 9
Schism.cooldown_duration = 24
Schism.mana_cost = 0.5
local SearingLight = Ability:Add(215768, false, true)
local MindbenderDisc = Ability:Add(123040, false, true)
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
local Misery = Ability:Add(238558, false, true)
local PsychicLink = Ability:Add(199484, false, true, 199486)
local SearingNightmare = Ability:Add(341385, false, true)
SearingNightmare.insanity_cost = 30
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
------ Tier Bonuses
local LivingShadow = Ability:Add(363469, false, true) -- T28 4 piece
-- Covenant abilities
local FirstStrike = Ability:Add(325069, true, true, 325381) -- Night Fae (Korayn Soulbind)
local Fleshcraft = Ability:Add(324631, true, true, 324867) -- Necrolord
Fleshcraft.buff_duration = 120
Fleshcraft.cooldown_duration = 120
local LeadByExample = Ability:Add(342156, true, true, 342181) -- Necrolord (Emeni Soulbind)
LeadByExample.buff_duration = 10
local PustuleEruption = Ability:Add(351094, true, true) -- Necrolord (Emeni Soulbind)
local SummonSteward = Ability:Add(324739, false, true) -- Kyrian
SummonSteward.cooldown_duration = 300
local UnholyNova = Ability:Add(324724, false, true) -- Necrolord
UnholyNova.cooldown_duration = 60
UnholyNova.mana_cost = 5
local UnholyTransfusion = Ability:Add(325203, false, true) -- Necrolord (Unholy Nova DoT)
UnholyTransfusion.buff_duration = 15
UnholyTransfusion.tick_interval = 3
UnholyTransfusion.hasted_ticks = true
UnholyTransfusion:AutoAoe(false, 'apply')
UnholyTransfusion:TrackAuras()
-- Soulbind conduits
local MindDevourer = Ability:Add(338332, true, true, 338333)
MindDevourer.conduit_id = 113
MindDevourer.buff_duration = 15
-- Legendary effects
local PainbreakerPsalm = Ability:Add(336165, false, true)
PainbreakerPsalm.bonus_id = 6981
local ShadowflamePrism = Ability:Add(336143, false, true)
ShadowflamePrism.bonus_id = 6982
local ShadowflameRift = Ability:Add(344748, false, true) -- triggered by Shadowflame Prism
ShadowflameRift:AutoAoe()
local Unity = Ability:Add(364911, true, true)
Unity.bonus_id = 8126
-- PvP talents

-- Racials

-- Trinket effects

-- End Abilities

-- Start Summoned Pets

local SummonedPet, Pet = {}, {}
SummonedPet.__index = SummonedPet
local summonedPets = {
	all = {},
	known = {},
	byNpcId = {},
}

function summonedPets:Find(guid)
	local npcId = guid:match('^Creature%-0%-%d+%-%d+%-%d+%-(%d+)')
	return npcId and self.byNpcId[tonumber(npcId)]
end

function summonedPets:Purge()
	local _, pet, guid, unit
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires <= Player.time then
				pet.active_units[guid] = nil
			end
		end
	end
end

function summonedPets:Count()
	local _, pet, guid, unit
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:Count()
	end
	return count
end

function SummonedPet:Add(npcId, duration, summonSpell)
	local pet = {
		npcId = npcId,
		duration = duration,
		active_units = {},
		summon_spell = summonSpell,
		known = false,
	}
	setmetatable(pet, self)
	summonedPets.all[#summonedPets.all + 1] = pet
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

-- Summoned Pets
Pet.Lightspawn = SummonedPet:Add(128140, 15, Lightspawn)
Pet.RattlingMage = SummonedPet:Add(180113, 20, UnholyNova)
Pet.Shadowfiend = SummonedPet:Add(19668, 15, Shadowfiend)
Pet.Mindbender = SummonedPet:Add(62982)
Pet.YourShadow = SummonedPet:Add(183955, 6, LivingShadow)

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
local EternalAugmentRune = InventoryItem:Add(190384)
EternalAugmentRune.buff = Ability:Add(367405, true, true)
local EternalFlask = InventoryItem:Add(171280)
EternalFlask.buff = Ability:Add(307166, true, true)
local PhialOfSerenity = InventoryItem:Add(177278) -- Provided by Summon Steward
PhialOfSerenity.max_charges = 3
local PotionOfPhantomFire = InventoryItem:Add(171349)
PotionOfPhantomFire.buff = Ability:Add(307495, true, true)
local PotionOfSpectralIntellect = InventoryItem:Add(171273)
PotionOfSpectralIntellect.buff = Ability:Add(307162, true, true)
local SpectralFlaskOfPower = InventoryItem:Add(171276)
SpectralFlaskOfPower.buff = Ability:Add(307185, true, true)
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.SoleahsSecretTechnique = InventoryItem:Add(190958)
Trinket.SoleahsSecretTechnique.buff = Ability:Add(368512, true, true)
-- End Inventory Items

-- Start Player API

function Player:Health()
	return self.health.current
end

function Player:HealthMax()
	return self.health.max
end

function Player:HealthPct()
	return self.health.current / self.health.max * 100
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

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.ability_casting and self.ability_casting.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderAttack()
	return self.threat.status >= 3
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

function Player:UpdateEquipment()
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
			_, inventoryItems[i].equip_slot = self:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if self.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end

	self.set_bonus.t28 = (self:Equipped(188875) and 1 or 0) + (self:Equipped(188878) and 1 or 0) + (self:Equipped(188879) and 1 or 0) + (self:Equipped(188880) and 1 or 0) + (self:Equipped(188881) and 1 or 0)
end

function Player:UpdateAbilities()
	self.rescan_abilities = false
	self.mana.base = BaseMana[self.level]
	self.mana.max = UnitPowerMax('player', 0)
	self.insanity.max = UnitPowerMax('player', 13)

	local node
	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		end
		if ability.bonus_id then -- used for checking enchants and Legendary crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.conduit_id then
			node = C_Soulbinds.FindNodeIDActuallyInstalled(C_Soulbinds.GetActiveSoulbindID(), ability.conduit_id)
			if node then
				node = C_Soulbinds.GetNode(node)
				if node then
					if node.conduitID == 0 then
						self.rescan_abilities = true -- rescan on next target, conduit data has not finished loading
					else
						ability.known = node.state == 3
						ability.rank = node.conduitRank
					end
				end
			end
		end
	end

	self.swp = PurgeTheWicked.known and PurgeTheWicked or ShadowWordPain
	if MindbenderDisc.known then
		self.fiend = MindbenderDisc
		Pet.Mindbender.duration = 12
		Pet.Mindbender.summon_spell = MindbenderDisc
	elseif MindbenderShadow.known then
		self.fiend = MindbenderShadow
		Pet.Mindbender.duration = 15
		Pet.Mindbender.summon_spell = MindbenderShadow
	elseif Lightspawn.known then
		self.fiend = Lightspawn
	else
		self.fiend = Shadowfiend
	end
	Shadowfiend.known = Shadowfiend.known and self.fiend == Shadowfiend
	MindSear.damage.known = MindSear.known
	Voidform.known = VoidEruption.known
	VoidBolt.known = VoidEruption.known
	ShadowflameRift.known = ShadowflamePrism.known
	UnholyTransfusion.known = UnholyNova.known
	LivingShadow.known = self.set_bonus.t28 >= 4

	wipe(abilities.bySpellId)
	wipe(abilities.velocity)
	wipe(abilities.autoAoe)
	wipe(abilities.trackAuras)
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

	wipe(summonedPets.known)
	wipe(summonedPets.byNpcId)
	for _, pet in next, summonedPets.all do
		pet.known = pet.summon_spell and pet.summon_spell.known
		if pet.known then
			summonedPets.known[#summonedPets.known + 1] = pet
			summonedPets.byNpcId[pet.npcId] = pet
		end
	end
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
	local _, start, duration, remains, spellId
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self:UpdateTime()
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.cast_remains = remains and (remains / 1000 - self.ctime) or 0
	self.execute_remains = max(self.cast_remains, self.gcd_remains)
	_, _, _, _, remains, _, _, spellId = UnitChannelInfo('player')
	self.ability_channeling = abilities.bySpellId[spellId]
	self.channel_remains = remains and (remains / 1000 - self.ctime) or 0
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	self.health.current = UnitHealth('player')
	self.health.max = UnitHealthMax('player')
	self.mana.regen = GetPowerRegen()
	self.mana.current = UnitPower('player', 0) + (self.mana.regen * self.execute_remains)
	if self.ability_casting and self.ability_casting.mana_cost > 0 then
		self.mana.current = self.mana.current - self.ability_casting:Cost()
	end
	self.mana.current = min(self.mana.max, max(0, self.mana.current))
	if Shadowform.known then
		self.insanity.current = UnitPower('player', 13)
		if self.ability_casting then
			if self.ability_casting.insanity_cost > 0 then
				self.insanity.current = self.insanity.current - self.ability_casting:InsanityCost()
			end
			if self.ability_casting.insanity_gain > 0 then
				self.insanity.current = self.insanity.current + self.ability_casting:InsanityGain()
			end
		end
		self.insanity.current = min(self.insanity.max, max(0, self.insanity.current))
	end
	self.moving = GetUnitSpeed('player') ~= 0
	self:UpdateThreat()

	summonedPets:Purge()
	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	propheticPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	events:GROUP_ROSTER_UPDATE()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player API

-- Start Target API

function Target:UpdateHealth(reset)
	timer.health = 0
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
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
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
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health.max > Player.health.max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		propheticPanel:Show()
		return true
	end
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (self.health.pct / 100))) / self.health.loss_per_sec)
end

-- End Target API

-- Start Ability Modifications

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

function VoidBolt:Usable(...)
	if Voidform:Down() then
		return false
	end
	return Ability.Usable(self, ...)
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

function DevouringPlague:InsanityCost()
	if MindDevourer.known and MindDevourer:Up() then
		return 0
	end
	return Ability.InsanityCost(self)
end

function SearingNightmare:Usable(...)
	if not MindSear:Channeling() then
		return false
	end
	return Ability.Usable(self, ...)
end

-- End Ability Modifications

-- Start Summoned Pet Modifications



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

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		Main = function() end
	},
	[SPEC.DISCIPLINE] = {},
	[SPEC.HOLY] = {},
	[SPEC.SHADOW] = {},
}

APL[SPEC.DISCIPLINE].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if Trinket.SoleahsSecretTechnique.can_use and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Trinket.SoleahsSecretTechnique:Usable() and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseExtra(SummonSteward)
		end
		if Fleshcraft:Usable() and Fleshcraft:Remains() < 10 then
			UseExtra(Fleshcraft)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
		if PowerWordFortitude:Usable() and PowerWordFortitude:Remains() < 300 then
			return PowerWordFortitude
		end
		if Shadowform:Usable() and Shadowform:Down() then
			return Shadowform
		end
		if VampiricTouch:Usable() and VampiricTouch:Down() then
			return VampiricTouch
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
	if Schism.known and Player.fiend:Usable() and Schism:Ready(3) and Target.timeToDie > 15 then
		UseCooldown(Player.fiend)
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
	if DivineStar:Usable() then
		UseCooldown(DivineStar)
	end
	if Player.fiend:Usable() and Target.timeToDie > 15 then
		UseCooldown(Player.fiend)
	end
	if Trinket1:Usable() then
		UseCooldown(Trinket1)
	elseif Trinket2:Usable() then
		UseCooldown(Trinket2)
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

APL[SPEC.HOLY].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if Trinket.SoleahsSecretTechnique.can_use and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Trinket.SoleahsSecretTechnique:Usable() and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseExtra(SummonSteward)
		end
		if Fleshcraft:Usable() and Fleshcraft:Remains() < 10 then
			UseExtra(Fleshcraft)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
		if PowerWordFortitude:Usable() and PowerWordFortitude:Remains() < 300 then
			return PowerWordFortitude
		end
	else
		if PowerWordFortitude:Down() and PowerWordFortitude:Usable() then
			UseExtra(PowerWordFortitude)
		end
	end
end

APL[SPEC.SHADOW].Main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/snapshot_stats
actions.precombat+=/fleshcraft,if=soulbind.pustule_eruption|soulbind.volatile_solvent
actions.precombat+=/shadowform,if=!buff.shadowform.up
actions.precombat+=/arcane_torrent
actions.precombat+=/use_item,name=shadowed_orb_of_torment
actions.precombat+=/variable,name=mind_sear_cutoff,op=set,value=2
actions.precombat+=/vampiric_touch,if=!talent.damnation.enabled
actions.precombat+=/mind_blast,if=talent.damnation.enabled
]]
		if Trinket.SoleahsSecretTechnique.can_use and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Trinket.SoleahsSecretTechnique:Usable() and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseExtra(SummonSteward)
		end
		if Fleshcraft:Usable() and Fleshcraft:Remains() < 10 then
			UseExtra(Fleshcraft)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
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
--[[
actions=potion,if=buff.power_infusion.up&(buff.bloodlust.up|(time+fight_remains)>=320)
actions+=/antumbra_swap,if=buff.singularity_supreme_lockout.up&!buff.power_infusion.up&!buff.voidform.up&!pet.fiend.active&!buff.singularity_supreme.up&!buff.swap_stat_compensation.up&!buff.bloodlust.up&!((fight_remains+time)>=330&time<=200|(fight_remains+time)<=250&(fight_remains+time)>=200)
actions+=/antumbra_swap,if=buff.swap_stat_compensation.up&!buff.singularity_supreme_lockout.up&(cooldown.power_infusion.remains<=30&cooldown.void_eruption.remains<=30&!((time>80&time<100)&((fight_remains+time)>=330&time<=200|(fight_remains+time)<=250&(fight_remains+time)>=200))|fight_remains<=40)
actions+=/variable,name=dots_up,op=set,value=dot.shadow_word_pain.ticking&dot.vampiric_touch.ticking
actions+=/variable,name=all_dots_up,op=set,value=dot.shadow_word_pain.ticking&dot.vampiric_touch.ticking&dot.devouring_plague.ticking
actions+=/variable,name=searing_nightmare_cutoff,op=set,value=spell_targets.mind_sear>2+buff.voidform.up
actions+=/variable,name=five_minutes_viable,op=set,value=(fight_remains+time)>=60*5+20
actions+=/variable,name=four_minutes_viable,op=set,value=!variable.five_minutes_viable&(fight_remains+time)>=60*4+20
actions+=/variable,name=do_three_mins,op=set,value=(variable.five_minutes_viable|!variable.five_minutes_viable&!variable.four_minutes_viable)&time<=200
actions+=/variable,name=cd_management,op=set,value=variable.do_three_mins|(variable.four_minutes_viable&cooldown.power_infusion.remains<=gcd.max*3|variable.five_minutes_viable&time>300)|fight_remains<=25,default=0
actions+=/variable,name=max_vts,op=set,default=1,value=spell_targets.vampiric_touch
actions+=/variable,name=max_vts,op=set,value=5+2*(variable.cd_management&cooldown.void_eruption.remains<=10)&talent.hungering_void.enabled,if=talent.searing_nightmare.enabled&spell_targets.mind_sear=7
actions+=/variable,name=max_vts,op=set,value=0,if=talent.searing_nightmare.enabled&spell_targets.mind_sear>7
actions+=/variable,name=max_vts,op=set,value=4,if=talent.searing_nightmare.enabled&spell_targets.mind_sear=8&!talent.shadow_crash.enabled
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
	if Opt.pot and Target.boss and not Player:InArenaOrBattleground() and PotionOfSpectralIntellect:Usable() and PowerInfusion:Up() and (Player:BloodlustActive() or (Player:TimeInCombat() + Target.timeToDie) >= 320) then
		UseCooldown(PotionOfSpectralIntellect)
	end
	self.dots_up = ShadowWordPain:Up() and VampiricTouch:Up()
	self.all_dots_up = self.dots_up and DevouringPlague:Up()
	self.mind_sear_cutoff = 2
	self.searing_nightmare_cutoff = Player.enemies > (2 + (Voidform:Up() and 1 or 0))
	self.five_minutes_viable = (Target.timeToDie + Player:TimeInCombat()) >= (60 * 5 + 20)
	self.four_minutes_viable = not self.five_minutes_viable and (Target.timeToDie + Player:TimeInCombat()) >= (60 * 4 + 20)
	self.do_three_mins = (self.five_minutes_viable or not self.four_minutes_viable) and Player:TimeInCombat() <= 200
	self.cd_management = self.do_three_mins or (self.four_minutes_viable and PowerInfusion:Ready(Player.gcd * 3)) or (self.five_minutes_viable and Player:TimeInCombat() > 300) or Target.timeToDie <= 25
	self.max_vts = Player.enemies
	if Voidform:Up() then
		self.max_vts = Player.enemies <= 5 and Player.enemies or 0
	elseif SearingNightmare.known then
		if Player.enemies == 8 and not ShadowCrash.known then
			self.max_vts = 4
		elseif Player.enemies > 7 then
			self.max_vts = 0
		elseif Player.enemies == 7 then
			self.max_vts = 5 + ((self.cd_management and VoidEruption:Ready(10) and HungeringVoid.known) and 2 or 0)
		end
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
actions.cds+=/fleshcraft,if=soulbind.volatile_solvent&buff.volatile_solvent_humanoid.remains<=3*gcd.max,cancel_if=buff.volatile_solvent_humanoid.up
actions.cds+=/silence,target_if=runeforge.sephuzs_proclamation.equipped&(target.is_add|target.debuff.casting.react)
actions.cds+=/fae_guardians,if=!buff.voidform.up&(!cooldown.void_torrent.up|!talent.void_torrent.enabled)&(variable.dots_up&spell_targets.vampiric_touch==1|variable.vts_applied&spell_targets.vampiric_touch>1)|buff.voidform.up&(soulbind.grove_invigoration.enabled|soulbind.field_of_blossoms.enabled)
actions.cds+=/unholy_nova,if=!talent.hungering_void&variable.dots_up|debuff.hungering_void.up&buff.voidform.up|(cooldown.void_eruption.remains>15|!variable.cd_management)&!buff.voidform.up
actions.cds+=/boon_of_the_ascended,if=variable.dots_up&(cooldown.fiend.up|!runeforge.shadowflame_prism)
actions.cds+=/void_eruption,if=variable.cd_management&(!soulbind.volatile_solvent|buff.volatile_solvent_humanoid.up)&(insanity<=85|talent.searing_nightmare.enabled&variable.searing_nightmare_cutoff)&!cooldown.fiend.up&(pet.fiend.active&!cooldown.shadow_word_death.up|cooldown.fiend.remains>=gcd.max*5|!runeforge.shadowflame_prism)&(cooldown.mind_blast.charges=0|time>=15)
actions.cds+=/call_action_list,name=trinkets
actions.cds+=/mindbender,if=(talent.searing_nightmare.enabled&spell_targets.mind_sear>variable.mind_sear_cutoff|dot.shadow_word_pain.ticking)&variable.vts_applied
actions.cds+=/desperate_prayer,if=health.pct<=75
]]
	if PowerInfusion:Usable() and Voidform:Up() and ((not self.five_minutes_viable or not between(Player:TimeInCombat(), 235, 300)) or Target.timeToDie <= 25) then
		return UseCooldown(PowerInfusion)
	end
	if UnholyNova:Usable() and ((not HungeringVoid.known and self.dots_up) or (HungeringVoid.known and HungeringVoid:Up() and Voidform:Up()) or (Voidform:Down() and (not VoidEruption:Ready(15) or not self.cd_management))) then
		return UseCooldown(UnholyNova)
	end
	if VoidEruption:Usable() and self.cd_management and (Player.insanity.current <= 85 or (SearingNightmare.known and self.searing_nightmare_cutoff)) and not Player.fiend:Ready() and ((Player.fiend:Up() and not ShadowWordDeath:Ready()) or not Player.fiend:Ready(Player.gcd * 5) or not ShadowflamePrism.known) and (MindBlast:Charges() == 0 or Player:TimeInCombat() >= 15) then
		return UseCooldown(VoidEruption)
	end
	if MindbenderShadow:Usable() and self.vts_applied and ((SearingNightmare.known and Player.enemies > self.mind_sear_cutoff) or ShadowWordPain:Up()) then
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
actions.cwc=mind_blast,only_cwc=1,target_if=set_bonus.tier28_4pc&buff.dark_thought.up&pet.fiend.active&runeforge.shadowflame_prism.equipped&!buff.voidform.up&pet.your_shadow.remains<fight_remains|buff.dark_thought.up&pet.your_shadow.remains<gcd.max*(3+(!buff.voidform.up)*16)&pet.your_shadow.remains<fight_remains
actions.cwc+=/searing_nightmare,use_while_casting=1,target_if=(variable.searing_nightmare_cutoff&!variable.pool_for_cds)|(dot.shadow_word_pain.refreshable&spell_targets.mind_sear>1)
actions.cwc+=/searing_nightmare,use_while_casting=1,target_if=talent.searing_nightmare.enabled&dot.shadow_word_pain.refreshable&spell_targets.mind_sear>2
actions.cwc+=/mind_blast,only_cwc=1
]]
	if MindBlast:Usable() and DarkThought:Up() and Pet.YourShadow:Remains() < Target.timeToDie and (
		(LivingShadow.known and ShadowflamePrism.known and Player.fiend:Up() and Voidform:Down()) or
		(Pet.YourShadow:Remains() < (Player.gcd * (3 + (Voidform:Up() and 0 or 1) * 16)))
	) then
		return MindBlast
	end
	if SearingNightmare:Usable() and ((self.searing_nightmare_cutoff and not self.pool_for_cds) or (ShadowWordPain:Refreshable() and Player.enemies > 1)) then
		return SearingNightmare
	end
	if MindBlast:Usable() then
		return MindBlast
	end
end

APL[SPEC.SHADOW].main = function(self)
--[[
actions.main=call_action_list,name=boon,if=buff.boon_of_the_ascended.up
actions.main+=/shadow_word_pain,if=buff.fae_guardians.up&!debuff.wrathful_faerie.up&spell_targets.mind_sear<4
actions.main+=/mind_sear,target_if=talent.searing_nightmare.enabled&spell_targets.mind_sear>variable.mind_sear_cutoff&!dot.shadow_word_pain.ticking&!cooldown.fiend.up&spell_targets.mind_sear>=4
actions.main+=/call_action_list,name=cds
actions.main+=/mind_sear,target_if=talent.searing_nightmare.enabled&spell_targets.mind_sear>variable.mind_sear_cutoff&!dot.shadow_word_pain.ticking&!cooldown.fiend.up
actions.main+=/damnation,target_if=(dot.vampiric_touch.refreshable|dot.shadow_word_pain.refreshable|(!buff.mind_devourer.up&insanity<50))&(buff.dark_thought.stack<buff.dark_thought.max_stack|!set_bonus.tier28_2pc)
actions.main+=/shadow_word_death,if=pet.fiend.active&runeforge.shadowflame_prism.equipped&pet.fiend.remains<=gcd&spell_targets.mind_sear<=7
actions.main+=/mind_blast,if=(cooldown.mind_blast.full_recharge_time<=gcd.max*2&(debuff.hungering_void.up|!talent.hungering_void.enabled)|pet.fiend.remains<=cast_time+gcd)&pet.fiend.active&runeforge.shadowflame_prism.equipped&pet.fiend.remains>cast_time&spell_targets.mind_sear<=7|buff.dark_thought.up&buff.voidform.up&!cooldown.void_bolt.up&(!runeforge.shadowflame_prism.equipped|!pet.fiend.active)&set_bonus.tier28_4pc
actions.main+=/mindgames,target_if=insanity<90&((variable.all_dots_up&(!cooldown.void_eruption.up|!variable.cd_management))|buff.voidform.up)&(!talent.hungering_void.enabled|debuff.hungering_void.remains>cast_time|!buff.voidform.up)
actions.main+=/void_bolt,if=talent.hungering_void&(insanity<=85&talent.searing_nightmare&spell_targets.mind_sear<=6|!talent.searing_nightmare|spell_targets.mind_sear=1)
actions.main+=/devouring_plague,if=(set_bonus.tier28_4pc|talent.hungering_void.enabled)&talent.searing_nightmare.enabled&pet.fiend.active&runeforge.shadowflame_prism.equipped&buff.voidform.up&spell_targets.mind_sear<=6
actions.main+=/devouring_plague,if=(refreshable|insanity>75|talent.void_torrent.enabled&cooldown.void_torrent.remains<=3*gcd&!buff.voidform.up|buff.voidform.up&(cooldown.mind_blast.charges_fractional<2|buff.mind_devourer.up))&(!variable.pool_for_cds|insanity>=85)&(!talent.searing_nightmare|!variable.searing_nightmare_cutoff)
actions.main+=/void_bolt,if=talent.hungering_void.enabled&(spell_targets.mind_sear<(4+conduit.dissonant_echoes.enabled)&insanity<=85&talent.searing_nightmare.enabled|!talent.searing_nightmare.enabled)
actions.main+=/shadow_word_death,target_if=(target.health.pct<20&spell_targets.mind_sear<4)|(pet.fiend.active&runeforge.shadowflame_prism.equipped&spell_targets.mind_sear<=7)
actions.main+=/surrender_to_madness,target_if=target.time_to_die<25&buff.voidform.down
actions.main+=/void_torrent,target_if=variable.dots_up&(buff.voidform.down|buff.voidform.remains<cooldown.void_bolt.remains|prev_gcd.1.void_bolt&!buff.bloodlust.react&spell_targets.mind_sear<3)&variable.vts_applied&spell_targets.mind_sear<(5+(6*talent.twist_of_fate.enabled))
actions.main+=/shadow_word_death,if=runeforge.painbreaker_psalm.equipped&variable.dots_up&target.time_to_pct_20>(cooldown.shadow_word_death.duration+gcd)
actions.main+=/shadow_crash,if=raid_event.adds.in>10
actions.main+=/mind_sear,target_if=spell_targets.mind_sear>variable.mind_sear_cutoff&buff.dark_thought.up,chain=1,interrupt_immediate=1,interrupt_if=ticks>=4
actions.main+=/mind_flay,if=buff.dark_thought.up&variable.dots_up&!buff.voidform.up&!variable.pool_for_cds&cooldown.mind_blast.full_recharge_time>=gcd.max,chain=1,interrupt_immediate=1,interrupt_if=ticks>=4&!buff.dark_thought.up
actions.main+=/mind_blast,if=variable.dots_up&raid_event.movement.in>cast_time+0.5&spell_targets.mind_sear<(4+2*talent.misery.enabled+active_dot.vampiric_touch*talent.psychic_link.enabled+(spell_targets.mind_sear>?5)*(pet.fiend.active&runeforge.shadowflame_prism.equipped))&(!runeforge.shadowflame_prism.equipped|!cooldown.fiend.up&runeforge.shadowflame_prism.equipped|variable.vts_applied)
actions.main+=/void_bolt,if=variable.dots_up
actions.main+=/vampiric_touch,target_if=refreshable&target.time_to_die>=18&(dot.vampiric_touch.ticking|!variable.vts_applied)&variable.max_vts>0|(talent.misery.enabled&dot.shadow_word_pain.refreshable)|buff.unfurling_darkness.up
actions.main+=/shadow_word_pain,if=refreshable&target.time_to_die>4&!talent.misery.enabled&talent.psychic_link.enabled&spell_targets.mind_sear>2
actions.main+=/shadow_word_pain,target_if=refreshable&target.time_to_die>4&!talent.misery.enabled&!(talent.searing_nightmare.enabled&spell_targets.mind_sear>variable.mind_sear_cutoff)&(!talent.psychic_link.enabled|(talent.psychic_link.enabled&spell_targets.mind_sear<=2))
actions.main+=/mind_sear,target_if=spell_targets.mind_sear>variable.mind_sear_cutoff,chain=1,interrupt_immediate=1,interrupt_if=ticks>=2
actions.main+=/mind_flay,chain=1,interrupt_immediate=1,interrupt_if=ticks>=2&(!buff.dark_thought.up|cooldown.void_bolt.up&(buff.voidform.up|!buff.dark_thought.up&buff.dissonant_echoes.up))
actions.main+=/shadow_word_death
actions.main+=/shadow_word_pain
]]
	if SearingNightmare.known and MindSear:Usable() and Player.enemies > self.mind_sear_cutoff and ShadowWordPain:Down() and not Player.fiend:Ready() and Player.enemies >= 4 then
		return MindSear
	end
	self:cds()
	if SearingNightmare.known and MindSear:Usable() and Player.enemies > self.mind_sear_cutoff and ShadowWordPain:Down() and not Player.fiend:Ready() then
		return MindSear
	end
	if Damnation:Usable() and (VampiricTouch:Refreshable() or ShadowWordPain:Refreshable() or (MindDevourer:Down() and Player.insanity.current < 50)) and (DarkThought:Stack() < 3 or Player.set_bonus.t28 < 2) then
		return Damnation
	end
	if ShadowflamePrism.known and ShadowWordDeath:Usable() and Player.fiend:Expiring() and Player.enemies <= 7 then
		return ShadowWordDeath
	end
	if MindBlast:Usable() and (
		(ShadowflamePrism.known and Player.fiend:Remains() > MindBlast:CastTime() and Player.enemies <= 7 and ((MindBlast:FullRechargeTime() <= (Player.gcd * 2) and (not HungeringVoid.known or HungeringVoid:Up())) or Player.fiend:Remains() <= (MindBlast:CastTime() + Player.gcd))) or
		(LivingShadow.known and DarkThought:Up() and Voidform:Up() and not VoidBolt:Ready() and (not ShadowflamePrism.known or not Player.fiend:Up()))
	) then
		return MindBlast
	end
	if HungeringVoid.known and VoidBolt:Usable() and (not SearingNightmare.known or Player.enemies == 1 or (Player.insanity.current <= 85 and Player.enemies <= 6)) then
		return VoidBolt
	end
	if DevouringPlague:Usable() and (
		((LivingShadow.known or HungeringVoid.known) and SearingNightmare.known and ShadowflamePrism.known and Player.enemies <= 6 and Player.fiend:Up() and Voidform:Up()) or
		((not self.pool_for_cds or Player.insanity.current >= 85) and (not SearingNightmare.known or not self.searing_nightmare_cutoff) and (DevouringPlague:Refreshable() or Player.insanity.current > 75 or (VoidTorrent.known and VoidTorrent:Ready(Player.gcd * 3) and Voidform:Down()) or (Voidform:Up() and (MindBlast:ChargesFractional() < 2 or MindDevourer:Up()))))
	) then
		return DevouringPlague
	end
	if HungeringVoid.known and VoidBolt:Usable() and (not SearingNightmare.known or (Player.enemies < (4 + (DissonantEchoes.known and 1 or 0)) and Player.insanity.current <= 85)) then
		return VoidBolt
	end
	if ShadowWordDeath:Usable() and ((Target.health.pct < 20 and Player.enemies < 4) or (ShadowflamePrism.known and Player.enemies <= 7 and Player.fiend:Up())) then
		return ShadowWordDeath
	end
	if SurrenderToMadness:Usable() and Target.timeToDie < 25 and Voidform:Down() then
		UseCooldown(SurrenderToMadness)
	end
	if VoidTorrent:Usable() and self.dots_up and self.vts_applied and Player.enemies < (5 + (TwistOfFate.known and 6 or 0)) and (Voidform:Down() or Voidform:Remains() < VoidBolt:Cooldown() or (VoidBolt:Previous() and not Player:BloodlustActive() and Player.enemies < 3)) then
		UseCooldown(VoidTorrent)
	end
	if ShadowWordDeath:Usable() and PainbreakerPsalm.known and self.dots_up and Target:TimeToPct(20) > (ShadowWordDeath:CooldownDuration() + Player.gcd) then
		return ShadowWordDeath
	end
	if ShadowCrash:Usable() then
		UseCooldown(ShadowCrash)
	end
	if MindSear:Usable() and Player.enemies > self.mind_sear_cutoff and DarkThought:Up() then
		return MindSear
	end
	if MindFlay:Usable() and DarkThought:Up() and self.dots_up and Voidform:Down() and not self.pool_for_cds and MindBlast:FullRechargeTime() >= Player.gcd then
		return MindFlay
	end
	if MindBlast:Usable() and self.dots_up and Player.enemies < (4 + (Misery.known and 2 or 0) + (PsychicLink.known and VampiricTouch:Ticking() or 0) + (ShadowflamePrism.known and Player.fiend:Up() and min(5, Player.enemies) or 0)) and (not ShadowflamePrism.known or self.vts_applied or not Player.fiend:Ready()) then
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
		(not (SearingNightmare.known and Player.enemies > self.mind_sear_cutoff) and (not PsychicLink.known or (PsychicLink.known and Player.enemies <= 2)))
	) then
		return ShadowWordPain
	end
	if not Player.moving then
		if MindSear:Usable() and Player.enemies > self.mind_sear_cutoff then
			return MindSear
		end
		if MindFlay:Usable() then
			return MindFlay
		end
	end
	if ShadowWordDeath:Usable() then
		return ShadowWordDeath
	end
	if ShadowWordPain:Usable() then
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
	local w, h, glow
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
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.DISCIPLINE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.SHADOW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		}
	},
	kui = { -- Kui Nameplates
		[SPEC.DISCIPLINE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[SPEC.SHADOW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
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

function UI:UpdateDisplay()
	timer.display = 0
	local dim, dim_cd, text_center, text_cd

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main and Player.main.requires_react then
		local react = Player.main:React()
		if react > 0 then
			text_center = format('%.1f', react)
		end
	end
	if Player.cd and Player.cd.requires_react then
		local react = Player.cd:React()
		if react > 0 then
			text_cd = format('%.1f', react)
		end
	end
	if Player.main and Player.main_freecast then
		if not propheticPanel.freeCastOverlayOn then
			propheticPanel.freeCastOverlayOn = true
			propheticPanel.border:SetTexture(ADDON_PATH .. 'freecast.blp')
		end
	elseif propheticPanel.freeCastOverlayOn then
		propheticPanel.freeCastOverlayOn = false
		propheticPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
	end

	propheticPanel.dimmer:SetShown(dim)
	propheticPanel.text.center:SetText(text_center)
	--propheticPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	propheticCooldownPanel.text:SetText(text_cd)
	propheticCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL[Player.spec]:Main()
	if Player.main then
		propheticPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.mana_cost > 0 and Player.main:Cost() == 0) or (Player.main.insanity_cost > 0 and Player.main:InsanityCost() == 0)
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
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Prophetic
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Prophetic1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
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
		autoAoe:Remove(dstGUID)
	end
	local pet = summonedPets:Find(dstGUID)
	if pet then
		pet:RemoveUnit(dstGUID)
	end
end

CombatEvent.SPELL_SUMMON = function(event, srcGUID, dstGUID)
	if srcGUID ~= Player.guid then
		return
	end
	local pet = summonedPets:Find(dstGUID)
	if pet then
		pet:AddUnit(dstGUID)
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	local pet = summonedPets:Find(srcGUID)
	if pet then
		local unit = pet.active_units[srcGUID]
		if unit then
			if event == 'SPELL_CAST_SUCCESS' and pet.CastSuccess then
				pet:CastSuccess(unit, spellId, dstGUID)
			elseif event == 'SPELL_CAST_START' and pet.CastStart then
				pet:CastStart(unit, spellId, dstGUID)
			elseif event == 'SPELL_CAST_FAILED' and pet.CastFailed then
				pet:CastFailed(unit, spellId, dstGUID, missType)
			elseif event == 'SPELL_DAMAGE' and pet.SpellDamage then
				pet:SpellDamage(unit, spellId, dstGUID)
			end
			--print(format('PET %d EVENT %s SPELL %s ID %d', pet.npcId, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		end
		return
	end

	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability:CastFailed(dstGUID, missType)
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
		if ability == VirulentPlague and eventType == 'SPELL_PERIODIC_DAMAGE' and not ability.aura_targets[dstGUID] then
			ability:ApplyAura(dstGUID) -- BUG: VP tick on unrecorded target, assume freshly applied (possibly by Raise Abomination?)
		end
	end
	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
	if Player.rescan_abilities then
		Player:UpdateAbilities()
	end
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

function events:UNIT_SPELLCAST_START(unitID, castGUID, spellId)
	if Opt.interrupt and unitID == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(unitID, castGUID, spellId)
	if Opt.interrupt and unitID == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
events.UNIT_SPELLCAST_FAILED = events.UNIT_SPELLCAST_STOP
events.UNIT_SPELLCAST_INTERRUPTED = events.UNIT_SPELLCAST_STOP

function events:UNIT_SPELLCAST_SENT(unitId, destName, castGUID, spellId)
	if unitID ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
end

function events:UNIT_SPELLCAST_SUCCEEDED(unitID, castGUID, spellId)
	if unitID ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		propheticPreviousPanel:Hide()
	end
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
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
	Player:UpdateEquipment()
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	propheticPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	UI.OnResourceFrameShow()
	Player:Update()
end

function events:SPELL_UPDATE_COOLDOWN()
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

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:SOULBIND_ACTIVATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_NODE_UPDATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_PATH_CHANGED()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = max(1, min(40, GetNumGroupMembers()))
end

function events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() events:PLAYER_EQUIPMENT_CHANGED() end)
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
for event in next, events do
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
	print(ADDON, '-', desc .. ':', opt_view, ...)
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
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra/Pet cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(0, min(100, tonumber(msg[2]) or 100)) / 100
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
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra/pet cooldown icon)', Opt.glow.extra)
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
				Opt.glow.color.r = max(0, min(1, tonumber(msg[3]) or 0))
				Opt.glow.color.g = max(0, min(1, tonumber(msg[4]) or 0))
				Opt.glow.color.b = max(0, min(1, tonumber(msg[5]) or 0))
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
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
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
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
		'pws |cFFFFD000[percent]|r - health percentage threshold to recommend Power Word: Shield',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Prophetic1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands 
