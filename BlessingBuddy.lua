-- BlessingBuddy: schneller Buff + Rettungs-Heilung für fremde Spieler
-- Klassen: Paladin, Druide, Priester, Magier, Hexenmeister, Schamane
-- Zeigt beim Anklicken eines befreundeten Spielers eine kleine Leiste:
--   Reihe 1: großer "Empfohlen"-Button + deine Buffs
--   Lebensbalken des Ziels
--   Reihe 2: Heil-/Rettungszauber
-- Außerhalb des Kampfes: Sichtbarkeit nach Einstellung (Fremde/Gruppe/Raid).
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
	OPT_SHOW_OUTSIDE = "Show for players outside group",
	OPT_SHOW_PARTY   = "Show for party members",
	OPT_SHOW_RAID    = "Show for raid members",
	OPT_SHOW_SELF    = "Show for yourself",
	OPT_INTRO        = "Controls when BlessingBuddy appears on friendly targets outside of combat.",
	HELP_OPTS        = "  Options: Interface > AddOns > BlessingBuddy",
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
	L.OPT_SHOW_OUTSIDE = "Für Spieler außerhalb der Gruppe anzeigen"
	L.OPT_SHOW_PARTY   = "Für Gruppenmitglieder anzeigen"
	L.OPT_SHOW_RAID    = "Für Schlachtzugmitglieder anzeigen"
	L.OPT_SHOW_SELF    = "Für dich selbst anzeigen"
	L.OPT_INTRO        = "Legt fest, wann BlessingBuddy außerhalb des Kampfes bei befreundeten Zielen erscheint."
	L.HELP_OPTS        = "  Optionen: Optionen > AddOns > BlessingBuddy"
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

-- Forever: Werte können "secret" sein (z. B. während der globalen Abklingzeit)
-- -> nie direkt vergleichen, sondern über SafeGreater prüfen
local function SafeGreater(v, limit)
	local ok, res = pcall(function() return type(v) == "number" and v > limit end)
	if ok then return res end
	return nil -- nicht vergleichbar (secret)
end

-- Liefert start, duration, isOnGCD (isOnGCD = nil, wenn der Client es nicht meldet)
local function Cooldown(name)
	if C_Spell and C_Spell.GetSpellCooldown then
		local cd = C_Spell.GetSpellCooldown(name)
		if cd then return cd.startTime, cd.duration, cd.isOnGCD end
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

-- Liefert: alle Buffs auf dem Ziel (Name -> true) und die von dir gewirkten.
-- Forever: Im Kampf sind die Buff-Daten fremder Ziele "secret" – die API wirft
-- dann einen Fehler. In dem Fall gilt der letzte lesbare Stand dieses Ziels
-- (wird beim Zielwechsel verworfen). 4. Rückgabewert: false = Daten veraltet.
-- Eigene Segen: Zeitpunkt des letzten Wirkens pro Ziel (Fallback, falls der
-- Client die Restzeit fremder Spieler nicht liefert). Forever: 60 Minuten.
local BUFF_DURATION = 3600

local auraCache -- { all, mine, mineExp, mineApp } des aktuellen Ziels
local Log, S -- unten definiert

local function ReadTargetBuffs()
	local all, mine, mineExp, mineApp = {}, {}, {}, {}
	for i = 1, 40 do
		local name, source, expires, dur
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local a = C_UnitAuras.GetAuraDataByIndex("target", i, "HELPFUL")
			if a then name, source, expires, dur = a.name, a.sourceUnit, a.expirationTime, a.duration end
		else
			local n, _, _, _, d, e, s = UnitBuff("target", i)
			name, source, expires, dur = n, s, e, d
		end
		if not name then break end
		all[name] = true
		if source and UnitIsUnit(source, "player") then
			mine[name] = true
			if SafeGreater(expires, 0) then mineExp[name] = expires end
			-- Zeitpunkt des Auflegens (nil, wenn secret)
			local okA, app = pcall(function()
				if type(expires) == "number" and type(dur) == "number" and dur > 0 then return expires - dur end
			end)
			if okA and app then mineApp[name] = app end
		end
	end
	return all, mine, mineExp, mineApp
end

-- Forever: Ist das Ziel im Kampf, liefert der Client seine Buffs entweder gar
-- nicht (Fehler) oder mit dem alten Stand von vor dem Kampf. Eigene, erfolgreich
-- gewirkte Buffs werden deshalb hier gemerkt und über jedes Leseergebnis gelegt,
-- bis die echten Daten sie bestätigen (oder das Ziel ohne sie außer Kampf ist).
local pendingOwn = {} -- [Zielname][Buffname] = GetTime() des eigenen Casts

local function ApplyPending(all, mine, mineExp, mineApp, fresh)
	local tname = UnitName("target")
	local p = tname and pendingOwn[tname]
	if not p then return end
	local okC, inCombat = pcall(function() return UnitAffectingCombat("target") and true or false end)
	local calm = fresh and okC and inCombat == false
	local now = GetTime()
	for s, t in pairs(p) do
		local app = mineApp and mineApp[s]
		if fresh and mine[s] and app and app >= t - 2 then
			p[s] = nil -- echte Daten zeigen den neuen Buff
			Log("pending %s on %s: confirmed", S(s), S(tname))
		elseif (calm and now - t > 3) or now - t > BUFF_DURATION then
			p[s] = nil -- Ziel außer Kampf, Daten wieder echt
			Log("pending %s on %s: dropped (calm=%s)", S(s), S(tname), S(calm))
		else
			all[s] = true
			mine[s] = true
			mineExp[s] = nil -- Restzeit aus myCasts
		end
	end
	if next(p) == nil then pendingOwn[tname] = nil end
end

local function TargetBuffs()
	if not UnitExists("target") then return {}, {}, {}, true end
	local ok, all, mine, mineExp, mineApp = pcall(ReadTargetBuffs)
	local fresh = ok
	if ok then
		auraCache = { all, mine, mineExp, mineApp }
	elseif auraCache then
		all, mine, mineExp, mineApp = auraCache[1], auraCache[2], auraCache[3], auraCache[4]
	else
		auraCache = { {}, {}, {}, {} }
		all, mine, mineExp, mineApp = auraCache[1], auraCache[2], auraCache[3], auraCache[4]
	end
	pcall(function() -- Diagnose: Lesestatus nur bei Änderung loggen
		if not pendingOwn[UnitName("target")] then return end
		local okC, inCombat = pcall(UnitAffectingCombat, "target")
		local state = S(fresh) .. "/" .. (okC and S(inCombat) or "secret")
		if state ~= auraCache.logState then
			auraCache.logState = state
			Log("pending read: fresh/targetCombat=%s", state)
		end
	end)
	pcall(ApplyPending, all, mine, mineExp, mineApp, fresh)
	return all, mine, mineExp, fresh
end

local REFRESH_BELOW = 300 -- ab 5 Minuten Restzeit wird Auffrischen empfohlen
local myCasts = {}        -- [Zielname][Zaubername] = GetTime()
local pendingCasts = {}   -- [castGUID] = Zielname

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

-- Eigenen, erfolgreich gewirkten Buff für ApplyPending merken (nur Buffs aus
-- der Buff-Liste, keine Heilzauber)
local function RememberOwnBuff(tname, sname)
	if not tname or not sname then return end
	for _, key in ipairs(ORDER) do
		for _, n in ipairs(NamesFor(key)) do
			if n == sname then
				pendingOwn[tname] = pendingOwn[tname] or {}
				pendingOwn[tname][sname] = GetTime()
				Log("pending %s on %s: noted", S(sname), S(tname))
				return
			end
		end
	end
end

-- Restzeit (Sekunden) deines eigenen Buffs dieses Schlüssels auf dem Ziel,
-- nil wenn nicht von dir oder unbekannt
local function MyRemaining(key, mine, mineExp)
	if not key then return nil end
	local tname = UnitName("target")
	for _, n in ipairs(NamesFor(key)) do
		if mine[n] then
			if mineExp[n] then return mineExp[n] - GetTime() end
			local t = tname and myCasts[tname] and myCasts[tname][n]
			if t then return BUFF_DURATION - (GetTime() - t) end
			return nil
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Zustand
------------------------------------------------------------------------
local db
local SyncOptionsPanel

local function EnsureDefaults()
	if not db then return end
	if db.showOutsideGroup == nil then db.showOutsideGroup = true end
	if db.showPartyMembers == nil then db.showPartyMembers = false end
	if db.showRaidMembers == nil then db.showRaidMembers = false end
	if db.showSelf == nil then db.showSelf = false end
end

------------------------------------------------------------------------
-- Debug-Log (landet in WTF\Account\<KONTO>\SavedVariables\BlessingBuddy.lua,
-- geschrieben bei /reload oder Ausloggen). Aktivieren mit /bb log on
------------------------------------------------------------------------
local LOG_MAX = 400
function S(v) -- local, vorab deklariert
	local ok, str = pcall(tostring, v)
	return ok and str or "<secret>"
end
function Log(fmt, ...) -- local, vorab deklariert (vor TargetBuffs)
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
			Log("  C_UnitAuras[%d] name=%s id=%s src=%s fromPlayer=%s dur=%s left=%s", i,
				S(a.name), S(a.spellId), S(a.sourceUnit), S(a.isFromPlayerOrPlayerPet), S(a.duration),
				S(SafeGreater(a.expirationTime, 0) and math.floor(a.expirationTime - GetTime()) or a.expirationTime))
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

-- Heil-Vorschau (wie Healium): Balken hängen an der rechten Kante der
-- Lebensanzeige; der Clip-Rahmen schneidet alles über 100 % ab (= Überheilung).
-- Forever: Lebenswerte fremder Spieler sind im Kampf "secret" -> nie in Lua
-- rechnen, sondern die Werte direkt an die StatusBars geben.
local predClip = CreateFrame("Frame", nil, hp)
predClip:SetAllPoints(hp)
predClip:SetClipsChildren(true)
predClip:SetFrameLevel(hp:GetFrameLevel() + 1)

local function CreatePredictBar(r, g, b, a)
	local bar = CreateFrame("StatusBar", nil, predClip)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(r, g, b, a)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:SetHeight(HP_H)
	bar:Hide()
	return bar
end
-- eingehende Heilung (deine und fremde, während des Zauberns)
local incBar = CreatePredictBar(0.0, 0.55, 0.3, 0.9)
incBar:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
-- Vorschau beim Drüberfahren über einen Heil-Button (schließt an die eingehende an)
-- verbleibende Heilung laufender HoTs (Verjüngung, Nachwachsen, Erneuerung)
local hotBar = CreatePredictBar(0.0, 0.75, 0.65, 0.85)
hotBar:SetPoint("TOPLEFT", incBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
local previewBar = CreatePredictBar(0.6, 1.0, 0.6, 0.7)
previewBar:SetPoint("TOPLEFT", hotBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
hp:SetScript("OnSizeChanged", function(self, w)
	incBar:SetWidth(w); hotBar:SetWidth(w); previewBar:SetWidth(w)
end)
local previewSpellID -- Heil-Button, über dem die Maus gerade steht
local UpdatePrediction -- wird weiter unten definiert

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

	-- Markierung "passt nicht zum Ziel" (im Kampf darf die Leiste nicht
	-- umgebaut werden): roter Rand + rote Überlagerung, Icon abgedunkelt
	b.badBorder = b:CreateTexture(nil, "BACKGROUND")
	b.badBorder:SetColorTexture(0.88, 0.16, 0.16, 1)
	b.badBorder:SetPoint("TOPLEFT", -2, 2)
	b.badBorder:SetPoint("BOTTOMRIGHT", 2, -2)
	b.badBorder:Hide()
	b.bad = b:CreateTexture(nil, "OVERLAY", nil, -1)
	b.bad:SetAllPoints(b.icon)
	b.bad:SetColorTexture(0.8, 0.08, 0.08, 0.42)
	b.bad:Hide()

	b:SetScript("OnEnter", function(self)
		if not self.spellID then return end
		GameTooltip:SetOwner(self, self.tooltipAnchor or "ANCHOR_TOP")
		GameTooltip:SetSpellByID(self.spellID)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	allButtons[#allButtons + 1] = b
	return b
end

-- Passt der Buff dieses Schlüssels zum aktuellen Ziel? Wie UpdateSecure:
-- Begleiter nehmen nur petOK-Buffs an, ohne passenden Rang kein Buff.
-- spellID = der auf dem Button liegende Rang: ist er für das Ziel zu hoch
-- (Lernstufe > Zielstufe + 10), schlägt der Zauber fehl -> ebenfalls markieren
local function BadForTarget(key, spellID)
	if not key or not UnitExists("target") then return false end
	if not UnitIsPlayer("target") and not (CFG.petOK and CFG.petOK[key]) then return true end
	local tLevel = TargetLevel()
	if BuffRankFor(BLESSINGS[key], tLevel) == nil then return true end
	if spellID and tLevel then
		local fallback
		for _, r in ipairs(BUFF_RANKS[BLESSINGS[key]] or {}) do
			if r[1] == spellID then fallback = r[2] end
		end
		local need = LearnLevel(spellID, fallback)
		if need and need > tLevel + 10 then return true end
	end
	return false
end

local function SetBad(b, bad)
	if (b.badState or false) ~= (bad or false) then
		Log("mark %s bad=%s combat=%s", S(b.spellName), S(bad), S(InCombatLockdown()))
	end
	b.badState = bad or nil
	b.badBorder:SetShown(bad)
	b.bad:SetShown(bad)
	b.icon:SetDesaturated(bad)
	if bad then b.icon:SetVertexColor(0.55, 0.55, 0.55) end
end

local best = CreateSpellButton("BlessingBuddyBestButton", BEST)
best.border = best:CreateTexture(nil, "OVERLAY")
best.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
best.border:SetBlendMode("ADD")
best.border:SetVertexColor(1, 0.82, 0)
best.border:SetPoint("CENTER")
best.border:SetSize(BEST * 1.8, BEST * 1.8)
best.border:Hide()
best.timer = best:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
best.timer:SetPoint("BOTTOM", 0, 2)
best.timer:SetTextColor(1, 0.82, 0)
best.timer:Hide()

-- Zustand des großen Buttons: normal / erledigt (ausgegraut) / auffrischen (gelb)
local function UpdateBestState()
	if best.badState then -- passt nicht zum Ziel: Markierung hat Vorrang
		best.border:Hide(); best.timer:Hide()
		return
	end
	if not best:IsShown() or not best.key then
		best.icon:SetDesaturated(false); best.border:Hide(); best.timer:Hide()
		return
	end
	local _, mine, mineExp = TargetBuffs()
	if not HasKey(mine, best.key) then
		best.icon:SetDesaturated(false); best.border:Hide(); best.timer:Hide()
		return
	end
	local rem = MyRemaining(best.key, mine, mineExp)
	if rem and rem <= REFRESH_BELOW then
		best.icon:SetDesaturated(false)
		best.border:Show()
		best.timer:SetText(string.format("%d:%02d", math.max(0, math.floor(rem / 60)), math.max(0, math.floor(rem % 60))))
		best.timer:Show()
	else
		best.icon:SetDesaturated(true) -- erledigt: dein Segen ist noch frisch
		best.border:Hide(); best.timer:Hide()
	end
end

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

local function UnitInPlayerRaid(unit)
	if UnitPlayerOrPetInRaid then return UnitPlayerOrPetInRaid(unit) end
	return UnitInRaid(unit)
end

local function UnitInPlayerParty(unit)
	if UnitPlayerOrPetInParty then return UnitPlayerOrPetInParty(unit) end
	return UnitInParty(unit)
end

local function InMyGroup(unit)
	return UnitInPlayerParty(unit) or UnitInPlayerRaid(unit)
end

local function GetTargetVisibilityCategory(unit)
	if UnitIsUnit(unit, "player") then
		return "self"
	end
	if UnitInRaid and UnitInRaid("player") and UnitInPlayerRaid(unit) then
		return "raid"
	end
	if UnitInPlayerParty(unit) then
		return "party"
	end
	return "outside"
end

local function VisibilityAllowedForCategory(cat)
	if not db then return false end
	EnsureDefaults()
	if cat == "outside" then return db.showOutsideGroup end
	if cat == "party" then return db.showPartyMembers end
	if cat == "raid" then return db.showRaidMembers end
	if cat == "self" then return db.showSelf end
	return false
end

local function TargetIsSelf()
	return UnitExists("target") and UnitIsUnit("target", "player")
end

-- Forever/Classic: UnitIsFriend("player", "target") is often nil when target is you.
local function IsVisibilityTarget()
	if not UnitExists("target") or UnitIsDeadOrGhost("target") then return false end
	if TargetIsSelf() then return true end
	return (UnitIsPlayer("target") or IsOtherPet("target")) and UnitIsFriend("player", "target")
end

local function IsBuffLayoutTarget()
	if not UnitExists("target") or UnitIsDeadOrGhost("target") then return false end
	if TargetIsSelf() then
		EnsureDefaults()
		return db.showSelf
	end
	return UnitIsFriend("player", "target")
		and (UnitIsPlayer("target") or IsOtherPet("target"))
end

local function ShouldShow()
	if forceShow then return true end
	return IsVisibilityTarget()
		and VisibilityAllowedForCategory(GetTargetVisibilityCategory("target"))
end

-- Sichtbarkeit über einen sicheren State-Driver, damit die Leiste auch im
-- Kampf beim Anklicken erscheint. Im Kampf: jeder befreundete, lebende Spieler
-- (die drei Sichtbarkeits-Optionen gelten nur außerhalb des Kampfes).
-- Außerhalb: das Ergebnis von ShouldShow().
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

-- Geschätzte Heilmenge eines Zaubers: Mittelwert aus dem Zaubertext
-- ("heilt 42 bis 51") plus anteiliger Heilungsbonus (Classic-Faustregel:
-- Zauberzeit / 3,5 Sek.). nil, wenn der Text keine Zahl liefert.
local descCache = {}
local function SpellBaseHeal(id)
	if descCache[id] ~= nil then return descCache[id] or nil end
	local getDesc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
	if not getDesc then return nil end
	local ok, d = pcall(getDesc, id)
	if not ok or type(d) ~= "string" or (issecretvalue and issecretvalue(d)) then return nil end
	if d == "" then return nil end -- Zauberdaten noch nicht geladen: später erneut
	d = d:gsub("(%d)[%.,](%d%d%d)", "%1%2") -- Tausenderpunkte entfernen
	local lo, hi = d:match("(%d+)%s*bis%s*(%d+)")
	if not lo then lo, hi = d:match("(%d+)%s*to%s*(%d+)") end
	local val
	if lo then
		val = (tonumber(lo) + tonumber(hi)) / 2
	else
		-- HoTs: "um 45 im Verlauf von 15 Sek." -> größte Zahl, die keine Zeitangabe ist
		for num, unit in d:gmatch("(%d+)%s*(%a*)") do
			local u = unit:lower()
			if not (u:find("^sek") or u:find("^sec") or u:find("^min")) then
				local n = tonumber(num)
				if n and (not val or n > val) then val = n end
			end
		end
	end
	descCache[id] = val or false
	return val
end

local function HealAmount(id)
	local base = SpellBaseHeal(id)
	if not base then return nil end
	local bonus = 0
	if GetSpellBonusHealing then
		local ok, b = pcall(GetSpellBonusHealing)
		if ok and SafeGreater(b, 0) then
			local castMs = 1500
			if C_Spell and C_Spell.GetSpellInfo then
				local info = C_Spell.GetSpellInfo(id)
				if info and SafeGreater(info.castTime, 0) then castMs = info.castTime end
			end
			bonus = b * math.min(castMs / 1000, 3.5) / 3.5
		end
	end
	return math.floor(base + bonus + 0.5)
end

------------------------------------------------------------------------
-- HoTs: verbleibende Heilung laufender HoTs auf dem Ziel.
-- UnitGetIncomingHeals kennt keine HoTs. Wir lesen die HoT-Buffs (Restzeit)
-- und schätzen die Gesamtheilung aus dem Zaubertext des Rangs. Im Kampf sind
-- die Buffs fremder Ziele secret -> letzter Stand wird weitergerechnet;
-- eigene HoTs, die im Kampf gewirkt werden, kommen über dein Wirken dazu.
------------------------------------------------------------------------
local HOT_BASE = { 774, 8936, 139 } -- Verjüngung, Nachwachsen, Erneuerung
local hotNames
local function IsHot(name)
	if not name then return false end
	if not hotNames then
		local t, n = {}, 0
		for _, id in ipairs(HOT_BASE) do
			local nm = SpellInfo(id)
			if nm then t[nm] = true; n = n + 1 end
		end
		if n == 0 then return false end
		hotNames = t
	end
	return hotNames[name] == true
end

local function IsTimeUnit(unit)
	local u = unit:lower()
	return u:find("^sek") or u:find("^sec") or u:find("^min")
end

-- Gesamtheilung und Dauer (Sek.) des HoT-Anteils aus dem Zaubertext.
-- Direktheilung ("93 bis 107", z. B. bei Nachwachsen) wird vorher entfernt.
local hotDescCache = {}
local function HotInfo(id)
	local c = hotDescCache[id]
	if c ~= nil then
		if c then return c[1], c[2] end
		return nil
	end
	local getDesc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
	if not getDesc or not id then return nil end
	local ok, d = pcall(getDesc, id)
	if not ok or type(d) ~= "string" or (issecretvalue and issecretvalue(d)) or d == "" then return nil end
	d = d:gsub("(%d)[%.,](%d%d%d)", "%1%2")
	local dur
	for num, unit in d:gmatch("(%d+)%s*(%a*)") do
		local u = unit:lower()
		if u:find("^sek") or u:find("^sec") then dur = tonumber(num) end
	end
	local rest = d:gsub("%d+%s*bis%s*%d+", ""):gsub("%d+%s*to%s*%d+", "")
	local total
	for num, unit in rest:gmatch("(%d+)%s*(%a*)") do
		if not IsTimeUnit(unit) then
			local n = tonumber(num)
			if n and (not total or n > total) then total = n end
		end
	end
	if total and dur and dur > 0 then
		hotDescCache[id] = { total, dur }
		return total, dur
	end
	hotDescCache[id] = false
	return nil
end

-- Heilungsbonus für eigene HoTs (Classic-Faustregel: Dauer / 15 Sek.)
local function OwnHotBonus(dur)
	if not GetSpellBonusHealing then return 0 end
	local ok, b = pcall(GetSpellBonusHealing)
	if ok and SafeGreater(b, 0) then return b * math.min(dur, 15) / 15 end
	return 0
end

local hots = {} -- { name, expires, duration, total, own } des aktuellen Ziels

local function ReadHots()
	local list = {}
	for i = 1, 40 do
		local a = C_UnitAuras.GetAuraDataByIndex("target", i, "HELPFUL")
		if not a then break end
		if IsHot(a.name) and SafeGreater(a.expirationTime, 0) then
			local total, ddur = HotInfo(a.spellId)
			if total then
				local dur = SafeGreater(a.duration, 0) and a.duration or ddur
				local own = a.sourceUnit ~= nil and UnitIsUnit(a.sourceUnit, "player")
				if own then total = total + OwnHotBonus(dur) end
				list[#list + 1] = { name = a.name, expires = a.expirationTime, duration = dur, total = total, own = own }
			end
		end
	end
	return list
end

local function RefreshHots()
	if not UnitExists("target") then hots = {}; return end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	local ok, list = pcall(ReadHots)
	if ok and list then hots = list end -- secret (Kampf): alten Stand behalten
end

-- Eigener HoT auf das aktuelle Ziel gewirkt (funktioniert auch im Kampf)
local function AddOwnHot(spellID)
	local name = SpellInfo(spellID or 0)
	if not IsHot(name) then return end
	local total, dur = HotInfo(spellID)
	if not total then return end
	for i = #hots, 1, -1 do
		if hots[i].own and hots[i].name == name then table.remove(hots, i) end
	end
	hots[#hots + 1] = { name = name, expires = GetTime() + dur, duration = dur,
		total = total + OwnHotBonus(dur), own = true }
end

local function HotRemaining()
	local now, sum = GetTime(), 0
	for i = #hots, 1, -1 do
		local h = hots[i]
		local left = h.expires - now
		if left <= 0 then
			table.remove(hots, i)
		else
			sum = sum + h.total * math.min(1, left / h.duration)
		end
	end
	return math.floor(sum + 0.5)
end

UpdatePrediction = function()
	if not UnitExists("target") then
		incBar:Hide(); hotBar:Hide(); previewBar:Hide()
		hots = {}
		return
	end
	local okMax, maxHP = pcall(UnitHealthMax, "target")
	if not okMax or not maxHP then incBar:Hide(); hotBar:Hide(); previewBar:Hide(); return end

	-- eingehende Heilung (secret-Werte gehen direkt an den Balken)
	local inc = 0
	if UnitGetIncomingHeals then
		local ok, v = pcall(UnitGetIncomingHeals, "target")
		if ok then
			if issecretvalue and issecretvalue(v) then inc = v -- secret: nur an den Balken
			elseif v then inc = v end
		end
	end
	pcall(function()
		incBar:SetMinMaxValues(0, maxHP)
		incBar:SetValue(inc)
	end)
	incBar:Show()

	-- laufende HoTs (Wert 0 = unsichtbar, Vorschau hängt trotzdem korrekt dahinter)
	RefreshHots()
	local hot = HotRemaining()
	pcall(function()
		hotBar:SetMinMaxValues(0, maxHP)
		hotBar:SetValue(hot)
	end)
	hotBar:Show()

	local amount = previewSpellID and HealAmount(previewSpellID)
	if amount then
		pcall(function()
			previewBar:SetMinMaxValues(0, maxHP)
			previewBar:SetValue(amount)
		end)
		previewBar:Show()
	else
		previewBar:Hide()
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
	UpdatePrediction()
end

for i = 1, MAX_HEALS do
	heal[i].tooltipAnchor = "ANCHOR_BOTTOM" -- Tooltip nach unten, damit die Heil-Vorschau sichtbar bleibt
	heal[i]:HookScript("OnEnter", function(self)
		previewSpellID = self.spellID
		UpdatePrediction()
	end)
	heal[i]:HookScript("OnLeave", function()
		previewSpellID = nil
		UpdatePrediction()
	end)
end

-- Nicht-geschützte Optik: darf auch im Kampf laufen
local function UpdateVisuals()
	if not frame:IsShown() then return end
	local all = TargetBuffs()
	for _, key in ipairs(ORDER) do
		local b = small[key]
		b.active:SetShown(b.spellName ~= nil and HasKey(all, key))
		SetBad(b, b.spellName ~= nil and BadForTarget(key, b.spellID))
	end
	best.active:SetShown(best.spellName ~= nil and HasKey(all, best.key))
	SetBad(best, best.spellName ~= nil and BadForTarget(best.key, best.spellID))
	UpdateBestState()
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

	-- Nur echte Buff-Ziele (befreundete Spieler oder Begleiter) bestimmen die
	-- Belegung. Gegner, NPCs oder du selbst (ohne Option): neutrale Belegung
	-- wie ohne Ziel (alle gelernten Buffs, höchster Rang), denn im Kampf kann
	-- die Leiste nicht mehr umgebaut werden und muss dann für jeden Spieler passen.
	local buffTarget = IsBuffLayoutTarget()
	local all, mine = TargetBuffs()
	local bestKey = buffTarget and PickBest(all, mine) or nil

	-- Reihe 1: Empfehlung + Buffs
	local x0 = bestKey and (PAD + BEST + GAP) or PAD
	local row1H = bestKey and BEST or SMALL
	local ySmall = -TITLE_H - (row1H - SMALL) / 2
	local nBuff = 0
	-- Begleiter: die meisten Buffs wirken in Forever nicht -> nur petOK-Buffs zeigen
	local petTarget = buffTarget and not UnitIsPlayer("target")
	local tLevel = buffTarget and TargetLevel() or nil
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
	if best.timer:IsShown() or best.icon:IsDesaturated() then UpdateBestState() end
	if #hots > 0 then UpdatePrediction() end
	local hasTarget = UnitExists("target")
	for _, b in ipairs(allButtons) do
		if b:IsShown() and b.spellName then
			if b.badState then
				b.icon:SetVertexColor(0.55, 0.55, 0.55) -- Markierung "passt nicht"
			elseif hasTarget and InRange(b.spellName) == false then
				b.icon:SetVertexColor(1, 0.3, 0.3)
			else
				b.icon:SetVertexColor(1, 1, 1)
			end
			local start, duration, onGCD = Cooldown(b.spellName)
			if onGCD then -- globale Abklingzeit ignorieren
				b.cd:Clear()
			else
				local long = SafeGreater(duration, 1.5)
				if long == true then
					b.cd:SetCooldown(start, duration)
				elseif long == false then
					b.cd:Clear()
				elseif not pcall(b.cd.SetCooldown, b.cd, start, duration) then
					b.cd:Clear() -- secret und vom Widget nicht angenommen
				end
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
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_HEAL_PREDICTION",
	"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_FAILED_QUIET", "UI_ERROR_MESSAGE",
}) do SafeRegister(e) end

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
	if event:find("^UNIT_SPELLCAST") then
		if arg1 == "player" then
			if event == "UNIT_SPELLCAST_SENT" and arg3 then
				pendingCasts[arg3] = arg2
			elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg2 and pendingCasts[arg2] then
				local tname = pendingCasts[arg2]
				pendingCasts[arg2] = nil
				local sname = SpellInfo(arg3 or 0)
				if tname and sname then
					-- Forever meldet hier "Vorname Nachname"; UnitName liefert nur den
					-- Vornamen -> nur das erste Wort (ohne Realm) als Schlüssel
					tname = tname:match("^[^%s%-]+") or tname
					myCasts[tname] = myCasts[tname] or {}
					myCasts[tname][sname] = GetTime()
					RememberOwnBuff(tname, sname)
					local okT, same = pcall(function() return UnitName("target") == tname end)
					if okT and same then
						AddOwnHot(arg3)
						UpdateVisuals()
						UpdatePrediction()
					end
				end
			end
		end
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
	end
	if event == "PLAYER_TARGET_CHANGED" then auraCache = nil; hots = {} end
	if event == "PLAYER_TARGET_CHANGED" and db and db.debug and UnitExists("target") then
		local _, class = UnitClass("target")
		Log("--- target %s class=%s level=%s player=%s friend=%s inGroup=%s category=%s myLevel=%s",
			S(UnitName("target")), S(class), S(UnitLevel("target")), S(UnitIsPlayer("target")),
			S(UnitIsFriend("player", "target")), S(InMyGroup("target")),
			S(GetTargetVisibilityCategory("target")), S(UnitLevel("player")))
		LogRawAuras()
	end
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			BlessingBuddyDB = BlessingBuddyDB or {}
			db = BlessingBuddyDB
			EnsureDefaults()
			RestorePosition()
			SyncOptionsPanel()
		end
		return
	elseif event == "PLAYER_LOGIN" then
		if not db then
			BlessingBuddyDB = BlessingBuddyDB or {}
			db = BlessingBuddyDB
		end
		EnsureDefaults()
		RestorePosition()
		BuildRankMap()
		SyncOptionsPanel()
	elseif event == "SPELLS_CHANGED" then
		BuildRankMap()
		wipe(descCache)
		wipe(hotDescCache)
		hotNames = nil
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH_FREQUENT"
		or event == "UNIT_HEAL_PREDICTION" then
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
			.. " selfTarget=" .. v(TargetIsSelf)
			.. " player=" .. v(UnitIsPlayer, "target")
			.. " controlled=" .. v(UnitPlayerControlled, "target")
			.. " ownPet=" .. v(UnitIsUnit, "target", "pet"))
		print("  friend=" .. v(UnitIsFriend, "player", "target")
			.. " dead=" .. v(UnitIsDeadOrGhost, "target")
			.. " inGroup=" .. v(InMyGroup, "target")
			.. " category=" .. (UnitExists("target") and GetTargetVisibilityCategory("target") or "-")
			.. " creatureType=" .. v(UnitCreatureType, "target"))
		if db then
			EnsureDefaults()
			print("  showOutside=" .. tostring(db.showOutsideGroup)
				.. " showParty=" .. tostring(db.showPartyMembers)
				.. " showRaid=" .. tostring(db.showRaidMembers)
				.. " showSelf=" .. tostring(db.showSelf))
		end
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
	elseif msg == "healtest" then
		-- Prüft, welche Daten der Client für eine Heil-Vorschau hergibt
		local function sec(x)
			if issecretvalue and issecretvalue(x) then return "|cffffa000secret|r" end
			return tostring(x)
		end
		local function has(x) return x and "|cff40ff40ja|r" or "|cffff4040nein|r" end
		-- Ausgabe in den Chat UND ins Log (auch ohne /bb log on)
		local print = function(line)
			_G.print(line)
			if db then
				db.log = db.log or {}
				table.insert(db.log, date("%H:%M:%S") .. " healtest " .. tostring(line):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
				while #db.log > LOG_MAX do table.remove(db.log, 1) end
			end
		end
		print(PREFIX .. "healtest:")
		print("  issecretvalue=" .. has(issecretvalue)
			.. " UnitGetIncomingHeals=" .. has(UnitGetIncomingHeals)
			.. " UnitGetDetailedHealPrediction=" .. has(UnitGetDetailedHealPrediction)
			.. " CreateUnitHealPredictionCalculator=" .. has(CreateUnitHealPredictionCalculator))
		print("  GetSpellDescription=" .. has(C_Spell and C_Spell.GetSpellDescription or GetSpellDescription)
			.. " GetSpellBonusHealing=" .. has(GetSpellBonusHealing))
		if UnitExists("target") then
			local okH, h = pcall(UnitHealth, "target")
			local okM, m = pcall(UnitHealthMax, "target")
			print("  target: health=" .. (okH and sec(h) or "ERR") .. " max=" .. (okM and sec(m) or "ERR"))
			if UnitGetIncomingHeals then
				local ok, inc = pcall(UnitGetIncomingHeals, "target")
				print("  incomingHeals=" .. (ok and sec(inc) or "ERR"))
			end
		end
		if GetSpellBonusHealing then
			local ok, b = pcall(GetSpellBonusHealing)
			print("  bonusHealing=" .. (ok and sec(b) or "ERR"))
		end
		local getDesc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
		for i = 1, MAX_HEALS do
			local b = heal[i]
			if b.spellID then
				local ok, d = pcall(getDesc or function() return nil end, b.spellID)
				print("  " .. tostring(b.spellName) .. " (" .. b.spellID .. "): " .. (ok and sec(d) or "ERR"))
				print("    -> geschätzt: " .. tostring(HealAmount(b.spellID)))
			end
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
		if L.HELP_OPTS then print(L.HELP_OPTS) end
	end
end

------------------------------------------------------------------------
-- Interface-Optionen
------------------------------------------------------------------------
local optionsPanel

local function OptionChecked(key, defaultWhenNil)
	if not db then return defaultWhenNil end
	EnsureDefaults()
	local v = db[key]
	if v == nil then return defaultWhenNil end
	return v == true
end

local function SetCheckState(cb, checked)
	if cb then cb:SetChecked(checked and true or false) end
end

SyncOptionsPanel = function()
	if not optionsPanel or not db then return end
	EnsureDefaults()
	SetCheckState(optionsPanel.outside, OptionChecked("showOutsideGroup", true))
	SetCheckState(optionsPanel.party, OptionChecked("showPartyMembers", false))
	SetCheckState(optionsPanel.raid, OptionChecked("showRaidMembers", false))
	SetCheckState(optionsPanel.self, OptionChecked("showSelf", false))
end

local function InitOptionsPanel()
	if optionsPanel then return end
	local panel = CreateFrame("Frame", "BlessingBuddyOptionsPanel")
	panel.name = "BlessingBuddy"
	optionsPanel = panel

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("BlessingBuddy")

	local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", -16, 0)
	intro:SetJustifyH("LEFT")
	intro:SetText(L.OPT_INTRO)

	local function AddCheck(y, label, key)
		local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 16, y)
		cb.Text:SetText(label)
		cb:SetScript("OnClick", function(self)
			if not db then return end
			db[key] = self:GetChecked() == true
			UpdateSecure()
		end)
		return cb
	end

	panel.outside = AddCheck(-72, L.OPT_SHOW_OUTSIDE, "showOutsideGroup")
	panel.party = AddCheck(-100, L.OPT_SHOW_PARTY, "showPartyMembers")
	panel.raid = AddCheck(-128, L.OPT_SHOW_RAID, "showRaidMembers")
	panel.self = AddCheck(-156, L.OPT_SHOW_SELF, "showSelf")

	panel:SetScript("OnShow", SyncOptionsPanel)
	-- Interface Options (legacy) and Settings > AddOns call refresh when the panel is shown.
	panel.refresh = SyncOptionsPanel
	panel.OnRefresh = SyncOptionsPanel

	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON)
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

InitOptionsPanel()
