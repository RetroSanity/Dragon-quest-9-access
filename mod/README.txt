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
   you hear "Dragon Quest 9 access 0.57 for the PC version is running. Press K for keys."

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
dq9-access-walls.txt   Walls of the map files that you have walked straight through, which the
                       mod no longer counts.
dq9-access-ship.txt    Where you left the ship.

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
Y          Story guide: where to go next. In a dungeon that has a walkthrough (Brigadoom), each
           press reads the next step for the part of the dungeon you are in; after the last
           step, the story's next step. It also says what opens the locked doors where you are.
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
  Right trigger (RT)             The story guide, as Y on the keyboard (Back does it too).


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
- Auto walk beeps once for every step it actually walks you, higher the nearer you are (along the
  way), with a soft low knock once a second while you are standing still, and a chime when you
  arrive.
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

CHANGES IN 0.52
---------------
This version changes only the mod's own files: it updates itself when the game starts, with no
need to run the installer again.
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
- People behind a counter, again: the mod now looks all round them for the nearest spot with only
  the counter between (some counters run on a slant, like Stornway's weapon shop) and turns you
  to face them, slant and all.
- Doors with no way through marked in the map (some shop doors in Stornway, the doors inside
  the Quester's Rest): auto walk now walks on through them instead of stopping in front.
- A chest or other thing right in front of you that you cannot stand nearer to: "In front of
  treasure chest, 1 step down. Press A." instead of "As close as you can get".
- Inns, shops and the church: the question ("Will you be staying?") is read on its own, not run
  together with the next thing said.
- A spell's description no longer comes after the next spell's name when you move quickly.
- Exits you cannot walk to from where you are (across a river, up a cliff) now end with "no way
  there from here" and come last, like doors and people in other rooms. Out in the open the
  category says "out of reach from here", and auto walk explains that the way there is round
  through another part of the area, or another area, instead of walking a few steps and stopping.
- Battle Records: every screen reads now. The first screen says the time played and how complete
  the Defeated Monster List, Wardrobe and Item List are, then the button you are on (Defeated
  Monster List, Wardrobe, Item List, Accolades Earnt) and again when you come back to it.
  - Defeated Monster List: how complete it is and how many kinds you have defeated; View All
    Monsters reads the list across the two columns with the page ("Cruelcumber, 2 of 16, page 1
    of 3"), then the monster's page: family, experience, gold, how many defeated, the item it
    drops, where it lives and its description. View By Family reads the families across, each
    with how many you have defeated.
  - Wardrobe and Item List: how complete they are and how many collected, the kinds (Weapons,
    Swords ...), then each thing with its description.
  - Accolades Earnt: each accolade with what it was awarded for.
  Coming back out of one list and going into another (Wardrobe, then Item List) works; before,
  the second list could stay silent. No "blocked" alert while you move the cursor in these screens.
- Castle doors are named after the room behind them: Princess's room door, throne room door,
  barracks door, treasure room door, and so on. Doors and stairs between a castle's floors say
  which floor: "castle door to the ground floor", "castle door to the 3rd floor", "stairs to
  the ground floor". "Stairs up to exit outside" is now "stairs up to the outside".
- Places with several levels (a castle's wall walk above its courtyard): a thing you cannot get
  to says "lower down" or "higher up" when it is on another level from you, for example "Well,
  7 steps right, 4 steps down, lower down, no way there from here", and auto walk tells you to go
  through a door or find stairs.
- Two questions in a row with the Yes / No box staying up (the church asks whether to record
  your adventure, then whether to carry on): the second question now says "Yes or no?" too.
- Story guide: hold the left trigger and press Back (or press Y on the keyboard) to hear where to
  go next in the story, from the start of the game to after the ending. It knows where you are
  in the story from the game itself, and from the places you reach and the bosses you beat
  (kept in dq9-access-guide.txt). It also says what each locked door where you are needs: which
  key opens it and where you get that key (the Thief's Key, the Magic Key, the Ultimate Key), or
  that the story opens it later (Stornway's treasure room: the King opens it as your reward).
- Doors and exits to rooms that only had a floor number now say the room: "exit to basement",
  "exit to northern tower throne room" (in Brigadoom it used to say "exit to door").
- Dungeon walkthroughs: in a dungeon that has one (Brigadoom so far), LT + Back (or Y) reads a
  step by step walkthrough for the part of the dungeon you are in, one step per press ("step 2
  of 3"): where to go, the optional chests, and how its locked doors open (Brigadoom's west
  double door is unlocked from inside the western tower and is then a short cut; the basement's
  door needs the Ultimate Key). After the last step, one more press gives the story's next
  step. Going into another part of the dungeon starts again from its first step.
- A door you unlock from its other side is now called that in the guide, instead of "kept shut
  by the story".
- Things on a higher or lower level that stand over floor you can walk on (a chest on top of a
  tower, with ground under it) are now marked "higher up, no way there from here", instead of
  looking close by. Chests, pots and the like now say "higher up" or "lower down" too.
- Auto walk, the route and the beacon now manage very narrow winding stairs (the stairs up inside
  Brigadoom's eastern tower), where they used to stop at the bottom.
- The Brigadoom walkthrough knew the wrong part of the dungeon in the eastern tower (it read the
  north western tower's step); it now goes by the map's own number. The eastern tower step now
  says the bandana chest is outside on the tower top: take the exit outside at the top of the
  stairs inside.
- Fixed: after the last change, stairs in a basement (Brigadoom's) were all called "higher up,
  no way there from here", even the ones you came down. Exits are no longer judged by height.
- Brigadoom walkthrough: once the west double door is unlocked, the ruins' steps change to the
  way on: through the double door, along the walkway north and up onto the roof, to the exit to
  northern tower throne room. The western tower's steps now match the dungeon (its stairs to the
  outside bring you out behind the double door), and the north western tower is called a side
  room with a chest.
- Auto walk and "no way there from here" no longer treat the space just outside a real door as
  off limits, or a roof walk right over a door as being in it. In Brigadoom this made the way to
  the northern tower look blocked.
- A door you unlock from its other side is now called "locked from this side", and walking to
  it says it opens from its other side, instead of "It will not open yet".
- Auto walk carries on after a battle: a long walk that a monster cuts short (out in Doomingale
  Forest, say) starts again by itself once the battle is over and you can move. Any button stops
  it, as always.
- Auto walk from Brigadoom's roof (beside the northern tower's door) back down to the forest no
  longer gives up straight away with "As close as you can get".
- Story guide: after beating Morag it moves on to going back to the King (with the way back on
  foot, or by chimaera wing), instead of still saying to go to Brigadoom.
- Battles: picking which monster of a group to attack, left and right now say each one as the
  arrow moves ("Bodkin fletcher A", "Bodkin fletcher B"); before, only the group was read.
- Auto walk across a big field (Doomingale Forest to the open field) works again. It was picking
  a spot just past the exit, off the edge of the map, so working out the route took ten seconds
  or more, standing still while monsters caught up. Routes to a spot right against a wall or the
  edge now finish quickly, a step short.
- After a battle, the walk starts again only once the battle's last messages are gone and you
  have stopped pressing buttons, so the press that clears them no longer stops it again.
- Big fields: exits you cannot walk to from where you are (the Zere region has two exits to
  Western Stornway, one of them across a cliff) are now marked "out of reach from here" and come
  last, a moment after you arrive, instead of auto walk trying and getting stuck. Before, fields
  were too big to check.
- Just after a battle the exits list no longer says "No exits nearby" for a moment.
- Item lists: when you move quickly through the bag, the last item's description no longer
  comes again after the next item's name.
- The Krak Pot, hidden away at the Quester's Rest before Erinn gives it to you, is no longer
  listed as a person "107 steps up, 100 steps left, no way there from here".

CHANGES IN 0.53
---------------
This version changes only the mod's own files: it updates itself when the game starts, with no
need to run the installer again.
- Big fields: exits were wrongly called "no way there from here" (in Western Stornway: the stairs
  to Stornway, the Mountain Pass and the Eastern Stornway exits), and auto walk refused to carry
  on to them after a battle. An exit's box out in a field is big, and its middle is far from
  where you can stand; now walking up to any side of it counts. Exits really across a cliff (one
  of the Zere region's exits to Western Stornway) are still marked out of reach.
- The auto walk beep now tells you that you are really moving: it beeps once for every step you
  actually cover, so it keeps pace with your walking and goes quiet the moment you stop. It gets
  higher the nearer you are (an octave up over the last 20 steps) and closer together for the
  last few steps. While auto walk is on but you are standing still (working out the way, turning,
  or held up by something), you hear a soft low knock about once a second instead. A walk starts
  with a beep straight away.
- The Krak Pot. The Alchenomicon (Use A Recipe) is read across its two columns: "Strong medicine,
  2 of 16", with the page when there is more than one, and recipes you have not found yet as "not
  found yet". Each recipe says what it needs and how many you have: "Needs 2 medicinal herb, you
  have 7. You can make it."
- Try Your Luck: each ingredient says how many you have and where it is in the list ("Slimedrop,
  you have 3, 3 of 8, page 1 of 3"). Before, the position was counted wrongly (out of 24, mixed in
  with the Alchenomicon's hidden list), the count was not read, and short lists counted rows not
  on screen. "How many?" is read, and changes as you press up and down, without listing every
  category and item as "Held". After you add something, the mod says what is in the pot ("In the
  pot: slimedrop 2, coagulant 3."), and "The pot is empty." when it is emptied. The right stick
  press (R3, or the gold key) says what is in the pot too while you are choosing.
- A question that comes up together with a list (the Krak Pot's "So, how will you be conducting
  your alchemy, hm?" with Use A Recipe under it, "How many of those would you like to throw into
  the mix?") is said once, then the list, instead of the question, the list and the question
  again. A question that is also written in the message box is no longer read twice.
- When an item's description lags behind the cursor, the last item's description is no longer
  read after the new item.
- Innkeepers and shopkeepers who have to be talked to from in front of their counter, such as the
  old woman who runs Coffinwell's inn: auto walk, the beacon and the route now take you to the
  front of the counter and face you to them. Before, auto walk took you round behind her, and
  from there she only talks about the disease instead of offering a room. The mod now carries
  the game's own list of where each of these people is talked to from, for every map.
- Auto walk to a monster walks right into it and keeps after it if it runs away, until the
  battle starts. Before, a monster standing near a table or wall was walked to "across the
  counter" and the walk stopped a step short, so you never touched it; metal slimes, which run
  from you, could not be caught at all. If one still gets away after a few seconds of chasing,
  the mod says so: come at it from behind, or between it and a wall.
- Battles: picking a target no longer says "3 of 2" or "Lost soul times 1" when one group of
  monsters has gone. The place in a list is counted among the lines that are there.
- The Quarantomb's two sage statues are called "statue of the sage, with a button on its wand"
  instead of something that says "There appears to be a button on the wand".
- Auto walk starts moving at once. When nothing is in the way it walks straight there without
  waiting for a route to be worked out; before, it could stand still for a second or more first,
  long enough for a metal slime to get away. A monster or person on the move is chased straight
  at, and if they go round a corner the old route is kept while the new one is worked out,
  instead of stopping to think every time they move.
- After a battle with a monster you walked into, the walk no longer starts again towards it.
- Things you work, such as the Quarantomb's sage statues with a button on the wand, and levers
  and switches, are in the Items list instead of Objects.
- The way from the Quarantomb's shrine into the tomb is called "exit inside, to Quarantomb"
  instead of "exit to Interior -".
- A boss waiting for you to talk to it (the Ragin' Contagion in the Quarantomb) is in the People
  list, with its name: "Ragin' Contagion, boss. Talk to it to fight". Before, it was not on any
  list.
- Going through a door that does not lead to another map (the Quarantomb's gate) now tells you
  what is on the other side: "Through door. In here: jar, stairs to basement."
- Story guide: after the Ragin' Contagion it tells you what to do back in Coffinwell (the Mayor,
  Catarrhina, the night, the graveyard, Dr Phlegming's sick people) instead of jumping ahead to
  the Observatory.
- Things you press A on from a spot the game marks (the Starflight Express's control panel, the
  Quarantomb's statues and mirrors) are walked to that spot, facing them, so A works. Before,
  auto walk stopped a step too far back from the control panel and A did nothing, so the train
  could not be made to leave the Mountain Pass.
- The Starflight Express's control panel and carriage door have names ("control panel",
  "carriage door"), and the control panel is in the Items list.
- Auto walk to someone across a counter (the royal guard in Alltrades Abbey) no longer walks on
  the spot for ever when a follower or a bit of furniture keeps you just short: a second without
  getting closer, within a step, counts as there, and you are turned to face them. A box the game
  draws round a person themselves is no longer mistaken for the far side of a counter.
- After a battle, the walk waits for the experience and gold messages to finish before it starts
  again, so the button you press to clear them no longer stops it straight away. A walk that gave
  up with "As close as you can get" just as a battle started carries on after the battle.
- The spot where the Starflight Express lands you on a field is called "Starflight Express
  landing spot" instead of something that says "s companions come into view".
- After a battle where someone levels up, an auto walk no longer starts again over the skill
  points screen (its presses could have moved your points about). Start it again yourself when
  you are done.
- The same words are no longer read twice in a row when nothing was pressed in between (the
  priest's question at Porth Llaffan's church).
- Shopkeepers whose place in the game's files is written a different way (Porth Llaffan's
  weapon and armour shop and item shop, and about 90 other people in all) are now walked to from
  the front of their counter too. From behind, Porth Llaffan's weapon seller only says he is
  shutting up shop and never opens it.
- Items menu: moving between people in Everyday Items no longer reads the last thing in their
  list as if you were on it ("Angel bell, 8 of 8") and then the person again. Choosing who to
  transfer something to says how much they carry ("bish, 4 of 5, carrying 2 of 8", or "hands
  full"). The bag says which page you are on when it changes ("page 2 of 3").
- An exit far below or above where you stand, more than a flight of steps, is marked out of reach
  and "lower down" or "higher up" (outside Tywll Cave's upper floor, the cave mouth under the
  ledge was read as "right next to you" and auto walk went round in circles). The Exits list says
  "out of reach from here" for these instead of "in other rooms".
- A step-by-step walkthrough for Tywll Cave and Cuddiedig Cliff, on the story guide button (left
  trigger and Back, or Y on the keyboard): each part of the cave, where its chests are, which
  exit is the way on, and how to fight Lleviathan.
- Tywll Cave's exits name their floor: "exit to the 1st floor", "exit to the 1st floor, part 2",
  instead of "exit inside, to Tywll Cave" for all of them. An exit you reach down a flight of
  steps ("stairs down to the 1st floor") is not marked out of reach because it is lower down.
- Tywll Cave's exits have names that say which one is which: "west cave mouth on the ledge, to
  the 2nd floor and on to Lleviathan", "east cave mouth on the ledge, to a side part of the 2nd
  floor", "cave mouth under the ledge, into the 1st floor", "opening into a side cave, north",
  "exit outside, to the east end of the ledge", "stairs down to the far side of the cave, the way
  on", and so on, instead of three exits all called "exit outside".
- The Tywll Cave walkthrough uses those names, and knows where you are: on the high ledge or
  down on the shore, and which of the 2nd floor's two parts you are in (the side part that does
  not lead on, or the part that does).
- A boss is called "Lleviathan, the boss", and auto walk to one is no longer sent "across the
  counter" to a spot it cannot reach: it stops a few steps away (bosses are big) so you can talk
  to it.
- After you use an item on someone, the windows closing one after another no longer read the
  menus again ("To who? lebon", "Everyday Items. retro", "To who? lebon"...).

CHANGES IN 0.54
---------------
This version changes only the mod's own files: it updates itself when the game starts, with no
need to run the installer again.
- People with the same name get a number each: "priest 1", "priest 2", "priest 3". The same
  person keeps the same number while you are there, wherever they are in the list.
- Picking a monster to attack reads only the one the arrow is on, with its place among all the
  monsters: "Chimaera A, 1 of 3", then left and right "Chimaera B, 2 of 3", and down "Lost
  soul, 3 of 3". Before, a group was read all at once ("Chimaera A and B, 1 of 2").
- Party tricks. Misc., Assign Party Tricks now says which button each row is for: "B and up:
  Air Punch", "B and right: empty", ... "B and down, 2nd trick" (down can do up to 4 tricks in a
  row; the others do one each). The list of tricks to pick from says "Pick a trick for B and
  right" when it opens, "not learned yet" for the question marks, and "nothing, clears the row"
  for the dashes at the end of page 2.
- Out in the world, hold B and press a direction on the D-pad to do your party tricks: the mod
  says the trick (or tricks, for down) as the game does them, or that nothing is set for that
  direction.
- Tower of Trades walkthrough (the guide key, or LT + Back): outside the door it says which
  button your Bow party trick is on and how to open the door with it (or how to put Bow on a
  button first), then a step by step guide for each of the seven floors and the boss, the Master
  of Nu'un. The tower's stairs are named by floor and direction ("stairs up to the 4th floor,
  north west"), the door is "tower door, it opens with the Bow party trick", and the floors'
  names were one floor off (the 2nd floor was called level 3).
- Auto walk and the beacon now go round other chests, pots and barrels on the way to the one you
  picked. Before, going to a chest in a row of chests walked into the one next to it and got
  stuck there.
- The Tower of Trades' floors all share one map file, so the mod took them for one place: stairs
  on the 3rd and 4th floors got the 1st floor's names, and something picked on one floor could be
  walked to on another. Each floor is now its own place.
- After a battle, auto walk carries on only once the gold and experience box has closed, so the
  press that closes it no longer stops the walk again.
- Spells & Abilities: moving through a party member's spells now reads each spell's name, with
  what it costs and how much MP they have ("Heal, 2 MP, you have 0, not enough", "Zoom, no MP
  needed"), then its description. Before, only the descriptions were read after the first spell.
- "Tower of Trades -???" is read as just "Tower of Trades".
- Ladders. What was called "something to search" is a ladder: the list now says "ladder, top end,
  it goes down" or "ladder, bottom end, it goes up". Auto walk to a ladder end walks onto the
  ladder and climbs to it. Auto walk to something at another height that a ladder reaches far
  sooner than the long way round (Dourbridge's doors down on the walkway by the river, from the
  bridge) goes down or up the ladder first, then on to it. Starting a walk while partway up a
  ladder climbs on toward where you are going instead of getting stuck. (On a ladder yourself:
  up on the D-pad climbs, down goes down.)
- Dourbridge: the rooms under the bridge are named "Item shop door, under the bridge on the
  right" and "Bar door, under the bridge on the left", not "Item shop on Right Under Bridge door".
- Coming out of the Tower of Trades says "Tower of Trades, outside", not "Newid Isle, tower door,
  it opens with the Bow party trick".
- Shopkeepers, innkeepers, priests and bank clerks say what they are in the people list:
  "weapon and armour shop, big man in a horned helmet", "item shop, old man with a walking stick",
  "church services, hooded man", "inn, ...". (Worked out from the game's own scripts: whoever's
  words open a shop, an inn, a church or the bank, where they stand.)
- Dourbridge's item shop: the door and the stairs at the back are in a shut-off back room. They
  now say so: the room is reached by the shop's upper door outside, which opens with the
  Ultimate Key, and the stairs lead down to the secret shop.
- Auto walk keeps clear of house doors on the way to someone, so it no longer walks in through a
  door that is beside them (the sailor by Dourbridge's bar).
- Auto walk steers much better (worked out by driving it round Dourbridge). The D-pad goes by
  the map, up being north, but the mod was working out "up" from where the camera hung, which
  swings after you; under Dourbridge's bridge it was a quarter of the way off, so walks zigzagged,
  turned back and gave up. Directions you hear ("5 steps up") are steadier for the same reason.
- A walk that had to work its route out again while you kept walking (someone moving, a bend)
  started the new route from where you had been, behind you, and walked back. It now carries on
  from where you are. A new route that gets less far than the one you are on is not taken.
- Setting off, and sliding along a slanting wall, no longer count as "something in the way": the
  marks those left made narrow lanes look shut, and walks went the long way round or stopped.
- A walk stuck over and over now stops and says so. Before, it felt its way along the walls,
  which in Dourbridge went round in circles and in through someone's door.
- The ladder leg of a walk heads for the ladder's end at your own height.
- Auto walk could not leave a room whose door leads to another room of the same building
  (Alltrades Abbey's abbot's room): the new keep-clear-of-house-doors rule shut that door too. It
  now only keeps clear of doors that lead out to somewhere else.
- Yes or no questions were not read in some places (the church's "shall I write it in the
  adventure log?"). The game keeps two yes / no boxes; once the mod had found the one Quick Save
  uses, it never looked at the other one again. It now looks for the one that is showing.
- Heights of Loneliness walkthrough (the guide key, or LT + Back): the outside, every floor, the
  caves off floor 3, the way out at the top, Zere Rocks and the boss, Garth Goyle, with what to
  do afterwards. The floors are named "Heights of Loneliness, floor 2" (they were one floor off),
  and the exits say where they go ("first hole, into a cave, to the kitty litter chest", "door at
  the end of the long vine, on to floor 6").
- Auto walk climbs a run of ladders or vines. Pick a chest on a ledge two vines up, or the vine
  at the top that leads to the next floor, and it walks to the first vine, climbs it, walks
  along that ledge to the next one and climbs that, and so on to what you picked. Before, it
  only managed one ladder, and on the Heights of Loneliness' second floor it headed for a vine
  it could not get to.
- A ladder or vine that leads to another floor is in the Exits list, named where it goes ("vine
  up to floor 3"; elsewhere "ladder up to the next floor" or "down to the floor below"). Auto
  walk to it climbs any vines on the way, then up it.
- At the top of a vine, auto walk turned round and went back down it instead of on to the chest
  on that ledge (the seed of deftness on the Heights of Loneliness' second floor): from the very
  edge of the ledge it worked out only a scrap of the ledge as where you could walk. It now looks
  from a few spots round where you step off.
- Just off the top of a vine, auto walk could not work out a route ("As close as you can get"
  a step from the vine, on the way to the vine up to the Heights of Loneliness' third floor): the
  ledge's edge right in front of you counted as a wall. A route now starts from the spots round
  you as well.
- Things that no run of ladders reaches no longer say "by ladders", and auto walk no longer sets
  off up a ladder that does not lead there (the kitty litter chest on the Heights of Loneliness'
  third floor sent you to the far east vine). That chest now says it is reached through the first
  hole, into a cave, in the exits list.
- Ladders whose ends hang out over a drop, with no floor right under them (floor 3's vines), are
  now found by auto walk's ladder routes: walking to the first hole from the mini medal ledge goes
  down the vine first.
- Bloomingdale was called "Basement on Right Under Bridge" (a name from Dourbridge's list), so
  its way in from outside was "stairs down to the basement, under the bridge on the right", and
  so was the way out of its inn. It is now "Bloomingdale", and the field round it is "fields
  round Bloomingdale", so arriving in the town is announced.
- A building's floors read better: "Inn door", not "Inn Lv 1 door"; "Bloomingdale, Inn", then
  "stairs to Inn, floor 2" and "Inn, basement".
- Zere Rocks: the slime you talk to before the boss was missing from the people list (the game
  places it like a story character). It is now there as "slime", in the north east house, just
  in front of you as you come in.
- Zere Rocks' places have proper names: "door to the north east house, where the slime is",
  "stairs down to the cellar, beside the north east house" (the ghost, after the boss),
  "doorway by the big stone tree" and "way back down to the Heights of Loneliness". Before, they
  had names from Angel Falls ("Petra's House", "Petra's House B1", "Cave"). The walkthrough says
  the same.
- Places whose own name says where they are no longer say it twice: "Heights of Loneliness,
  outside", not "Heights of Loneliness - L7, Heights of Loneliness, outside".
- The outside of a place (Zere Rocks, the Heights of Loneliness) now uses the mod's own names for
  its exits; they were only used inside.
- A few object names were cut short: "statue of a beautiful large bird with its wings spread
  wide", "peculiar sculpture that sort of looks like a person".
- Auto walk to a chest, pot or barrel now stands you square in front of it, a step away (on
  your side of it), waits for the game to catch up with the pad, steps back if it carried you
  past, and turns you straight at it, then says "In front of treasure chest. Press A." Before,
  it aimed at the middle of the chest and could end on a slant beside it, where A does nothing.
- A chest is only counted as opened once the game says something after you press A by it.
  Pressing A beside one that did not open marked it "opened" anyway.
- Auto walk from a ledge to a chest on another ledge at much the same height (from the blue
  chest to the seed of deftness on the Heights of Loneliness' second floor) said there was no
  way there. It now goes down the vine and up the other one.
- Something up a ladder (or an exit down one) says "higher up, by ladders" instead of "no way
  there from here", and
  the Items list says "9 of them on other levels, up or down ladders or another way" where there
  are ladders, not "in other rooms".
- Auto walk squeezes along narrower ledges further off (the path round the second floor of the
  Heights of Loneliness is barely wider than you).

CHANGES IN 0.55
---------------
- Shops: equipment that changes a percentage (kung fu shoes' Evasion Chance) left out the
  people who can wear it. It now says "Jezza, Evasion Chance up 2.5%, 0.5% to 3%".
- Shops, "How many?": the list of how many each person holds no longer mixes in the equipment
  comparison ("Defence, Retro, Lebon 81"), and someone holding none says "none".
- Auto walk goes through a building when that is the only way. Out of Bloomingdale's workshop
  into its back yard, the weapon shop could not be walked to ("As close as you can get"): the
  only way out of the yard is back through the workshop. Now it says "The way is through the
  workshop: in at its door, out by its other door, and on", walks in, out of the workshop's
  other door, and on to the weapon shop. (A door that takes a moment to swing open no longer
  counts as being stuck.)
- Out of a building by a door named after the place ("Bloomingdale door") says "Bloomingdale",
  not "Bloomingdale, Bloomingdale".
- Someone with people all round them (Marion at her table, between her two guests): auto walk
  kept bumping into the guests and gave up ("Stuck"). It now goes to the spot in front of them,
  the way they face, across whatever is in between (Marion: across her table, from its far
  side), or failing that a free spot straight beside them; turns you to face them and says "In
  front of Marion. Press A to talk." (From beside her, A spoke to a guest.)
- The game window's menu bar (Game, Graphics, Screen, View, Wireless, Modern, Mods, Help) now
  opens from the keyboard, as in any Windows program, so your screen reader reads it: Alt and
  the menu's letter (Alt+W for Wireless, Alt+G for Game), or Alt on its own and then the
  arrow keys (Escape closes it). Not in fullscreen, where the menu bar is hidden. This changes
  the game itself (game patch 4): close the game and run Install DQ9 Access.bat once after
  updating, when the game says so.
- DQVC (Sellma's shop): each item now says its price and how many are left ("Metal slime
  spear, 45000 gold, 1 left, 5 of 6"), then, after its description, what it does for each of
  you ("Attack. Retro, cannot equip. ... Bish, up 43, 173 to 216") or, for other items, how
  many each of you and the bag already hold ("Held: Retro none, ... bag 5").
- Pavo, at the right end of the Quester's Rest counter: auto walk took you round behind the
  counter, where he only says "......". It now takes you to the front of the counter, facing
  him, where he talks to you properly (people behind a counter are talked to from the side
  they face).
- Erinn's menu (Stay at the inn, Canvass for guests, View the guestbook, Leave) was silent
  after you had been in DQVC: the game had put her messages somewhere the mod did not look.
  It now finds them there too.
- The Quester's Rest door's "Visit which room?" list was silent. It now reads each room as you
  move ("Royal Suite, 1 of 24"); up and down move through a page of six, left and right turn
  the page.

CHANGES IN 0.56
---------------
- Auto walk sets off at once: while a long route is still being worked out (a second or so in a
  big town such as Bloomingdale) it makes a start toward the place when the way straight on is
  open, instead of standing still, and routes are worked out about twice as fast.
- Auto walk steers round people standing in the way. In Bloomingdale, with a crowd at the foot
  of the steps up to Marion's gate, it kept walking into the man beside the steps and gave up
  ("Stuck"); it now goes round him.
- Bloomingdale: the gate at the top of those steps was called "door to a small room"; it is now
  "gate to Marion's yard".
- Doors in a slanting row of houses (Bloomingdale's Terrace House): auto walk came at the door
  along the row, ran into the house front beside it and said "it did not open". It now steps
  round to the front of the door and walks straight in.
- Going into a house by its door no longer says "Through ... In here: ..." with the things
  outside; the game takes you in and the mod says where you are.
- Wells: auto walk to a well stands you at its rim, facing it, and says "At the well. Press A to
  climb down." (It used to try to walk into it, then round the far side.)
- Starting or reloading the mod out in the street no longer says "Buy, 1 of 3" (the last shop's
  menu, still in memory).
- The Bad Cave walkthrough, on the story guide button: outside (which of the two entrances is
  the way in), floor 1 (the kidnappers' chair and their ladder; floor 1 is in pieces joined
  only through the caves below, so the steps follow the piece you are in), the caves under it,
  B1, B2 and the boss, Tyrantula, and what to do afterwards. Its exits are named ("cave
  entrance, left, the way in", "hole, east, down into the caves", "way on, west, down to B1")
  and so are its floors ("The Bad Cave - B1").
- The changes to auto walk listed above did not all reach the copy in your DQ9 access folder
  the first time; they are all in it now (the gate to Marion's yard is named in the doors list).
- The story guide and the dungeon walkthroughs are now on the left trigger and the right trigger
  (hold LT, press RT), easier to find than Back. LT and Back still work.
- The Bad Cave: the chair at the kidnappers' table only says "It's a rickety old chair" until you
  have overheard the kidnappers, which happens at the east end of their ledge, above their door.
  That spot is now in the objects list ("end of the ledge, above the kidnappers' door: walk here
  to overhear the kidnappers") until you have been there, and the walkthrough says to go there
  first.
- Signs: auto walk to a sign ended on its back ("standing on the wrong side of it") when the game
  marks the spot where it notices you on that side (the Bad Cave's sign by the bridge), or with
  your back to it when the last step was a correction. It now goes round to the front, settles,
  and keeps turning until you really face it.
- The Bad Cave's overhearing spot dropped out of the objects list if you had walked under it, on
  the floor by the kidnappers' door below the ledge, as if you had been there. It now only counts
  once you have stood on the ledge itself.
- The Bad Cave's kidnappers cannot be overheard, and their chair does nothing, until a step in
  Bloomingdale is done: talk to the ghost on the ground floor of Marion's mansion (it only says
  "......"), then examine the gravestone in the mansion's garden. The ghost is now called "ghost"
  in the people list. The Bad Cave walkthrough (outside and on the ledge) checks this and, if it
  is not done, says what is left; the overhearing spot in the objects list says "not yet" until
  then. Bloomingdale's story guide step says the same.
- The Bad Cave walkthrough also says to read the sign by the kidnappers' table before sitting in
  the chair (the chair needs that too), and leaves out the steps you have already done.
- The overhearing spot now counts as done only when the game says you have overheard the
  kidnappers, not when you have stood there (standing there too early hid it).
- Signs everywhere: auto walk now stands you where the game itself reads each sign from. The
  game marks a box in front of its signs (and gravestones, plaques and inscriptions); stand
  anywhere else and it says you are "standing on the wrong side of it". The mod now has those
  boxes from the game's files (76 of them), and walks you to a clear spot well inside the box, a
  step from the sign, then turns you to face it straight on (slanted if the sign stands at a
  slant, as some of Bloomingdale's shop signs do). Before, it guessed from the camera, which
  went wrong for signs that face sideways and in the open fields, where the camera turns.
  For anything without such a box it still goes by the camera, but never to the wrong side.
- Ladders and vines on the way are climbed for you more often:
  - Picking the end of a ladder you are standing at (the bottom end, from the bottom) now climbs
    it; it used to walk you to the foot of it and stop.
  - Picking something you cannot walk to that the mod had not yet marked out of reach (just after
    coming into a place, or in a big field still being worked out) now goes by the ladders when
    they lead there, instead of setting off on foot and getting stuck.
  - The Bad Cave walkthrough now says to pick the hole once the kidnappers' ladder is down: auto
    walk climbs down it on the way.
- Exits list: exits that all lead to the same place but each have their own name are now all
  listed. In the caves under the Bad Cave's floor 1, all four ways out go up to floor 1, so only
  the nearest was listed ("nearest of 4"), and the two at the west end the walkthrough talks
  about could not be picked. Exits with the same name are still grouped as before.
- Something the mod thinks you cannot walk to, at your own height and not far away: auto walk
  now heads straight for it, feeling its way along walls, instead of saying "There is no way
  to ... from here". The mod's map of the walls is sometimes wrong: at the foot of the
  kidnappers' ladder in the Bad Cave it showed walls all round, though you can walk straight
  east to the hole. It says first that the map shows no way, and gives up after about 40
  seconds if it really cannot get there.
- Chasing monsters that run away (metal medleys, metal slimes): auto walk now heads for where
  the monster is going, from how it has been moving, so it cuts it off instead of trailing
  behind it, and keeps after it in a straight line while nothing is in the way, instead of
  stopping to work out a route every time it gets no closer.
- The Bad Cave walkthrough said to examine Marion's doll after the fight, in the boss's lair.
  The scene there plays by itself; the doll is then back in Bloomingdale, by the grave in
  Marion's garden, and examining it gives the fygg. Once Tyrantula is beaten, the walkthrough
  (anywhere in the Bad Cave) and the story guide now say so, and the doll is called "Marion's
  doll, by the grave" in the people list (it was called Marion).
- The mod's map of the walls is sometimes wrong: it has walls the game lets you walk straight
  through (the Bad Cave's floor 1, round the foot of the kidnappers' ladder). Now, whenever you
  walk through one of those, by yourself or by auto walk, the mod forgets that wall and writes
  it down in dq9-access-walls.txt in the DQ9 access folder, so from then on the lists stop
  saying "no way there from here" and auto walk plans its route through. Walking up or down a
  ladder never counts.
- Walls of a ledge above you that start just over your head no longer count as being in your
  way (in the Bad Cave they made some places down below look shut in).
- The Bad Cave walkthrough on the ledge says to climb down the kidnappers' ladder first and then
  pick the hole, which auto walk heads straight for.

CHANGES IN 0.57
---------------
- Locked doors and gates inside a place: auto walk no longer tries to go through them. In the
  ship's hold, the barred gate to the room with two chests is locked (it opens with the Ultimate
  Key), and walking to the stairs from beside it went straight into it, so the game kept saying
  "The door is locked" and the walk stopped. The mod was missing the game's rules for that gate
  and for one other door in a dungeon; it has them now. A door the game says is locked when you
  walk into it is also counted as locked from then on, even where the mod has no rules for it.
- Something you cannot get to because it is behind a locked door now says so: "There is no way
  to treasure chest from here. It is behind a locked door, right next to you. The door opens with
  the Ultimate Key." Auto walk does not try heading straight for it.
- At sea: the exits list now has the towns and other places of the world (Bloomingdale, Hope
  Springs, Dourbridge, Gleeba and the rest, the ones the world map shows), nearest first, with
  the way to each. Pick one and auto walk sails there: straight for the nearest bit of coast by
  it where the ship can land, feeling its way along any land in between, and stops at that
  coast, saying where the place is from there. Sail on into the land to go ashore. The places
  come from the game's own world map data, the coasts you can land on from the ocean map.
- Sailing keeps clear of the other coasts you can land on: touching one asks "Disembark?" and
  stopped the sailing short (on the way to Gleeba you could end up ashore on the Slurry Coast).
  It now plans a route round the land and round those coasts, to the one by the place you
  picked. It says "Sailing to" at sea instead of "Walking to".
- Sailing goes right up to the coast by the place: it sails to just off it, on the water side,
  then straight into it until the game asks "Disembark?". It used to stop a few steps short and
  leave you to find the coast yourself.
- Vehicles: a new list. When you have gone ashore from the ship, the ship is in it, at the dock
  where you left it: pick it and auto walk takes you to the shore beside it, facing the ship,
  ready to press A to go aboard. The mod remembers where you left the ship, in dq9-access-ship.txt.
- The mod's sounds (the auto walk beep, the beacon, the bump) follow your sound output: when you
  switch to other headphones or speakers, or unplug them, they move to the new default output
  within a couple of seconds. Before, they stayed on the output that was in use when the game
  started, so after a switch you heard nothing from the mod until you restarted the game. This
  is a change to the game's part of the mod: close the game and run Install DQ9 Access.bat again.
- Gleeba: the exit to the Djust Desert, at the bottom of the long slope south of the square, was
  called "no way there from here", so auto walk would not go. Its box sits far below where you
  start, and the mod took that for another level; an exit you can walk right up to now counts
  as reachable however low or high its box is.
- Shops, "How many?": the number and the price were sometimes not read at all, nor when you
  changed them (Gleeba's weapon shop). Once you pick something, the game draws the item's
  details on the top screen last, and the mod looked for the How many? window only there; it
  now looks in the list's layout too.
- The ship, when it is not where you are: the Vehicles list says where it is docked ("ship, not
  here: it is docked in Western Wormwood"), named after the place where you went ashore, and
  picking it says where to go back to.
- The ship after a Zoom or a chimaera wing: it follows you, to the dock nearest where you
  arrive, out in the fields by the town (Zoom to Bloomingdale and it waits on the shore just
  south-west of the town gate, not at the town's jetty). The mod now finds the ship itself on
  the map, so wherever it has moved to, the Vehicles list has it as "ship" with its directions,
  and in a town it says to go out into the fields. Auto walk takes you to the shore beside it,
  up against its side, and says "Press A to go aboard". Before, it said the ship was at
  Bloomingdale's jetty, where it is not.
- At sea, places no ship can reach are listed as "not by ship", and picking one says why
  instead of sailing you to the nearest coast you can land on (Eastern Coffinwell's), where the
  game asked to go ashore somewhere else. The Tower of Nod: only the Starflight Express goes
  there, once the main story is finished. The Gortress and Gittingham Palace: the Gittish
  Empire has no coast to land on; the story takes you there later, and after that the
  Starflight Express flies there.
