<p align="center">
  <img src="docs/logo.png" alt="Double Cross: two spies shaking hands under crossing searchlights, one hiding a lit bomb behind his back, the other with his fingers crossed" width="760">
</p>

<p align="center">
  <b>Rival agents. One secret base. Only one gets out.</b><br>
  A two-to-four-player, one-device-each game of sneaking, booby traps and very bad manners.
</p>

<p align="center">
  <a href="../../actions/workflows/android.yml"><img src="../../actions/workflows/android.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/engine-Godot%204.3-478cbf" alt="Godot 4.3">
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20macOS-3ddc84" alt="Android and macOS">
  <img src="https://img.shields.io/badge/licence-all%20rights%20reserved-red" alt="All rights reserved">
</p>

---

## The idea

Up to four agents, **Crimson**, **Cobalt**, **Amber** and **Jade**, have all
broken into the same secret base to steal the same intel. Each player has
their own phone, tablet or Mac on the same Wi-Fi, so nobody can see what the
others are up to. Or play alone against one to three bots.

- **Explore** a grid of isometric rooms: the Reactor Core, the Armoury, the Server Vault…
- **Search** desks, lockers, safes and crates for four pieces of intel.
- **Booby-trap** the furniture and doorways for your rivals to find the hard way.
- **Carry the right gadget** to disarm a trap before it disarms you.
- **Fight** when you meet: a cosh up close or a dart pistol across the room.
- **Escape** with all four pieces before your own clock runs out.

It's a love letter to **Spy vs. Spy**, the 1984 split-screen classic where two
spies booby-trapped an embassy while hunting for a briefcase full of secrets.
Double Cross keeps that mischievous trap-and-sneak spirit but is built from
scratch: one device per player over Wi-Fi, an isometric secret base, and its
own characters, artwork, sound, music and code. See [Acknowledgements](#acknowledgements).

<p align="center">
  <img src="docs/screenshot-room.jpg" alt="All four agents, Crimson, Cobalt, Amber and Jade, in a lamp-lit server vault with steel tread-plate floors and riveted walls" width="49%">
  <img src="docs/screenshot-shock.jpg" alt="Agent Cobalt caught in a shock trap: an x-ray skeleton crackling with sparks under a BZZZT! caption" width="49%">
</p>
<p align="center">
  <img src="docs/screenshot-bomb.jpg" alt="A bomb going off in the Armoury: a fireball, sparks and a KABOOM! caption" width="49%">
  <img src="docs/screenshot-menu.png" alt="Title screen styled as a classified case file: stencilled DOUBLE CROSS title, TOP SECRET stamp, polaroids of the agents and typed mission orders" width="49%">
</p>

## How a match plays

**The goal.** Four pieces of intel, a PASSPORT, CASH, MICROFILM and a KEYCARD,
are hidden in the furniture, one of each. Collect all four and walk out of the
**EXIT** (green on the mini-map). First one out wins.

**Searching.** Stand by furniture until it glows and press SEARCH. Without a
**BRIEFCASE** you can carry only one item: search with full hands and you swap,
leaving yours behind for someone else to find. There's one briefcase fewer than
there are agents, so somebody always goes without.

**Traps** (up to three each, and only you can see your own, though they still
work on you):

| Trap | Where | Beaten by |
|---|---|---|
| **Bomb** | in furniture | Extinguisher |
| **Spring trap** | in furniture | Toolkit |
| **Shock trap** (fries you, skeleton and all) | in furniture | Rubber gloves |
| **Tripwire** | across a doorway | Wire cutters |

Getting caught knocks you out for a few seconds, costs **20 seconds** and sends
any intel you're carrying flying into the furniture around the room. A gadget
is used up when it saves you, then turns up somewhere else in the base.

**Fighting.** Swing your cosh up close or fire a dart (three per life,
auto-aimed at a rival roughly in front of you). Three hits take an agent out:
they drop their intel, lose **30 seconds** and wake up back in their starting
room.

**Clocks.** Every agent has their own clock: 4, 6, 8 or 10 minutes for a two-agent
game (set by the host), scaled up for the bigger bases. Under 30 seconds the
room's alarm light starts beating. If your clock runs out you're out of the
mission and your intel scatters; the last agent still in wins. Once you're
out, the camera follows the agents still playing, room by room, until the
match ends: **NEXT AGENT** (or <kbd>Tab</kbd>) switches who you're watching.

**Air vents.** Some rooms have a crawl-through vent that joins a room two or
more rooms away. Stand at one and press CRAWL. The ones you've used appear on
your mini-map.

**Nacho the dog.** Somewhere in the base is a kennel with Nacho in it: a
scruffy, ginger, very good boy. Search the kennel and he's yours. He follows
you everywhere, through doors and air vents, and sniffs round each room as
you go. He **growls** at trapped furniture and wired doorways (he never sets
them off) and **barks and wags his tail** at furniture with something hidden
in it; a paw print over the furniture shows you which is which. Anyone who
attacks you, or him, gets chased and bitten (each bite counts like a blow
from a cosh) for as long as they keep attacking; once they leave off for a
few seconds, so does he. He can be hurt, though: three hits (his health
shows over him) and he limps home to his kennel. He goes home too if you're
taken out. Either way he's nobody's dog until someone finds him again. Bots
look for him too, and use his nose.

In about two matches in five, while he's out with an agent (never at home
in his kennel), Nacho stops at some point for a **poo** ("hnnng…"), which
takes a few seconds. He won't go while he's fighting, and if anyone starts
on him or his agent mid-poo he stops and goes for them (and tries again
later). What he leaves behind stays put until someone treads in it,
his own agent included: they skid, go feet-up and land flat on their back
with a squelch and a bang, seeing stars, taken out, and everything they're
carrying (intel, briefcase, gadgets) goes flying. The turd's gone, but they
stay smeared in it, with flies buzzing round them, for a good while after.
Medium and hard bots walk round turds; easy bots blunder straight into them.

<p align="center"><img src="docs/nacho.png" alt="Nacho, a scruffy ginger dog with long ears and a red collar, standing, trotting, sitting, sniffing, barking, growling and biting" width="80%"></p>

**The base** is generated from a random number shared by every device, so
everyone sees the same map, and it's different every match. It grows with the
party: 3×3 rooms for two agents, 4×3 for three, 4×4 for four.

### Playing against bots

**TAKE ON THE BOTS** puts you against one, two or three computer agents that
play by the same rules: they have to search to find things, can carry one
item until they find a briefcase, remember what they've searched and set traps
of their own. **EASY** bots are slow, forgetful, ignore the air vents and now
and then walk into their own traps; **MEDIUM** ones learn the vents as they go;
**HARD** ones know every vent from the start and are quickest to pick a fight
with anyone carrying intel. **SOLO TRAINING** lets you explore alone.

Each bot also has a personality, shown on its name tag: a **TRAPPER** rigs
far more furniture and strings tripwires across doorways; a **BRAWLER** picks
fights whether or not you're carrying anything, and chases hard; a **SNEAK**
knows every air vent, uses them all, slips away from fights and comes back to
search wherever it hears intel go flying. With several bots, each gets a
different one.

One-player games can be paused (**PAUSE**, <kbd>Esc</kbd> or <kbd>P</kbd>):
the clocks stop and nobody moves until you resume. They pause themselves when
you switch away from the app.

## Look and sound

- **Art from Blender:** the agents, furniture, floors and walls are 3D models
  built and rendered entirely by script, with normal maps, so the rooms' real
  2D lights (ceiling lamps, wall strips, screens, the exit's daylight,
  explosions, the alarm) shade every surface.
- **Effects:** fireballs and soot, spring launches, lightning and an x-ray
  skeleton for the shock trap, a duct cut-away when you crawl through a vent,
  screen shake, a moment of slow motion on knockouts, film grain, and an iris
  wipe between rooms.
- **Sound:** every effect and the music are synthesised by `tools/make_audio.py`,
  with no samples: wooden knocks and drawer thuds when searching, heel-and-toe
  footsteps on steel, layered explosions, a stuttering mains buzz, typewriter
  keys and rubber stamps. Sounds from other rooms are muffled through the walls.
- **Room tone:** each room has its own quiet background (air-conditioning,
  server racks with clicking relays, or dripping pipes), crossfading as you move.
- **Voices:** agents grunt when hit, cry out when knocked down, shriek when
  electrocuted and crow "ha-HAH!" when they win, each at their own pitch.
- **Music that reacts:** the spy-jazz loop is three loops played together. A
  shaker, toms and a low swell come in while a rival is in your room; driving
  hats, brass stabs and a rising riff come in when your clock is nearly out.
- **Spy-file screens:** the title screen is a case-file dossier, each match
  opens with a briefing that self-destructs, and ends with a stamped debrief
  with a timeline clipped to it: who found what, who trapped or took out whom,
  who ran out of time, and when the winner got out.
- **First person:** the **1ST PERSON** button (or <kbd>Tab</kbd>)
  switches to seeing the room through your agent's eyes: real 3D walls,
  floor and Blender-modelled furniture, with the other agents as *Doom*-style
  cut-outs from their sprite sheets. Through each doorway you see the next
  room (though not who's in it, which stays hidden as it does overhead), and
  beyond that, dim corridors fading into the haze, so the base carries on. The
  walls carry the same screens, maps, clocks and posters as overhead.
  W/S walk, ←/→ turn, A/D sidestep, Q/Z look up and down; on a touch screen
  the stick walks and turns, and you can swipe the right half to look around,
  up and down too. Overhead there are ceiling tiles, steel beams, strip
  lights, pipes and an air duct.
  Explosions, shocks, flying paperwork and the comic-book words happen in 3D
  too, your trap markers and tripwires show, and when you're stunned the
  view reels (or drops to the floor when you're taken out). On slower phones,
  turn off **Detailed first person** in SETTINGS for a lighter version (no
  rooms next door, still screens); if first person runs slowly for a few
  seconds, the game switches to it by itself and tells you.
- **Readable for everyone:** each agent has a shape as well as a colour
  (● Crimson, ▲ Cobalt, ■ Amber, ◆ Jade) on their name tag and clock, and new
  players get a few one-off tips on the ticker tape.

## Playing it

### Download

No GitHub account needed. Every update to `main` publishes a new
[**release**](https://github.com/petherin/doublecross/releases/latest), and these links
always fetch the newest one:

| | |
|---|---|
| **Android** phones and tablets | [⬇ DoubleCross.apk](https://github.com/petherin/doublecross/releases/latest/download/DoubleCross.apk) |
| **Mac** with Apple Silicon (M1 and later) | [⬇ DoubleCross-macOS-AppleSilicon.zip](https://github.com/petherin/doublecross/releases/latest/download/DoubleCross-macOS-AppleSilicon.zip) |
| **Mac** with an Intel processor | [⬇ DoubleCross-macOS-Intel.zip](https://github.com/petherin/doublecross/releases/latest/download/DoubleCross-macOS-Intel.zip) |

Not sure which Mac you have? **Apple menu → About This Mac** shows *Chip: Apple M…* or *Processor: Intel…*.

Older builds are on the [releases page](https://github.com/petherin/doublecross/releases).
Each build has a higher version number, so a new APK installs over the old one.
**Everyone in a match needs the same version**: the host turns away a device
running a different one and says which version each side has.

### On Android phones and tablets

1. On each device, download [**DoubleCross.apk**](https://github.com/petherin/doublecross/releases/latest/download/DoubleCross.apk)
   and open it. Android will ask you to allow installs from that source the first time.
2. Put all the devices on **the same Wi-Fi network**.
3. On one, type a codename and choose **HOST A MISSION**.
4. On the others, tap **JOIN AGENT …** under **INTERCEPTED TRANSMISSIONS** when
   the host appears. **FIND HOST** looks again straight away; **TYPE IP** is the
   fallback (the host's screen shows its address).
5. Once everyone's in the lobby (two to four agents), the host presses
   **START MISSION**. With four it starts by itself. With fewer, the host can
   tick **Fill the empty seats with bots** to make up the numbers: the bots
   play at the difficulty picked under **TAKE ON THE BOTS**, and run on the
   host's device.

Phones and tablets can play together: wide screens get a wider view, and on
small screens the controls and text are scaled up.

> Some routers (guest networks, many office and hotel Wi-Fi networks) stop
> devices seeing each other. If the host doesn't show up, try **TYPE IP**, or
> a phone hotspot.

### As a Mac app

1. Download the zip for your Mac from the [Download](#download) table
   and unzip it to get **Double Cross.app**.
2. Drag it into **Applications**.
3. The app isn't signed with an Apple developer certificate, so the first time you open it macOS will
   refuse. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the
   Double Cross message. Or run this once in Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Double Cross.app"
   ```
4. When macOS asks whether Double Cross may find devices on your local network, click **Allow**.
   It needs that to find and join games.

A Mac can play against phones and tablets on the same Wi-Fi.

### From source in Godot (Mac, Windows or Linux)

1. Install **Godot 4.3** from [godotengine.org](https://godotengine.org/download/archive/4.3-stable/)
   (the standard version, not .NET).
2. In Godot, choose **Import** and pick this folder's `project.godot`.
3. **Solo:** press ▶ and choose **TAKE ON THE BOTS** or **SOLO TRAINING**.
4. **Several players on one computer:** go to **Debug → Customize Run Instances…**,
   tick **Enable Multiple Instances**, choose 2–4 and press ▶. In one window
   choose **HOST A MISSION**. In each of the others choose **TYPE IP**, enter
   `127.0.0.1` and press **JOIN**. Then press **START MISSION** in the host's window.

## Controls

| Action | Touch | Keyboard | Gamepad |
|---|---|---|---|
| Move | Drag on the left half of the screen | WASD / arrow keys | Left stick / D-pad |
| Search furniture (it glows) | **SEARCH** | <kbd>E</kbd> or <kbd>Space</kbd> | A |
| Set a trap | **TRAP**, then pick one | <kbd>1</kbd> bomb · <kbd>2</kbd> spring · <kbd>3</kbd> tripwire · <kbd>4</kbd> shock | LB bomb · RB spring · Back tripwire · right-stick click shock |
| Cosh | **ATTACK** | <kbd>F</kbd> | X |
| Fire a dart | **FIRE** | <kbd>G</kbd> | Y |
| Crawl through a vent | **CRAWL** (appears at a vent) | <kbd>V</kbd> | B |
| Switch overhead / first person | **1ST PERSON** / **OVERHEAD** (top bar) | <kbd>Tab</kbd> | Start |
| First person: turn / sidestep | Stick left/right, or swipe the right half | <kbd>←</kbd>/<kbd>→</kbd> turn · <kbd>A</kbd>/<kbd>D</kbd> sidestep | Right stick turns · left stick sidesteps |
| First person: look up / down | Swipe up or down on the right half | <kbd>Q</kbd>/<kbd>Z</kbd> or <kbd>Page Up</kbd>/<kbd>Page Down</kbd> | Right stick up/down |
| Pause (one-player games) | **PAUSE** (top bar) | <kbd>Esc</kbd> or <kbd>P</kbd> | |
| Skip the briefing | Tap | Any key | |
| Leave the match | **LEAVE** / Android back | Close the window | |

The keys are Godot input actions (**Project → Project Settings → Input Map**), so
they're easy to change.

**SETTINGS** on the title screen has music and effects volume, vibration,
first-person detail, **reduced motion** (no screen shake, slow motion, film
grain, flicker or iris wipes, and softer flashes), the clock length, and a
button to see the new-player tips again. **HOW TO PLAY** is the field manual.

## Ideas for what's next

Suggestions, roughly in the order they'd pay off. Nothing here is promised.

### Top five

1. **Survive a host dropping out.** Today the match ends for everyone if the
   host's device leaves or sleeps. Hand refereeing to another device, or at
   least let players rejoin a match after a brief disconnect.
2. **Match options for the host:** how many traps each, fewer briefcases,
   hidden exit, faster clocks.
3. **Locked rooms:** some doors need the KEYCARD, making it worth grabbing early.
4. **More gadgets and traps:** a smoke bomb that hides you from everyone in the
   room, a glue trap that slows you down, a bug you plant to see into another
   room, and decoy intel that looks real until you reach the exit.
5. **Team mode:** two against two, sharing a briefcase and escaping together.

### Gameplay

- **Bots that learn from you:** a bot that notices which rooms you favour and
  lays traps there.

### Look and feel

- **Doors and drawers that open:** animated doorways, and furniture doors that
  swing open when searched (a second Blender render of each piece).
- **Taunts:** a button to make your agent gloat, wave or shake a fist.
- **Stats and achievements** kept on the device: wins, fastest escape, traps
  sprung, rivals taken out.
- **A guided first mission** with the bot, instead of tips alone.

### Reaching more players

- **Play over the internet**, not just the same Wi-Fi, through a small relay
  server or a join code.
- **Store releases:** Google Play (needs a release signing key and a developer
  account), and a signed, notarised Mac app so macOS stops warning about it
  (needs an Apple developer account).
- **More platforms:** Godot can also build for Windows, Linux, iPhone and iPad.
- **Remappable controls** in SETTINGS, full gamepad navigation of the menus,
  and **translations** of the on-screen text.

### Under the hood

- **Profiling on low-end Android** phones for frame rate and battery use.
- **Screenshot tests** in CI, comparing key screens against approved images so
  visual changes are caught in review.

## How it's built

- **[Godot 4.3](https://godotengine.org/)** using GDScript and the *Compatibility*
  renderer, so it runs on older devices too. Everything except the main scene is
  built in code.
- **Networking:** the host runs the match over ENet on UDP port `47810` and
  referees every search, trap, hit and escape, so all devices agree. Hosts
  announce themselves on UDP port `47811`, and joiners also probe every address
  on their subnet on port `47812` (many Android phones ignore broadcasts).
- **Isometric projection:** the game logic happens on a flat floor plan and the
  renderer projects it to isometric. Controls are screen-relative.
- **Reproducible matches:** the base, the bots' decisions and the referee's dice
  all come from the match's seed, so a given match replays exactly (handy for tests).

```
scripts/
  main.gd               menu ⇄ lobby ⇄ match flow
  core/                 autoloads and shared data
    net.gd                hosting, joining, discovery, version check ("Net")
    settings.gd           saved player settings ("Settings")
    sound.gd              effects, music layers, room tone, audio buses ("Sound")
    world.gd              the seeded base: rooms, furniture, items, vents, exit
  game/                 one match
    game.gd               setup, input, shared match state, network endpoints
    referee.gd            the rules: searches, traps, doors, hits, clocks
    event_presenter.gd    shows each event on this device: animation, text, sound
    agent.gd              one spy: movement, sync, sprite drawing
    bot.gd                computer opponents (room routing + AStarGrid2D)
    tips.gd               one-off tips for new players
  render/               drawing the room
    room_view.gd          isometric renderer and depth sorting
    room_effects.gd       explosions, springs, sparks, hits, dust
    wall_decor.gd         screens, maps, clocks and posters on the walls
    room_lights.gd        real 2D lights; light_layer.gd adds glows and shafts
    art.gd, grain.gd      shared textures, film grain
  ui/                   menus and HUD
    menu.gd               the dossier title screen and lobby
    hud/                  in-match HUD, briefing, debrief, duct view, iris wipe
    style.gd, icons.gd    paper, stamps, fonts, drawn icons
    joystick.gd, action_button.gd, ui.gd   touch controls, screen sizing
tests/
  smoke.gd              every script compiles, inputs mapped, 300 seeds of base rules
  bot_match.gd          a full match against 1–3 hard bots must end in an escape
                        (--spectate: you're put out, and the camera must follow them)
  nacho_poo.gd          his poo: squats, leaves a turd, stops if attacked, won't
                        start mid-fight or unowned; treading in it takes you out,
                        kit and all, and it's gone; easy bots blunder into them
  nacho.gd              Nacho: found in his kennel, sniffs out an item and a trap,
                        follows to the next room, bites an attacker until they stop,
                        taken out by three hits, goes home and is anyone's to find
  net_match.gd          a real host and joiner (two processes) with bots in the
                        empty seats: the host runs them, the joiner sees them move
tools/
  make_audio.py         synthesises every sound, voice, ambience and music loop
  blender/              models and renders agents, furniture and room surfaces
  thin_macos_template.py  splits Godot's universal Mac template per processor
```

### Tests and CI

Every push and pull request runs `gdlint` over the scripts, the smoke test, and
bot matches with two and four agents, and one where you're out and the camera
must follow the bots, and a network match between two processes (GitHub Actions, `.github/workflows/android.yml`).
Only after a change reaches `main` are the APK and both Mac apps built and
published as a release. To run the tests yourself:

```bash
godot --headless -s res://tests/smoke.gd
godot --headless --fixed-fps 60 -s res://tests/bot_match.gd -- --bots=3 --seed=7
godot --headless -s res://tests/net_match.gd -- --role=host &
godot --headless -s res://tests/net_match.gd -- --role=join
```

### Re-rendering the art in Blender

Every piece of 3D art is built, posed and rendered by script, using Blender 4.2
as a Python module:

```bash
python3.11 -m venv .blendenv
.blendenv/bin/pip install bpy==4.2.0 pillow
.blendenv/bin/python tools/blender/build_agents.py                 # all four agents
.blendenv/bin/python tools/blender/build_agents.py --only amber    # just one
.blendenv/bin/python tools/blender/build_crawl.py                  # duct-crawl sheets
.blendenv/bin/python tools/blender/build_dog.py                    # Nacho (sprites and duct sheet)
.blendenv/bin/python tools/blender/build_furniture.py --only safe  # furniture
.blendenv/bin/python tools/blender/build_rooms.py                  # floor and wall surfaces
```

`tools/blender/agent_model.py` sculpts each spy procedurally: a body skinned
around a jointed skeleton (so knees and elbows really bend), a head with a big
spy nose, brows, smirk and shades, a snap-brim fedora, a belted trench coat,
gloves and polished shoes. `build_agents.py` poses it and renders 8 directions
of every animation (idle, walk, run, search, crouching to set a trap, cosh
swing, a two-way flinch, a dizzy sway after a trap, falling and lying flat,
victory) with ink outlines from an orthographic camera at the game's isometric
angle, plus a normal map for every frame, then `pack_sprites.py` trims and packs
the frames into compact atlases. Add `--preview` for small, quick renders.

<p align="center"><img src="docs/agent-turnaround.png" alt="The crimson agent from eight directions, plus walk, search, swing, hurt and knocked-down poses" width="90%"></p>

`build_dog.py` does the same for Nacho (`dog_model.py`): skin-modifier body,
legs and tail over a posable dog skeleton, a sculpted head with beard, long
ears, brown nose and a jaw that opens to bark, and Blender's own rendered hair
(curled, clumped and roughened) for his wiry ginger coat. He's rendered with
the agents' camera in seven animations (idle, trot, sniff, sit, bark, growl,
bite), plus a side-on trot for the air-duct cut-away.

`build_furniture.py` models every piece (desk with monitor and mug, control
console, filing cabinet, lockers, TOP SECRET crate, bookcase, safe, potted plant,
gadget rack, sofa, and Nacho's kennel) in game units and renders it for each wall it can stand
against, at exactly the game's scale so the sprites line up with the collision
boxes. `build_rooms.py` renders the steel tread-plate floor and riveted wall
panels as tiling textures with normal maps.

### Regenerating the audio

```bash
python3 tools/make_audio.py              # everything
python3 tools/make_audio.py zap boom     # just these effects
python3 tools/make_audio.py music        # the three music loops
python3 tools/make_audio.py ambience     # the room-tone loops
```

It needs `numpy`, and `ffmpeg` for the Ogg loops.

### Building the apps yourself

Install the Android SDK and OpenJDK 17, set their paths in **Editor → Editor
Settings → Export → Android**, then use **Project → Export…**. The Mac presets
need the single-processor templates that CI makes with `tools/thin_macos_template.py`.

`android/debug.keystore` is a throwaway **debug-only** signing key (password
`android`). It's committed so every build is signed the same way and installs
over the previous one. Never use it for a store release.

## Fonts

- **Black Ops One** by James Grieshaber (SIL Open Font License 1.1)
- **Special Elite** by Astigmatic (Apache License 2.0)
- **Courier Prime** by Quote-Unquote Apps (SIL Open Font License 1.1)

The fonts and their licence files are in `assets/fonts/`. They're covered by
their own licences, not by this project's.

## Acknowledgements

Double Cross is inspired by **Spy vs. Spy** (1984), the computer game by
First Star Software based on Antonio Prohías's *Spy vs. Spy* comic strip in
*MAD* Magazine, and by the many happy hours spent playing it split-screen on
8-bit machines.

Double Cross is an independent, original fan project. It does not use any
artwork, characters, names, music or code from Spy vs. Spy, and is not
affiliated with, endorsed by or connected to First Star Software, *MAD*
Magazine, DC Comics or Warner Bros. *Spy vs. Spy* is a trademark of its
respective owners.

## Licence

Copyright © 2026 petherin. **All rights reserved.** The code is public so you can
look at it, but you may not copy, reuse, modify or distribute any of it without
written permission. See [LICENSE](LICENSE).
