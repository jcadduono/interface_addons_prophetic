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

local function InitializeOpts()
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
			shadow = false
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
		pws_threshold = 60,
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	DISCIPLINE = 1,
	HOLY = 2,
	SHADOW = 3
}

local events, glows = {}, {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

local currentSpec, targetMode, combatStartTime = 0, 0, 0

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

-- list of previous GCD abilities
local PreviousGCD = {}

-- items equipped with special effects
local ItemEquipped = {

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

local var = {
	gcd = 1.5,
	time_diff = 0,
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
propheticPanel.text = propheticPanel:CreateFontString(nil, 'OVERLAY')
propheticPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 10, 'OUTLINE')
propheticPanel.text:SetTextColor(1, 1, 1, 1)
propheticPanel.text:SetAllPoints(propheticPanel)
propheticPanel.text:SetJustifyH('CENTER')
propheticPanel.text:SetJustifyV('CENTER')
propheticPanel.swipe = CreateFrame('Cooldown', nil, propheticPanel, 'CooldownFrameTemplate')
propheticPanel.swipe:SetAllPoints(propheticPanel)
propheticPanel.dimmer = propheticPanel:CreateTexture(nil, 'BORDER')
propheticPanel.dimmer:SetAllPoints(propheticPanel)
propheticPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
propheticPanel.dimmer:Hide()
propheticPanel.targets = propheticPanel:CreateFontString(nil, 'OVERLAY')
propheticPanel.targets:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
propheticPanel.targets:SetPoint('BOTTOMRIGHT', propheticPanel, 'BOTTOMRIGHT', -1.5, 3)
propheticPanel.button = CreateFrame('Button', 'propheticPanelButton', propheticPanel)
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

-- Start Auto AoE

local targetModes = {
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

local function SetTargetMode(mode)
	if mode == targetMode then
		return
	end
	targetMode = min(mode, #targetModes[currentSpec])
	var.enemy_count = targetModes[currentSpec][targetMode][1]
	propheticPanel.targets:SetText(targetModes[currentSpec][targetMode][2])
end
Prophetic_SetTargetMode = SetTargetMode

function ToggleTargetMode()
	local mode = targetMode + 1
	SetTargetMode(mode > #targetModes[currentSpec] and 1 or mode)
end
Prophetic_ToggleTargetMode = ToggleTargetMode

local function ToggleTargetModeReverse()
	local mode = targetMode - 1
	SetTargetMode(mode < 1 and #targetModes[currentSpec] or mode)
end
Prophetic_ToggleTargetModeReverse = ToggleTargetModeReverse

local autoAoe = {
	targets = {},
	blacklist = {}
}

function autoAoe:add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = var.time
	if update and new then
		self:update()
	end
end

function autoAoe:remove(guid)
	self.blacklist[guid] = var.time
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:clear(guid)
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		SetTargetMode(1)
		return
	end
	var.enemy_count = count
	for i = #targetModes[currentSpec], 1, -1 do
		if count >= targetModes[currentSpec][i][1] then
			SetTargetMode(i)
			var.enemy_count = count
			return
		end
	end
end

function autoAoe:purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if var.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	for guid, t in next, self.blacklist do
		if var.time - t > 2 then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability.add(spellId, buff, player, spellId2)
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
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable()
	if not self.known then
		return false
	end
	if self:cost() > var.mana then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready()
end

function Ability:remains()
	if self:traveling() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - var.time - var.execute_remains, 0)
		end
	end
	return 0
end

function Ability:refreshable()
	if self.buff_duration > 0 then
		return self:remains() < self:duration() * 0.3
	end
	return self:down()
end

function Ability:up()
	if self:traveling() then
		return true
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if self:match(id) then
			return expires == 0 or expires - var.time > var.execute_remains
		end
	end
end

function Ability:down()
	return not self:up()
end

function Ability:setVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if var.time - self.travel_start[Target.guid] < 40 / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - (var.time - var.time_diff) > var.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (var.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (var.time - start) - var.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			return (expires == 0 or expires - var.time > var.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * var.mana_base) or 0
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:chargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, var.time - recharge_start + var.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (var.time - recharge_start) - var.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return var.ability_casting == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and var.gcd or 0
	end
	return castTime / 1000
end

function Ability:castRegen()
	return var.mana_regen * self:castTime() - self:cost()
end

function Ability:tickTime()
	return self.hasted_ticks and (var.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:previous()
	if self:casting() or self:channeling() then
		return true
	end
	return PreviousGCD[1] == self or var.last_ability == self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:autoAoe()
	self.auto_aoe = true
	self.first_hit_time = nil
	self.targets_hit = {}
end

function Ability:recordTargetHit(guid)
	self.targets_hit[guid] = var.time
	if not self.first_hit_time then
		self.first_hit_time = self.targets_hit[guid]
	end
end

function Ability:updateTargetsHit()
	if self.first_hit_time and var.time - self.first_hit_time >= 0.3 then
		self.first_hit_time = nil
		autoAoe:clear()
		local guid
		for guid in next, self.targets_hit do
			autoAoe:add(guid)
			self.targets_hit[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:purge()
	local now = var.time - var.time_diff
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= now then
				ability:removeAura(guid)
			end
		end
	end
end

function trackAuras:remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:removeAura(guid)
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
end

function Ability:applyAura(timeStamp, guid)
	local aura = {
		expires = timeStamp + self:duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:refreshAura(timeStamp, guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(timeStamp, guid)
		return
	end
	local remains = aura.expires - timeStamp
	local duration = self:duration()
	aura.expires = timeStamp + min(duration * 1.3, remains + duration)
end

function Ability:removeAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Priest Abilities
---- Multiple Specializations
local DesperatePrayer = Ability.add(19236, true, true)
DesperatePrayer.buff_duration = 10
DesperatePrayer.cooldown_duration = 90
local DispelMagic = Ability.add(528, false, true)
DispelMagic.mana_cost = 1.6
local Fade = Ability.add(586, false, true)
Fade.buff_duration = 10
Fade.cooldown_duration = 30
local HolyNova = Ability.add(132157, false, true, 281265)
HolyNova.mana_cost = 1.6
HolyNova:autoAoe()
local LeapOfFaith = Ability.add(73325, false, true)
LeapOfFaith.mana_cost = 2.6
LeapOfFaith.cooldown_duration = 90
local Levitate = Ability.add(1706, true, false, 111759)
Levitate.mana_cost = 0.9
Levitate.buff_duration = 600
local Lightspawn = Ability.add(254224, false, true)
Lightspawn.cooldown_duration = 180
local MassDispel = Ability.add(32375, true, true)
MassDispel.mana_cost = 8
MassDispel.cooldown_duration = 45
local MindControl = Ability.add(605, false, true)
MindControl.mana_cost = 2
MindControl.buff_duration = 30
local PowerWordFortitude = Ability.add(21562, true, false)
PowerWordFortitude.mana_cost = 4
PowerWordFortitude.buff_duration = 3600
local Purify = Ability.add(527, true, true)
Purify.mana_cost = 1.3
Purify.cooldown_duration = 8
local Shadowfiend = Ability.add(34433, false, true)
Shadowfiend.cooldown_duration = 180
local ShadowWordPain = Ability.add(589, false, true)
ShadowWordPain.mana_cost = 1.8
ShadowWordPain.buff_duration = 16
ShadowWordPain.tick_interval = 2
ShadowWordPain.hasted_ticks = true
local Smite = Ability.add(585, false, true, 208772)
Smite.mana_cost = 0.5
------ Talents
local DivineStar = Ability.add(110744, false, true, 110745)
DivineStar.mana_cost = 2
DivineStar.cooldown_duration = 15
DivineStar:autoAoe()
local Halo = Ability.add(120517, false, true, 120692)
Halo.mana_cost = 2.7
Halo.cooldown_duration = 40
local ShiningForce = Ability.add(204263, false, true)
ShiningForce.cooldown_duration = 45
ShiningForce.buff_duration = 3
------ Procs

---- Discipline
local Atonement = Ability.add(81749, true, true, 194384)
Atonement.buff_duration = 15
local PainSuppression = Ability.add(33206, true, true)
PainSuppression.mana_cost = 1.6
PainSuppression.buff_duration = 8
PainSuppression.cooldown_duration = 180
local Penance = Ability.add(47540, false, true, 47666)
Penance.mana_cost = 2
Penance.buff_duration = 2
Penance.cooldown_duration = 9
Penance.hasted_duration = true
local PowerWordBarrier = Ability.add(62618, true, true, 81782)
PowerWordBarrier.mana_cost = 4
PowerWordBarrier.buff_duration = 10
PowerWordBarrier.cooldown_duration = 180
local PowerWordRadiance = Ability.add(194509, true, true)
PowerWordRadiance.mana_cost = 6.5
PowerWordRadiance.cooldown_duration = 20
PowerWordRadiance.requires_charge = true
local PowerWordShield = Ability.add(17, true, true)
PowerWordShield.mana_cost = 2.65
PowerWordShield.buff_duration = 15
local Rapture = Ability.add(47536, true, true)
Rapture.buff_duration = 10
Rapture.cooldown_duration = 90
local ShadowMend = Ability.add(186263, false, true)
ShadowMend.buff_duration = 10
local WeakenedSoul = Ability.add(6788, false, true)
WeakenedSoul.buff_duration = 6
WeakenedSoul.auraTarget = 'player'
------ Talents
local PurgeTheWicked = Ability.add(204197, false, true, 204213)
PurgeTheWicked.buff_duration = 20
PurgeTheWicked.mana_cost = 1.8
PurgeTheWicked.tick_interval = 2
PurgeTheWicked.hasted_ticks = true
local PowerWordSolace = Ability.add(129250, false, true)
PowerWordSolace.mana_cost = -1
local Schism = Ability.add(214621, false, true)
Schism.buff_duration = 9
Schism.cooldown_duration = 24
Schism.mana_cost = 0.5
local SearingLight = Ability.add(215768, false, true)
local MindbenderDisc = Ability.add(123040, false, true)
------ Procs

---- Holy
local HolyFire = Ability.add(14914, false, true)
local HolyWordChastise = Ability.add(88625, false, true)
local Renew = Ability.add(139, true, true)
Renew.mana_cost = 1.8
Renew.buff_duration = 15
Renew.tick_interval = 2
Renew.hasted_ticks = true
------ Talents

------ Procs

---- Shadow
local Dispersion = Ability.add(47585, true, true)
local Silence = Ability.add(15487, false, true)
Silence.cooldown_duration = 45
Silence.buff_duration = 4
local Voidform = Ability.add(194249, true, true)
------ Talents
local MindbenderShadow = Ability.add(200174, false, true)
------ Procs

-- Azerite Traits

-- Racials
local ArcaneTorrent = Ability.add(232633, true, false) -- Blood Elf
ArcaneTorrent.mana_cost = -3
ArcaneTorrent.insanity_gain = 15
ArcaneTorrent.triggers_gcd = false
-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems = {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration = GetItemCooldown(self.itemId)
	return startTime == 0 and 0 or duration - (var.time - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:usable(seconds)
	if self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local FlaskOfEndlessFathoms = InventoryItem.add(152693)
FlaskOfEndlessFathoms.buff = Ability.add(251837, true, true)
local BattlePotionOfIntellect = InventoryItem.add(163222)
BattlePotionOfIntellect.buff = Ability.add(279151, true, true)
BattlePotionOfIntellect.buff.triggers_gcd = false
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:initialize()
	self.locations = {}
	self.traits = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:update()
	local _, loc, tinfo, tslot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			tinfo = C_AzeriteEmpoweredItem.GetAllTierInfo(loc)
			for _, tslot in next, tinfo do
				if tslot.azeritePowerIDs then
					for _, pid in next, tslot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
end

-- End Azerite Trait API

-- Start Helpful Functions

local function Health()
	return var.health
end

local function HealthMax()
	return var.health_max
end

local function HealthPct()
	return var.health / var.health_max * 100
end

local function Mana()
	return var.mana
end

local function ManaMax()
	return var.mana_max
end

local function ManaPct()
	return var.mana / var.mana_max * 100
end

local function ManaRegen()
	return var.mana_regen
end

local function ManaTimeToMax()
	local deficit = var.mana_max - var.mana
	if deficit <= 0 then
		return 0
	end
	return deficit / var.mana_regen
end

local function GCD()
	return var.gcd
end

local function Enemies()
	return var.enemy_count
end

local function TimeInCombat()
	if combatStartTime > 0 then
		return var.time - combatStartTime
	end
	if var.ability_casting then
		return 0.1
	end
	return 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or	-- Bloodlust (Horde Shaman)
			id == 32182 or	-- Heroism (Alliance Shaman)
			id == 80353 or	-- Time Warp (Mage)
			id == 90355 or	-- Ancient Hysteria (Hunter Pet - Core Hound)
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

local function PlayerIsMoving()
	return GetUnitSpeed('player') ~= 0
end

local function TargetIsStunnable()
	if Target.player then
		return true
	end
	if Target.boss then
		return false
	end
	if var.instance == 'raid' then
		return false
	end
	if Target.health_max > var.health_max * 10 then
		return false
	end
	return true
end

local function InArenaOrBattleground()
	return var.instance == 'arena' or var.instance == 'pvp'
end

-- End Helpful Functions

-- Start Ability Modifications

function PowerWordShield:usable()
	if WeakenedSoul:up() then
		return false
	end
	return Ability.usable(self)
end

function Penance:cooldown()
	local remains = Ability.cooldown(self)
	if SearingLight.known and Smite:casting() then
		remains = max(remains - 1, 0)
	end
	return remains
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite, always)
	if always or (Opt.cooldown and (not Opt.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not var.extra or overwrite then
		var.extra = ability
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
	if TimeInCombat() == 0 then
		if PowerWordFortitude:usable() and PowerWordFortitude:remains() < 300 then
			return PowerWordFortitude
		end
	else
		if PowerWordFortitude:down() and PowerWordFortitude:usable() then
			UseExtra(PowerWordFortitude)
		end
	end
	if HealthPct() < 30 and DesperatePrayer:usable() then
		UseExtra(DesperatePrayer)
	elseif (HealthPct() < Opt.pws_threshold or Atonement:remains() < GCD()) and PowerWordShield:usable() then
		UseExtra(PowerWordShield)
	end
	if var.swp:usable() and var.swp:down() and Target.timeToDie > 4 then
		return var.swp
	end
	if Schism:usable() and not PlayerIsMoving() and Target.timeToDie > 4 then
		return Schism
	end
	if ManaPct() < 95 and PowerWordSolace:usable() then
		return PowerWordSolace
	end
	if Penance:usable() then
		return Penance
	end
	if var.swp:usable() and var.swp:refreshable() and Target.timeToDie > var.swp:remains() + 4 then
		return var.swp
	end
	if PowerWordSolace:usable() then
		return PowerWordSolace
	end
	if DivineStar:usable() then
		UseCooldown(DivineStar)
	end
	if Shadowfiend:usable() and Target.timeToDie > 15 then
		UseCooldown(Shadowfiend)
	end
	if PlayerIsMoving() and var.swp:usable() and var.swp:refreshable() then
		return var.swp
	end
	if Schism:usable() and Target.timeToDie > 4 then
		return Schism
	end
	return Smite
end

APL[SPEC.HOLY].main = function(self)
	if TimeInCombat() == 0 then
		if PowerWordFortitude:usable() and PowerWordFortitude:remains() < 300 then
			return PowerWordFortitude
		end
	else
		if PowerWordFortitude:down() and PowerWordFortitude:usable() then
			UseExtra(PowerWordFortitude)
		end
	end
end

APL[SPEC.SHADOW].main = function(self)
	if TimeInCombat() == 0 then
		if PowerWordFortitude:usable() and PowerWordFortitude:remains() < 300 then
			return PowerWordFortitude
		end
	else
		if PowerWordFortitude:down() and PowerWordFortitude:usable() then
			UseExtra(PowerWordFortitude)
		end
	end
end

APL.Interrupt = function(self)
	if Silence:usable() then
		return Silence
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start then
		_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
	end
	if not start or notInterruptible then
		var.interrupt = nil
		propheticInterruptPanel:Hide()
		return
	end
	var.interrupt = APL.Interrupt()
	if var.interrupt then
		propheticInterruptPanel.icon:SetTexture(var.interrupt.icon)
		propheticInterruptPanel.icon:Show()
		propheticInterruptPanel.border:Show()
	else
		propheticInterruptPanel.icon:Hide()
		propheticInterruptPanel.border:Hide()
	end
	propheticInterruptPanel:Show()
	propheticInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
end

local function DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
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

local function CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			glows[#glows + 1] = glow
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
	UpdateGlowColorAndScale()
end

local function UpdateGlows()
	local glow, icon, i
	for i = 1, #glows do
		glow = glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and var.main and icon == var.main.icon) or
			(Opt.glow.cooldown and var.cd and icon == var.cd.icon) or
			(Opt.glow.interrupt and var.interrupt and icon == var.interrupt.icon) or
			(Opt.glow.extra and var.extra and icon == var.extra.icon)
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

function events:ACTIONBAR_SLOT_CHANGED()
	UpdateGlows()
end

local function ShouldHide()
	return (currentSpec == SPEC.NONE or
		   (currentSpec == SPEC.DISCIPLINE and Opt.hide.discipline) or
		   (currentSpec == SPEC.HOLY and Opt.hide.holy) or
		   (currentSpec == SPEC.SHADOW and Opt.hide.shadow))
end

local function Disappear()
	propheticPanel:Hide()
	propheticPanel.icon:Hide()
	propheticPanel.border:Hide()
	propheticPanel.text:Hide()
	propheticCooldownPanel:Hide()
	propheticInterruptPanel:Hide()
	propheticExtraPanel:Hide()
	var.main, var.last_main = nil
	var.cd, var.last_cd = nil
	var.interrupt = nil
	var.extra, var.last_extra = nil
	UpdateGlows()
end

function Equipped(name, slot)
	local function SlotMatches(name, slot)
		local ilink = GetInventoryItemLink('player', slot)
		if ilink then
			local iname = ilink:match('%[(.*)%]')
			return (iname and iname:find(name))
		end
		return false
	end
	if slot then
		return SlotMatches(name, slot)
	end
	local i
	for i = 1, 19 do
		if SlotMatches(name, i) then
			return true
		end
	end
	return false
end

local function UpdateDraggable()
	propheticPanel:EnableMouse(Opt.aoe or not Opt.locked)
	if Opt.aoe then
		propheticPanel.button:Show()
	else
		propheticPanel.button:Hide()
	end
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

local function SnapAllPanels()
	propheticPreviousPanel:ClearAllPoints()
	propheticPreviousPanel:SetPoint('BOTTOMRIGHT', propheticPanel, 'BOTTOMLEFT', -10, -5)
	propheticCooldownPanel:ClearAllPoints()
	propheticCooldownPanel:SetPoint('BOTTOMLEFT', propheticPanel, 'BOTTOMRIGHT', 10, -5)
	propheticInterruptPanel:ClearAllPoints()
	propheticInterruptPanel:SetPoint('TOPLEFT', propheticPanel, 'TOPRIGHT', 16, 25)
	propheticExtraPanel:ClearAllPoints()
	propheticExtraPanel:SetPoint('TOPRIGHT', propheticPanel, 'TOPLEFT', -16, 25)
end

local resourceAnchor = {}

local ResourceFramePoints = {
	['blizzard'] = {
		[SPEC.DISCIPLINE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -28 }
		},
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.SHADOW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		}
	},
	['kui'] = {
		[SPEC.DISCIPLINE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.SHADOW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		}
	},
}

local function OnResourceFrameHide()
	if Opt.snap then
		propheticPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if Opt.snap then
		propheticPanel:ClearAllPoints()
		local p = ResourceFramePoints[resourceAnchor.name][currentSpec][Opt.snap]
		propheticPanel:SetPoint(p[1], resourceAnchor.frame, p[2], p[3], p[4])
		SnapAllPanels()
	end
end

local function HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		resourceAnchor.name = 'kui'
		resourceAnchor.frame = KuiNameplatesPlayerAnchor
	else
		resourceAnchor.name = 'blizzard'
		resourceAnchor.frame = ClassNameplateManaBarFrame
	end
	resourceAnchor.frame:HookScript("OnHide", OnResourceFrameHide)
	resourceAnchor.frame:HookScript("OnShow", OnResourceFrameShow)
end

local function UpdateAlpha()
	propheticPanel:SetAlpha(Opt.alpha)
	propheticPreviousPanel:SetAlpha(Opt.alpha)
	propheticCooldownPanel:SetAlpha(Opt.alpha)
	propheticInterruptPanel:SetAlpha(Opt.alpha)
	propheticExtraPanel:SetAlpha(Opt.alpha)
end

local function UpdateTargetHealth()
	timer.health = 0
	Target.health = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[15] = Target.health
	Target.timeToDieMax = Target.health / UnitHealthMax('player') * 20
	Target.healthPercentage = Target.healthMax > 0 and (Target.health / Target.healthMax * 100) or 100
	Target.healthLostPerSec = (Target.healthArray[1] - Target.health) / 3
	Target.timeToDie = Target.healthLostPerSec > 0 and min(Target.timeToDieMax, Target.health / Target.healthLostPerSec) or Target.timeToDieMax
end

local function UpdateDisplay()
	timer.display = 0
	if Opt.dimmer then
		if not var.main then
			propheticPanel.dimmer:Hide()
		elseif var.main.spellId and IsUsableSpell(var.main.spellId) then
			propheticPanel.dimmer:Hide()
		elseif var.main.itemId and IsUsableItem(var.main.itemId) then
			propheticPanel.dimmer:Hide()
		else
			propheticPanel.dimmer:Show()
		end
	end
end

local function UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	var.time = GetTime()
	var.last_main = var.main
	var.last_cd = var.cd
	var.last_extra = var.extra
	var.main =  nil
	var.cd = nil
	var.extra = nil
	start, duration = GetSpellCooldown(61304)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	var.ability_casting = abilities.bySpellId[spellId]
	var.execute_remains = max(remains and (remains / 1000 - var.time) or 0, var.gcd_remains)
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	var.gcd = 1.5 * var.haste_factor
	var.health = UnitHealth('player')
	var.health_max = UnitHealthMax('player')
	var.mana_regen = GetPowerRegen()
	var.mana = UnitPower('player', 0) + (var.mana_regen * var.execute_remains)
	var.mana_max = UnitPowerMax('player', 0)
	if var.ability_casting then
		var.mana = var.mana - var.ability_casting:cost()
	end
	var.mana = min(max(var.mana, 0), var.mana_max)

	trackAuras:purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:updateTargetsHit()
		end
		autoAoe:purge()
	end

	var.main = APL[currentSpec]:main()
	if var.main ~= var.last_main then
		if var.main then
			propheticPanel.icon:SetTexture(var.main.icon)
			propheticPanel.icon:Show()
			propheticPanel.border:Show()
		else
			propheticPanel.icon:Hide()
			propheticPanel.border:Hide()
		end
	end
	if var.cd ~= var.last_cd then
		if var.cd then
			propheticCooldownPanel.icon:SetTexture(var.cd.icon)
			propheticCooldownPanel:Show()
		else
			propheticCooldownPanel:Hide()
		end
	end
	if var.extra ~= var.last_extra then
		if var.extra then
			propheticExtraPanel.icon:SetTexture(var.extra.icon)
			propheticExtraPanel:Show()
		else
			propheticExtraPanel:Hide()
		end
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
	UpdateDisplay()
end

local function UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local start, duration
		local _, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
			if start <= 0 then
				return propheticPanel.swipe:Hide()
			end
		end
		propheticPanel.swipe:SetCooldown(start, duration)
		propheticPanel.swipe:Show()
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'DISCIPLINE_CHARGES' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:ADDON_LOADED(name)
	if name == 'Prophetic' then
		Opt = Prophetic
		if not Opt.frequency then
			print('It looks like this is your first time running Prophetic, why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Prophetic1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] Prophetic is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitializeOpts()
		Azerite:initialize()
		UpdateDraggable()
		UpdateAlpha()
		SnapAllPanels()
		propheticPanel:SetScale(Opt.scale.main)
		propheticPreviousPanel:SetScale(Opt.scale.previous)
		propheticCooldownPanel:SetScale(Opt.scale.cooldown)
		propheticInterruptPanel:SetScale(Opt.scale.interrupt)
		propheticExtraPanel:SetScale(Opt.scale.extra)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName, spellSchool, extraType = CombatLogGetCurrentEventInfo()
	var.time = GetTime()
	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:remove(dstGUID)
		end
	end
	if Opt.auto_aoe and (eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED') then
		if dstGUID == var.player then
			autoAoe:add(srcGUID, true)
		elseif srcGUID == var.player then
			autoAoe:add(dstGUID, true)
		end
	end
	if srcGUID ~= var.player or not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_HEAL' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end
	local castedAbility = abilities.bySpellId[spellId]
	if not castedAbility then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end
--[[ DEBUG ]
	print(format('EVENT %s TRACK CHECK FOR %s ID %d', eventType, spellName, spellId))
	if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' or eventType == 'SPELL_PERIODIC_DAMAGE' or eventType == 'SPELL_DAMAGE' then
		print(format('%s: %s - time: %.2f - time since last: %.2f', eventType, spellName, timeStamp, timeStamp - (castedAbility.last_trigger or timeStamp)))
		castedAbility.last_trigger = timeStamp
	end
--[ DEBUG ]]
	var.time_diff = var.time - timeStamp
	UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		var.last_ability = castedAbility
		castedAbility.last_used = var.time
		if castedAbility.triggers_gcd then
			PreviousGCD[10] = nil
			table.insert(PreviousGCD, 1, castedAbility)
		end
		if castedAbility.travel_start then
			castedAbility.travel_start[dstGUID] = var.time
		end
		if Opt.previous and propheticPanel:IsVisible() then
			propheticPreviousPanel.ability = castedAbility
			propheticPreviousPanel.border:SetTexture('Interface\\AddOns\\Prophetic\\border.blp')
			propheticPreviousPanel.icon:SetTexture(castedAbility.icon)
			propheticPreviousPanel:Show()
		end
		return
	end
	if castedAbility.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			castedAbility:applyAura(timeStamp, dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			castedAbility:refreshAura(timeStamp, dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			castedAbility:removeAura(dstGUID)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if castedAbility.travel_start and castedAbility.travel_start[dstGUID] then
			castedAbility.travel_start[dstGUID] = nil
		end
		if Opt.auto_aoe then
			if castedAbility.auto_aoe then
				castedAbility:recordTargetHit(dstGUID)
			end
			if castedAbility == Ignite and (eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH') then
				autoAoe:add(dstGUID, true)
			end
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and propheticPanel:IsVisible() and castedAbility == propheticPreviousPanel.ability then
			propheticPreviousPanel.border:SetTexture('Interface\\AddOns\\Prophetic\\misseffect.blp')
		end
	end
end

local function UpdateTargetInfo()
	Disappear()
	if ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		Target.guid = nil
		Target.player = false
		Target.boss = false
		Target.hostile = true
		Target.healthMax = 0
		Target.freezable = '?'
		local i
		for i = 1, 15 do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateTargetHealth()
			UpdateCombat()
			propheticPanel:Show()
			return true
		end
		if Opt.previous and combatStartTime == 0 then
			propheticPreviousPanel:Hide()
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		Target.freezable = '?'
		local i
		for i = 1, 15 do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.level = UnitLevel('target')
	Target.healthMax = UnitHealthMax('target')
	Target.player = UnitIsPlayer('target')
	if Target.player then
		Target.boss = false
	elseif Target.level == -1 then
		Target.boss = true
	elseif var.instance == 'party' and Target.level >= UnitLevel('player') + 2 then
		Target.boss = true
	else
		Target.boss = false
	end
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or Opt.always_on then
		UpdateTargetHealth()
		UpdateCombat()
		propheticPanel:Show()
		return true
	end
end

function events:PLAYER_TARGET_CHANGED()
	UpdateTargetInfo()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:PLAYER_REGEN_DISABLED()
	combatStartTime = GetTime()
end

function events:PLAYER_REGEN_ENABLED()
	combatStartTime = 0
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for guid in next, autoAoe.targets do
			autoAoe.targets[guid] = nil
		end
		SetTargetMode(1)
	end
	if var.last_ability then
		var.last_ability = nil
		propheticPreviousPanel:Hide()
	end
end

local function UpdateAbilityData()
	var.mana_base = BaseMana[UnitLevel('player')]
	local _, ability
	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = (IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) or Azerite.traits[ability.spellId]) and true or false
	end
	Lightspawn.known = Shadowfiend.known
	if currentSpec == SPEC.DISCIPLINE then
		var.swp = PurgeTheWicked.known and PurgeTheWicked or ShadowWordPain
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

function events:PLAYER_EQUIPMENT_CHANGED()
	Azerite:update()
	UpdateAbilityData()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		currentSpec = GetSpecialization() or 0
		Azerite:update()
		UpdateAbilityData()
		local _, i
		for i = 1, #inventoryItems do
			inventoryItems[i].name, _, _, _, _, _, _, _, _, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId)
		end
		propheticPreviousPanel.ability = nil
		PreviousGCD = {}
		SetTargetMode(1)
		UpdateTargetInfo()
		events:PLAYER_REGEN_ENABLED()
	end
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, var.instance = IsInInstance()
	var.player = UnitGUID('player')
end

propheticPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			ToggleTargetMode()
		elseif button == 'RightButton' then
			ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			SetTargetMode(1)
		end
	end
end)

propheticPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UpdateCombat()
	end
	if timer.display >= 0.05 then
		UpdateDisplay()
	end
	if timer.health >= 0.2 then
		UpdateTargetHealth()
	end
end)

propheticPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	propheticPanel:RegisterEvent(event)
end

function SlashCmdList.Prophetic(msg, editbox)
	msg = { strsplit(' ', strlower(msg)) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return print('Prophetic - Locked: ' .. (Opt.locked and '|cFF00C000On' or '|cFFC00000Off'))
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
			OnResourceFrameShow()
		end
		return print('Prophetic - Snap to Blizzard combat resources frame: ' .. (Opt.snap and ('|cFF00C000' .. Opt.snap) or '|cFFC00000Off'))
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				propheticPreviousPanel:SetScale(Opt.scale.previous)
			end
			return print('Prophetic - Previous ability icon scale set to: |cFFFFD000' .. Opt.scale.previous .. '|r times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				propheticPanel:SetScale(Opt.scale.main)
			end
			return print('Prophetic - Main ability icon scale set to: |cFFFFD000' .. Opt.scale.main .. '|r times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				propheticCooldownPanel:SetScale(Opt.scale.cooldown)
			end
			return print('Prophetic - Cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.cooldown .. '|r times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				propheticInterruptPanel:SetScale(Opt.scale.interrupt)
			end
			return print('Prophetic - Interrupt ability icon scale set to: |cFFFFD000' .. Opt.scale.interrupt .. '|r times')
		end
		if startsWith(msg[2], 'to') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				propheticExtraPanel:SetScale(Opt.scale.extra)
			end
			return print('Prophetic - Extra cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.extra .. '|r times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('Prophetic - Action button glow scale set to: |cFFFFD000' .. Opt.scale.glow .. '|r times')
		end
		return print('Prophetic - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
		end
		return print('Prophetic - Icon transparency set to: |cFFFFD000' .. Opt.alpha * 100 .. '%|r')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return print('Prophetic - Calculation frequency (max time to wait between each update): Every |cFFFFD000' .. Opt.frequency .. '|r seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Prophetic - Glowing ability buttons (main icon): ' .. (Opt.glow.main and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Prophetic - Glowing ability buttons (cooldown icon): ' .. (Opt.glow.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Prophetic - Glowing ability buttons (interrupt icon): ' .. (Opt.glow.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Prophetic - Glowing ability buttons (extra icon): ' .. (Opt.glow.extra and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Prophetic - Blizzard default proc glow: ' .. (Opt.glow.blizzard and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return print('Prophetic - Glow color:', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return print('Prophetic - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Prophetic - Previous ability icon: ' .. (Opt.previous and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Prophetic - Show the Prophetic UI without a target: ' .. (Opt.always_on and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return print('Prophetic - Use Prophetic for cooldown management: ' .. (Opt.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
			if not Opt.spell_swipe then
				propheticPanel.swipe:Hide()
			end
		end
		return print('Prophetic - Spell casting swipe animation: ' .. (Opt.spell_swipe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
			if not Opt.dimmer then
				propheticPanel.dimmer:Hide()
			end
		end
		return print('Prophetic - Dim main ability icon when you don\'t have enough mana to use it: ' .. (Opt.dimmer and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return print('Prophetic - Red border around previous ability when it fails to hit: ' .. (Opt.miss_effect and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			SetTargetMode(1)
			UpdateDraggable()
		end
		return print('Prophetic - Allow clicking main ability icon to toggle amount of targets (disables moving): ' .. (Opt.aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return print('Prophetic - Only use cooldowns on bosses: ' .. (Opt.boss_only and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.discipline = not Opt.hide.discipline
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Prophetic - Discipline specialization: |cFFFFD000' .. (Opt.hide.discipline and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'm') then
				Opt.hide.holy = not Opt.hide.holy
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Prophetic - Holy specialization: |cFFFFD000' .. (Opt.hide.holy and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 's') then
				Opt.hide.shadow = not Opt.hide.shadow
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Prophetic - Shadow specialization: |cFFFFD000' .. (Opt.hide.shadow and '|cFFC00000Off' or '|cFF00C000On'))
			end
		end
		return print('Prophetic - Possible hidespec options: |cFFFFD000discipline|r/|cFFFFD000holy|r/|cFFFFD000shadow|r - toggle disabling Prophetic for specializations')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return print('Prophetic - Show an icon for interruptable spells: ' .. (Opt.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return print('Prophetic - Automatically change target mode on AoE spells: ' .. (Opt.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return print('Prophetic - Length of time target exists in auto AoE after being hit: |cFFFFD000' .. Opt.auto_aoe_ttl .. '|r seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return print('Prophetic - Show Battle potions in cooldown UI: ' .. (Opt.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'pws' then
		if msg[2] then
			Opt.pws_threshold = max(min(tonumber(msg[2]) or 60, 100), 0)
		end
		return print('Prophetic - Health percentage threshold to show Power Word: Shield reminder: |cFFFFD000' .. Opt.pws_threshold .. '%|r')
	end
	if msg[1] == 'reset' then
		propheticPanel:ClearAllPoints()
		propheticPanel:SetPoint('CENTER', 0, -169)
		SnapAllPanels()
		return print('Prophetic - Position has been reset to default')
	end
	print('Prophetic (version: |cFFFFD000' .. GetAddOnMetadata('Prophetic', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Prophetic UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Prophetic UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Prophetic UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Prophetic UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Prophetic UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Prophetic for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough mana to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000discipline|r/|cFFFFD000holy|r/|cFFFFD000shadow|r - toggle disabling Prophetic for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show Battle potions in cooldown UI',
		'pws |cFFFFD000[percent]|r - health percentage threshold to show Power Word: Shield reminder',
		'|cFFFFD000reset|r - reset the location of the Prophetic UI to default',
	} do
		print('  ' .. SLASH_Prophetic1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Contact |cFFFFFFFFOled|cFFFFD000-Zul\'jin|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end
