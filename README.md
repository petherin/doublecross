<p align="center">
  <img src="docs/logo.svg" alt="Double Cross: two spies shaking hands, one hiding a bomb and the other a mallet" width="720">
</p>

<p align="center">
  <b>Two rival agents. One secret base. Only one gets out.</b><br>
  A two-player, one-tablet-each game of sneaking, booby traps and very bad manners.
</p>

<p align="center">
  <a href="../../actions/workflows/android.yml"><img src="../../actions/workflows/android.yml/badge.svg" alt="Android build"></a>
  <img src="https://img.shields.io/badge/engine-Godot%204.3-478cbf" alt="Godot 4.3">
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20macOS-3ddc84" alt="Android and macOS">
  <img src="https://img.shields.io/badge/licence-all%20rights%20reserved-red" alt="All rights reserved">
</p>

---

## The idea

Agent **Crimson** and Agent **Cobalt** have both broken into the same secret
base to steal the same intel. Each player has their own Android tablet on the
same Wi-Fi network, so neither can see what the other is up to.

- **Explore** a grid of isometric rooms: the Reactor Core, the Armoury, the Server Vault…
- **Search** desks, lockers, safes and crates for the mission items and the escape key.
- **Booby-trap** the furniture and doorways for your rival to find the hard way.
- **Carry the right gadget** to disarm a trap before it disarms you.
- **Fight** when you meet in the same room: melee *or* a dart pistol.
- **Escape** with everything before your own clock runs out. Dying costs you time.

It's a love letter to the split-screen trap-and-sneak games of the 8-bit era,
rebuilt with an original setting, original characters and a lot more polish.

<p align="center">
  <img src="docs/screenshot-room.png" alt="Isometric secret-base room with an agent in a red trench coat" width="49%">
  <img src="docs/screenshot-menu.png" alt="Title screen with host, join and practice options" width="49%">
</p>

## Status and roadmap

| | Milestone | Status |
|---|---|---|
| 1 | Two players on separate tablets moving through a shared, synced base over the local network | ✅ Done |
| 2 | Searching furniture, mission items, briefcase, escape door and the win condition | ✅ Done |
| 3 | Traps and counter-gadgets (tripwire ⇄ wire cutters, paint bomb ⇄ extinguisher…) | ⏳ Next |
| 4 | Combat (melee and dart pistol), per-player countdown and respawn penalty | 🔜 |
| 5 | Sound, music, menus, settings | 🔜 |
| 6 | Richer, more detailed graphics | 🔜 |
| ★ | One-player mode against a bot | ✅ Done |
| ★ | Phones as well as tablets, and a Mac app | ✅ Done |

What works today:

- Host a game on one tablet. The other tablet finds it automatically, or you can type the host's IP address.
- A seeded 3×3 secret base. Both tablets build the identical map from one shared number.
- Isometric rooms with depth-sorted furniture, doors and a mini-map.
- Touch joystick (left half of the screen), plus WASD or arrow keys on a computer.
- Works on phones as well as tablets: wide screens get a wider view, and on small screens the controls and text are scaled up. You can mix a phone and a tablet in one match.
- You only see your rival when you're in the same room.
- Four pieces of intel (PASSPORT, CASH, MICROFILM, KEYCARD) and a BRIEFCASE are hidden in the furniture. There's only one of each, so it's a race.
- Without the briefcase you can carry just one item. Search with full hands and you swap: your item stays behind in that furniture for your rival to find.
- The EXIT (green on the mini-map) only opens for an agent carrying all four pieces of intel. First one out wins, then the host can call a rematch on a freshly shuffled base.
- The host's tablet referees every search and escape, so both tablets always agree on who has what.
- **PLAY VS BOT**: a one-player mode against a computer agent that plays by the same rules. It has to search to find things, can only carry one item until it finds the briefcase, and remembers what it has searched.

## Playing it

### On two Android tablets (or phones)

1. Open the [**Actions** tab](../../actions/workflows/android.yml), click the latest green run,
   and download the **double-cross-apk** artifact (it's a zip with the APK inside).
2. Copy `double-cross.apk` to each tablet and open it. Android will ask you to allow
   installs from that source the first time.
3. Put both tablets on **the same Wi-Fi network**.
4. On one tablet tap **HOST GAME**. On the other, tap the game that appears under
   **GAMES ON YOUR NETWORK**, or type the IP address shown on the host's screen.

> Some routers (guest networks, many office and hotel Wi-Fi networks) block
> devices from seeing each other. If the game doesn't show up, use the IP
> address instead, or try a phone hotspot.

### As a Mac app

1. Open the [**Actions** tab](../../actions/workflows/android.yml), click the latest green run and
   download **double-cross-mac**. Unzip it, then unzip `DoubleCross-macOS.zip` inside to get **Double Cross.app**.
   It runs natively on Apple Silicon and Intel Macs.
2. Drag it into **Applications**.
3. The app isn't signed with an Apple developer certificate, so the first time you open it macOS will
   refuse. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the
   Double Cross message. Or run this once in Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Double Cross.app"
   ```
4. When macOS asks whether Double Cross may find devices on your local network, click **Allow**.
   It needs that to find and join games.

A Mac can play against tablets and phones on the same Wi-Fi.

### From source in Godot (Mac, Windows or Linux)

You don't need a tablet to try it. The game runs on a computer and can play
against itself.

1. Install **Godot 4.3** from [godotengine.org](https://godotengine.org/download/archive/4.3-stable/)
   (the standard version, not .NET). It runs natively on Apple Silicon.
2. In Godot, choose **Import** and pick this folder's `project.godot`.
3. **Solo:** press ▶ (or <kbd>⌘</kbd>+<kbd>B</kbd>) and choose **PLAY VS BOT** (or **PRACTICE SOLO** to explore alone). Move with WASD/arrows or drag with the mouse.
4. **Two players on one Mac:** go to **Debug → Customize Run Instances…**, tick
   **Enable Multiple Instances**, set it to **2** and press ▶. In one window click
   **HOST GAME**. In the other, type `127.0.0.1` and click **JOIN**.

## Controls

| Action | Tablet | Keyboard |
|---|---|---|
| Move | Drag anywhere on the left half of the screen | WASD / arrow keys |
| Search nearby furniture (it glows) | **SEARCH** button (bottom right) | <kbd>E</kbd> or <kbd>Space</kbd> |
| Escape | Walk into the EXIT with all four items | |
| Leave match | **LEAVE** button / Android back | Close window |

Trap and attack buttons arrive with milestones 3 and 4.

## How it's built

- **[Godot 4.3](https://godotengine.org/)** using GDScript and the *Compatibility* renderer, so it runs on older tablets too.
- **Networking:** host-and-join over ENet on UDP port `47810`. LAN discovery broadcasts on UDP port `47811`.
- **No art files yet:** rooms, furniture and agents are drawn in code, so the art can be replaced piece by piece later.
- **Isometric projection:** the game logic happens on a flat floor plan, and the renderer projects it to isometric. The controls are screen-relative.

```
scripts/
  main.gd       menu ⇄ match flow, starts the match on both tablets
  net.gd        hosting, joining, LAN discovery (autoload "Net")
  world.gd      the seeded base layout + isometric projection maths
  game.gd       one match: spawns agents, reads input, rules (search/swap/escape)
  agent.gd      movement, collisions, doors, network sync, agent artwork
  room_view.gd  isometric room renderer (walls, floor, furniture, depth sorting)
  hud.gd        top bar, mini-map, joystick, room-change fade
  joystick.gd   floating touch joystick
  menu.gd       title screen
  bot.gd        computer opponent (room-to-room routing + AStarGrid2D within rooms)
  ui.gd         phone/tablet screen-size helpers
  action_button.gd  multi-touch round button (SEARCH, and later TRAP/ATTACK)
  icons.gd      drawn item icons
.github/workflows/android.yml   builds the Android APK and the Mac app on every push
```

### Building the APK yourself

Every push to `main` builds a debug APK and a Mac app automatically with GitHub Actions. To
build locally instead, install the Android SDK and OpenJDK 17, set their paths in
**Editor → Editor Settings → Export → Android**, then use **Project → Export… → Android**.

`android/debug.keystore` is a throwaway **debug-only** signing key (password
`android`). It's committed so that every build is signed the same way and
installs over the previous one. Never use it for a store release.

## Licence

Copyright © 2026 petherin. **All rights reserved.** The code is public so you can
look at it, but you may not copy, reuse, modify or distribute any of it without
written permission. See [LICENSE](LICENSE).
