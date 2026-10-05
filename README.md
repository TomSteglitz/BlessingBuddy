<p align="center"><img src="media/logo.png" width="160" alt="BlessingBuddy logo"></p>

# BlessingBuddy

One-click buffs and rescue heals for players and pets **outside your group** in World of Warcraft: Forever.

Target a friendly stranger and BlessingBuddy shows a small bar with your single-target buffs, a recommended buff for the target's class, the target's health and a row of rescue heals.

<p align="center">
  <img src="media/gallery-1-recommended-buff.png" width="640" alt="Kings already active, Might recommended next">
  <img src="media/gallery-2-out-of-range.png" width="640" alt="Icons turn red when the target is out of range">
  <img src="media/gallery-3-every-class.png" width="640" alt="Works for every buffing class, here a level 2 priest">
  <img src="media/gallery-4-pvp-warning.png" width="640" alt="Red PvP warning when helping the target would flag you">
  <img src="media/gallery-5-spellcasters.png" width="640" alt="A mage sees Arcane Intellect recommended for a priest">
</p>

## Download
- [CurseForge](https://www.curseforge.com/wow/addons/blessingbuddy)
- [GitHub Releases](../../releases)

## Features
- Recommended buff by target class, skips buffs the target already has
- Paladin one-blessing rule aware (refreshes instead of overwriting)
- Rescue row: heals, shields, dispels + target health bar
- Heal prediction on the health bar: incoming heals, remaining healing of running HoTs, and a preview when you hover a heal button – overhealing is cut off at 100 %
- Paladin: your own blessing shows as done (greyed out) and turns into a refresh button with countdown when it has less than 5 minutes left
- Buff ranks match the target's level (no "target too low" errors)
- Pets of other players: health bar, heals, Thorns
- Works in combat, keybinds, range/cooldown display, PvP warning
- Always casts your highest learned rank
- English and German interface

Supported classes: Paladin, Druid, Priest, Mage, Warlock, Shaman.

## Commands
| Command | Effect |
|---|---|
| `/bb move` | show the bar to move it (Shift + drag title) |
| `/bb reset` | reset position |
| `/bb debug` | diagnostic info about your target |
| `/bb log on\|off\|clear` | write a detailed debug log to the SavedVariables file |
| `/bb healtest` | show which heal-prediction data the client provides |

German aliases: `/segen move`, `/segen reset`, `/segen debug`.

## Reporting bugs
Please open an [issue](../../issues) and include your WoW version, class/level, the target and the output of `/bb debug`. For tricky bugs, `/bb log on`, reproduce, `/reload` and attach `WTF\Account\<ACCOUNT>\SavedVariables\BlessingBuddy.lua`.

## Releasing (maintainers)
1. Update `CHANGELOG.md` and the version in `BlessingBuddy.toc` (scheme `MAJOR.MINOR.PATCH`, two-digit patch: new feature → `1.6.00`, bug fix → `1.5.01`)
2. Commit, then tag: `git tag v1.5.00 && git push --tags`
3. The GitHub Action packages the addon with the [BigWigs packager](https://github.com/BigWigsMods/packager) and uploads it to CurseForge and GitHub Releases.

Requires the repository secret `CF_API_KEY` (CurseForge API token).

## License
MIT – see [LICENSE](LICENSE).
