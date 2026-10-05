# BlessingBuddy Changelog

## 1.5.00 (2026-10-04)
- New: running HoTs on the target (Rejuvenation, Regrowth, Renew – yours and others') show their remaining healing as a teal section on the health bar, right after incoming heals
  - In combat the client protects the target's buffs: the last known HoTs keep counting down, and HoTs you cast yourself are added from your own casts

## 1.4.01 (2026-10-04)
- Fixed: the tooltip of heal buttons covered the health bar and its heal preview – it now opens below the button

## 1.4.00 (2026-10-04)
- New: heal prediction on the health bar – incoming heals (yours and others', while being cast) show as a dark green extension; anything beyond 100 % is cut off, so overhealing is visible at a glance
- New: hover a heal button to preview how far it would fill the health bar (light green, estimated from the spell text plus your bonus healing)
- New: `/bb healtest` shows which heal-prediction data the client provides and also writes it to the debug log

## 1.3.02 (2026-10-04)
- Fixed: Lua error "Auras cannot be accessed when secret" in combat – while the client protects the target's buffs, the last known state is kept

## 1.3.01 (2026-10-04)
- Fixed: Lua error "attempt to compare local 'duration' (a secret number value)" during the global cooldown – cooldown and buff timers are now read safely when the client protects them

## 1.3.00 (2026-10-03)
- Paladin: removed Blessing of Protection from the rescue row – it can only be cast on party/raid members
- Fixed: Greater Blessings and group buffs (Gift of the Wild, Prayer of Fortitude, Arcane Brilliance, …) now count as the matching single buff – the recommendation moves on instead of suggesting a buff that wouldn't stack
- Fixed: buffs now respect the target-level limit – the highest rank that works on the target is cast, and buffs with no usable rank are hidden (e.g. Kings on targets below level 10)
- Paladin: when your own blessing is already on the target, the big button is greyed out ("done") while it has more than 5 minutes left, and turns into a yellow-framed refresh button with a countdown below 5 minutes (Forever blessings last 60 minutes)
- `/bb` help now shows the addon version
- `/bb debug` now lists the target's buffs (yours marked with *)
- New: `/bb log on|off|clear` writes a detailed debug log (target, raw buff data, casts, error messages) to the SavedVariables file – helpful for bug reports

## 1.2.6 (2026-10-03)
- Fixed: buffs and heals now always cast your highest learned rank (WoW: Forever doesn't pick it automatically when casting by name)
- Fixed: recommendation now also updates when the client doesn't send aura events for players outside your group (checks the target's buffs twice per second)
- Druid: after Mark of the Wild, Thorns is now recommended for every class (was melee only)
- New: `/bb debug` prints diagnostic info about the current target

## 1.2.3 (2026-10-03)
- New: pets of other players (hunter pets, warlock demons) are supported with health bar and rescue row
  - Most buffs don't apply to pets in WoW: Forever, so the buff row only shows what works (Druid: Thorns, also recommended)
  - Pets of your own party/raid members are excluded like their owners (outside combat)
  - Title shows the pet name in green with "(Pet)"

## 1.1.2 (2026-10-03)
- Fixed: the recommended button now updates right after a buff lands on the target (e.g. Druid: Mark -> Thorns)

## 1.1.1 (2026-10-03)
- Cleaner title bar: class-colored name + level on the left, health percent on the right
- Removed the arrow glyph that the game font can't display
- Health bar now works with protected ("secret") health values of the new client

## 1.1.0 (2026-10-03)
- New: rescue row with heals, shields and dispels below the buffs
  - Paladin: Flash of Light, Holy Light, Lay on Hands, Blessing of Protection, Blessing of Freedom, Cleanse/Purify
  - Druid: Regrowth, Healing Touch, Rejuvenation, Swiftmend, Remove Curse, Abolish/Cure Poison
  - Priest: Power Word: Shield, Flash Heal, Greater Heal/Heal/Lesser Heal, Renew, Dispel Magic, Abolish/Cure Disease
  - Shaman: Lesser Healing Wave, Healing Wave, Chain Heal, Cure Poison, Cure Disease
  - Mage: Remove Lesser Curse
- New: target health bar with percentage
- New: cooldown display on all buttons (e.g. Lay on Hands)
- New: bar now also appears when you target a friendly player while already in combat (any friendly player, also party members)
- New: red "PvP" warning when the target is PvP-flagged and you are not
- New: keybinds for heal slots 1-3

## 1.0.0 (2026-10-03)
- First public release for WoW: Forever (beta, interface 16001)
- Supported classes: Paladin, Druid, Priest, Mage, Warlock, Shaman
- Recommended-buff button based on the target's class, skips buffs the target already has
- Paladin: refreshes your existing blessing instead of overwriting it (one blessing per paladin per target)
- Range indicator (red icon) and "already active" checkmark
- Keybind for the recommended buff, movable bar (`/bb move`, `/bb reset`)
- English and German interface (spell names come from your game client)
