# Dragon Quest 9 Access

A screen reader mod for the PC version of Dragon Quest IX: Sentinels of the Starry Skies that lets blind players play the whole game with an Xbox controller or the keyboard.

It reads the game out loud through your screen reader (NVDA, JAWS, Narrator, ZDSR, System Access and others) or, with none running, through a Windows voice. It also tells you what is around you and can walk you to anything nearby.

[Download the latest version](https://github.com/RetroSanity/Dragon-quest-9-access/releases/latest)

## What it does

- Reads the game: menus with their descriptions, dialogue page by page with who is speaking, yes or no questions, shops and Sellma's DQVC (prices, stock, who can equip what and how it changes their attributes), battles (whose turn it is, each monster as you pick a target, HP, spells with their MP cost), the status screens, Battle Records and the character creation keyboards.
- Nearby lists: people, monsters, items, sparkly spots, doors, exits, objects and your own marks, each with its direction ("4 steps down, 3 steps right"). Things you cannot get to from where you are say so, and things on a higher or lower level say "higher up" or "lower down".
- Doors named after where they lead, for the whole game ("Inn door", "Princess's room door", "door to a room with stairs up and a bookshelf"), and whether they are locked right now and what opens them ("opens with the Magic Key").
- Objects named from the game's own words for them: signs and what they say, statues, gravestones, books and more.
- Auto walk: pick anything in the list and the mod walks you there, round walls and furniture, up stairs and across big fields, with a beep that gets faster as you get close. If a monster stops you, the walk carries on after the battle.
- 3D beacon: if you'd rather walk yourself, follow a knock placed all round you on headphones (OpenAL Soft with HRTF). It leads you round obstacles, turn by turn. There are spoken step-by-step routes too.
- Story guide: where to go next in the story, worked out from the game's own story progress, and what opens each locked door where you are. Dungeons with a walkthrough (Brigadoom, Tywll Cave, the Tower of Trades and the Heights of Loneliness so far) are read step by step for the part you are in.
- The game window's menu bar from the keyboard: Alt, or Alt and a menu's letter, opens it so your screen reader reads it (not in fullscreen).
- Mod settings (at the end of the game's Misc. menu): the volume of each of the mod's sounds, a beacon test and the alerts.
- Updates itself: it checks for a new version each time the game starts.

## Requirements

- Windows 10 or 11, 64-bit
- Your own copy of the Dragon Quest IX PC version, [DQIX Enhanced](https://github.com/sackchief/dqix-enhanced), already set up and working (its folder has BUILD.bat and a "game" folder in it). The game is not included here.
- An Xbox controller (or any controller the game sees as one), or the keyboard
- A screen reader is recommended; without one, a Windows voice is used
- The internet while installing, and for the automatic updates

## Installing

1. Download the zip from the [latest release](https://github.com/RetroSanity/Dragon-quest-9-access/releases/latest) and unzip it anywhere, for example in Documents.
2. Run Install DQ9 Access.bat. It finds your copy of the PC version (or asks you where it is), adds the mod's part to the game and builds the game again, which takes a few minutes. It puts the mod in its own folder, DQ9 access, in your Documents. Your save and settings are not touched.
3. Start Dragon Quest IX as usual. After a moment the mod says "Dragon Quest 9 access is running. Press K for keys."

## Controls

| Button | What it does |
| --- | --- |
| Left stick press | Everyone's HP and MP (in a battle too) |
| Right stick press | Your gold (in a shop too) |

Hold the left trigger and use:

| Button | What it does |
| --- | --- |
| D-pad left and right | Previous and next list |
| D-pad up and down | Previous and next thing in the list |
| Left stick press | Auto walk to it (again to stop) |
| Right stick press | 3D beacon to it (again to stop) |
| Y | The route to it, step by step |
| Back | The story guide |

The game ignores these buttons while the left trigger is held. There are keyboard keys for everything too: press K in the game, or see README.txt in the download.

## Updating

- The mod updates itself when the game starts and says so. If an update also needs the game to be built again, it tells you to run Install DQ9 Access.bat from your DQ9 access folder.
- If you update the PC version itself (its Help menu, Check for updates), run Install DQ9 Access.bat again afterwards: the PC version's update builds the game without the mod.

## Reporting a problem

Press C in the game while the problem is on screen: that saves a snapshot to dq9-access-log.txt in your DQ9 access folder. Please attach it, and say where in the game you were, when you report a problem in [Issues](https://github.com/RetroSanity/Dragon-quest-9-access/issues).

## Credits and licences

- [Prism](https://github.com/ethindp/prism) for screen reader and Windows voice support (MPL 2.0)
- [OpenAL Soft](https://openal-soft.org/) for the 3D sound (LGPL)
- NVDA Controller Client for speech through NVDA
- [Lua 5.4](https://www.lua.org/) (MIT licence, Lua.org, PUC-Rio)
- The mod's part of the game's code changes DQIX Enhanced, so it is under the same licence, the GNU GPL version 3.

Their licences are in the `mod` folder of the download.

Dragon Quest IX belongs to Square Enix. This is a fan-made accessibility project. It contains no game code, graphics, sound or ROM. So that it can describe the game, the mod carries some information taken from it: the layout of walls and floors used for routes and auto walk, where each door leads and the rules for which doors are locked, what each object is, and the names of people and item descriptions.
