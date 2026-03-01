# Portal-style 2D Platformer Game (Godot Exercise/Project)

A 2D platformer built in **Godot 4.6** featuring a full **Portal gun** mechanic — place linked blue and orange portals on surfaces and fling yourself through them with preserved momentum. *"Speedy thing goes in, speedy thing comes out."*

---

## Gameplay

- **Move:** `A` / `D`
- **Jump:** `W` / `Space`
- **Sprint:** `Shift` (ground only)
- **Blue Portal:** `Left Click`
- **Orange Portal:** `Right Click`
- **Reset Portals:** `R`

The player can place two linked portals on any valid wall/floor/ceiling surface. Entering one teleports you out the other, preserving your speed and redirecting it along the exit portal's normal. Air friction is intentionally reduced after a portal fling so momentum carries properly.

---

## Project Structure

```
├── main.gd / Main.tscn            # Root scene
├── CharacterScript.gd              # Player controller (extends PortalEntity)
├── CharacterModel.tscn             # Player scene with sprites & animations
├── project.godot                   # Project configuration & input map
│
├── portal/                         # Portal system
│   ├── portal_entity.gd            # Base class for anything that travels through portals
│   ├── portal_gun.gd               # Fires raycasts to place portals on surfaces
│   ├── portal.gd                   # Portal teleportation logic & momentum transfer
│   ├── PortalBlue.tscn             # Blue portal scene
│   ├── PortalOrange.tscn           # Orange portal scene
│   └── PortalGun.tscn              # Portal gun scene
│
├── hazards/                        # Enemies & environmental hazards
│   ├── saw.gd / Saw.tscn           # Spinning saw (moving or stationary)
│   ├── laser.gd / Laser.tscn       # Continuous-damage laser beam
│   ├── spike.gd / Spike.tscn       # Timed spike trap (cycles hidden → active)
│   ├── spike_group.gd              # Groups spikes for sync or staggered activation
│   ├── turret.gd / Turret.tscn     # Auto-firing turret (shoots portal-compatible bullets)
│   ├── turret_bullet.gd            # Turret projectile (extends PortalEntity)
│   ├── turret_bullet_hit.gd        # Turret bullet impact effect
│   ├── night_borne_enemy.gd        # Melee AI enemy (patrol → chase → slash)
│   ├── striker_enemy.gd            # Melee + ranged AI enemy with dash attack
│   ├── striker_bullet.gd           # Striker ranged projectile (extends PortalEntity)
│   └── striker_bullet_hit.gd       # Striker bullet impact effect
│
├── levels/
│   └── Level1.tscn                 # First level
│
├── debugs/
│   └── debug_hud.gd               # On-screen debug overlay (velocity, portals, aim line)
│
├── asssets/                        # Sprites & tilesets
│   ├── character/                  # Player sprite sheets
│   ├── enemies/                    # Enemy sprite sheets
│   ├── guns/                       # Portal gun art
│   ├── portals/                    # Portal art
│   └── tilesets/                   # Tileset assets
│
└── addons/                         # Editor plugins
    ├── AsepriteWizard/             # Aseprite import pipeline
    ├── FastSpriteAnimation/        # Quick sprite animation editor
    ├── GitGodot/                   # Git integration for Godot
    ├── github_copilot/             # GitHub Copilot integration
    ├── godot_doctor/               # Project diagnostics
    └── nklbdev.aseprite_importers/ # Aseprite format loaders
```

---

## Physics Layers

| Layer | Name    | Purpose                                          |
|-------|---------|--------------------------------------------------|
| 1     | Player  | Player character body                            |
| 2     | Walls   | Static environment collision (portal-placeable)  |
| 3     | Portals | Portal area detection                            |
| 4     | Hazards | Damage-dealing areas (saws, spikes, lasers, etc.)|
| 5     | Enemies | Enemy bodies                                     |

---

## Core Systems

### Portal Mechanic

- **PortalEntity** — base class for any body that can travel through portals. Implements custom `move_and_collide` loop that detects portal surfaces and defers to the portal's teleport logic. Tracks a `launched_by_portal` flag to reduce air friction for 1.5 seconds after a fling.
- **Portal Gun** — raycasts from the player to the mouse cursor. On click, places a blue or orange portal on the hit surface (Walls layer). Both portals are automatically linked when both exist.
- **Portal** — when a `PortalEntity` overlaps, it teleports it to the linked portal. Exit velocity equals entry speed directed along the exit portal's outward normal. A brief cooldown prevents instant re-teleportation.

### Player Controller

Extends `PortalEntity` with full platformer movement:
- Ground acceleration, air acceleration, and a weaker "fling" air acceleration for portal launches
- Coyote time (0.12s) and jump buffering (0.1s) for responsive input
- Sprint multiplier on ground
- Health system with damage, knockback, death, and respawn
- AnimationTree-driven state machine (Idle, Walk, Sprint, Jump, Land, Knockback, Die)
- Invincibility frames with sprite blinking

### Enemies

- **NightBorne** — melee-only patrol AI with idle/roam/chase/attack states. Uses line-of-sight raycasts for player detection, edge and wall raycasts to stay on platforms, and a deaggro leash area. Only damaged by turret bullets.
- **Striker** — melee + ranged patrol AI with an additional dash state. The Strike animation has melee hitbox frames and a bullet-spawn frame. Only damaged by turret bullets.

### Hazards

- **Saw** — moves between two points (or stays stationary). Damages on contact with knockback.
- **Laser** — continuous damage ticks while the player overlaps.
- **Spike / SpikeGroup** — timed spike traps that cycle between hidden and active. Groups can activate in sync or staggered waves.
- **Turret** — auto-fires bullets on a timed animation loop. Turret bullets extend `PortalEntity` and can travel through portals, allowing the player to redirect them into enemies.

### Bullets Through Portals

Both turret and striker bullets extend `PortalEntity`, so they can be teleported through portals just like the player. After exiting a portal, their velocity is redirected along the exit normal — this allows the player to strategically place portals to redirect turret fire into enemies.

---

## TODO

- [ ] Design levels
- [ ] UI/UX & Audio

---

## Requirements

- **Godot 4.6** (Forward+ renderer)
- **Aseprite** (optional, for sprite editing — path configured in project settings)

---

## Running

1. Open the project in Godot 4.6
2. Press **F5** or click **Play** to run the main scene
