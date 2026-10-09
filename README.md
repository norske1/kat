# KAT-style Medical System for Roblox

An advanced, server-authoritative medical system for Roblox, inspired by
[KAT - Advanced Medical](https://steamcommunity.com/workshop/filedetails/?id=2020940806) for ArmA 3.
It is written from scratch in Luau. The mechanics follow the KAT/ACE design, but no SQF code was ported.

## Features

| Area | What is simulated |
|---|---|
| Wounds | 6 body parts, 8 wound types × 3 sizes, per-wound bleeding & pain, weighted by damage type (bullet, explosive, blunt, fall, stab, melee) |
| Circulation | Blood volume (6 L) with hemorrhage classes, HR/BP from cardiac output & peripheral resistance, coagulation factors, clotting agents, internal bleeding |
| Bandages | Field dressing, packing, elastic, hemostatic gauze, each with its own effectiveness and reopening chance. Stitching and NPWT close wounds permanently |
| Tourniquets | Stop limb bleeding and IV flow on that limb. They become painful after a while |
| Fractures | Simple, compound, comminuted. Splints, closed reduction, surgical pathway (incision, retraction, irrigation, clamping, plating, stitching) |
| Airway | Obstruction (tongue) and occlusion (vomit/blood) while unconscious. Head tilt (held), recovery position, Guedel, airway tube, suction, manual sweep |
| Breathing | PaO2/SpO2 (oxygen dissociation curve), RR, EtCO2, pneumothorax stages 1-4, tension PTX, hemothorax. Chest seal, needle decompression, chest drain, BVM, oxygen, medication-induced respiratory depression |
| Cardiac | Arrest on blood loss, hypoxia, brady/tachycardia, tension PTX, tamponade, adverse medication reactions, transfusion reaction. VF/VT/PEA/asystole, arrest timer, CPR (slows the timer), AED and AED-X with manual shocks, reversible causes block ROSC, pericardiocentesis |
| Pharmacy | 16g IV / FAST IO, saline/plasma/blood bags (all ABO/Rh types, compatibility, hemolytic reaction), and 18 medications with onset/peak/decay curves, dose stacking and adverse reactions. Reversal Spray and Sedative Reversal antidotes. All medications use fictional game names |
| Monitoring | Manual pulse/BP/response checks, pulse oximeter, AED-X monitor with live ECG trace, ultrasound, blood type test |
| Animations & sound | Every treatment has a procedural animation (kneel, bandage wrap, tourniquet, injection, CPR compressions, BVM, surgery, carry/drag holds) and sounds (bandage, ratchet, syringe, suction, AED charge/shock, body falls, pain) |
| Guns | M4A1 rifle, G17 pistol, M870 shotgun built from parts, server-validated hitscan, hits become medical wounds on the exact limb, magazines/reloads, fire modes, recoil, spread, muzzle flash, tracers, impacts, weapon/ammo racks |
| Gameplay | Unconsciousness with ragdoll, carry and drag, medic levels (0 non-medic, 1 medic, 2 doctor) gating treatments, loadouts and supply crates, triage tags, treatment log, screen effects (pain vignette, blur, desaturation, blackout) |

## Project layout

```
src/shared/Medical/        ReplicatedStorage.Medical (shared, pure Luau)
  Config.luau              all tuning values
  Wounds / Medications / Items / BloodTypes / BodyParts
  Sim/                     pure simulation (no Roblox instances)
    Patient, Simulation, Circulation, Breathing, Cardiac, Pharmacy, Damage
    Actions.luau           every treatment: requirements, duration, effect
    Snapshot.luau          serialisable view for the UI
src/server/                ServerScriptService.MedicalServer
  Main.server.luau         bootstrap, remotes, debug commands, supply crates, training casualties
  MedicalService.luau      patient registry, damage interception, tick loop, character state
  ActionRunner.luau        server-side validation + timed treatments
  Inventory / Carry / Ragdoll / Dummies
  MedicalAPI.luau          public API for weapon/game code
  Weapons/WeaponService    gun tools, ammo, server hit validation, racks
src/shared/Medical/Animations.luau  procedural poses for treatments and guns
src/shared/Medical/ActionFx.luau    which animation + sounds each treatment uses
src/shared/Medical/Sounds.luau      every sound id in one place
src/shared/Medical/Weapons/ ReplicatedStorage.Medical.Weapons: Config (weapon stats) and Models (part-built guns)
src/client/                StarterPlayerScripts.MedicalClient (menu, HUD, screen effects, Animator, Weapons/)
src/character/             StarterCharacterScripts (disables default regen, client ragdoll state)
tests/                     Lune test harness + scenario tests
```

## Getting started

**Open the prebuilt place:** open `build/KATMedical.rbxl` in Roblox Studio and press Play.

**Or build it yourself / sync live with [Rojo](https://rojo.space) 7.4+:**

```bash
rojo build place.project.json -o KATMedical.rbxl   # standalone test place
rojo serve default.project.json                    # sync into an existing place
```

In Studio, five training casualties spawn in front of the spawn point (GSW leg, unconscious airway,
VF arrest, blast, over-medicated). There's also a debug panel for hurting yourself, healing, changing medical
level and spawning casualties. Everyone is level 2 (doctor) in Studio. See `Config.StudioMedicalLevel`.

### Controls

| Key | Action |
|---|---|
| F (prompt) | Open the medical menu on a nearby patient |
| H | Self-treatment menu |
| X | Cancel the current treatment (also stops repeating CPR) |
| G | Drop a carried / dragged patient |
| I | Toggle the medical bag |
| F2 | Toggle the debug panel (Studio / admins only, hidden by default) |

**Guns** (equip with the hotbar, 1/2/3):

| Input | Action |
|---|---|
| Left mouse | Fire (hold for automatic) |
| Right mouse | Aim down sights (zooms in, lower mouse sensitivity) |
| R | Reload |
| V | Switch fire mode (M4A1: auto / semi) |
| Left Alt (hold) | Free the mouse cursor |
| Left Shift (hold) | Sprint (gun lowered, can't shoot) |
| C | Crouch / stand (lowers your hitbox) |
| Q / E | Lean left / right (press again to stand straight) |

Sprint, crouch and lean also work without a gun.

The menu has a body diagram (colour = bleeding severity; TQ/FX/SP/IV/IO/Ox badges), action
categories, the injuries on the selected part, a vitals monitor, airway and medication status, and the log.
Vitals are only visible once measured, or live with a pulse oximeter / AED-X attached, as in KAT.

## Integrating with weapons

All Humanoid health loss is intercepted and converted into wounds (`Config.InterceptHumanoidDamage`).
Humanoids are kept at `Config.HealthBuffer` health, and death is decided by the medical simulation.
To get accurate hit locations and damage types:

```lua
local MedicalAPI = require(game.ServerScriptService.MedicalServer.MedicalAPI)
MedicalAPI.damage(character, hitPart.Name, 35, "Bullet")   -- R15/R6 part names are mapped automatically
MedicalAPI.damage(character, nil, 80, "Explosive")         -- spread over several body parts

-- or, without requiring the module, before Humanoid:TakeDamage():
humanoid:SetAttribute("MedicalHitPart", hitPart.Name)
humanoid:SetAttribute("MedicalDamageType", "Bullet")
humanoid:TakeDamage(35)
```

Other API: `isAlive`, `isConscious`, `getState`, `fullHeal`, `setMedicalLevel`, `giveItem`, `restock`, `registerNPC`.

Medical level: set the `MedicalLevel` attribute (0-2) on a Player, or map team names in `Config.TeamMedicalLevels`.
Supply crates: tag any part with `MedicalSupply` to give it a restock prompt.

## Guns, animations and sounds

**Weapon locker.** Guns come from a weapon locker: point at a gun in it (it lights up) and left-click (or tap) to
equip it; click the ammo box to resupply. If no part is tagged `WeaponLocker`, one is built next to your
SpawnLocation (`WeaponConfig.AutoSpawnLocker`). To place your own, insert a Part, add the tag `WeaponLocker`, and the
locker is built standing on it, opening towards the part's front face. Shelf contents are
`WeaponConfig.LockerItems`. Set `WeaponConfig.GiveOnSpawn = true` to also spawn with `WeaponConfig.Loadout`.
Racks still work too: tag a part `WeaponRack` and set a `WeaponId` attribute (no attribute = ammo crate).

**First person (ACS style).** While a gun is out the camera locks to first person and you see gloved arms holding
the gun (a local copy of the equipped model, `client/Weapons/Viewmodel.luau`). There is no hip crosshair: bullets
leave the barrel, so aim with the sights (right mouse). The gun sways behind mouse movement, bobs while walking,
drops into a sprint pose, kicks back on recoil and plays equip / reload / shell-loading / pump motions; injuries and
pain make it shake. Other players see the third-person poses (including crouch, lean and sprint). Settings are in
`Weapons/Config.luau`: `FirstPerson` (false = old over-the-shoulder camera), `ShowHipCrosshair`, `AimSensitivity`,
`Viewmodel` (hip position, sight distance and zoom per hold type), `SleeveColor` / `GloveColor`, and the movement
speeds. Sights line up through each gun's `Aim` point (`mesh.aim` for imported models); `Support` (`mesh.support`)
is where the left hand holds it.

**Ballistics.** Bullets are not instant: they fly at the weapon's `velocity` (studs/s) and drop under
`BulletGravity`, simulated on the server for damage and on every client for tracers and impacts
(`Weapons/Ballistics.luau`). Bullets passing close to you crack past, and other players' gunshots are heard after
distance / `SpeedOfSound`, so far-away shots arrive late.

The client only sends the shot origin and directions. The server checks the weapon, ammo, fire rate and origin,
simulates every bullet and calls `MedicalService.applyDamage` with the limb that was hit and `"Bullet"` damage, so
a leg hit bleeds and can fracture, chest hits can cause a pneumothorax, and so on. You can't shoot while unconscious,
treating someone or carrying a patient, and arm fractures, tourniquets and pain slow reloads and widen spread.
Stats (damage, RPM, magazine, spread, recoil, falloff) are in `src/shared/Medical/Weapons/Config.luau`.

**Models.** The M4A1 and G17 use your imported meshes when they exist, otherwise the part-built models from
`src/shared/Medical/Weapons/Models.luau`. To import them (once, in Edit mode):

1. In Studio: **File > Import 3D** (or Avatar tab > Import 3D), pick `assets/weapons/roblox/M4A1.obj`, click Import.
2. Do the same for `assets/weapons/roblox/G17.obj`.
3. In ServerStorage, insert a Folder named `WeaponModels`. Drag both imported models into it and rename them
   exactly `M4A1` and `G17` (`M17` also works).
4. Press Play.

The files in `assets/weapons/roblox/` are your Blender exports converted by `tools/convert_weapon_obj.py`: barrel
along -Z, one mesh per material and coloured in code. The original Blender OBJ files also work. Models are scaled to
`mesh.length` and get a Handle at `mesh.grip` and a Muzzle at `mesh.muzzle` (in `Weapons/Config.luau`). If a gun
faces backwards, set `yaw = 180` in its `mesh` entry. Any other Model in `WeaponModels` can be used the same way
through a `mesh` entry.

The Blender files have flat colours, not texture images, so imported models look grey in Studio. The game colours
each part by name when it builds the gun (merged `Gunmetal`/`Polymer`/... meshes, or the Blender part names from
an FBX/OBJ import). To see the colours in Edit mode too, paste this in View > Command Bar and press Enter:

```lua
require(game.ReplicatedStorage.Medical.Weapons.Models).paint(game.ServerStorage.WeaponModels)
```

For real textures, bake them in Blender to PNG images and add a `SurfaceAppearance` (ColorMap etc.) to each
MeshPart. Parts with a SurfaceAppearance, or a colour you picked yourself, are left alone.

**Animations.** Roblox only plays uploaded animations owned by you or your group, so treatments and guns are
animated in code: `client/Animator.luau` poses the character's joints from the data in `Animations.luau`, driven by
character attributes the server sets (`MedAnim`, `GunHold`, `GunAim`, `GunAction`...), so every player sees them.
Edit the angles there to change a pose; `ActionFx.luau` picks which motion and sounds each treatment uses.

**Sounds.** All sound ids are in `src/shared/Medical/Sounds.luau` (free Creator Store sounds). Replace any
id with your own `rbxassetid://` to change it.

### Optional editable prop and sound pack

`src/shared/Medical/WeaponAssets/Models.luau` also builds **FieldCarbine** and **ServicePistol**, two
low-poly editable Tool props with welded details, moving magazines/bolts, muzzle attachments and Sound
instances. These are *separate* from the M4A1/G17/M870 gameplay guns above: the optional props do
not fire projectiles, consume ammo, or cause wounds. Keep them out of `StarterPack` during normal
gameplay so players do not mistake them for functional guns.

After this change is merged, run `git pull` and `rojo serve default.project.json` on your Windows PC,
connect the Rojo Studio plugin, then run this **once in Edit mode** in **View → Command Bar**:

```lua
require(game.ReplicatedStorage.Medical.WeaponAssets.Models).createAll(game.ServerStorage)
```

This creates editable props in `ServerStorage` and never overwrites existing edits. To preview one,
**copy** it into `StarterPack` temporarily, press Play, then remove the copy when done. Left click
plays visual recoil, right mouse aims, and R animates a reload; `WeaponPreview.client.luau` runs
only for Tools marked `WeaponAsset`. The gameplay guns are marked `WeaponId` instead, so their
controls continue to use the server-authoritative gun system. The optional animation controller
can also be used directly via `require(game.ReplicatedStorage.Medical.WeaponAssets.Animations).new(tool)`.

The five original mono WAVs are in `assets/weapons/` and are silent until uploaded under the
experience owner/group via Studio **Asset Manager → Import** or Creator Dashboard. Set the matching
`SoundId` on each prop's `Handle.Fire`, `Handle.Reload`, `Handle.DryFire`, or `Handle.Equip` Sound.
Use `carbine_fire.wav` for FieldCarbine, `pistol_fire.wav` for ServicePistol, and the matching
`reload.wav`, `dry_fire.wav`, and `equip.wav` for either Tool. You can instead replace the
`RifleShot`/`PistolShot`/`DryFire`/`Equip` IDs in `src/shared/Medical/Sounds.luau` to use those
uploaded effects with the *functional* guns. Asset ownership and audio permissions must allow
your experience to play the uploaded IDs.

## Game mode: tickets and objectives (Squad-style)

Two sides, **Side A** and **Side B**, are created as Teams and players are auto-balanced. Settings live in
`ReplicatedStorage.Medical.GameMode.Config`; the rules are in `GameMode/Rules.luau`, which has no Roblox
dependencies and is tested under Lune.

- **Tickets:** each side starts with `StartTickets` (250). Every death costs `DeathTickets` (1); being unconscious
  doesn't count, only medical death or a reset. Losing an objective costs `ObjectiveLossTickets` (50), taken when the
  enemy neutralises it. A side at 0 tickets loses; after `RoundEndSeconds` the round resets and everyone respawns.
- **Objectives in order:** side A starts owning objective 1, side B owns the last one, and the ones between are
  neutral. Each side can only attack the first objective it doesn't own counting from its own end, so A goes
  1 -> 2 -> 3 and B goes 3 -> 2 -> 1. If A holds 1 and 2, B must take 2 back before 1 unlocks.
- **Capturing:** the side with more living, conscious players in the zone moves it. An owned objective must be
  neutralised first, then captured. Equal numbers freeze it (contested). Each extra player speeds it up
  (`ExtraCapperBonus`, up to `MaxCaptureMultiplier`). Empty objectives drift back to their owner.
- **Map:** tag Parts `Objective` and give each a number attribute `Order` (1, 2, 3...). The Part's box is the zone.
  With no tagged Parts and `AutoBuildMap = true`, three objectives are built in a line, with a main base at each end.
  Each base has a team spawn, a weapon locker and a medical crate, and neutral SpawnLocations are disabled.
- **HUD:** the bar at the top shows both ticket counts and every objective in its owner's colour, with capture
  progress and ATTACK / DEFEND / LOCKED for your side. A capture panel shows while you stand in a zone, and a
  banner shows the winner.

## Roblox content and maturity

- Medications use fictional game names (Analgesic, Adrenaline, Clotting Agent, Reversal Spray...), not real drug or brand names. Equipment brand names were replaced with generic ones (Hemostatic Gauze, Airway Tube, Suction Pump, Clot Tester).
- No drug-use mechanics: medications only exist as treatments given to a casualty.
- Blood particles are off by default (`Config.BloodEffects = false`). Character hits show a light grey puff instead.
- No gore, dismemberment or corpses. Defeated players respawn.
- No player-written text, chat, HTTP requests, `loadstring` or third-party asset `require`s.
- Realistic firearms and medical injuries still need declaring in the Maturity & Compliance questionnaire (Creator Dashboard > your experience > Audience). Answer it honestly for violence, blood (if you turn it on) and realistic weapons.
- `M4A1` and `G17` are real-world model names. Rename them in `Weapons/Config.luau` if you want to avoid trademarked names.

## Development

```bash
lune run tests/run.luau          # simulation scenario tests (add -- -v for details)
stylua src tests && selene src   # format + lint
```

Not implemented yet (deferred from KAT): chemical warfare, hypothermia, ophthalmology, helicopter stretchers.
