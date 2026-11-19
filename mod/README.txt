DRAGON QUEST IX ACCESS MOD - PC VERSION - READ ME
=================================================

WHAT THIS IS
------------
The Dragon Quest IX Access mod, built into the PC version of the game (DQIX Enhanced). It reads
the game out loud through your screen reader, so you can play the whole game without seeing
the screen. It is the same mod as version 0.2 for BizHawk, running inside the PC game instead
of the emulator, so everything it did there it does here.

INSTALLING
----------
You need your own copy of the Dragon Quest IX PC version (DQIX Enhanced), set up from your own
ROM with its BUILD.bat or its installer (github.com/sackchief/dqix-enhanced). Then:
1. Download the mod from its GitHub page (the green Code button, then Download ZIP) and unzip it.
2. Double-click "Install DQ9 Access.bat". It finds your copy of the PC version (or asks where
   it is), adds the mod to it, builds the game again (a few minutes) and puts the mod in its
   own folder, "DQ9 access" in your Documents. Your save and settings are not touched.
3. Run Dragon Quest IX as usual (your shortcut, or dqix.exe in the game folder). After a moment
   you hear "Dragon Quest 9 access 0.51 for the PC version is running. Press K for keys."

You can run "Install DQ9 Access.bat" again at any time (there is a copy in the DQ9 access
folder): for example after updating the PC version itself, which builds the game again
without the mod.


SPEECH
------
The mod talks through your screen reader, whichever one it is, using Prism (prism.dll in the
DQ9 access folder): NVDA, JAWS, Narrator, ZDSR, System Access, PC-Talker, ZoomText and others.
With no screen reader running it uses a Windows voice. It notices when you start or close your
screen reader while playing. (Without prism.dll it uses NVDA, JAWS or the Windows voice.)


WHERE THE FILES ARE
-------------------
The mod has its own folder, "DQ9 access" in your Documents (Documents\DQ9 access):
dq9-access.lua           The mod's script (the same as the BizHawk one).
dq9-access-maps.bin      The walls and floors of every map, for routes and auto walk.
prism.dll                Lets the mod talk to any screen reader (Prism, MPL 2.0 licence: its
                         licences are in the prism-licences folder).
nvdaControllerClient64.dll  Lets the mod talk to NVDA when prism.dll is not there.
README.txt               This file.
Install DQ9 Access.bat   The installer (run it again after updating the PC version).
installer\               The installer's files, and the mod's part of the game's code.
version.txt              The version of the mod in this folder (for the automatic updates).
pc-port-path.txt         Where your copy of the PC version is (written by the installer).

The mod makes these in its folder as you play:
dq9-access-places.txt  Your marks, the names of people you have talked to, places it has learned
                       and the chests you have opened.
dq9-access-log.txt     Snapshots saved with the C key, for reporting problems.
dq9-access-speech.txt  Only if you make an empty file called dq9-access-debug.txt in the mod's
                       folder: everything the mod says.

The game is in the game folder of your copy of the PC version (for example
Documents\DQIX-Enhanced\game): dqix.exe and dqixcore.dll are the game with the Access mod's
part built in, and dqix.sav is your save. When the game starts it looks
for the mod in Documents\DQ9 access; if that folder is not there, it uses the access folder
inside the game folder, as older versions of the mod did.

To turn the mod off, rename the DQ9 access folder (for example to DQ9 access off), and the
access folder in the game folder if there is one. The game then plays as usual.


PLAYING ON THE KEYBOARD
-----------------------
The game's buttons are on the same keys you used with BizHawk:
Z = A, X = B, A = X, S = Y, Q = L, E = R, Enter = Start, Right Shift = Select,
arrow keys = D-pad.
They can be changed in the game's menu bar: Game, then Controls. (If you change them, the
mod's keys stay as they are.)

A controller works as well: the buttons are by position, like on a DS (right face button = A,
bottom = B, top = X, left = Y), the shoulders are L and R, the left stick walks.


THE MOD'S KEYS
--------------
The nearby list:
Page Down          Next thing in the category, nearest first, with directions.
Page Up            Previous thing in the category.
Ctrl + Page Down   Next category of the nearby list.
Ctrl + Page Up     Previous category.
Ctrl + Home        The route to the thing you picked, step by step, for you to walk yourself.
Ctrl + End         Walk there for you. Press it again, or any game button, to stop.
N and B also go through the things in a category, V goes to the next category, D gives the
directions again, P gives the route and J walks there.

Information:
H   Everyone's HP (works in battles too).
M   Everyone's MP (works in battles too).
G   Gold.
W   Where am I: the place and your position.
L   Attributes, one at a time: who it is (name, vocation, level), then experience, strength,
    agility and so on, each with "3 of 13". After the last one it goes on to the next person
    in the party. Shift + L goes back one.
U   What everyone has equipped.
I   Repeat the last information window, such as experience earned.
O   Read every option in the menu that is open.

Speech and other keys:
R          Repeat the last thing said.
Ctrl       Press and let go of Ctrl on its own to stop speaking.
Shift + M  Mark this spot so you can find it again later (category Marks).
T          Turn the "blocked" alert on or off.
F          The 3D beacon to the thing you picked, to walk there yourself. F again stops it.
C          Save a snapshot of what the game is showing to dq9-access-log.txt.
K          Hear the list of keys.

Controller (Xbox-style):
Press in the left stick (L3)    Everyone's HP and MP (in a battle too).
Press in the right stick (R3)   Your gold (in a shop too).
Hold the left trigger (LT), then:
  D-pad right / left   Next / previous category of the nearby list.
  D-pad down / up      Next / previous thing in that category.
  Press in the left stick (L3)   Walk to the thing you picked. Press it again to stop.
  Press in the right stick (R3)  The 3D beacon to the thing you picked. Press it again to stop
                                 the beacon.
  Top face button (Y)            The route to the thing you picked, step by step (while the
                                 beacon is on: how far there is to go and the next turns).


THE GAME'S OWN KEYS
-------------------
These belong to the PC version and still work:
Tab            Fast forward on and off.
Pause          Pause and continue.
Minus / Equals Volume down and up (the mod says the new volume).
Ctrl + R       Reset the game (back to the title screen; save first).
F10            Save a bug report for the PC version.
F11            Fullscreen on and off. Escape leaves fullscreen, or asks to quit.
Alt            Opens the menu bar (Game, Graphics, Screen, View, Wireless, Modern, Mods, Help).
               Your screen reader reads it like any Windows menu.
The PC version's keys that were on letters (P for pause, U, K, I and O for the widescreen's
small screen) and its left trigger and stick clicks were taken off, because the mod uses them.

Saving: the game saves in its own way, at a church (or with the Save option the game gives
you). Your save is dqix.sav in the game folder.


UPDATES
-------
The mod keeps itself up to date. Each time the game starts it checks the mod's GitHub page in
the background; when there is a newer version it downloads it into the DQ9 access folder and
says "The access mod has been updated to version ...". If a new version also changes the game,
it says so: close the game and run "Install DQ9 Access.bat" in the DQ9 access folder.
To stop the automatic updates, make an empty file called no-auto-update.txt in the DQ9 access
folder.

The PC version itself normally offers to update itself too. That would build the game again
without the mod, so its automatic check is switched off while the mod is here. If you update
the PC version by hand (Help, Check for updates), run "Install DQ9 Access.bat" afterwards.


IF SOMETHING IS SILENT
----------------------
Press C while it is on screen. That saves a snapshot to dq9-access-log.txt in the mod's folder. Say what was
on screen, so it can be fixed. If the mod itself stops with an error it says so, and the
details are in last-run.log in the game folder.


CHANGES IN THE PC VERSION (since 0.2 for BizHawk)
--------------------------------------------------
- Runs inside the PC game and talks through NVDA, JAWS or the Windows voice.
- Character creation: every choice is read again as you move through it (body type, hairstyle and
  so on, with the description).
- Battles: when there is more than one monster of a kind, the target list names them with their
  letters, the way the battle messages do: "Slime A, 1 of 3", "Cruelcumber, 2 of 3",
  "Slime B, 3 of 3". A group of several says them all, such as "Slime A and B". A monster that is
  the only one of its kind is just its name, without "times 1".
- The nearby list no longer has an Events category.
- Yes or no questions opened from the menu (such as Quick Save) are read, with the answer the
  cursor is on, and the question is said only once.
- People and monsters coming close are no longer announced by themselves: use the nearby list.
- Doors and exits use the names from the game's own map list (data/map/maplist9.bin) where the
  mod had none, in every town: such as "Church door", "Item Shop door" and "Well" in Angel Falls.
- People the game has a name for (Ivor, Erinn, Hugo, Mayor Litlun and so on, in every town) are
  in the nearby list by that name from the start, before you talk to them. The names come from
  the game's own talk files (data/scenario).
- The nearby list always has a Monsters category (after People), even where there are none, so
  you know it is there: in the open fields it lists the monsters walking about, nearest first.
- L goes through the attributes one at a time (Shift + L back) instead of reading them all at once.
  Picking someone in the game's Attributes menu still reads all of theirs, and L then carries on
  from that person.
- The vocation and level are read correctly (they said "level 1" with no vocation before).
- Options, yes or no questions and windows that come up after a message wait for the message to be
  read to the end, instead of cutting it off. Once you press a button or key, speech is cut off as
  before so moving through a menu stays quick.
- The attributes are no longer read out by themselves (pressing A in a shop or while talking read
  them, because the Attributes menu stays in the game's memory after it closes).
- Auto walk takes you down (and up) stairs: it goes round to the open end of the stairway and walks
  down it. It also keeps to its route more closely, so it no longer slips down a stairway by
  accident on the way somewhere else (as it did upstairs in Erinn's house).
- A list of choices that comes with a message (such as Erinn's "Stay at the inn, Canvass for
  guests, View the guestbook, Leave") is read every time it comes up, not only the first time.
- Profile Settings (Misc., or canvassing for guests at the inn) is read in full:
  - each line with what it is set to, such as "Location: Europe" and "Birthday: 1 January 2000",
    and "not set" for one not chosen yet;
  - the birthday's Day, Month and Year as you change them;
  - the long lists of titles and countries say "Next page" and "Previous page" when left and right
    turn the page;
  - a speech style's sample greeting is read after its name;
  - the greeting keyboard says the key you are on and each letter you type.
- Smoother: the mod's searches through the game's memory (for a yes or no box, a list of choices,
  the battle, the equipment screen and so on) are done by the game itself and no longer hold up a
  frame, and auto walk plans its route in smaller steps.
- A list of choices that was not ready when its question came up (Erinn's "Stay at the inn ...")
  is looked for again, so it is read.
- Menus gone through and fixed:
  - Items: every item is followed by what it does, from the game's own descriptions (also in shops
    and on the equipment screen); the bag says how many you have ("Horse manure, 5").
  - Misc.: no longer read as the skill points screen; the status window (Tactics, Allocate Skill
    Points) is read with its numbers; Tactics says each party member's tactics.
  - Yes or no questions on the skill points screen ("End skill point allocation?") are read.
  - Organise Items' question is no longer followed by a wrong "Yes or no? No".
  - Battle Records: the Wardrobe's two columns are read with their row and column, monsters not
    met yet are "not found yet", and the button you are on is said again when you come back.
  - Title screen: "Load quick save data / Cancel" is read, and "Title screen" is no longer said
    while the game is loading the quick save.
- No more "Yes or no?" after a message that has no choices (such as "...okay?").
- Auto walk to someone you talk to over a counter (the bank clerk Ginny, shopkeepers, the inn)
  takes you to the spot in front of the counter that the game lets you talk to them from, and
  turns you to face them, even when their counter is a solid block or you start behind it.
- A list whose last choice is Cancel (Patty's "Call Up a Friend, Recruit a Friend, Part With a
  Friend, Cancel") reads Cancel, instead of saying the first choice again or saying nothing.
- Choices from another person's menu (Pavo's "Invite friends from other worlds.") are no longer
  read out when you start talking to someone else.
- The name keyboard when making a companion at Patty's is read again (it had stopped working
  when the game had a different set of words loaded).
- On the name keyboard (and the greeting keyboard) the down arrow key is said as "Caps lock" and
  the up arrow key as "Shift, a capital for the next letter"; pressing them says "Caps lock on"
  or "off", "Shift on" or "off", and the letters are said as capitals while they are capitals.
- The "blocked" alert no longer goes off while you move around a keyboard.
- The mod has its own folder, Documents\DQ9 access, apart from the game. (The game still uses
  the access folder in the game folder if there is no DQ9 access folder.)

CHANGES IN 0.3
--------------
- An installer: it finds your own copy of the PC version, adds the mod to it and builds the game.
- The mod keeps itself up to date from its GitHub page when the game starts.
- 0.3.1 and 0.3.2: the first automatic updates (tests that updates reach everyone).

CHANGES IN 0.51
---------------
- Every screen reader: the mod talks through Prism, so NVDA, JAWS, Narrator, ZDSR, System Access,
  PC-Talker, ZoomText and others all work, and a Windows voice when none is running.
  This version changes the game's part of the mod: run Install DQ9 Access.bat once.
- The Observatory's first floor: the doors round the main hall are named after where they go
  (prayer room, study, storeroom, and which ones are locked); from the rooms, the doors are
  "door back to the main hall".
- Auto walk to a locked door says it is locked, and walking into a locked door again reads
  "The door is locked." again.
- Auto walk to a person turns you to face them, so A talks to them.
- Auto walk to a door on the far side of a wall tries the door's other side, and if there is no
  way to it from where you are, says so instead of walking part of the way.
- Doors everywhere in the game are named after where they lead, from the game's own map files:
  a door into a place with a name says it ("Inn door", "Church door"); a door into rooms that
  have no name of their own says what is in the room on the other side ("door to a room with
  stairs up and a bookshelf", "door to a house with a treasure chest", "cell door", "lift").
  A door between two rooms of the same place names the room on the other side from you.
  Two doors with the same name get a side ("left", "right").
- Locked doors say so: "locked door to a room with a bookshelf". This comes from the game's own
  rules for each door, checked against how far you are in the story and the game's event flags,
  so a door that opens later in the story, or one you have unlocked, is no longer called locked.
  A door with a keyhole also says which key opens it ("opens with the Magic Key").
  Auto walk to a door that will not open yet tells you so instead of walking there.
- Mod settings: a new item at the end of the game's Misc. menu, after Quick Save (down from Quick
  Save, or up from Heal All, as the menu wraps round). A opens it; up and down choose, left and
  right or A change, B goes back. Auto walk beep on or off and its volume, the beacon's volume,
  the beacon's chime at each turn, a test of the beacon on headphones (a knock in front, to the
  right, behind and to the left), the blocked alert, saying the position in menus, and saying
  people and monsters coming close. Kept in dq9-access-settings.txt.
- 3D beacon, to walk somewhere yourself (left trigger and press in the right stick, or F; the
  same again stops it): pick something on the list and follow a knock placed all round you on
  headphones. The knock comes from where the next turn of the way is: faster the nearer it is,
  lower when it is behind you, with a second higher knock when you are heading straight for it.
  "Ahead" is up on the screen, the way up on the D-pad walks you. A chime at each turn of the way
  and when you arrive. If you wander off the way, it is worked out again from where you are.
  Uses OpenAL Soft (openal_soft.dll, LGPL, licence in openal-licence) with HRTF for headphones.
- Auto walk beeps while it walks you: faster the nearer you are (along the way), and a chime when
  you arrive.
  The beacon and the beep need the new game part of the mod: run Install DQ9 Access.bat once.
- The object list names every thing from the game's own words for it, all through the game:
  signs and what they say ("sign: East of here lies Stornway"), statues, gravestones, books,
  mirrors, beds, things to pick up ("horse manure, to pick up"), lifts and so on, even before you
  have looked at them. Spots that only say a door is locked are left out (the door list says
  so), and so are unnamed spots right where a person stands behind a counter.
- A person the game names (Apus Major, Aquila ...) speaking no longer gives their name to whoever
  stands nearest you; a name wrongly learned that way before is dropped.
- Things in other rooms: one area of the game can hold several rooms joined only through another
  area (the prayer room, study and storeroom off the Observatory hall). People, items and doors you
  cannot walk to from where you stand now come after the rest of the list and end with "no way
  there from here"; the category says how many are in other rooms ("People, 6, 5 of them in
  other rooms"), and auto walk tells you to go through a door instead of walking into a wall.

CHANGES AFTER 0.51 (not released yet)
-------------------------------------
- The beacon is quiet while someone talks, a menu is open, a scene plays or a battle is on, and
  carries on afterwards. It follows people and monsters who walk about. The route key (P, or LT and
  Y) while it is on says how far there is to go and the next turns ("12
  steps to go. Next: 3 steps up, then 5 steps left."). On arriving it says which way to face
  ("Face up and press A to talk"). "Beacon says each turn of the way" in Mod settings speaks each
  turn as you reach it.
- In battle, moving between monsters with left and right no longer says "Next page".
- Bump sound: a thud from the side you pushed when you walk into something, a moment after you
  stop (quicker than the spoken "blocked"). On or off in Mod settings.
- Exits named after the game's part names now say the place: "exit to Mountain Pass" instead of
  "exit to Exterior". Also Brigadoom, Tywll Cave, Gerzuun, the Oubliette, the Old School of
  Swinedimples, the Starflight Express and grottoes.
- At the start of a battle, the last battle's command list ("Retro's turn. Attack") is no longer
  read before "Fight"; the turn is said once, when it really comes.
- Shops: moving through the list no longer reads the last item's description before the new one.
  On Mod settings in the Misc. menu, Quick Save's description is no longer read.
- A person behind a counter that auto walk or the beacon cannot get round to: you are turned to
  face them and told "most likely across a counter. Press A to talk." The route key says the same.
- Route directions read better: "Sign: it is 1 step up; face it and press A to read it" instead of
  repeating the name, and "you are as close as the way goes. It is 2 steps right."
- The beacon arriving at a monster says "walk into it to fight" instead of "press A to talk".
- Starting the beacon stops an auto walk, and starting an auto walk stops the beacon (both used to
  run at once).
- Stray letters after finding something ("KRetro acquires", "benevolessence.<", "joins retro!;")
  are gone, and "Erinn:,Guardian" reads "Erinn: Guardian".
- A yes or no answer reads only the answer you picked, not both.
- Waking up in bed: doors are no longer called "no way there from here" for a moment.
- "1 point left" when allocating skill points.
- New controller keys: pressing in the left stick (L3) gives everyone's HP and MP, anywhere (in
  a battle too); pressing in the right stick (R3) gives your gold, anywhere (in a shop too). The
  route to the thing you picked moved to the left trigger and the top face button (LT + Y).
  Walking (LT + L3) and the beacon (LT + R3) are as before.
- The auto walk beep is louder: volume 10 is now a little over twice as loud as before.
- People behind a counter you cannot walk up to, such as Ivor at the Angel Falls inn: auto walk,
  the beacon and the route now take you round to the front of the counter and face you to them,
  instead of stopping on the far side of a wall. This uses the game's own marking of furniture
  you can talk across.
- The battle start still sometimes read the last battle's "Retro's turn. Attack" before "Fight";
  it should not any more.
- Heal All no longer says "Yes or no? Yes" after each spell (it was a question from earlier).
- Experience after a battle is read once per person ("retro +9 Exp." then "lebon +4 Exp."),
  instead of the whole growing line again for each new name.
- Auto walk over a long way in a big field keeps going instead of stopping part way with "As close
  as you can get".
- Doors out of the Starflight Express say where they go ("door to Mountain Pass") instead of
  "Exterior door", and the carriage is no longer named twice when you go in.
- HP and MP in a battle (L3, H, M) are the battle's own, so they go down and up as the fight goes;
  before, a party of more than one could be given the numbers from before the battle.
- The party is read hero first, then the companions in the order they joined, as on screen.
- The auto walk beep is quicker from the start: half a second apart when far, down to a tenth
  of a second when close.
- People behind a counter: the mod now goes by the way they face (a shopkeeper faces the side
  you talk to them from), so the old woman at Zere's inn is reached from the right side, and you
  are lined up straight across from them before "Press A to talk".
- Treasure chests and other things a step away: you are turned square on to them, so A opens
  the chest instead of talking to someone standing beside it.
- Heal All no longer says "Yes or no? Yes" after each spell (the first fix missed one case).
- A spell's description is read once, after the spell, instead of before it and again after.
- Coming into a town, things are no longer called "all in other rooms" for the first moment.
