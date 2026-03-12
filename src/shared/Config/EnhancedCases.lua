--[[
	EnhancedCases.lua
	Robux-only exclusive cases with curated streamer pools.
	Purchased in packs of 1/3/10 — added to ownedCrates and opened from Case Shop.
	May contain elemental mutations (base odds only — luck stats do not apply).
]]

local EnhancedCases = {}

EnhancedCases.List = {
	{
		key    = "WraithCase",
		name   = "Wraith Case",
		accent = Color3.fromRGB(160, 80, 220),
		imageId = "rbxassetid://99231786333180",
		pool   = {
			{ streamerId = "Pokimane",   weight = 75   },
			{ streamerId = "OhnePixel",  weight = 16   },
			{ streamerId = "Kai Cenat",  weight = 7    },
			{ streamerId = "Tyler1",     weight = 1.5  },
			{ streamerId = "IShowSpeed", weight = 0.5  },
		},
		packs = {
			{ amount = 1,  productId = 3554325028 },
			{ amount = 3,  productId = 3554325487 },
			{ amount = 10, productId = 3554325835 },
		},
	},
	{
		key    = "StarlightCase",
		name   = "Starlight Case",
		accent = Color3.fromRGB(255, 220, 80),
		imageId = "rbxassetid://75771152494250",
		pool   = {
			{ streamerId = "JasondaWeen",   weight = 70   },
			{ streamerId = "Ninja",         weight = 19   },
			{ streamerId = "Jynxzi",        weight = 9    },
			{ streamerId = "MoistCr1TiKaL", weight = 1.5  },
			{ streamerId = "XQC",           weight = 0.5  },
		},
		packs = {
			{ amount = 1,  productId = 3554326167 },
			{ amount = 3,  productId = 3554326375 },
			{ amount = 10, productId = 3554326766 },
		},
	},
}

EnhancedCases.ByKey = {}
for _, c in ipairs(EnhancedCases.List) do
	EnhancedCases.ByKey[c.key] = c
end

EnhancedCases.ProductToCase = {}
for _, c in ipairs(EnhancedCases.List) do
	for _, pack in ipairs(c.packs) do
		EnhancedCases.ProductToCase[pack.productId] = { key = c.key, amount = pack.amount }
	end
end

function EnhancedCases.Roll(caseKey: string): string?
	local caseData = EnhancedCases.ByKey[caseKey]
	if not caseData then return nil end

	local totalWeight = 0
	for _, entry in ipairs(caseData.pool) do
		totalWeight = totalWeight + entry.weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(caseData.pool) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry.streamerId
		end
	end

	return caseData.pool[#caseData.pool].streamerId
end

return EnhancedCases
