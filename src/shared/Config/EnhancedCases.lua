--[[
	EnhancedCases.lua
	Robux-only exclusive cases with fixed streamer+element pools.
	Each case has a small curated pool of elemental streamers with set odds.
	Purchased via Developer Products — one spin per purchase.
]]

local EnhancedCases = {}

EnhancedCases.List = {
	{
		key      = "LunarEnhanced",
		name     = "Lunar Enhanced Case",
		accent   = Color3.fromRGB(200, 220, 255),
		pool     = {
			{ streamerId = "CaseOh",     effect = "Lunar", weight = 60, label = "Lunar CaseOh"     },
			{ streamerId = "Adapt",      effect = "Lunar", weight = 25, label = "Lunar Adapt"       },
			{ streamerId = "Ninja",      effect = "Lunar", weight = 13, label = "Lunar Ninja"       },
			{ streamerId = "IShowSpeed", effect = "Lunar", weight = 2,  label = "Lunar IShowSpeed"  },
		},
	},
	{
		key      = "SolarEnhanced",
		name     = "Solar Enhanced Case",
		accent   = Color3.fromRGB(255, 220, 60),
		pool     = {
			{ streamerId = "JasondaWeen", effect = "Solar", weight = 60, label = "Solar JasondaWeen" },
			{ streamerId = "Kai Cenat",   effect = "Solar", weight = 30, label = "Solar Kai Cenat"   },
			{ streamerId = "IShowSpeed",  effect = "Solar", weight = 5,  label = "Solar IShowSpeed"  },
			{ streamerId = "XQC",         effect = "Solar", weight = 5,  label = "Solar xQc"         },
		},
	},
	{
		key      = "VoidEnhanced",
		name     = "Void Enhanced Case",
		accent   = Color3.fromRGB(140, 15, 50),
		pool     = {
			{ streamerId = "JasondaWeen", effect = "Void", weight = 30, label = "Void JasondaWeen" },
			{ streamerId = "Kai Cenat",   effect = "Void", weight = 20, label = "Void Kai Cenat"   },
			{ streamerId = "Jynxzi",      effect = "Void", weight = 20, label = "Void Jynxzi"      },
			{ streamerId = "XQC",         effect = "Void", weight = 15, label = "Void xQc"         },
			{ streamerId = "IShowSpeed",  effect = "Void", weight = 15, label = "Void IShowSpeed"  },
		},
	},
}

EnhancedCases.ByKey = {}
for _, c in ipairs(EnhancedCases.List) do
	EnhancedCases.ByKey[c.key] = c
end

--- Roll a random streamer from a case pool based on weights.
function EnhancedCases.Roll(caseKey: string): (string?, string?)
	local caseData = EnhancedCases.ByKey[caseKey]
	if not caseData then return nil, nil end

	local totalWeight = 0
	for _, entry in ipairs(caseData.pool) do
		totalWeight = totalWeight + entry.weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(caseData.pool) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry.streamerId, entry.effect
		end
	end

	local last = caseData.pool[#caseData.pool]
	return last.streamerId, last.effect
end

return EnhancedCases
