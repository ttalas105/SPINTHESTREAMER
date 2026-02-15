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
	{ rarity = "Common",    count = 100, gems = 300 },
	{ rarity = "Rare",     count = 85,  gems = 600 },
	{ rarity = "Epic",     count = 50,  gems = 2000 },
	{ rarity = "Legendary", count = 25, gems = 3500 },
	{ rarity = "Mythic",   count = 10,  gems = 5000 },
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
		gems    = 100000,
		req     = {
			{ rarity = "Common",    count = 1 },
			{ rarity = "Rare",      count = 1 },
			{ rarity = "Epic",     count = 1 },
			{ rarity = "Legendary", count = 1 },
			{ rarity = "Mythic",   count = 1 },
		},
	},
	-- ======== ONE-TIME SACRIFICES (ordered least → most gems) ========
	CommonArmy = {
		name    = "Common Army",
		gems    = 1500,
		req     = {
			{ rarity = "Common", count = 5 },
		},
	},
	RareRoundup = {
		name    = "Rare Roundup",
		gems    = 8000,
		req     = {
			{ streamerId = "Shroud",         effect = nil, count = 1 },
			{ streamerId = "StableRonaldo",  effect = nil, count = 1 },
			{ streamerId = "Train",          effect = nil, count = 1 },
			{ streamerId = "Lacy",           effect = nil, count = 1 },
		},
	},
	ContentHouse = {
		name    = "Content House",
		gems    = 10000,
		req     = {
			{ streamerId = "Adapt",          effect = "Solar",  count = 1 },
			{ streamerId = "JasondaWeen",    effect = nil,      count = 1 },
			{ streamerId = "Lacy",           effect = "Void",   count = 1 },
			{ streamerId = "StableRonaldo",  effect = "Acid",   count = 1 },
		},
	},
	EpicEnsemble = {
		name    = "Epic Ensemble",
		gems    = 15000,
		req     = {
			{ streamerId = "Cinna",       effect = nil, count = 1 },
			{ streamerId = "CaseOh",      effect = nil, count = 1 },
			{ streamerId = "Pokimane",    effect = nil, count = 1 },
			{ streamerId = "Adapt",       effect = nil, count = 1 },
		},
	},
	GamblingAddicts = {
		name    = "Gambling Addicts",
		gems    = 24000,
		req     = {
			{ streamerId = "XQC",   effect = nil,     count = 1 },
			{ streamerId = "Train", effect = "Solar",  count = 1 },
		},
	},
	TheOGs = {
		name    = "The OGs",
		gems    = 25000,
		req     = {
			{ streamerId = "XQC",       effect = nil,       count = 1 },
			{ streamerId = "OhnePixel", effect = "Lava",    count = 1 },
			{ streamerId = "Train",     effect = "Glitchy", count = 1 },
			{ streamerId = "Ninja",     effect = "Snow",    count = 1 },
		},
	},
	FPSLegends = {
		name    = "FPS Legends",
		gems    = 35000,
		req     = {
			{ streamerId = "Shroud", effect = "Void", count = 1 },
			{ streamerId = "Ninja",  effect = "Void", count = 1 },
		},
	},
	TwitchRoyalty = {
		name    = "Twitch Royalty",
		gems    = 40000,
		req     = {
			{ streamerId = "Ninja",     effect = "Acid",  count = 1 },
			{ streamerId = "Kai Cenat", effect = nil,     count = 1 },
			{ streamerId = "Jynxzi",    effect = "Lunar", count = 1 },
		},
	},
	TheUntouchables = {
		name    = "The Untouchables",
		gems    = 100000,
		req     = {
			{ streamerId = "IShowSpeed", effect = nil, count = 1 },
			{ streamerId = "XQC",        effect = nil, count = 1 },
		},
	},
	MythicRoyale = {
		name    = "Mythic Royale",
		gems    = 3000000,
		req     = {
			{ streamerId = "IShowSpeed", effect = "Acid",      count = 1 },
			{ streamerId = "IShowSpeed", effect = "Snow",      count = 1 },
			{ streamerId = "IShowSpeed", effect = "Lava",      count = 1 },
			{ streamerId = "IShowSpeed", effect = "Lightning", count = 1 },
			{ streamerId = "IShowSpeed", effect = "Shadow",    count = 1 },
			{ streamerId = "IShowSpeed", effect = "Glitchy",   count = 1 },
			{ streamerId = "IShowSpeed", effect = "Lunar",     count = 1 },
			{ streamerId = "IShowSpeed", effect = "Solar",     count = 1 },
			{ streamerId = "IShowSpeed", effect = "Void",      count = 1 },
			{ streamerId = "XQC",        effect = "Acid",      count = 1 },
			{ streamerId = "XQC",        effect = "Snow",      count = 1 },
			{ streamerId = "XQC",        effect = "Lava",      count = 1 },
			{ streamerId = "XQC",        effect = "Lightning", count = 1 },
			{ streamerId = "XQC",        effect = "Shadow",    count = 1 },
			{ streamerId = "XQC",        effect = "Glitchy",   count = 1 },
			{ streamerId = "XQC",        effect = "Lunar",     count = 1 },
			{ streamerId = "XQC",        effect = "Solar",     count = 1 },
			{ streamerId = "XQC",        effect = "Void",      count = 1 },
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

-- Gem Roulette: wager any amount of gems, 50/50 double or lose them all. 1 charge, 60 min recharge.
Sacrifice.GemRoulette = {
	name    = "Gem Roulette",
	desc    = "Wager your gems! 50% chance to DOUBLE, 50% chance they're GONE!",
	maxCharges = 1,
	rechargeMinutes = 60,
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
