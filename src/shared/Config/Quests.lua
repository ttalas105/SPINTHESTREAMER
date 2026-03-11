--[[
	Quests.lua
	Daily, Weekly, and Lifetime quest definitions.
	Daily quests reset every 24h. Weekly quests reset every 7 days.
	Lifetime quests are one-time achievements.

	Quest types (match what the server tracks):
	  spins          – total spins performed
	  sells          – total streamers sold
	  rebirths       – total rebirths performed
	  gemsEarned     – total gems earned
	  cashEarned     – total cash earned
	  epicPulls      – Epic+ streamer pulls
	  legendaryPulls – Legendary+ pulls
	  mythicPulls    – Mythic pulls
	  effectPulls    – any elemental streamer pulls
	  potionsBought  – potions purchased
	  sacrificesDone – any sacrifice performed
	  casesOpened    – gem cases opened
	  indexClaimed   – index entries claimed
	  indexDefault   – default index entries claimed
	  indexAcid      – Acid index entries claimed
	  indexSnow      – Snow index entries claimed
	  indexLava      – Lava index entries claimed
	  indexLightning – Lightning index entries claimed
	  indexShadow    – Shadow index entries claimed
	  indexGlitchy   – Glitchy index entries claimed
	  indexLunar     – Lunar index entries claimed
	  indexSolar     – Solar index entries claimed
	  indexVoid      – Void index entries claimed
	  logins         – daily login (auto-incremented on join)
]]

local Quests = {}

Quests.Daily = {
	{
		id = "daily_spin_100",
		name = "Spin Grinder",
		desc = "Spin 100 cases today",
		type = "spins",
		goal = 100,
		reward = { gems = 200 },
	},
	{
		id = "daily_login",
		name = "Daily Login",
		desc = "Log in today",
		type = "logins",
		goal = 1,
		reward = { gems = 100 },
	},
	{
		id = "daily_elements_5",
		name = "Element Hunter",
		desc = "Unbox 5 elemental mutations",
		type = "effectPulls",
		goal = 5,
		reward = { gems = 300 },
	},
}

Quests.Weekly = {
	{
		id = "weekly_cases_1000",
		name = "Case Grinder",
		desc = "Open 1,000 cases this week",
		type = "casesOpened",
		goal = 1000,
		reward = { gems = 500 },
	},
	{
		id = "weekly_elements_50",
		name = "Mutation Madness",
		desc = "Unbox 50 elemental mutations this week",
		type = "effectPulls",
		goal = 50,
		reward = { gems = 1000 },
	},
	{
		id = "weekly_epic",
		name = "Epic Find",
		desc = "Pull an Epic+ streamer this week",
		type = "epicPulls",
		goal = 1,
		reward = { gems = 350 },
	},
	{
		id = "weekly_legendary",
		name = "Legendary Find",
		desc = "Pull a Legendary+ streamer this week",
		type = "legendaryPulls",
		goal = 1,
		reward = { gems = 350 },
	},
}

Quests.Lifetime = {
	-- Spins
	{
		id = "life_spin_100000",
		name = "100K Spins",
		desc = "Spin 100,000 times total",
		type = "spins",
		goal = 100000,
		reward = { gems = 20000 },
	},

	-- Rebirths
	{
		id = "life_rebirth_5",
		name = "Reborn x5",
		desc = "Reach Rebirth 5",
		type = "rebirths",
		goal = 5,
		reward = { gems = 600 },
	},
	{
		id = "life_rebirth_10",
		name = "Reborn x10",
		desc = "Reach Rebirth 10",
		type = "rebirths",
		goal = 10,
		reward = { gems = 1200 },
	},
	{
		id = "life_rebirth_15",
		name = "Reborn x15",
		desc = "Reach Rebirth 15",
		type = "rebirths",
		goal = 15,
		reward = { gems = 2000 },
	},

	-- Index completion: Default (32 streamers, 1,785 base gems x2 = 3,570)
	{
		id = "life_index_default",
		name = "Default Collector",
		desc = "Complete the Default Index",
		type = "indexDefault",
		goal = 32,
		reward = { gems = 3570 },
	},
	-- Index completion: Acid (x2 multiplier, 1,785 x2 x2 = 7,140)
	{
		id = "life_index_acid",
		name = "Acid Collector",
		desc = "Complete the Acid Index",
		type = "indexAcid",
		goal = 32,
		reward = { gems = 7140 },
	},
	-- Index completion: Snow (x3 multiplier, 1,785 x3 x2 = 10,710)
	{
		id = "life_index_snow",
		name = "Snow Collector",
		desc = "Complete the Snow Index",
		type = "indexSnow",
		goal = 32,
		reward = { gems = 10710 },
	},
	-- Index completion: Lava (x4 multiplier, 1,785 x4 x2 = 14,280)
	{
		id = "life_index_lava",
		name = "Lava Collector",
		desc = "Complete the Lava Index",
		type = "indexLava",
		goal = 32,
		reward = { gems = 14280 },
	},
	-- Index completion: Lightning (x5 multiplier, 1,785 x5 x2 = 17,850)
	{
		id = "life_index_lightning",
		name = "Lightning Collector",
		desc = "Complete the Lightning Index",
		type = "indexLightning",
		goal = 32,
		reward = { gems = 17850 },
	},
	-- Index completion: Shadow (x6 multiplier, 1,785 x6 x2 = 21,420)
	{
		id = "life_index_shadow",
		name = "Shadow Collector",
		desc = "Complete the Shadow Index",
		type = "indexShadow",
		goal = 32,
		reward = { gems = 21420 },
	},
	-- Index completion: Glitchy (x7 multiplier, 1,785 x7 x2 = 24,990)
	{
		id = "life_index_glitchy",
		name = "Glitchy Collector",
		desc = "Complete the Glitchy Index",
		type = "indexGlitchy",
		goal = 32,
		reward = { gems = 24990 },
	},
	-- Index completion: Lunar (x8 multiplier, 1,785 x8 x2 = 28,560)
	{
		id = "life_index_lunar",
		name = "Lunar Collector",
		desc = "Complete the Lunar Index",
		type = "indexLunar",
		goal = 32,
		reward = { gems = 28560 },
	},
	-- Index completion: Solar (x9 multiplier, 1,785 x9 x2 = 32,130)
	{
		id = "life_index_solar",
		name = "Solar Collector",
		desc = "Complete the Solar Index",
		type = "indexSolar",
		goal = 32,
		reward = { gems = 32130 },
	},
	-- Index completion: Void (x10 multiplier, 1,785 x10 x2 = 35,700)
	{
		id = "life_index_void",
		name = "Void Collector",
		desc = "Complete the Void Index",
		type = "indexVoid",
		goal = 32,
		reward = { gems = 35700 },
	},
}

Quests.ById = {}
for _, list in pairs({ Quests.Daily, Quests.Weekly, Quests.Lifetime }) do
	for _, q in ipairs(list) do
		Quests.ById[q.id] = q
	end
end

return Quests
