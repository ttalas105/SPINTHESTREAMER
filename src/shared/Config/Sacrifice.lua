--[[
	Sacrifice.lua
	Config for the Sacrifice system: gem trades, one-time quests,
	test-your-luck sacrifices (with charges), and elemental conversion.
]]

local Sacrifice = {}

-------------------------------------------------
-- GEM SACRIFICE (repeatable)
-- Sacrifice X streamers of rarity → get Y gems
-------------------------------------------------
Sacrifice.GemTrades = {
	{ rarity = "Common",    count = 100, gems = 100 },
	{ rarity = "Rare",     count = 85,  gems = 250 },
	{ rarity = "Epic",     count = 50,  gems = 500 },
	{ rarity = "Legendary", count = 25, gems = 750 },
	{ rarity = "Mythic",   count = 10,  gems = 1000 },
}

-------------------------------------------------
-- ONE-TIME GEM SACRIFICES (id → requirements → gems)
-- Requirements: list of { streamerId, effect?, count }
-------------------------------------------------
Sacrifice.OneTime = {
	FatPeople = {
		name    = "Fat People",
		gems    = 2000,
		req     = {
			{ streamerId = "Cinna",       effect = nil, count = 1 },
			{ streamerId = "Lacy",       effect = nil, count = 1 },
			{ streamerId = "Fanum",      effect = nil, count = 1 },
			{ streamerId = "StableRonaldo", effect = nil, count = 1 },
		},
	},
	GirlPower = {
		name    = "Girl Power",
		gems    = 2000,
		req     = {
			{ streamerId = "Pokimane", effect = nil, count = 2 },
			{ streamerId = "Cinna",   effect = nil, count = 1 },
		},
	},
	Rainbow = {
		name    = "Rainbow",
		gems    = 2000,
		req     = {
			{ rarity = "Common",    count = 1 },
			{ rarity = "Rare",      count = 1 },
			{ rarity = "Epic",     count = 1 },
			{ rarity = "Legendary", count = 1 },
			{ rarity = "Mythic",   count = 1 },
		},
	},
	-- ELEMENTAL ONE-TIME SACRIFICES (20 cards of a specific effect, any rarity)
	AcidReflex = {
		name = "Acid Reflex",
		gems = 1000,
		req  = { { effectReq = "Acid", count = 20 } },
	},
	SnowyAvalanche = {
		name = "Snowy Avalanche",
		gems = 3000,
		req  = { { effectReq = "Snow", count = 20 } },
	},
	LavaEruption = {
		name = "Lava Eruption",
		gems = 5000,
		req  = { { effectReq = "Lava", count = 20 } },
	},
	LightningStrike = {
		name = "Lightning Strike",
		gems = 7000,
		req  = { { effectReq = "Lightning", count = 20 } },
	},
	ShadowRealm = {
		name = "Shadow Realm",
		gems = 9000,
		req  = { { effectReq = "Shadow", count = 20 } },
	},
	GlitchStorm = {
		name = "Glitch Storm",
		gems = 11000,
		req  = { { effectReq = "Glitchy", count = 20 } },
	},
	LunarTide = {
		name = "Lunar Tide",
		gems = 13000,
		req  = { { effectReq = "Lunar", count = 20 } },
	},
	SolarFlare = {
		name = "Solar Flare",
		gems = 15000,
		req  = { { effectReq = "Solar", count = 20 } },
	},
	VoidAbyss = {
		name = "Void Abyss",
		gems = 17000,
		req  = { { effectReq = "Void", count = 20 } },
	},
}

-------------------------------------------------
-- TEST YOUR LUCK
-------------------------------------------------
Sacrifice.LuckWarning = "These sacrifices bring great riches but could also bring devastating drawbacks. Play at your own risk!"

-- 50/50: half cash or 2x cash. 3 charges, 1 every 10 min.
Sacrifice.FiftyFifty = {
	name    = "50/50",
	desc    = "50% chance: HALF your cash. 50% chance: 2x your cash!",
	maxCharges = 3,
	rechargeMinutes = 10,
	req     = {
		{ rarity = "Rare",      count = 20 },
		{ rarity = "Epic",     count = 20 },
		{ rarity = "Legendary", count = 5 },
	},
}

-- Feeling Lucky: +100% or -100% luck for 10 min. 1 charge, 20 min recharge.
Sacrifice.FeelingLucky = {
	name    = "Feeling Lucky?",
	desc    = "50% chance: +100% luck for 10 min. 50% chance: -100% luck for 10 min!",
	maxCharges = 1,
	rechargeMinutes = 20,
	durationSeconds = 10 * 60,
	req     = {
		{ rarity = "Common", count = 1 },
		{ rarity = "Rare",   count = 1 },
		{ rarity = "Epic",   count = 20 },
	},
}

-- Don't do it: sacrifice your highest-earning streamer, chance to upgrade to next rarity.
Sacrifice.DontDoIt = {
	name    = "Don't do it (please)",
	desc    = "Sacrifice your highest-earning streamer for a chance to upgrade it to the next rarity!",
	upgradeChances = {
		Common    = 50,   -- common → rare
		Rare      = 30,   -- rare → epic
		Epic      = 10,   -- epic → legendary
		Legendary = 4,    -- legendary → mythic
	},
	-- infinite charges
}

-------------------------------------------------
-- ELEMENTAL SACRIFICE
-- X of same effect + same rarity → 1 random streamer of that rarity with that effect
-------------------------------------------------
Sacrifice.ElementalRates = {
	Common    = 20,
	Rare      = 15,
	Epic      = 10,
	Legendary = 8,
	-- Mythic = no conversion
}

return Sacrifice
