# KAT-style Medical System for Roblox

An advanced, server-authoritative medical system for Roblox, inspired by
[KAT - Advanced Medical](https://steamcommunity.com/workshop/filedetails/?id=2020940806) for ArmA 3.
It is written from scratch in Luau. The mechanics follow the KAT/ACE design, but no SQF code was ported.

## Features

| Area | What is simulated |
|---|---|
| Wounds | 6 body parts, 8 wound types × 3 sizes, per-wound bleeding & pain, weighted by damage type (bullet, explosive, blunt, fall, stab, melee) |
| Circulation | Blood volume (6 L) with hemorrhage classes, HR/BP from cardiac output & peripheral resistance, coagulation factors, TXA/EACA, internal bleeding |
| Bandages | Field dressing, packing, elastic, QuikClot, each with its own effectiveness and reopening chance. Stitching and NPWT close wounds permanently |
| Tourniquets | Stop limb bleeding and IV flow on that limb. They become painful after a while |
| Fractures | Simple, compound, comminuted. Splints, closed reduction, surgical pathway (incision, retraction, irrigation, clamping, plating, stitching) |
| Airway | Obstruction (tongue) and occlusion (vomit/blood) while unconscious. Head tilt (held), recovery position, Guedel, KingLT, suction, manual sweep |
| Breathing | PaO2/SpO2 (oxygen dissociation curve), RR, EtCO2, pneumothorax stages 1-4, tension PTX, hemothorax. Chest seal, needle decompression, chest drain, BVM, oxygen, opioid respiratory depression |
| Cardiac | Arrest on blood loss, hypoxia, brady/tachycardia, tension PTX, tamponade, overdose, transfusion reaction. VF/VT/PEA/asystole, arrest timer, CPR (slows the timer), AED and AED-X with manual shocks, reversible causes block ROSC, pericardiocentesis |
| Pharmacy | 16g IV / FAST IO, saline/plasma/blood bags (all ABO/Rh types, compatibility, hemolytic reaction), and 18 medications with onset/peak/decay curves, dose stacking and overdoses. Naloxone and flumazenil reversal |
| Monitoring | Manual pulse/BP/response checks, pulse oximeter, AED-X monitor with live ECG trace, ultrasound, blood type test |
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
src/client/                StarterPlayerScripts.MedicalClient (menu, HUD, screen effects)
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
VF arrest, blast, opioid overdose). There's also a debug panel for hurting yourself, healing, changing medical
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

## Optional weapon asset pack

This repo includes **FieldCarbine** and **ServicePistol**, two original, low-poly, editable Roblox
Tools built from Parts. They have welded details, animated magazines/bolts, muzzle attachments, and
Sound instances. The five original mono WAV effects are in `assets/weapons/`. These are **assets
and a visual/audio preview**, not a shooting system: clicking does not create bullets, use ammo,
or deal damage. Your weapon server code should call `MedicalAPI.damage(...)` on validated hits.

After this change is merged, on your own Windows PC update the repo and sync it to Studio as usual:

```powershell
git pull
rojo serve default.project.json
```

Connect the Rojo Studio plugin, then open **View → Command Bar** in Studio and run this **once in
Edit mode** (not while playing) to create persistent, editable Tools in `StarterPack`:

```lua
local models = require(game.ReplicatedStorage.Medical.WeaponAssets.Models)
models.createAll(game.StarterPack)
```

The command is safe to rerun: it returns existing asset Tools without replacing edits. To rebuild
from source, manually delete the two generated Tools first, then run it again. Press **Play** and
equip one to preview: **left click** = recoil/slide + shot sound, **right mouse button** = aim,
**R** = magazine/bolt reload animation. The preview script lives in `src/client/WeaponPreview.client.luau`
and only responds to Tools with the `WeaponAsset` attribute. Remove or disable that script when
your own weapon input/controller takes over.

Audio starts silent because Roblox requires audio uploads in the experience owner/group's account.
In Studio, import each WAV from `assets/weapons/` through **Asset Manager → Import** (or the
Creator Dashboard); copy each new audio asset ID into the matching Sound's `SoundId` property as
`rbxassetid://YOUR_ID`:

| WAV file | Where to set SoundId |
|---|---|
| `carbine_fire.wav` | `StarterPack.FieldCarbine.Handle.Fire` |
| `pistol_fire.wav` | `StarterPack.ServicePistol.Handle.Fire` |
| `reload.wav` | both Tools' `Handle.Reload` |
| `dry_fire.wav` | both Tools' `Handle.DryFire` |
| `equip.wav` | both Tools' `Handle.Equip` |

The animations are procedural local Tool-grip/Motor6D motion, not uploaded Roblox AnimationIds.
For integration, use `require(game.ReplicatedStorage.Medical.WeaponAssets.Animations).new(tool)`;
call `:equip()`, `:setAiming(true/false)`, `:fire()`, `:reload()`, and `:unequip()` from your
controller. The preview calls these methods but does not replicate gunshot audio or implement
server-side firing. Ensure uploaded audio is permitted for the experience before testing.

## Development

```bash
lune run tests/run.luau          # simulation scenario tests (add -- -v for details)
stylua src tests && selene src   # format + lint
```

Not implemented yet (deferred from KAT): chemical warfare, hypothermia, ophthalmology, helicopter stretchers.
