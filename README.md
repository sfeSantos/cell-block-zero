# Cell Block Zero

A prison break in the shape of the first Wolfenstein 3D, written in Lua for
[LÖVE](https://love2d.org/) 11.x. One ray per screen column, billboard sprites,
text files for levels. Everything is drawn in code at startup: the walls and
the ground are written pixel by pixel into an atlas, the guards and the
weapons into a canvas, and every sound is synthesised. The art files in
`assets/` are painted over that when the game loads, and the game runs the
same with the folder empty.

Lights out an hour ago, and the guard who let himself into your cell was not
there to talk. He is still on the floor of it, and everything you own came
off him: a hatchet, a revolver, a throwing knife and a vest, torn and half as
good as it was.
The way out is three blocks away and the sun comes up in a few hours.

## Running

```
love .
```

Or pack it: `zip -9 -r cellblockzero.love . -x '*.git*'` and run
`love cellblockzero.love`.

### On Windows

1. Install LÖVE 11.5 from [love2d.org](https://love2d.org/), the 64 bit
   installer. Lua itself is not needed: LÖVE carries its own.
2. Clone or download this folder, say to `C:\Users\you\CellBlockZero`:

```
git clone https://github.com/sfeSantos/cell-block-zero.git CellBlockZero
```

3. Drag that folder onto `love.exe`, or run it from a command prompt:

```
"C:\Program Files\LOVE\love.exe" C:\Users\you\CellBlockZero
```

To get a single file to double click instead, zip the contents of the folder,
not the folder itself, and rename the zip to `cellblockzero.love`. In
PowerShell, from inside the folder:

```
Compress-Archive -Path * -DestinationPath cellblockzero.zip
Rename-Item cellblockzero.zip cellblockzero.love
```

Settings and the blocks you have opened are kept in
`%APPDATA%\LOVE\prison-break-fps\progress.txt`. Deleting that file puts
everything back to the way it comes out of the box.

## Controls

| Action | Key |
| --- | --- |
| Walk | W and S |
| Step sideways | A and D |
| Turn | the mouse, the arrow keys, Q and E, or alt with A and D |
| Look up and down | mouse, page up and page down, home to centre |
| Run | shift |
| Fire, or execute | left mouse button, or ctrl |
| Open a door, use the exit | space |
| Free a prisoner | space, standing in front of him |
| Weapons | 1 to 7, or the mouse wheel |
| Throw a grenade | G, or the right mouse button |
| Throw a flash grenade | F |
| Throw a knife | R |
| Set a leg trap | B |
| Silencer on and off | T, or the middle mouse button |
| Mouse speed | [ and ] |
| Developer console | F2 or tilde |
| Mouse diagnostics | F6 |
| Cheats | F3 god, F4 invisible, F5 endless ammunition |
| Map on and off | tab |
| Pause | P |
| Save the block as it is | F9, or the line in the menu |
| Menu, with the block left as it is | escape |
| Fullscreen, controls | F11, F1 |

F9 writes the block to the save file exactly as it stands: where everybody
is, what is on the floor, which doors and lockers are open, what you are
carrying and how long you have been at it. The menu has the same thing on a
line of its own while a block is in progress, and `Load the saved game` at the
top of the menu takes you back into it. There is one slot, and the newest save
is what is in it.

Escape puts the block on hold and goes out to the menu. The block is kept
exactly as it was, and the menu grows a line at the top, `Carry on`, that
drops you back into it where you left off. Escape again from the menu does the
same thing. The clock on the end of level screen does not run while you are
out there.

The menu works with the mouse as well as the keyboard: the line under the
pointer is the selected one, a click runs it, and clicking a setting cycles it.
The game opens fullscreen at the desktop resolution, F11 switches to a window.
The pointer belongs to the game while a block is being played and comes back
when you pause, open the menu or leave the window. A and D step sideways and
the mouse turns, the way the games you already play do it; the keyboard keeps
a full set of turn keys for playing without a mouse, on the arrows, on Q and
E, and on A and D while alt is held. Use one of those together with the mouse
and the mouse has the last word: while it is aiming, the turn keys stand down,
and they take over again a moment after the hand stops, so the two never
fight over the view. The mouse has nine speeds, the third by default. Four
menu lines cover all of it: Mouse input, Turn, Vertical look and Mouse speed,
with `[` and `]` changing the speed without leaving the corridor, and the lot
is remembered between sessions along with the difficulty.

The sight sits in the middle of the screen and nothing moves it except you:
walking rocks the view and firing kicks it, and the sight stays put through
both. Push the mouse up or down and it goes with you, and about a second
after you stop it comes back to the middle. Looking up and down is for seeing
rather than aiming, since a shot goes straight out from the sight whatever
the view is tilted to, so Vertical look can also be set to off and leave the
mouse doing nothing but turning.

The sight sits on the horizon because that is where the bullet goes, and a
shot connects only while the sight is on the figure, about half a tile across
the shoulders. Looking up and down is for seeing, not for aiming: guards move
with the horizon and stay under the sight whatever the view does, so the view
eases itself back to level half a second after you stop looking up or down
rather than leaving the sight parked somewhere you are not looking. Home
levels it at once.

The Mouse input line chooses between working that out automatically and
driving the view from the pointer alone, which is the setting for a window
manager that claims relative mode and then leaves the pointer stuck against
the edge of the window. There are three ways the mouse can drive the view and
automatic falls through them by itself. Relative mode first, except that a window manager claiming
relative mode while the pointer still wanders is not believed: the pointer
moving is taken as proof it is not on. Then motion events, or reading the
pointer twice when no events arrive, never both at once, with the pointer
dragged back to the middle whenever it strays. Then, when that drag is refused
too and the pointer parks against the edge, a steady turn that keeps going
while the hand is still moving and stops a quarter of a second after it is
let go. F6 says which one is live, whether the
recentre takes, and what the last movement reported. The Turn line reverses
the direction if your setup hands it over backwards.

## Testing it

There is a developer console on F2, or on the tilde key. It pauses the game,
takes a line and runs it; `help` lists everything. The cheats are `god`,
`invis` and `ammo`, also on F3, F4 and F5, and what is switched on is printed
above the status bar so you never wonder. `noclip` walks through walls.

The rest is for trying things out. `guard 3 4` drops four riot captains in
front of you, `guard 1 2 dummy` drops two that will not fight back, `clear`
empties the block, `killall` drops everyone where they stand, `distract` makes
every guard forget you and go back to his round, `freeze` stops them thinking,
and `dmg` prints what each of your hits took off. There is also `give`, `heal`,
`armor`, `tp`, `where`, `block` and `restart`.

The **shooting range**, from the menu or with `range`, is a long hall with a
bench holding every weapon, every box of ammunition and both vests, and targets
down the lane at roughly five, fifteen, twenty five, thirty five and forty
tiles. The markers on the walls are five tiles apart. The targets stand still,
say what each hit took off them, and get back up a couple of seconds after they
drop, so you can measure a weapon and watch where its range runs out: the far
two are past every barrel in the game.

## The blocks

Three of them, played in order. A block only opens once the one before it has
been finished, which means walking out of its exit: the menu will not let you
pick a block you have not earned, and what you have opened is kept in the save
directory between sessions. Health, armour, weapons and ammunition carry from
one block to the next. Dying puts you back at the start of the block you are
in, with the loadout you entered it with.

Walking out of a block stops at a page that adds it up before the next one
starts: how long it took, how many of each rank went down and how many were
still on their feet, how many of those never heard it coming and how many
went in their sleep, lockers opened and how many of the ones left behind had
something in them, loose panels pushed, pickups taken, prisoners let out, how
often the alarm went off, and what health and vest you walked out with.

## Weapons

| Weapon | Ammunition | Notes |
| --- | --- | --- |
| Hatchet | none | silent, and twice as hard from behind |
| Revolver | bullets | accurate, loud, takes the silencer |
| Uzi | bullets | fast and wild, takes the silencer |
| Rocket launcher | rockets | clears a room, including you if you are in it |
| Grenade | grenades | arcs, bounces, goes off on a fuse |
| Flash grenade | flashes | blinds everyone who can see it, you included |
| Throwing knife | blades | silent, lethal in the back, three throws a blade |
| Leg trap | traps | set with B, kills a dog or a guard who is not looking |

The silencer is a pickup. Once you have it, T fits it to the revolver or the
uzi: a shot then carries about four tiles instead of seventeen, and it costs
nothing in stopping power. Against somebody who has not noticed you, a quiet
round hits for well over twice as much, which puts a guard down with one shot
from the revolver, and a man asleep in his chair never wakes up. Once he is
shooting back the surprise is gone and it does what the loud round does. It
is the difference between killing one guard and fighting the wing.

The throwing knife is the quiet way of killing somebody who is too far off to
walk up to: 45 damage, 77 in the back, which kills a guard or a sergeant
outright. It drops where it hit, so you walk over and pick it up again, and
the third throw snaps the blade. Four blades is as many as you can carry.

Leg traps come out of lockers and are set on the floor with B, where they stay
until something walks into one: 60 damage to a dog, which kills it, and 45 to
a man, which kills a guard and leaves a riot captain pinned for two and a half
seconds and shouting. You never spring your own. They are for the two things
you cannot walk up behind: a dog running at you in a straight line, and a
guard walking his round. A guard who is already hunting you is looking where
he puts his feet and spots one about seven times in ten. Measured over twenty
runs each, sent straight down a lane with a trap in it: a dog sprang it 20 of
20 and died, a guard on his round the same, a guard already hunting 6 of 20, a
riot captain 5 of 20 and he lived, pinned and down half his health.

## Executions

Come up on a guard who has not seen you, or stand behind one who has lost you,
and the fire button kills him in one move instead of shooting. With the hatchet
in hand it is the throat or the back of the head, bare handed it is the neck.
All three are quiet, so the next guard down the corridor keeps walking his
round. The bodies stay where they fall for the rest of the block, and a guard
who walks past one raises the alarm, so where you leave them matters.

## The guards

Three tiers, one brain, told apart by their uniform: the blue **guard**, the
olive **sergeant** in a flak vest, the black **riot captain** behind a red
visor. Each tier is faster, tougher, quicker to react and better shot than the
one before.

They only open fire when they can actually see you. Short of that they walk a
round: a post to stand at and scan from, a route to pace, or a wing to sweep,
picked per guard at the start so two in the same corridor do not move alike. On
a quiet round they keep to the corridors and the rooms, they do not go rattling
cell doors, which is the only reason you get out of yours.

A gunshot, a scream, a door or a body on the floor is answered by the two to
four guards nearest to it, depending on the difficulty, and nobody else moves.
The number of guards on their feet at any moment is capped at one more than
that, so the shooting never snowballs into the whole block: a guard who sees
you himself always engages, but nobody else is sent while the quota is full.
Earshot is eight to twelve tiles by tier, measured on foot through the
doorways, so a shot in the laundry does not empty the yard, and a guard who
heard it from further off only gets sharper where he stands. The first guard
who sees you calls it in, and that reaches five and a half tiles and two
colleagues at a time. Every one of them still has to find you himself before he
shoots.

Nobody stands inside anybody. Guards are solid to each other and keep their
distance in every state, so a squad arrives spread across the room instead of
stacked in one tile, and two told about the same noise are sent to spots a
little apart so they cover it between them.

Nobody ever walks towards where you are. A guard walks towards the last place
he had a reason to believe you were, on a path worked out to that spot, and
when he gets there and finds nothing he looks around and tries the next corner
along until he runs out of patience. Break line of sight and move, and what
follows you is a search, not a homing missile.

The klaxon goes off the first time anyone sees you. It reaches the whole block
and makes every guard sharper for a few seconds, a wider cone, more scanning,
quicker to react, but it tells nobody where you are: only the handful already
near you have anywhere to go.

In a fight they hold the distance their weapon likes, strafe while they shoot,
spread out instead of queueing in the doorway, open doors, step out of the way
of a rocket, break line of sight to recover when they are hurt, and lob a
grenade at the corner they last saw you behind. Lose them for long enough and
they give up and go back to the round: eleven seconds for a guard, forty for a
captain.

Here and there a guard is asleep in a chair. He sees nothing and hears nothing
until a noise wakes him, so he can be walked up to from the front and executed
like anyone caught unaware. A shot nearby, a door opening next to him or the
klaxon will have him on his feet, groggy for about a second and then an
ordinary guard of his tier.

The dogs are a fourth kind and do not count as guards: 34 health, 3.5 tiles a
second, no radio and no round to keep. They roam their end of the block and go
for the nearest prisoner they can see, which means you or any man you have let
out. A dog beats a freed prisoner about three times in four. Against you it is
two revolver rounds, as long as you hear the bark in time.

## Lockers, panels and keys

Lockers are the steel cupboards set into the walls: press space and one opens,
once. What is in it was rolled when the block loaded, so it can hold bullets,
food, a first aid kit, a vest, a leg trap, grenades, a knife, rockets, an uzi,
a riot vest, the silencer, two or three of those, or nothing at all. About one
in five has already been cleared out, and every block has armour in a locker
somewhere: if the dice leave it out, one is put in.

Panels are sections of wall that slide back when you press space on them. They
are built out of the same wall as everything around them, but one that has
been pushed before shows it: a hairline down both sides, scrape marks and dust
along the floor at its foot, and a worn patch where hands have pushed it.
Stand in front of one and the screen says "[space] this section is loose".
They never show on the map.

Keys are never on the floor. Each one is on a guard, in a locker or behind a
panel, and the level file says which.

## Noise and where it carries

The block is cut into areas: a room, or a stretch of corridor between doors.
A gunshot is heard inside the area it was fired in and no further. Guards in
the next room hear something, get sharper and change their round, but they do
not come and they do not know where you are. Rockets and grenades are the
exception: a blast carries through the wing, and while the two or three
nearest walk in, the rest only change what they are doing.

A guard belongs to the area he starts in. He leaves it to go and look at
something only while a colleague is still in there, so no corner is ever left
empty, and however a level file is drawn nobody starts the block standing on
top of a colleague.

## The other prisoners

Some cells hold scenery that says what the place is: a skeleton still hanging
from its shackles, a man who used his own sheet, a body face down, remains
nobody could put a name to. None of it moves.

Some of them are alive. Open his door with space, step in front of him, and
the screen offers "[space] tell him to come with you". The door has to be
open: through the bars he cannot hear you. From then on he is gone: he does
not wait for you and does not follow you about, he goes looking for the
nearest guard anywhere in the block, opening any door that is not locked with
a key, and goes at him with his hands. He falls in behind you only when there
is nobody left to go after. He has sixteen hit
points, no gun and no armour. Measured over forty fights of each kind: one on
one with a guard three tiles apart he wins about three in four, starting seven
tiles apart he dies about three in four, against a sergeant face to face he
dies almost every time, and coming at one from behind he wins about two in
three. Against a riot captain he dies having taken half the captain's health
with him. He is a distraction that hits back, not a soldier.

A guard who has lost you will fight a loose prisoner where he stands, and
seeing one sets off the klaxon without telling anybody where you are. Your own
bullets do not pass through him either.

## Level files

A level is a text file in `levels/`. Everything above the `[map]` marker is a
`key = value` header, everything below it is the grid, read exactly as typed:
a space and a dot are both floor, so trailing blanks count. Lines starting with
`;` are comments.

```
name = D Block
next = 02.txt
brief = shown on the loading screen
ceiling = 0.10,0.11,0.14
floor = 0.21,0.19,0.17

[map]
########################################
#...%...%...%...%...%...%...%...%2.....#
...
[end]
```

| Group | Characters |
| --- | --- |
| Walls | `#` stone, `=` brick, `%` cell tile, `&` metal, `~` rock, `*` poster |
| Doors | `\|` steel, `+` bars, `r` `b` `y` locked red, blue, yellow |
| Exit | `X`, a wall tile you press E at to finish the block |
| Start | `N` `S` `W` `E`, one per level, the letter is the way you face |
| Guards | `1` guard, `2` sergeant, `3` riot captain, `4` dog |
| Lockers | `L` a steel cupboard set into the wall, `/` a panel that slides back |
| Traps | `T` a leg trap to pick up and set with B |
| Asleep | `z` a guard in a chair, `Z` a sergeant in a chair |
| Weapons | `u` uzi, `l` rocket launcher, `g` grenades, `f` flash grenades, `K` throwing knife |
| Ammunition | `a` bullets, `A` box of bullets, `o` rockets |
| Gear | `v` vest, `V` riot vest, `m` first aid, `h` food, `s` silencer |
| Keys | `R` red, `B` blue, `Y` yellow |
| Scenery | `k` chained skeleton, `n` hanged man, `d` dead prisoner, `c` remains and blood |
| Prisoner | `p` one who is still alive and will fight for you |

The header also says where each key is: `redkey = guard` puts it on the man
furthest from the start, `bluekey = locker` in the furthest locker,
`yellowkey = secret` in the space behind a panel. A key is never left lying on
the floor.

Leaving `next` out ends the game when that block is finished. A door slides
into the wall it is flush with, so put a locked door in a wall and the key
somewhere you can reach without it.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md). Use it, change it, build on it and
pass it on freely, for any purpose that is not commercial. Selling it, or
anything made from it, is not allowed.

## Layout

| File | What it does |
| --- | --- |
| `main.lua` | love callbacks, menu, the run through the blocks |
| `src/level.lua` | reads a level file, doors, line of sight, the ray cast |
| `src/raycaster.lua` | the 3D view: walls, sprites, the depth buffer |
| `src/textures.lua` | wall, door and ground textures, pixel by pixel into one atlas |
| `src/art.lua` | guards, pickups, explosions, the weapon in your hands |
| `src/world.lua` | one level being played, and everything in it |
| `src/player.lua` | movement, weapons, pickups, the executions |
| `src/weapons.lua` | what the player can carry |
| `src/enemy.lua` | the guards: senses, rounds, fighting, dying |
| `src/nav.lua` | the shared distance field, cover and flank queries |
| `src/projectile.lua` | rockets and grenades |
| `src/save.lua` | the saved game: the whole block written down and read back |
| `assets/` | art painted over what the code draws, see its own README |
| `tools/` | the Python scripts that drew what is in `assets/` |
| `src/fx.lua` | blood, sparks, smoke, fireballs |
| `src/hud.lua` | status bar, map, menus |
| `src/audio.lua` | generated sound effects |
| `src/progress.lua` | which blocks are open |
| `src/console.lua` | the developer console and the cheats |
