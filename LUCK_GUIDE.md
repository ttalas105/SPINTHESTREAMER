# Luck guide: what luck for Rare / Epic / Legendary / Mythic?

Luck multiplies drop weights so **rarer streamers get a bigger boost** than commons. Your **total luck multiplier** is:

- **Total mult** = `1 + (player luck %) + (crate luck %)`
- **Player luck %** = 1% per 20 luck (e.g. 100 luck = 5%, 1000 luck = 50%)
- **Crate 7** = +250% → adds 2.5 to the formula

So with **Case 7** and **0 player luck**: mult = 1 + 0 + 2.5 = **3.55**.  
With **Case 7** and **1000 luck** (50%): mult = 1 + 0.5 + 2.5 = **4.0**.

---

## Rough targets (use **Case 7** for best results)

| Goal | Player luck (approx) | What you get |
|------|----------------------|--------------|
| **Rare or better “often”** (e.g. 15–25% of pulls) | **400–800** | Rare+ chance clearly higher than base; still mostly Common. |
| **Rare+ “consistent”** (e.g. 25–35% of pulls) | **1,000–2,000** | Around 1 in 3–4 pulls Rare or better. |
| **Epic or better showing up regularly** (e.g. 2–5% of pulls) | **1,500–3,000** | Epics become a realistic goal. |
| **Legendary / Mythic “sometimes”** (e.g. 0.1%+ Leg, 0.01%+ Mythic) | **3,000+** | Still rare, but noticeably more often than at low luck. |

So in short:

- **Rare:** aim for **~600–1,000+** luck with Case 7 to see Rares consistently.
- **Epic:** **~1,500–2,000+** luck with Case 7 to get Epics regularly.
- **Legendary:** **~3,000+** luck to see them sometimes.
- **Mythic:** same as Legendary range; they stay very rare but scale up with high luck.

Without Case 7, you need more player luck to hit the same total mult (e.g. 250% from Case 7 ≈ 5,000 player luck at 1% per 20).

---

## Exact numbers in Studio

In Roblox Studio **Command Bar** run:

```lua
require(game:GetService("ReplicatedStorage").Shared.LuckChances).PrintLuckTable()
```

This prints tables of **luck multiplier** and **player luck (with Case 7)** vs **Common / Rare / Epic / Legendary / Mythic** and **Rare+** / **Epic+** chances so you can tune to your liking.
