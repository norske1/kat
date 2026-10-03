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

## Development

```bash
lune run tests/run.luau          # simulation scenario tests (add -- -v for details)
stylua src tests && selene src   # format + lint
```

Not implemented yet (deferred from KAT): chemical warfare, hypothermia, ophthalmology, helicopter stretchers.
