--[[
	DailyRewards.lua
	7-day login streak rewards. Day 7 is the "jackpot" day, then the
	cycle resets. Missing a day resets the streak to 1.
]]

local DailyRewards = {}

DailyRewards.Rewards = {
	[1] = { cash = 5000,      gems = 50,   label = "Day 1" },
	[2] = { cash = 10000,     gems = 75,   label = "Day 2" },
	[3] = { cash = 20000,     gems = 100,  label = "Day 3" },
	[4] = { cash = 40000,     gems = 150,  label = "Day 4" },
	[5] = { cash = 75000,     gems = 200,  label = "Day 5" },
	[6] = { cash = 150000,    gems = 300,  label = "Day 6" },
	[7] = { cash = 500000,    gems = 750,  spinCredits = 10, label = "Day 7 JACKPOT" },
}

DailyRewards.MaxStreak = 7

return DailyRewards
