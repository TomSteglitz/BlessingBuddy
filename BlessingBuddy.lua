-- BlessingBuddy: schneller Buff + Rettungs-Heilung für fremde Spieler
-- Klassen: Paladin, Druide, Priester, Magier, Hexenmeister, Schamane
-- Zeigt beim Anklicken eines befreundeten Spielers eine kleine Leiste:
--   Reihe 1: großer "Empfohlen"-Button + deine Buffs
--   Lebensbalken des Ziels
--   Reihe 2: Heil-/Rettungszauber
-- Außerhalb des Kampfes nur für Spieler, die nicht in deiner Gruppe sind.
-- Im Kampf für jeden befreundeten Spieler (Rettung geht vor).

local ADDON = ...
local _, myClass = UnitClass("player")

------------------------------------------------------------------------
-- Daten je Spielerklasse
------------------------------------------------------------------------
-- Rang-1-Spell-IDs. Gewirkt wird per Name ohne Rang -> höchster bekannter Rang.
-- exclusive = true: pro Ziel nur ein eigener Buff dieser Art (Paladin-Segen).
-- heals: Liste von Slots. Ein Slot enthält eine oder mehrere IDs; die erste
--        bekannte gewinnt (z. B. Großes Heilen > Heilen > Geringes Heilen).
local CLASS_DATA = {
	PALADIN = {
		exclusive = true,
		spells = {
			KINGS     = 20217, -- Segen der Könige (Schutz-Talent)
			MIGHT     = 19740, -- Segen der Macht
			WISDOM    = 19742, -- Segen der Weisheit
			LIGHT     = 19977, -- Segen des Lichts
			SANCTUARY = 20911, -- Segen des Refugiums (Schutz-Talent)
			SALVATION = 1038,  -- Segen der Rettung
		},
		order = { "KINGS", "MIGHT", "WISDOM", "LIGHT", "SANCTUARY", "SALVATION" },
		priority = {
			WARRIOR = { "KINGS", "MIGHT", "LIGHT" },
			ROGUE   = { "KINGS", "MIGHT", "LIGHT" },
			HUNTER  = { "KINGS", "MIGHT", "WISDOM" },
			MAGE    = { "KINGS", "WISDOM", "LIGHT" },
			PRIEST  = { "KINGS", "WISDOM", "LIGHT" },
			WARLOCK = { "KINGS", "WISDOM", "LIGHT" },
			DRUID   = { "KINGS", "WISDOM", "MIGHT" },
			SHAMAN  = { "KINGS", "WISDOM", "MIGHT" },
			PALADIN = { "KINGS", "WISDOM", "MIGHT" },
		},
		default = { "KINGS", "MIGHT", "WISDOM" },
		heals = {
			{ 19750 },       -- Lichtblitz
			{ 635 },         -- Heiliges Licht
			{ 633 },         -- Handauflegung
			-- Segen des Schutzes (1022) bewusst nicht dabei: nur auf Gruppen-/Raidmitglieder wirkbar
			{ 1044 },        -- Segen der Freiheit
			{ 4987, 1152 },  -- Reinigung des Glaubens / Läutern
		},
	},
	DRUID = {
		exclusive = false,
		spells = {
			MARK   = 1126, -- Mal der Wildnis
			THORNS = 467,  -- Dornen
		},
		order = { "MARK", "THORNS" },
		petOK = { THORNS = true }, -- in Forever auf Begleitern wirksam (Mal nicht)
		priority = {},
		default = { "MARK", "THORNS" }, -- in der offenen Welt bekommt jeder Schaden ab
		heals = {
			{ 8936 },        -- Nachwachsen
			{ 5185 },        -- Heilende Berührung
			{ 774 },         -- Verjüngung
			{ 18562 },       -- Rasche Heilung (Talent)
			{ 2782 },        -- Fluch aufheben
			{ 2893, 8946 },  -- Vergiftung aufheben / Vergiftung heilen
		},
	},
	PRIEST = {
		exclusive = false,
		spells = {
			FORT     = 1243,  -- Machtwort: Seelenstärke
			SPIRIT   = 14752, -- Göttlicher Willen (Disziplin-Talent)
			SHADOW   = 976,   -- Schattenschutz
			FEARWARD = 6346,  -- Furchtschutz (in Classic nur Zwerg-Priester)
		},
		order = { "FORT", "SPIRIT", "SHADOW", "FEARWARD" },
		priority = {
			WARRIOR = { "FORT" },
			ROGUE   = { "FORT" },
		},
		default = { "FORT", "SPIRIT" },
		heals = {
			{ 17 },                -- Machtwort: Schild
			{ 2061 },              -- Blitzheilung
			{ 2060, 2054, 2050 },  -- Großes Heilen / Heilen / Geringes Heilen
			{ 139 },               -- Erneuerung
			{ 527 },               -- Magiebannung
			{ 552, 528 },          -- Krankheit aufheben / heilen
		},
	},
	MAGE = {
		exclusive = false,
		spells = {
			INTELLECT = 1459, -- Arkane Intelligenz
			AMPLIFY   = 1008, -- Magie verstärken
			DAMPEN    = 604,  -- Magie dämpfen
		},
		order = { "INTELLECT", "AMPLIFY", "DAMPEN" },
		priority = {
			WARRIOR = {}, -- kein Mana -> keine Empfehlung (Button bleibt nutzbar)
			ROGUE   = {},
		},
		default = { "INTELLECT" },
		heals = {
			{ 475 },   -- Geringen Fluch aufheben
		},
	},
	WARLOCK = {
		exclusive = false,
		spells = {
			BREATH = 5697, -- Unendlicher Atem
			INVIS  = 132,  -- Geringe Unsichtbarkeit entdecken
		},
		order = { "BREATH", "INVIS" },
		priority = {},
		default = {},
		heals = {},
	},
	SHAMAN = {
		exclusive = false,
		spells = {
			WATERBREATH = 131, -- Wasseratmung
			WATERWALK   = 546, -- Wasserwandeln
		},
		order = { "WATERBREATH", "WATERWALK" },
		priority = {},
		default = {},
		heals = {
			{ 8004 },  -- Geringe Welle der Heilung
			{ 331 },   -- Welle der Heilung
			{ 1064 },  -- Kettenheilung
			{ 526 },   -- Vergiftung heilen
			{ 2870 },  -- Krankheit heilen
		},
	},
}

local CFG = CLASS_DATA[myClass]
if not CFG then return end -- Klasse ohne Fremd-Buffs: Addon bleibt inaktiv

local BLESSINGS = CFG.spells
local ORDER = CFG.order
local PRIORITY = CFG.priority
local DEFAULT_PRIORITY = CFG.default
local HEALS = CFG.heals or {}

-- Gleichwertige Buffs: Gruppen- bzw. "Große" Fassungen stapeln nicht mit der
-- Einzelfassung. Liegt eine davon auf dem Ziel, gilt der Buff als vorhanden.
local EQUIV = {
	KINGS     = { 25898 }, -- Großer Segen der Könige
	MIGHT     = { 25782 }, -- Großer Segen der Macht
	WISDOM    = { 25894 }, -- Großer Segen der Weisheit
	LIGHT     = { 25890 }, -- Großer Segen des Lichts
	SANCTUARY = { 25899 }, -- Großer Segen des Refugiums
	SALVATION = { 25895 }, -- Großer Segen der Rettung
	MARK      = { 21849 }, -- Gabe der Wildnis
	FORT      = { 21562 }, -- Gebet der Seelenstärke
	SPIRIT    = { 27681 }, -- Gebet der Willenskraft
	SHADOW    = { 27683 }, -- Gebet des Schattenschutzes
	INTELLECT = { 23028 }, -- Arkane Brillanz
}
local MAX_HEALS = 6

------------------------------------------------------------------------
-- Lokalisierung (Zaubernamen kommen automatisch aus dem Client)
------------------------------------------------------------------------
local L = {
	DRAG      = "(Shift+drag)",
	COMBAT    = "Not in combat.",
	MOVE_ON   = "Move mode ON (Shift+drag the title bar)",
	MOVE_OFF  = "Move mode OFF",
	RESET     = "Position reset.",
	CMDS      = "commands:",
	HELP_MOVE = "  /bb move  - show/move the bar",
	HELP_RST  = "  /bb reset - reset position",
	HELP_KEY  = "  Keybinds: Options > Keybindings > AddOns > BlessingBuddy",
	BIND_BEST = "Cast recommended buff on target",
	BIND_HEAL = "Heal slot %d on target",
	PVP       = "PvP",
	PET       = "Pet",
}
if GetLocale() == "deDE" then
	L.DRAG      = "(Shift+Ziehen)"
	L.COMBAT    = "Nicht im Kampf."
	L.MOVE_ON   = "Verschiebemodus AN (Shift+Ziehen an der Titelzeile)"
	L.MOVE_OFF  = "Verschiebemodus AUS"
	L.RESET     = "Position zurückgesetzt."
	L.CMDS      = "Befehle:"
	L.HELP_MOVE = "  /segen move  - Leiste anzeigen/verschieben"
	L.HELP_RST  = "  /segen reset - Position zurücksetzen"
	L.HELP_KEY  = "  Tasten belegen: Optionen > Tastenbelegung > AddOns > BlessingBuddy"
	L.BIND_BEST = "Empfohlenen Buff auf Ziel wirken"
	L.BIND_HEAL = "Heil-Slot %d auf Ziel wirken"
	L.PET       = "Begleiter"
end
local PREFIX = "|cff66ccffBlessingBuddy|r: "

------------------------------------------------------------------------
-- API-Kompatibilität (Forever-Client ist noch Beta, daher beide Varianten)
------------------------------------------------------------------------
local function SpellInfo(id)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		if info then return info.name, info.iconID end
		return nil
	end
	local name, _, icon = GetSpellInfo(id)
	return name, icon
end

local function Known(id)
	if IsPlayerSpell then return IsPlayerSpell(id) end
	if IsSpellKnown then return IsSpellKnown(id) end
	return SpellInfo(id) ~= nil
end

local function InRange(name)
	if C_Spell and C_Spell.IsSpellInRange then
		return C_Spell.IsSpellInRange(name, "target")
	end
	if IsSpellInRange then
		local r = IsSpellInRange(name, "target")
		if r == nil then return nil end
		return r == 1
	end
	return nil
end

local function Cooldown(name)
	if C_Spell and C_Spell.GetSpellCooldown then
		local cd = C_Spell.GetSpellCooldown(name)
		if cd then return cd.startTime, cd.duration end
		return 0, 0
	end
	if GetSpellCooldown then
		local start, duration = GetSpellCooldown(name)
		return start or 0, duration or 0
	end
	return 0, 0
end

-- Höchster gelernter Rang je Zaubername (Name -> Spell-ID).
-- Forever wirkt bei Namen ohne Rang nicht automatisch den höchsten Rang,
-- daher durchsuchen wir das Zauberbuch und wirken gezielt per ID.
local rankMap = {}
local function BuildRankMap()
	local map = {}
	local function add(id)
		if not id then return end
		local name = SpellInfo(id)
		if not name then return end
		local prev = map[name]
		-- Im Zauberbuch stehen Ränge aufsteigend; bei gleichem Namen gewinnt
		-- der höhere Rang (Rangtext), sonst der spätere Eintrag
		if prev and GetSpellSubtext then
			local function rank(x)
				local t = GetSpellSubtext(x)
				return t and tonumber(t:match("%d+")) or 0
			end
			if rank(id) < rank(prev) then return end
		end
		map[name] = id
	end
	local ok = pcall(function()
		if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
			local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
			for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
				local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
				if line then
					local first = (line.itemIndexOffset or 0) + 1
					for j = first, first + (line.numSpellBookItems or 0) - 1 do
						local item = C_SpellBook.GetSpellBookItemInfo(j, bank)
						if item and item.spellID and not item.isPassive then add(item.spellID) end
					end
				end
			end
		elseif GetNumSpellTabs then
			for t = 1, GetNumSpellTabs() do
				local _, _, offset, num = GetSpellTabInfo(t)
				for j = offset + 1, offset + num do
					local kind, id = GetSpellBookItemInfo(j, BOOKTYPE_SPELL or "spell")
					if kind == "SPELL" then add(id) end
				end
			end
		end
	end)
	if ok then rankMap = map end
end

local function HighestRank(id)
	local name = SpellInfo(id)
	return (name and rankMap[name]) or id
end

-- Ränge der Buffs mit Lernstufe (Classic-Werte). Buffs unterliegen einer
-- Stufengrenze: Ein Rang wirkt nur, wenn das Ziel höchstens 10 Stufen unter
-- seiner Lernstufe liegt. Heilzauber haben diese Grenze nicht.
local BUFF_RANKS = {
	[20217] = { {20217, 20} },                                                           -- Könige
	[19740] = { {19740, 4}, {19834, 12}, {19835, 22}, {19836, 32}, {19837, 42}, {19838, 52}, {25291, 60} }, -- Macht
	[19742] = { {19742, 14}, {19850, 24}, {19852, 34}, {19853, 44}, {19854, 54}, {25290, 60} },             -- Weisheit
	[19977] = { {19977, 40}, {19978, 50}, {19979, 60} },                                   -- Licht
	[20911] = { {20911, 30}, {20912, 40}, {20913, 50}, {20914, 60} },                      -- Refugium
	[1038]  = { {1038, 26} },                                                              -- Rettung
	[1126]  = { {1126, 1}, {5232, 10}, {6756, 20}, {5234, 30}, {8907, 40}, {9884, 50}, {9885, 60} }, -- Mal
	[467]   = { {467, 6}, {782, 14}, {1075, 24}, {8914, 34}, {9756, 44}, {9910, 54} },     -- Dornen
	[1243]  = { {1243, 1}, {1244, 12}, {1245, 24}, {2791, 36}, {10937, 48}, {10938, 60} }, -- Seelenstärke
	[14752] = { {14752, 30}, {14818, 40}, {14819, 50}, {27841, 60} },                      -- Göttlicher Willen
	[976]   = { {976, 30}, {10957, 42}, {10958, 56} },                                     -- Schattenschutz
	[6346]  = { {6346, 20} },                                                              -- Furchtschutz
	[1459]  = { {1459, 1}, {1460, 14}, {1461, 28}, {10156, 42}, {10157, 56} },             -- Arkane Intelligenz
	[1008]  = { {1008, 18}, {8455, 30}, {10169, 42}, {10170, 54} },                        -- Magie verstärken
	[604]   = { {604, 12}, {8450, 24}, {8451, 36}, {10173, 48}, {10174, 60} },             -- Magie dämpfen
	[5697]  = { {5697, 16} },                                                              -- Unendlicher Atem
	[132]   = { {132, 26} },                                                               -- Unsichtbarkeit entdecken
	[131]   = { {131, 22} },                                                               -- Wasseratmung
	[546]   = { {546, 28} },                                                               -- Wasserwandeln
}

-- Lernstufe eines Rangs: bevorzugt vom Client, sonst aus der Tabelle
local function LearnLevel(id, fallback)
	local ok, lvl = pcall(function()
		if C_Spell and C_Spell.GetSpellLevelLearned then return C_Spell.GetSpellLevelLearned(id) end
		if GetSpellLevelLearned then return GetSpellLevelLearned(id) end
	end)
	if ok and type(lvl) == "number" and lvl > 0 then return lvl end
	return fallback
end

-- Höchster bekannter Buff-Rang, der auf ein Ziel dieser Stufe wirkt.
-- Liefert nil, wenn kein Rang passt (z. B. Könige auf Stufe 8).
local function BuffRankFor(baseID, targetLevel)
	if not Known(baseID) then return nil end
	local limit = (targetLevel and targetLevel > 0) and (targetLevel + 10) or math.huge
	local ranks = BUFF_RANKS[baseID] or {}
	local tableLevel = {}
	for _, r in ipairs(ranks) do tableLevel[r[1]] = r[2] end

	-- 1. Höchster Rang laut Zauberbuch (deckt auch abweichende Forever-IDs ab)
	local top = HighestRank(baseID)
	local topLevel = LearnLevel(top, tableLevel[top])
	if not topLevel or topLevel <= limit then return top end

	-- 2. Zu stark für das Ziel: höchsten passenden Rang aus der Tabelle nehmen
	local pick
	for _, r in ipairs(ranks) do
		local id = r[1]
		local lvl = LearnLevel(id, r[2])
		if lvl <= limit and (id == baseID or Known(id)) then pick = id end
	end
	return pick
end

local function TargetLevel()
	if not UnitExists("target") then return nil end
	local lvl = UnitLevel("target")
	if type(lvl) == "number" and lvl > 0 then return lvl end
	return nil -- unbekannt (??): keine Begrenzung
end

-- Liefert: alle Buffs auf dem Ziel (Name -> true) und die von dir gewirkten
local function TargetBuffs()
	local all, mine = {}, {}
	if not UnitExists("target") then return all, mine end
	for i = 1, 40 do
		local name, source
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local a = C_UnitAuras.GetAuraDataByIndex("target", i, "HELPFUL")
			if a then name, source = a.name, a.sourceUnit end
		else
			local n, _, _, _, _, _, s = UnitBuff("target", i)
			name, source = n, s
		end
		if not name then break end
		all[name] = true
		if source and UnitIsUnit(source, "player") then mine[name] = true end
	end
	return all, mine
end

-- Namen (lokalisiert), unter denen ein Buff-Schlüssel auf dem Ziel liegen kann
local equivNames = {}
local function NamesFor(key)
	if equivNames[key] then return equivNames[key] end
	local list = {}
	local main = SpellInfo(BLESSINGS[key])
	if main then list[#list + 1] = main end
	for _, id in ipairs(EQUIV[key] or {}) do
		local n = SpellInfo(id)
		if n then list[#list + 1] = n end
	end
	if #list > 0 then equivNames[key] = list end -- erst cachen, wenn Zauberdaten geladen sind
	return list
end

local function HasKey(set, key)
	if not key then return false end
	for _, n in ipairs(NamesFor(key)) do
		if set[n] then return true end
	end
	return false
end

------------------------------------------------------------------------
-- Zustand
------------------------------------------------------------------------
local db

------------------------------------------------------------------------
-- Debug-Log (landet in WTF\Account\<KONTO>\SavedVariables\BlessingBuddy.lua,
-- geschrieben bei /reload oder Ausloggen). Aktivieren mit /bb log on
------------------------------------------------------------------------
local LOG_MAX = 400
local function S(v)
	local ok, str = pcall(tostring, v)
	return ok and str or "<secret>"
end
local function Log(fmt, ...)
	if not (db and db.debug) then return end
	db.log = db.log or {}
	local ok, line = pcall(string.format, fmt, ...)
	if not ok then line = fmt .. " <format error>" end
	table.insert(db.log, date("%H:%M:%S") .. " " .. line)
	while #db.log > LOG_MAX do table.remove(db.log, 1) end
end

-- Rohdaten aller Buffs des Ziels über beide Abfragewege des Clients
local function LogRawAuras()
	if not (db and db.debug) then return end
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local n = 0
		for i = 1, 40 do
			local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HELPFUL")
			if not ok then Log("  C_UnitAuras[%d] ERROR %s", i, S(a)) break end
			if not a then break end
			n = n + 1
			Log("  C_UnitAuras[%d] name=%s id=%s src=%s fromPlayer=%s", i,
				S(a.name), S(a.spellId), S(a.sourceUnit), S(a.isFromPlayerOrPlayerPet))
		end
		Log("  C_UnitAuras total=%d", n)
	else
		Log("  C_UnitAuras.GetAuraDataByIndex not available")
	end
	if UnitBuff then
		local n = 0
		for i = 1, 40 do
			local ok, name, _, _, _, _, _, src, _, _, sid = pcall(UnitBuff, "target", i)
			if not ok then Log("  UnitBuff[%d] ERROR %s", i, S(name)) break end
			if not name then break end
			n = n + 1
			Log("  UnitBuff[%d] name=%s id=%s src=%s", i, S(name), S(sid), S(src))
		end
		Log("  UnitBuff total=%d", n)
	else
		Log("  UnitBuff not available")
	end
end
local forceShow = false     -- /segen move: Leiste dauerhaft zeigen zum Verschieben
local pendingSecure = false -- Änderungen, die bis Kampfende warten müssen

local BEST, SMALL, HEAL, GAP, TITLE_H, PAD, HP_H = 40, 28, 32, 4, 20, 3, 6
local DEFAULT_POS = { "CENTER", "CENTER", 0, -180 }

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local frame = CreateFrame("Frame", "BlessingBuddyFrame", UIParent)
frame:SetSize(BEST + 2 * PAD, BEST + TITLE_H + PAD)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:Hide()

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.45)

local function SavePosition()
	if not db then return end
	local p, _, rp, x, y = frame:GetPoint()
	db.pos = { p, rp, x, y }
end

local function RestorePosition()
	if InCombatLockdown() then return end
	local pos = (db and db.pos) or DEFAULT_POS
	frame:ClearAllPoints()
	frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
end

-- Titelleiste: Zielname + Empfehlung, Shift+Ziehen zum Verschieben
local title = CreateFrame("Button", nil, frame)
title:SetPoint("TOPLEFT")
title:SetPoint("TOPRIGHT")
title:SetHeight(TITLE_H)
title:RegisterForDrag("LeftButton")
title.right = title:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title.right:SetPoint("RIGHT", -4, 0)
title.right:SetJustifyH("RIGHT")
title.text = title:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title.text:SetPoint("LEFT", 4, 0)
title.text:SetPoint("RIGHT", title.right, "LEFT", -6, 0)
title.text:SetJustifyH("LEFT")
title.text:SetWordWrap(false)
title:SetScript("OnDragStart", function()
	if IsShiftKeyDown() and not InCombatLockdown() then frame:StartMoving() end
end)
title:SetScript("OnDragStop", function()
	frame:StopMovingOrSizing()
	SavePosition()
end)

-- Lebensbalken des Ziels
local hp = CreateFrame("StatusBar", nil, frame)
hp:SetHeight(HP_H)
hp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
hp:SetMinMaxValues(0, 1)
hp.bg = hp:CreateTexture(nil, "BACKGROUND")
hp.bg:SetAllPoints()
hp.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
hp:SetStatusBarColor(0.1, 0.85, 0.1)
hp:Hide()

local allButtons = {}

local function CreateSpellButton(name, size)
	local b = CreateFrame("Button", name, frame, "SecureActionButtonTemplate")
	b:SetSize(size, size)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "spell")
	b:SetAttribute("unit", "target")

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilite-Square", "ADD")
	b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints()

	-- Häkchen: Buff liegt schon auf dem Ziel
	b.active = b:CreateTexture(nil, "OVERLAY")
	b.active:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	b.active:SetSize(size * 0.5, size * 0.5)
	b.active:SetPoint("BOTTOMRIGHT", 2, -2)
	b.active:Hide()

	b:SetScript("OnEnter", function(self)
		if not self.spellID then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetSpellByID(self.spellID)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	allButtons[#allButtons + 1] = b
	return b
end

local best = CreateSpellButton("BlessingBuddyBestButton", BEST)

local small = {}
for _, key in ipairs(ORDER) do
	small[key] = CreateSpellButton("BlessingBuddy" .. key .. "Button", SMALL)
	small[key]:Hide()
end

local heal = {}
for i = 1, MAX_HEALS do
	heal[i] = CreateSpellButton("BlessingBuddyHeal" .. i .. "Button", HEAL)
	heal[i]:Hide()
end

------------------------------------------------------------------------
-- Logik
------------------------------------------------------------------------
-- Begleiter eines Spielers (Jäger-Tier, Hexer-Dämon), nicht dein eigener
local function IsOtherPet(unit)
	return not UnitIsPlayer(unit)
		and UnitPlayerControlled(unit)
		and not UnitIsUnit(unit, "pet")
end

local function InMyGroup(unit)
	if UnitPlayerOrPetInParty then
		return UnitPlayerOrPetInParty(unit) or UnitPlayerOrPetInRaid(unit)
	end
	return UnitInParty(unit) or UnitInRaid(unit)
end

local function ShouldShow()
	if forceShow then return true end
	return UnitExists("target")
		and (UnitIsPlayer("target") or IsOtherPet("target"))
		and UnitIsFriend("player", "target")
		and not UnitIsUnit("target", "player")
		and not UnitIsDeadOrGhost("target")
		and not InMyGroup("target")
end

-- Sichtbarkeit über einen sicheren State-Driver, damit die Leiste auch im
-- Kampf beim Anklicken erscheint. Im Kampf: jeder befreundete, lebende Spieler.
-- Außerhalb: das Ergebnis von ShouldShow() (nur Fremde).
local function SetVisible(show)
	RegisterStateDriver(frame, "visibility",
		"[combat,@target,help,nodead] show; [combat] hide; " .. (show and "show" or "hide"))
end

-- Ein Paladin kann pro Ziel nur EINEN Einzelsegen halten (Classic-Regel).
-- Liegt also schon dein Segen drauf -> diesen auffrischen statt überschreiben.
local function PickBest(all, mine)
	local prio
	if UnitIsPlayer("target") then
		local _, class = UnitClass("target")
		prio = (class and PRIORITY[class]) or DEFAULT_PRIORITY
	else
		-- Begleiter: nur Buffs, die in Forever auf Begleitern wirken (petOK)
		prio = {}
		for _, key in ipairs(ORDER) do
			if CFG.petOK and CFG.petOK[key] then prio[#prio + 1] = key end
		end
	end

	if CFG.exclusive then
		for _, key in ipairs(ORDER) do
			if HasKey(mine, key) and BuffRankFor(BLESSINGS[key], TargetLevel()) then return key end
		end
	end

	local fallback
	for _, key in ipairs(prio) do
		if BuffRankFor(BLESSINGS[key], TargetLevel()) then
			fallback = fallback or key
			if not HasKey(all, key) then return key end
		end
	end
	return fallback
end

local function ClassColored(unit)
	local name = UnitName(unit) or "?"
	if not UnitIsPlayer(unit) then
		return "|cff7fd17f" .. name .. "|r |cffaaaaaa(" .. L.PET .. ")|r"
	end
	local _, class = UnitClass(unit)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
	end
	return name
end

-- Lebenswerte können im neuen Client "geheim" sein (keine Rechnung möglich).
-- Der Balken darf sie trotzdem anzeigen; die Prozentzahl nur, wenn erlaubt.
local function HealthPercentText()
	if UnitHealthPercent then
		local ok, txt = pcall(function()
			return string.format("%d%%", UnitHealthPercent("target", true, CurveConstants and CurveConstants.ScaleTo100) or 0)
		end)
		if ok and txt then return txt end
	end
	local ok, txt = pcall(function()
		local cur, max = UnitHealth("target"), UnitHealthMax("target")
		if not max or max <= 0 then return "" end
		return math.floor(cur / max * 100 + 0.5) .. "%"
	end)
	return ok and txt or ""
end

local function HealthColor()
	local ok, pct = pcall(function()
		local cur, max = UnitHealth("target"), UnitHealthMax("target")
		if not max or max <= 0 then return nil end
		return cur / max
	end)
	if ok and type(pct) == "number" then
		hp:SetStatusBarColor(math.min(1, 2 * (1 - pct)), math.min(1, 2 * pct), 0)
	else
		hp:SetStatusBarColor(0.1, 0.85, 0.1)
	end
end

local function UpdateHealth()
	if not UnitExists("target") then
		hp:SetMinMaxValues(0, 1)
		hp:SetValue(0)
		title.right:SetText("")
		return
	end
	pcall(function()
		hp:SetMinMaxValues(0, UnitHealthMax("target"))
		hp:SetValue(UnitHealth("target"))
	end)
	HealthColor()
	title.right:SetText(HealthPercentText())
end

-- Nicht-geschützte Optik: darf auch im Kampf laufen
local function UpdateVisuals()
	if not frame:IsShown() then return end
	local all = TargetBuffs()
	for _, key in ipairs(ORDER) do
		local b = small[key]
		b.active:SetShown(b.spellName ~= nil and HasKey(all, key))
	end
	best.active:SetShown(best.spellName ~= nil and HasKey(all, best.key))
	for i = 1, MAX_HEALS do
		local b = heal[i]
		b.active:SetShown(b.spellName ~= nil and all[b.spellName] == true) -- z. B. Erneuerung/Verjüngung
	end

	if UnitExists("target") then
		local txt = ClassColored("target")
		local lvl = UnitLevel("target")
		if lvl and lvl > 0 then txt = txt .. " |cffaaaaaa" .. lvl .. "|r" end
		-- Warnung: Heilen/Buffen eines PvP-geflaggten Spielers flaggt dich mit
		if UnitIsPVP("target") and not UnitIsPVP("player") then
			txt = txt .. "  |cffff4040" .. L.PVP .. "|r"
		end
		title.text:SetText(txt)
	else
		title.text:SetText("BlessingBuddy |cffaaaaaa" .. L.DRAG .. "|r")
		title.right:SetText("")
	end
	UpdateHealth()
end

local function AssignButton(b, id, exact)
	local castID = exact and id or HighestRank(id)
	local name, icon = SpellInfo(castID)
	b.spellID, b.spellName = castID, name
	b:SetAttribute("spell", castID) -- gezielt der höchste gelernte Rang
	b.icon:SetTexture(icon)
end

-- Geschützte Änderungen (Attribute, Layout, Sichtbarkeit): nur außerhalb des Kampfes
local function UpdateSecure()
	if InCombatLockdown() then
		pendingSecure = true
		UpdateVisuals()
		return
	end
	pendingSecure = false

	local all, mine = TargetBuffs()
	local bestKey = PickBest(all, mine)

	-- Reihe 1: Empfehlung + Buffs
	local x0 = bestKey and (PAD + BEST + GAP) or PAD
	local row1H = bestKey and BEST or SMALL
	local ySmall = -TITLE_H - (row1H - SMALL) / 2
	local nBuff = 0
	-- Begleiter: die meisten Buffs wirken in Forever nicht -> nur petOK-Buffs zeigen
	local petTarget = UnitExists("target") and not UnitIsPlayer("target")
	local tLevel = TargetLevel()
	for _, key in ipairs(ORDER) do
		local b = small[key]
		local allowed = not petTarget or (CFG.petOK and CFG.petOK[key])
		local castID = allowed and BuffRankFor(BLESSINGS[key], tLevel)
		if castID and SpellInfo(castID) then
			AssignButton(b, castID, true)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", frame, "TOPLEFT", x0 + nBuff * (SMALL + GAP), ySmall)
			b:Show()
			nBuff = nBuff + 1
		else
			b.spellID, b.spellName = nil, nil
			b:Hide()
		end
	end

	best.key = bestKey
	if bestKey then
		AssignButton(best, BuffRankFor(BLESSINGS[bestKey], tLevel) or BLESSINGS[bestKey], true)
		best:ClearAllPoints()
		best:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TITLE_H)
		best:Show()
	else
		best.spellID, best.spellName = nil, nil
		best:Hide()
	end

	local row1W = (nBuff > 0) and (x0 + nBuff * (SMALL + GAP) - GAP + PAD) or (bestKey and (PAD + BEST + PAD) or 0)
	if nBuff == 0 and not bestKey then row1H = 0 end

	-- Reihe 2: Heilung
	local nHeal = 0
	for i = 1, MAX_HEALS do heal[i]:Hide(); heal[i].spellID, heal[i].spellName = nil, nil end
	for _, slot in ipairs(HEALS) do
		if nHeal >= MAX_HEALS then break end
		for _, id in ipairs(slot) do
			if SpellInfo(id) and Known(id) then
				nHeal = nHeal + 1
				AssignButton(heal[nHeal], id)
				break
			end
		end
	end

	local yHp = -TITLE_H - row1H - (row1H > 0 and GAP or 0)
	local yHeal = yHp - HP_H - GAP
	for i = 1, nHeal do
		local b = heal[i]
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * (HEAL + GAP), yHeal)
		b:Show()
	end
	local row2W = (nHeal > 0) and (PAD + nHeal * (HEAL + GAP) - GAP + PAD) or 0

	if nBuff == 0 and nHeal == 0 and not bestKey then -- noch nichts Passendes gelernt
		SetVisible(false)
		return
	end

	local width = math.max(row1W, row2W, 140)
	hp:ClearAllPoints()
	hp:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, yHp)
	hp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, yHp)
	hp:Show()

	local height = -yHp + HP_H + PAD
	if nHeal > 0 then height = -yHeal + HEAL + PAD end
	frame:SetSize(width, height)

	SetVisible(ShouldShow())
	UpdateVisuals()

	if db and db.debug then
		local parts = {}
		for _, key in ipairs(ORDER) do
			parts[#parts + 1] = key .. "=" .. S(small[key]:IsShown() and small[key].spellID or "-")
		end
		Log("state: best=%s(%s) tLevel=%s buttons: %s", S(bestKey), S(best.spellID),
			S(tLevel), table.concat(parts, " "))
	end
end

-- Fingerabdruck der Buffs am Ziel: erkennt Änderungen auch dann, wenn der
-- Client kein UNIT_AURA für fremde Spieler schickt (Forever-Beta)
local lastAuraSig, auraAcc = nil, 0
local function AuraSignature()
	local all = TargetBuffs()
	local list = {}
	for name in pairs(all) do list[#list + 1] = tostring(name) end
	table.sort(list)
	return table.concat(list, "|")
end

-- Reichweite (rot) und Abklingzeiten, 5x pro Sekunde
local acc = 0
frame:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	auraAcc = auraAcc + elapsed
	if auraAcc >= 0.5 then
		auraAcc = 0
		local ok, sig = pcall(AuraSignature)
		if ok and sig ~= lastAuraSig then
			lastAuraSig = sig
			UpdateSecure()
		end
	end
	if acc < 0.2 then return end
	acc = 0
	local hasTarget = UnitExists("target")
	for _, b in ipairs(allButtons) do
		if b:IsShown() and b.spellName then
			if hasTarget and InRange(b.spellName) == false then
				b.icon:SetVertexColor(1, 0.3, 0.3)
			else
				b.icon:SetVertexColor(1, 1, 1)
			end
			local start, duration = Cooldown(b.spellName)
			if duration and duration > 1.5 then -- globale Abklingzeit ignorieren
				b.cd:SetCooldown(start, duration)
			else
				b.cd:Clear()
			end
		end
	end
end)

frame:SetScript("OnShow", UpdateVisuals)

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function SafeRegister(event) pcall(ev.RegisterEvent, ev, event) end
for _, e in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED",
	"UNIT_AURA", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED", "UNIT_FLAGS",
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT",
	"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_FAILED_QUIET", "UI_ERROR_MESSAGE",
}) do SafeRegister(e) end

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
	if event:find("^UNIT_SPELLCAST") then
		if arg1 == "player" and db and db.debug then
			-- SENT: unit, targetName, castGUID, spellID; sonst: unit, castGUID, spellID
			local spellID = (event == "UNIT_SPELLCAST_SENT") and arg4 or arg3
			Log("cast %s spell=%s(%s) target=%s", event:gsub("UNIT_SPELLCAST_", ""),
				S(SpellInfo(spellID or 0)), S(spellID), S(event == "UNIT_SPELLCAST_SENT" and arg2 or UnitName("target")))
		end
		return
	elseif event == "UI_ERROR_MESSAGE" then
		Log("error: %s (%s)", S(arg2), S(arg1))
		return
	elseif event == "PLAYER_TARGET_CHANGED" and db and db.debug and UnitExists("target") then
		local _, class = UnitClass("target")
		Log("--- target %s class=%s level=%s player=%s friend=%s inGroup=%s myLevel=%s",
			S(UnitName("target")), S(class), S(UnitLevel("target")), S(UnitIsPlayer("target")),
			S(UnitIsFriend("player", "target")), S(InMyGroup("target")), S(UnitLevel("player")))
		LogRawAuras()
	end
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			BlessingBuddyDB = BlessingBuddyDB or {}
			db = BlessingBuddyDB
			RestorePosition()
		end
		return
	elseif event == "PLAYER_LOGIN" then
		if not db then
			BlessingBuddyDB = BlessingBuddyDB or {}
			db = BlessingBuddyDB
		end
		RestorePosition()
		BuildRankMap()
	elseif event == "SPELLS_CHANGED" then
		BuildRankMap()
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH_FREQUENT" then
		if arg1 == "target" then UpdateHealth() end
		return
	elseif event == "UNIT_AURA" or event == "UNIT_FLAGS" then
		if arg1 ~= "target" then return end
		-- Buffs haben sich geändert -> Empfehlung neu berechnen
		-- (im Kampf nur Optik; die Empfehlung folgt nach Kampfende)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if not pendingSecure then return end
	end
	UpdateSecure()
end)

------------------------------------------------------------------------
-- Tastenbelegung + Slash-Befehle
------------------------------------------------------------------------
BINDING_HEADER_BLESSINGBUDDY = "BlessingBuddy"
_G["BINDING_NAME_CLICK BlessingBuddyBestButton:LeftButton"] = L.BIND_BEST
for i = 1, 3 do
	_G["BINDING_NAME_CLICK BlessingBuddyHeal" .. i .. "Button:LeftButton"] = string.format(L.BIND_HEAL, i)
end

SLASH_BLESSINGBUDDY1 = "/segen"
SLASH_BLESSINGBUDDY2 = "/bb"
SLASH_BLESSINGBUDDY3 = "/blessingbuddy"
SlashCmdList.BLESSINGBUDDY = function(msg)
	msg = strtrim((msg or ""):lower())
	if InCombatLockdown() then
		print(PREFIX .. L.COMBAT)
		return
	end
	if msg == "move" then
		forceShow = not forceShow
		print(PREFIX .. (forceShow and L.MOVE_ON or L.MOVE_OFF))
		UpdateSecure()
	elseif msg == "log on" or msg == "log off" or msg == "log clear" then
		if not db then return end
		if msg == "log clear" then
			db.log = {}
			print(PREFIX .. "log cleared")
		else
			db.debug = (msg == "log on")
			print(PREFIX .. "log " .. (db.debug and "ON – /reload writes it to SavedVariables\\BlessingBuddy.lua" or "OFF"))
			if db.debug then Log("=== log started, version %s, client %s", S((C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version")), S((GetBuildInfo()))) end
		end
	elseif msg == "debug" then
		local function v(f, ...)
			local ok, r = pcall(f, ...)
			if not ok then return "|cffff4040ERR|r" end
			return tostring(r)
		end
		print(PREFIX .. "debug (target):")
		local allB, mineB = TargetBuffs()
		local names = {}
		for n in pairs(allB) do names[#names + 1] = (mineB[n] and (n .. "*") or n) end
		table.sort(names)
		print("  buffs (*=yours): " .. (#names > 0 and table.concat(names, ", ") or "-"))
		print("  exists=" .. v(UnitExists, "target")
			.. " player=" .. v(UnitIsPlayer, "target")
			.. " controlled=" .. v(UnitPlayerControlled, "target")
			.. " ownPet=" .. v(UnitIsUnit, "target", "pet"))
		print("  friend=" .. v(UnitIsFriend, "player", "target")
			.. " dead=" .. v(UnitIsDeadOrGhost, "target")
			.. " inGroup=" .. v(InMyGroup, "target")
			.. " creatureType=" .. v(UnitCreatureType, "target"))
		print("  shouldShow=" .. v(ShouldShow)
			.. " frameShown=" .. tostring(frame:IsShown())
			.. " best=" .. tostring(best.spellName))
		for _, key in ipairs(ORDER) do
			local id = BLESSINGS[key]
			print("  " .. key .. ": known=" .. v(Known, id)
				.. " castID=" .. tostring(HighestRank(id))
				.. " rank=" .. v(GetSpellSubtext or function() return "?" end, HighestRank(id))
				.. " petOK=" .. tostring(CFG.petOK and CFG.petOK[key] or false)
				.. " button=" .. tostring(small[key]:IsShown()))
		end
	elseif msg == "reset" then
		if db then db.pos = nil end
		RestorePosition()
		print(PREFIX .. L.RESET)
	else
		local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
		local version = getMeta and getMeta(ADDON, "Version") or "?"
		print("|cff66ccffBlessingBuddy|r " .. version .. " - " .. L.CMDS)
		print(L.HELP_MOVE)
		print(L.HELP_RST)
		print(L.HELP_KEY)
	end
end
