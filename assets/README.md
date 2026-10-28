# Dropping your own art in here

Nothing in this folder is required. Everything in the game is drawn in code at
startup, and a file here takes the place of the one the code drew: where there
is a file, that file is what you see, and the drawing in code is only what
happens when the file is missing. Put in the ones you want to replace, leave
out the ones you do not, and the game runs either way.

A file is matched to what it replaces by its name.

## assets/sprites

Everything that stands in the world, one file per frame, square and
transparent where it should be. 64 by 64 is what the game draws at, but any
size works: the file is scaled into the cell. The whole cell is one tile wide
and one tile tall, the feet belong at the bottom edge, and a figure that fills
about two thirds of the width looks right next to the rest.

| Name | What it is |
| --- | --- |
| `g1.<frame>.png` | guard |
| `g2.<frame>.png` | sergeant |
| `g3.<frame>.png` | riot captain |
| `dg.<frame>.png` | dog |
| `con.<frame>.png` | prisoner |
| `prop.skeleton.png`, `prop.hanged.png`, `prop.body.png`, `prop.remains.png`, `prop.deadguard.png` | scenery |
| `prop.stain.png` | blood on the floor, painted into the ground rather than stood up in it |
| `item.<name>.png` | pickups: `uzi`, `launcher`, `grenades`, `flashes`, `bullets`, `clips`, `ammobox`, `rockets`, `vest`, `vestheavy`, `medkit`, `snack`, `silencer`, `redkey`, `bluekey`, `yellowkey`, `knife`, `trap`, `trapset`, `trapsprung` |
| `fx.<name>.png` | effects: `knife`, `rocket`, `grenade`, `flash`, `boom1` to `boom4`, `pop`, `blood`, `spark`, `smoke` |

Guard and prisoner frames: `idle`, `walk1` to `walk4`, `aim`, `fire`, `pain`,
`die1`, `die2`, `die3`, `dead`, `sleep`. The dog has `walk1`, `walk2`, `bite`,
`pain`, `dead`, and the rest of its frames point at those.

`prop.stain` is the one that does not stand up. It is painted flat into the
ground, so its cell is a square of floor seen from above: fill the whole of
it, and leave nothing along the bottom edge the way a standing figure has its
feet.

## assets/views

The weapon in your hands, `<weapon>.<frame>.png`, drawn at 200 by 150 with the
grip at the bottom of the cell. `hatchet`, `launcher`, `grenades`, `flashes`
and `knife` have two frames, `throat`, `head` and `neck` are the four frames of
an execution, and `revolver` and `uzi` have ten:

| 1 | 2 | 3 | 4 | 5 6 7 | 8 9 10 |
| --- | --- | --- | --- | --- | --- |
| in your hands | firing | with the silencer | firing, silenced | the reload | the reload, silenced |

The three of a reload are the magazine coming out, the new one going in, and
the gun coming back up. Which one is on screen comes off the weapon's own
reload time, so a file dropped in here is shown for a third of it.

These are the one place the game draws the same thing twice. The files here
are written by `tools/weapons.py`, and `src/art.lua` draws the same frames in
code for whichever file is missing. They are meant to match, so a change to a
weapon in your hands belongs in both, and a change to only one of them shows
up as the game looking different with this folder empty.

## assets/flats

The ground, tiled across the floor and the ceiling of every block, 64 by 64
and no transparency: `floor.png` and `ceiling.png`. These two are not stretched
over one tile like a wall, they repeat, so the edges of the file want to meet
each other. The level tints them with its own colour, which is why the ones
drawn in code are painted dark and plain. A block with `sky = true` in its
header, like the yard, keeps its open sky instead of a ceiling.

## assets/walls

One file per wall, 64 by 64, no transparency: `stone`, `brick`, `cell`,
`metal`, `rock`, `poster`, `door-steel`, `door-bars`, `door-red`, `door-blue`,
`door-yellow`, `exit`, `locker`, `locker-open`, and `panel-stone` and friends,
which are the loose panels and want to look like the wall of the same name
with the hairline and the scuff marks on it.

The game prints a line at startup saying how many files it picked up.

## Making a set

`tools/` has the scripts that drew what is in here, which need Python and
Pillow:

    python3 tools/guards.py assets/sprites     the three ranks, 13 frames each
    python3 tools/dogs.py assets/sprites       the dogs
    python3 tools/props.py assets/sprites      the pickups, the bodies, the explosions
    python3 tools/weapons.py assets/views      the weapons in your hands
    python3 tools/walls.py assets/walls clean  walls, doors and ground

None of these paints blood into a wall or a ground tile. One file is painted
on every tile of its kind, so a stain in the texture would run the length of
the corridor: the blood on the ground is `prop.stain`, which the game drops
on a dozen or so single tiles of each block.

`tools/walls.py` takes the look as its second argument: `clean` for a block
somebody still washes, `dirty` for mould, soot and what was left on the floor
after a bad night, `worn` for rust and flaking paint. It writes `floor.png`
and `ceiling.png` along with the walls, and those two belong in
`assets/flats`.
