--!strict
-- Procedural animation data for treatments and weapons. Nothing has to be uploaded: clients pose the
-- character's Motor6D joints directly (see client/Animator). Values are additive Euler angles in degrees
-- { rx, ry, rz, px, py, pz } applied in the parent part's space at the joint:
--   arms/legs:  +rx swings the limb forward, +rz swings the right arm outwards (left arm: -rz)
--   +ry on the right shoulder turns the arm towards the body centre (left: -ry)
--   waist/neck: -rx leans forward / looks down
--   elbows/knees: +rx bends the elbow, -rx bends the knee
local Animations = {}

export type JointPose = { number }
export type Pose = { [string]: JointPose }
export type Key = { t: number, pose: Pose }
export type Motion = { period: number, keys: { Key } }

Animations.LowerJoints = { "Root", "RightHip", "RightKnee", "LeftHip", "LeftKnee" }

local function k(t: number, pose: Pose): Key
	return { t = t, pose = pose }
end

-- Base poses for the medic --------------------------------------------------------------------
Animations.Bases = {
	-- kneeling next to a patient on the ground (full body)
	Kneel = {
		Root = { 0, 0, 0, 0, -0.95, 0 },
		LeftHip = { 85, 0, 0 },
		LeftKnee = { -85, 0, 0 },
		RightHip = { -10, 0, 0 },
		RightKnee = { -80, 0, 0 },
		Waist = { -25, 0, 0 },
		Neck = { -20, 0, 0 },
		RightShoulder = { 40, 10, 0 },
		RightElbow = { 25, 0, 0 },
		LeftShoulder = { 40, -10, 0 },
		LeftElbow = { 25, 0, 0 },
	},
	-- treating a standing patient (upper body only, legs keep walking/idling)
	Stand = {
		Waist = { -8, 0, 0 },
		Neck = { -12, 0, 0 },
		RightShoulder = { 55, 10, 0 },
		RightElbow = { 30, 0, 0 },
		LeftShoulder = { 55, -10, 0 },
		LeftElbow = { 30, 0, 0 },
	},
	-- treating yourself: hands to your own body
	Self = {
		Waist = { -5, 0, 0 },
		Neck = { -30, 0, 0 },
		RightShoulder = { 30, 30, 0 },
		RightElbow = { 65, 0, 0 },
		LeftShoulder = { 30, -30, 0 },
		LeftElbow = { 65, 0, 0 },
	},
	-- fireman's carry: patient over the right shoulder
	Carry = {
		Waist = { -5, 0, 0 },
		RightShoulder = { 160, 10, 0 },
		RightElbow = { 70, 0, 0 },
		LeftShoulder = { 40, -20, 0 },
		LeftElbow = { 60, 0, 0 },
	},
	-- dragging a patient behind you
	Drag = {
		Waist = { -20, 0, 0 },
		Neck = { 10, 0, 0 },
		RightShoulder = { -35, 0, 15 },
		RightElbow = { 10, 0, 0 },
		LeftShoulder = { -35, 0, -15 },
		LeftElbow = { 10, 0, 0 },
	},
} :: { [string]: Pose }

-- Looping motions layered on top of a base -------------------------------------------------------
Animations.Motions = {
	Hold = { period = 1, keys = { k(0, {}), k(1, {}) } },
	Work = {
		period = 1,
		keys = {
			k(0, {}),
			k(0.5, {
				RightShoulder = { 12, -5, 0 },
				RightElbow = { -12, 0, 0 },
				LeftShoulder = { -6, 5, 0 },
				LeftElbow = { 8, 0, 0 },
			}),
			k(1, {}),
		},
	},
	Wrap = {
		period = 1.2,
		keys = {
			k(0, {}),
			k(0.3, { RightShoulder = { 10, -15, 0 }, LeftShoulder = { -5, -10, 0 } }),
			k(0.6, { RightShoulder = { 0, -25, 0 }, LeftShoulder = { 5, 15, 0 } }),
			k(0.9, { RightShoulder = { -8, -10, 0 }, LeftShoulder = { 10, 10, 0 } }),
			k(1.2, {}),
		},
	},
	Tighten = {
		period = 0.8,
		keys = {
			k(0, {}),
			k(0.4, { RightShoulder = { -10, 0, 15 }, RightElbow = { 25, 0, 0 }, LeftShoulder = { 5, 0, 0 } }),
			k(0.8, {}),
		},
	},
	Inject = {
		period = 1.4,
		keys = {
			k(0, {}),
			k(0.5, { RightShoulder = { -15, 0, 0 }, RightElbow = { 20, 0, 0 } }),
			k(0.65, { RightShoulder = { 12, 0, 0 }, RightElbow = { -15, 0, 0 } }),
			k(1.1, { RightShoulder = { 12, 0, 0 }, RightElbow = { -15, 0, 0 } }),
			k(1.4, {}),
		},
	},
	Mouth = {
		period = 1.6,
		keys = {
			k(0, {}),
			k(0.6, { RightShoulder = { 15, -15, 0 }, RightElbow = { 60, 0, 0 }, Neck = { 25, 0, 0 } }),
			k(1.2, { RightShoulder = { 15, -15, 0 }, RightElbow = { 60, 0, 0 }, Neck = { 25, 0, 0 } }),
			k(1.6, {}),
		},
	},
	Examine = {
		period = 2,
		keys = {
			k(0, {}),
			k(1, { RightShoulder = { 8, -10, 0 }, Neck = { -6, 10, 0 }, LeftShoulder = { -10, 0, 0 } }),
			k(2, {}),
		},
	},
	Airway = {
		period = 1.5,
		keys = {
			k(0, {}),
			k(0.75, { RightElbow = { -8, 0, 0 }, LeftElbow = { -8, 0, 0 }, Waist = { -4, 0, 0 } }),
			k(1.5, {}),
		},
	},
	Squeeze = {
		period = 1.5,
		keys = {
			k(0, {}),
			k(0.4, { RightElbow = { 18, 0, 0 }, RightShoulder = { -6, 0, 0 } }),
			k(0.8, {}),
			k(1.5, {}),
		},
	},
	-- ~110 compressions per minute, arms locked, whole upper body pushing down
	Cpr = {
		period = 0.55,
		keys = {
			k(0, {
				Waist = { -15, 0, 0 },
				RightShoulder = { 20, 10, 0 },
				LeftShoulder = { 20, -10, 0 },
				RightElbow = { -25, 0, 0 },
				LeftElbow = { -25, 0, 0 },
			}),
			k(0.25, {
				Root = { 0, 0, 0, 0, -0.2, 0 },
				Waist = { -22, 0, 0 },
				RightShoulder = { 24, 10, 0 },
				LeftShoulder = { 24, -10, 0 },
				RightElbow = { -25, 0, 0 },
				LeftElbow = { -25, 0, 0 },
			}),
			k(0.55, {
				Waist = { -15, 0, 0 },
				RightShoulder = { 20, 10, 0 },
				LeftShoulder = { 20, -10, 0 },
				RightElbow = { -25, 0, 0 },
				LeftElbow = { -25, 0, 0 },
			}),
		},
	},
	Surgery = {
		period = 0.6,
		keys = {
			k(0, {}),
			k(0.3, { RightShoulder = { 6, 5, 0 }, RightElbow = { -8, 0, 0 }, LeftShoulder = { 4, -4, 0 } }),
			k(0.6, {}),
		},
	},
	Fluids = {
		period = 2.5,
		keys = {
			k(0, {}),
			k(0.8, { RightShoulder = { 60, 0, 0 }, RightElbow = { -20, 0, 0 } }),
			k(1.8, { RightShoulder = { 60, 0, 0 }, RightElbow = { -20, 0, 0 } }),
			k(2.5, {}),
		},
	},
	Lift = {
		period = 1,
		keys = {
			k(0, {}),
			k(0.5, { Waist = { -15, 0, 0 }, RightShoulder = { 15, 0, 0 }, LeftShoulder = { 15, 0, 0 } }),
			k(1, {}),
		},
	},
} :: { [string]: Motion }

-- Weapons ----------------------------------------------------------------------------------------
-- The gun is welded to the right hand and points along the forearm, so the shoulder + elbow angles
-- decide where the barrel points (aim: wrist roll compensates the inward turn of the arm).
Animations.Gun = {
	Rifle = {
		hip = {
			RightShoulder = { 25, 0, 0 },
			RightElbow = { 65, 0, 0 },
			LeftShoulder = { 70, -35, 0 },
			LeftElbow = { 25, 0, 0 },
		},
		aim = {
			Neck = { 0, 0, -8 },
			RightShoulder = { 65, 25, 0 },
			RightElbow = { 25, 0, 0 },
			RightWrist = { 0, 0, 25 },
			LeftShoulder = { 80, -30, 0 },
			LeftElbow = { 15, 0, 0 },
		},
	},
	Pistol = {
		hip = {
			RightShoulder = { 55, 10, 0 },
			RightElbow = { 15, 0, 0 },
			LeftShoulder = { 55, -30, 0 },
			LeftElbow = { 25, 0, 0 },
		},
		aim = {
			RightShoulder = { 88, 18, 0 },
			RightElbow = { 2, 0, 0 },
			RightWrist = { 0, 0, 18 },
			LeftShoulder = { 85, -35, 0 },
			LeftElbow = { 20, 0, 0 },
		},
	},
} :: { [string]: { hip: Pose, aim: Pose } }

-- How much of the aim pitch each joint takes (sums to roughly 1 along the arm chain).
Animations.PitchWeights =
	{ Waist = 0.35, Neck = 0.45, RightShoulder = 0.65, LeftShoulder = 0.65 } :: { [string]: number }

-- Weapon actions. `normalized` motions are stretched to the action duration (keys 0..1),
-- the others loop with their own period (e.g. inserting shotgun shells one by one).
Animations.GunActions = {
	Equip = {
		normalized = true,
		motion = {
			period = 1,
			keys = { k(0, { RightShoulder = { -35, 0, 0 }, LeftShoulder = { -50, 0, 0 } }), k(1, {}) },
		},
	},
	Reload = {
		normalized = true,
		motion = {
			period = 1,
			keys = {
				k(0, {}),
				k(0.15, { LeftShoulder = { -50, 20, 0 }, LeftElbow = { 30, 0, 0 }, RightShoulder = { -5, 0, -10 } }),
				k(0.35, { LeftShoulder = { -65, 25, 0 }, LeftElbow = { 50, 0, 0 }, RightShoulder = { -5, 0, -10 } }),
				k(0.6, { LeftShoulder = { -40, 15, 0 }, LeftElbow = { 40, 0, 0 }, RightShoulder = { -5, 0, -10 } }),
				k(0.8, { LeftShoulder = { -20, 25, 0 }, LeftElbow = { 10, 0, 0 } }),
				k(1, {}),
			},
		},
	},
	ReloadShells = {
		normalized = false,
		motion = {
			period = 0.5,
			keys = {
				k(0, { RightShoulder = { -8, 0, -15 } }),
				k(0.25, { LeftShoulder = { -50, 10, 0 }, LeftElbow = { 40, 0, 0 }, RightShoulder = { -8, 0, -15 } }),
				k(0.5, { RightShoulder = { -8, 0, -15 } }),
			},
		},
	},
	Pump = {
		normalized = true,
		motion = {
			period = 1,
			keys = { k(0, {}), k(0.4, { LeftShoulder = { -12, 0, 0 }, LeftElbow = { 25, 0, 0 } }), k(1, {}) },
		},
	},
} :: { [string]: { normalized: boolean, motion: Motion } }

-- Helpers -------------------------------------------------------------------------------------------
local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

-- Adds `pose * scale` into `into` (mutates and returns `into`).
function Animations.add(into: Pose, pose: Pose, scale: number?): Pose
	local s = scale or 1
	for joint, values in pose do
		local target = into[joint]
		if not target then
			target = { 0, 0, 0, 0, 0, 0 }
			into[joint] = target
		end
		for i = 1, 6 do
			target[i] = (target[i] or 0) + (values[i] or 0) * s
		end
	end
	return into
end

function Animations.copy(pose: Pose): Pose
	return Animations.add({}, pose)
end

-- Samples a motion at time t (looping by its period).
function Animations.sample(motion: Motion, t: number): Pose
	local keys = motion.keys
	local time = t % motion.period
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if time >= a.t and time <= b.t then
			local f = if b.t > a.t then smooth((time - a.t) / (b.t - a.t)) else 0
			local out = Animations.add({}, a.pose, 1 - f)
			return Animations.add(out, b.pose, f)
		end
	end
	return Animations.copy(keys[#keys].pose)
end

-- Medical clip "Base.Motion" (e.g. "Kneel.Cpr") at time t. Returns the pose and whether it is full-body.
function Animations.medical(clip: string, t: number): (Pose?, boolean)
	local baseName, motionName = string.match(clip, "^(%w+)%.(%w+)$")
	if not baseName or not motionName then
		return nil, false
	end
	local base = Animations.Bases[baseName :: string]
	local motion = Animations.Motions[motionName :: string]
	if not base or not motion then
		return nil, false
	end
	local pose = Animations.copy(base)
	Animations.add(pose, Animations.sample(motion, t))
	return pose, pose.Root ~= nil
end

-- Weapon pose. aim is a 0..1 blend between hip and aim, pitch is in degrees (+ up).
-- action/actionT: optional action name and time (seconds, or 0..1 progress for normalized actions).
function Animations.gun(
	hold: string,
	aim: number,
	pitch: number,
	action: string?,
	actionT: number?,
	kick: number?
): Pose?
	local set = Animations.Gun[hold]
	if not set then
		return nil
	end
	local a = math.clamp(aim, 0, 1)
	local pose = Animations.add(Animations.copy(set.hip), set.hip, -a)
	Animations.add(pose, set.aim, a)
	for joint, weight in Animations.PitchWeights do
		Animations.add(pose, { [joint] = { pitch * weight, 0, 0 } })
	end
	if action and actionT then
		local def = Animations.GunActions[action]
		if def then
			local t = if def.normalized then math.clamp(actionT, 0, 1) * def.motion.period else actionT
			Animations.add(pose, Animations.sample(def.motion, t))
		end
	end
	if kick and kick > 0.001 then
		Animations.add(pose, {
			RightShoulder = { 6 * kick, 0, 0 },
			LeftShoulder = { 5 * kick, 0, 0 },
			Waist = { 2 * kick, 0, 0 },
			Neck = { -1.5 * kick, 0, 0 },
		})
	end
	return pose
end

return Animations
