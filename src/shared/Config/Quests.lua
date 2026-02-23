--[[
	Quests.lua
	Daily, Weekly, and Lifetime quest definitions.
	Daily quests reset every 24h. Weekly quests reset every 7 days.
	Lifetime quests are one-time achievements.

	Quest types (match what the server tracks):
	  spins       – total spins performed
	  sells       – total streamers sold
	  rebirths    – total rebirths performed
	  gemsEarned  – total gems earned
	  cashEarned  – total cash earned
	  epicPulls   – Epic+ streamer pulls
	  legendaryPulls – Legendary+ pulls
	  mythicPulls – Mythic pulls
	  effectPulls – any elemental streamer pulls
	  potionsBought – potions purchased
	  sacrificesDone – any sacrifice performed
	  casesOpened – gem cases opened
	  indexClaimed – index entries claimed
]]

local Quests = {}

Quests.Daily = {
	{
		id = "daily_spin_50",
		name = "Spin Enthusiast",
		desc = "Spin 50 times today",
		type = "spins",
		goal = 50,
		reward = { cash = 25000, gems = 50 },
	},
	{
		id = "daily_sell_20",
		name = "Spring Cleaning",
		desc = "Sell 20 streamers",
		type = "sells",
		goal = 20,
		reward = { cash = 15000 },
	},
	{
		id = "daily_earn_100k",
		name = "Cash Collector",
		desc = "Earn $100K total",
		type = "cashEarned",
		goal = 100000,
		reward = { gems = 75 },
	},
	{
		id = "daily_epic_pull",
		name = "Epic Finder",
		desc = "Pull an Epic or better streamer",
		type = "epicPulls",
		goal = 1,
		reward = { cash = 50000, gems = 30 },
	},
	{
		id = "daily_potion",
		name = "Brew Master",
		desc = "Buy 2 potions",
		type = "potionsBought",
		goal = 2,
		reward = { cash = 20000 },
	},
}

Quests.Weekly = {
	{
		id = "weekly_spin_500",
		name = "Spin Maniac",
		desc = "Spin 500 times this week",
		type = "spins",
		goal = 500,
		reward = { cash = 250000, gems = 300 },
	},
	{
		id = "weekly_sell_100",
		name = "Bulk Liquidation",
		desc = "Sell 100 streamers this week",
		type = "sells",
		goal = 100,
		reward = { cash = 150000, gems = 200 },
	},
	{
		id = "weekly_legendary",
		name = "Legendary Hunter",
		desc = "Pull a Legendary or better streamer",
		type = "legendaryPulls",
		goal = 1,
		reward = { cash = 500000, gems = 500 },
	},
	{
		id = "weekly_rebirth",
		name = "Born Again",
		desc = "Rebirth once this week",
		type = "rebirths",
		goal = 1,
		reward = { gems = 400 },
	},
	{
		id = "weekly_sacrifice",
		name = "Offering",
		desc = "Complete 5 sacrifices this week",
		type = "sacrificesDone",
		goal = 5,
		reward = { gems = 350, cash = 100000 },
	},
	{
		id = "weekly_cases_10",
		name = "Case Cracker",
		desc = "Open 10 gem cases this week",
		type = "casesOpened",
		goal = 10,
		reward = { gems = 400 },
	},
}

Quests.Lifetime = {
	{
		id = "life_spin_1000",
		name = "1K Spins",
		desc = "Spin 1,000 times total",
		type = "spins",
		goal = 1000,
		reward = { gems = 500 },
	},
	{
		id = "life_spin_10000",
		name = "10K Spins",
		desc = "Spin 10,000 times total",
		type = "spins",
		goal = 10000,
		reward = { gems = 2000 },
	},
	{
		id = "life_spin_100000",
		name = "100K Spins",
		desc = "Spin 100,000 times total",
		type = "spins",
		goal = 100000,
		reward = { gems = 10000 },
	},
	{
		id = "life_rebirth_5",
		name = "Reborn x5",
		desc = "Reach Rebirth 5",
		type = "rebirths",
		goal = 5,
		reward = { gems = 750 },
	},
	{
		id = "life_rebirth_10",
		name = "Reborn x10",
		desc = "Reach Rebirth 10",
		type = "rebirths",
		goal = 10,
		reward = { gems = 2000 },
	},
	{
		id = "life_rebirth_19",
		name = "Maxed Out",
		desc = "Reach Rebirth 19 (MAX)",
		type = "rebirths",
		goal = 19,
		reward = { gems = 10000 },
	},
	{
		id = "life_mythic_1",
		name = "Mythic Pull",
		desc = "Pull your first Mythic streamer",
		type = "mythicPulls",
		goal = 1,
		reward = { gems = 1000 },
	},
	{
		id = "life_mythic_10",
		name = "Mythic Collector",
		desc = "Pull 10 Mythic streamers",
		type = "mythicPulls",
		goal = 10,
		reward = { gems = 5000 },
	},
	{
		id = "life_effect_50",
		name = "Elemental Master",
		desc = "Pull 50 elemental streamers",
		type = "effectPulls",
		goal = 50,
		reward = { gems = 3000 },
	},
	{
		id = "life_index_50",
		name = "Half Indexed",
		desc = "Claim 50 Index entries",
		type = "indexClaimed",
		goal = 50,
		reward = { gems = 2000 },
	},
	{
		id = "life_gems_50k",
		name = "Gem Hoarder",
		desc = "Earn 50,000 gems total",
		type = "gemsEarned",
		goal = 50000,
		reward = { cash = 5000000 },
	},
}

Quests.ById = {}
for _, list in pairs({ Quests.Daily, Quests.Weekly, Quests.Lifetime }) do
	for _, q in ipairs(list) do
		Quests.ById[q.id] = q
	end
end

return Quests
