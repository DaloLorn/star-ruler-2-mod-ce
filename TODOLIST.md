# TODO List

This is primarily intended as a developer focused project planning list, rather than something to read. I'm making it public because it's easier for me to keep track of if its in the repository, and it still has some value as a 'where CE is going' indicator.

- Bug list / issues to fix
  - Making parasite AI do razing at end of a budget cycle not start
  - Prevent Dyson Sphere generating with Ice
  - Remove duplicated light png files from repo
  - Teach AI to not put comets on worlds being razed
  - Teach AI to melt ice
  - Teach AI to make most of the constructions by extending the building hint code
  - Teach AI to deprioritise water/food colonisation if have built a stockpile of unused ones
  - Fix adding local asteroid field not applying asteroid graphics (think this was in community patch already)
  - Prevent AI from deliberately researching/building FTL extractors if they don't have any FTL unlocked
    - This hurts the First AI's budget

- Not planned for any time soon
  - Work out how should implement deep space trading
    - Lighting Systems need to create a mini region around their planet, with the location of the planet being regularly updated
    - However the current region system assumes regions don't move, and has some bookkeeping that it does to make indexing for regions fast
    - Either need a way to create mobile regions or allow planets with Lighting Systems to bypass region based trade logic
  - Colonisation ships similar to Motherships for other races
  - AI code to build orbitals like Outposts and Stations
  - Teach AI to scuttle unneeded FTL income orbitals
  - Prevent dillemas occuring multiple times (not sure what's causing this bug, it's quite rare)
  - Teach Mechanoid AI to use FTL Breeder Reactors
  - Motherstation hull for StarChildren (granting positive income but requiring sacrifice of a planet for balance?)
  - StarChildren transfering of pop from Mothership -> Mothership
  - Make autoexplore continue to work after all systems have been visited once (will also split off into own mod or community patch)
  - Add user interface improvements to make it easier to select multiple planets at once, as when every planet can be given move orders it is a bit of a pain to do them individually or after holding CTRL and selecting everything first.
- Long term plans
  - A campaign that doubles as an extended tutorial
    - I will rename all the existing races and tweak them rather than trying to build on established lore I don't know
    - If you can't tell from reading this README I like playing as StarChildren a lot. I think the best way for this is to start the player with a Terrestrial empire, introduce 1 AI and then once they get the hang of some basics have the AI suicide by destroying the system's black hole, prompting campaign episode #2 where your race evacuates on a hastily created mothership and drops down in a larger galaxy to discover more threats
  - Improving the AI
    - Things players can do but AI just doesn't right now
      - Create stations at all??
      - Attempt to achieve the influence victory themselves??
      - Fling battle stations
      - Use/design Motherships well
      - Mine asteroids for ore
      - Move asteroids and other resources around with tractor beams
      - Create battleworlds
      - Use slipstreams to speed up colony ships
      - Attack enemy territory that doesn't border AI's owned systems
      - Recognise that it can't win a fair 1v1 flagship fight with another empire and instead spam loads of cheap siege ships to attack every system possible at once
      - Carpet bomb enemy planets (especially useful vs Mechanoid)
      - Use the tractor beam on Motherships to drag around an Outpost - hey presto my mothership can always fire its weapons and if the outpost gets shot down the labor cost to build a new one is low enough to queue up immediately
      - Use gates to coordinate surprise attacks on an enemy (the AI is already good at doing rapid attacks with Hyperdrives/Jumpdrives/Fling but gates and slipstreams aren't used as well here)
      - Immediately seek to destroy a player's Senatorial Palace if they start one of the Galatic votes that can achieve the influence victory