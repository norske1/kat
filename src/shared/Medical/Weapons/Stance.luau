--!nonstrict
local Stance = {}

function Stance.isDriving(humanoid): boolean
	local seat = humanoid and humanoid.SeatPart
	return seat ~= nil and (seat:IsA("VehicleSeat") or seat:GetAttribute("Role") == "driver")
end

return Stance
