--!strict
-- Squad-style game mode: two sides, tickets and a lane of objectives captured in order.
local GameConfig = {}

GameConfig.Enabled = true
GameConfig.StartTickets = 250
GameConfig.DeathTickets = 1 -- per death (unconscious doesn't count, only medical death / respawn)
GameConfig.ObjectiveLossTickets = 50 -- when one of your objectives is neutralised by the enemy

-- Capturing: one player takes CaptureSeconds to neutralise an objective and the same again to capture it.
-- Every extra player (more than the enemy has in the zone) adds ExtraCapperBonus, up to MaxCaptureMultiplier.
GameConfig.CaptureSeconds = 45
GameConfig.ExtraCapperBonus = 0.5
GameConfig.MaxCaptureMultiplier = 3
GameConfig.RegenSeconds = 90 -- empty objectives drift back to their owner (or to neutral)
GameConfig.CountIncapacitated = false -- unconscious players don't hold or capture objectives
GameConfig.TickRate = 0.25 -- seconds between capture updates

GameConfig.Sides = {
	A = { name = "Side A", color = Color3.fromRGB(60, 130, 230) },
	B = { name = "Side B", color = Color3.fromRGB(215, 60, 55) },
}

-- Map: Parts tagged "Objective" with a number attribute "Order" (1, 2, 3...) are the capture zones (the Part's box
-- is the zone). If there are none, a lane of AutoObjectiveCount objectives is built with a main base (team spawn,
-- weapon locker, medical crate) at each end, and neutral SpawnLocations are disabled so teams spawn at their base.
GameConfig.AutoBuildMap = true
GameConfig.AutoObjectiveCount = 3
GameConfig.ObjectiveSpacing = 100 -- studs between objectives
GameConfig.ZoneSize = Vector3.new(50, 30, 50)

GameConfig.RoundEndSeconds = 15 -- scoreboard time before everything resets and everyone respawns

return GameConfig
