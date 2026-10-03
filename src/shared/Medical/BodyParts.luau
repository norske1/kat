--!strict
local BodyParts = {}

BodyParts.List = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
BodyParts.Limbs = { "LeftArm", "RightArm", "LeftLeg", "RightLeg" }

BodyParts.DisplayName = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left Arm",
	RightArm = "Right Arm",
	LeftLeg = "Left Leg",
	RightLeg = "Right Leg",
} :: { [string]: string }

-- Relative chance a body part is hit when the damage source gives no hit location.
BodyParts.HitWeights = {
	Head = 10,
	Torso = 40,
	LeftArm = 12,
	RightArm = 12,
	LeftLeg = 13,
	RightLeg = 13,
} :: { [string]: number }

local partMap: { [string]: string } = {
	Head = "Head",
	UpperTorso = "Torso",
	LowerTorso = "Torso",
	Torso = "Torso",
	HumanoidRootPart = "Torso",
	LeftUpperArm = "LeftArm",
	LeftLowerArm = "LeftArm",
	LeftHand = "LeftArm",
	["Left Arm"] = "LeftArm",
	RightUpperArm = "RightArm",
	RightLowerArm = "RightArm",
	RightHand = "RightArm",
	["Right Arm"] = "RightArm",
	LeftUpperLeg = "LeftLeg",
	LeftLowerLeg = "LeftLeg",
	LeftFoot = "LeftLeg",
	["Left Leg"] = "LeftLeg",
	RightUpperLeg = "RightLeg",
	RightLowerLeg = "RightLeg",
	RightFoot = "RightLeg",
	["Right Leg"] = "RightLeg",
}

function BodyParts.isValid(part: string?): boolean
	return part ~= nil and BodyParts.DisplayName[part] ~= nil
end

function BodyParts.isLimb(part: string): boolean
	return part == "LeftArm" or part == "RightArm" or part == "LeftLeg" or part == "RightLeg"
end

function BodyParts.isLeg(part: string): boolean
	return part == "LeftLeg" or part == "RightLeg"
end

-- Maps a Roblox character part name (R6 or R15) to a medical body part.
function BodyParts.fromInstanceName(name: string): string?
	return partMap[name]
end

return BodyParts
