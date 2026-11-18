# Dragon Quest 9 Access

A screen reader mod for the PC version of Dragon Quest IX: Sentinels of the Starry Skies. It
reads the whole game out loud through your screen reader (NVDA, JAWS, Narrator, ZDSR, System
Access and others) or a Windows voice, so it can be played
from start to finish without seeing the screen: menus, dialogue and choices, battles, the map
and what is around you, auto walk to people, doors, stairs and chests, and much more.

[Download the latest version](https://github.com/RetroSanity/Dragon-quest-9-access/releases/latest)

## What it does

- Reads everything: menus with their descriptions, dialogue page by page with who is speaking,
  yes or no questions, shops (prices, what each person could equip and how it changes their
  attributes), battles (whose turn it is, targets with their HP, spells with their MP cost),
  the status screens and the character creation keyboards.
- The nearby list: people, monsters, items, sparkly spots, doors, exits, objects and your own
  marks, each with directions ("4 steps down, 3 steps right"). Things in another room say there
  is no way there from where you are.
- Doors named after where they lead, for the whole game, from the game's own map files ("Inn
  door", "door to a room with stairs up and a bookshelf"), and whether they are locked right
  now, from the game's own rules, your story progress and its event flags ("opens with the Magic
  Key").
- Objects named from the game's own words for them: signs and what they say, statues,
  gravestones, books and more, before you have looked at them.
- Auto walk to anything on the list, round walls and furniture, with a beep that gets faster as
  you get close; spoken step-by-step routes; and a 3D beacon on headphones (OpenAL Soft with
  HRTF) to walk there yourself, following a knock placed where the next turn of the way is.
- Mod settings at the end of the game's own Misc. menu: the sounds' volumes, a beacon test and
  the alerts.
- Speech through Prism: NVDA, JAWS, Narrator, ZDSR, System Access, PC-Talker, ZoomText and
  others, or a Windows voice.
- Plays with an Xbox controller (hold the left trigger for the mod's commands) or the keyboard.
- Updates itself when the game starts.

This repository holds only the mod. The game is not here. You need your own copy of the
Dragon Quest IX PC version, [DQIX Enhanced](https://github.com/sackchief/dqix-enhanced), which
is built from your own copy of the game.

## What you need

- Windows 10 or 11, 64-bit.
- Your own copy of the DQIX Enhanced PC version, already set up and working (its folder has
  BUILD.bat and a "game" folder in it).
- The internet while installing, and for the automatic updates.

## Installing

1. Download the zip from the [latest release](https://github.com/RetroSanity/Dragon-quest-9-access/releases/latest)
   (or the green "Code" button, then "Download ZIP"). Unzip it anywhere.
2. Double-click **Install DQ9 Access.bat**. A text window shows what it is doing; your screen
   reader can read it. It:
   - finds your copy of the PC version (or asks you to type where it is),
   - adds the mod's part to the game's code and builds the game again (a few minutes),
   - puts the mod in its own folder, **DQ9 access**, in your Documents.
   Your save and settings are not touched.
3. Start Dragon Quest IX as usual. After a moment you hear "Dragon Quest 9 access 0.51 for the
   PC version is running. Press K for keys."

The full guide to the mod, its keys and everything it reads is in
[mod/README.txt](mod/README.txt) (also in your DQ9 access folder).

## Updates

The mod updates itself. Each time the game starts it checks this page in the background, and
when there is a newer version it downloads it and says so. If an update also needs the game
to be built again, the mod tells you to run **Install DQ9 Access.bat** from your DQ9 access
folder.

If you update the PC version itself (its Help menu, Check for updates), run
**Install DQ9 Access.bat** again afterwards: the PC version's update builds the game without
the mod.

## Reporting a problem

Press C in the game while the problem is on screen: that saves a snapshot to
dq9-access-log.txt in your DQ9 access folder. Open an issue on this page saying what happened
and attach that file.

## What is in this repository

- `Install DQ9 Access.bat`: the installer.
- `mod/`: everything that goes into your DQ9 access folder: the mod's script
  (`dq9-access.lua`), the maps used for routes and auto walk, the installer's files and the
  mod's part of the game's code (`mod/installer/game-patch`), and `manifest.txt`, which the
  automatic updates read.
- `make-manifest.py`: writes `mod/manifest.txt` when a new version is published.

## Licences

- The mod's part of the game's code (`mod/installer/game-patch`) changes DQIX Enhanced, so it
  is under the same licence, the GNU GPL version 3.
- Lua 5.4 (`mod/installer/game-patch/files/third_party/lua`): MIT licence, Lua.org, PUC-Rio.
- Prism (`mod/prism.dll`, github.com/ethindp/prism), which lets the mod talk through any screen
  reader: Mozilla Public License 2.0; its licence and notices are in `mod/prism-licences`.
- NVDA Controller Client (`mod/nvdaControllerClient64.dll`): see `mod/LICENSE-NVDA.txt`.
- OpenAL Soft (`mod/openal_soft.dll`, openal-soft.org), for the 3D sound: GNU LGPL; its licence
  is in `mod/openal-licence`.
- Dragon Quest IX belongs to Square Enix. This is a fan-made accessibility project. It contains
  no game code, graphics, sound or ROM. So that it can describe the game, the mod does carry
  some information taken from it: the layout of walls and floors used for routes and auto walk
  (`dq9-access-maps.bin`), where each door leads and the rules for which doors are locked
  (`dq9-access-doors.lua`), what each object is (`dq9-access-objects.lua`), and the names of
  people and item descriptions in the script.
