// One-off: compute rarity chances vs luck multiplier (same formula as SpinService)
const LOG_MAX = Math.log(1e7);
const streamers = [
  { odds: 2, rarity: "Common" }, { odds: 5, rarity: "Common" }, { odds: 7, rarity: "Common" },
  { odds: 12, rarity: "Common" }, { odds: 20, rarity: "Common" }, { odds: 22, rarity: "Common" },
  { odds: 40, rarity: "Rare" }, { odds: 50, rarity: "Rare" }, { odds: 100, rarity: "Rare" },
  { odds: 200, rarity: "Rare" }, { odds: 500, rarity: "Rare" }, { odds: 1000, rarity: "Rare" },
  { odds: 2000, rarity: "Epic" }, { odds: 5000, rarity: "Epic" }, { odds: 8500, rarity: "Epic" },
  { odds: 13000, rarity: "Epic" }, { odds: 23000, rarity: "Epic" }, { odds: 36000, rarity: "Epic" },
  { odds: 100000, rarity: "Legendary" }, { odds: 500000, rarity: "Legendary" }, { odds: 1000000, rarity: "Legendary" },
  { odds: 5000000, rarity: "Mythic" }, { odds: 10000000, rarity: "Mythic" },
];

function weight(odds, L) {
  let w = 1 / odds;
  if (L > 1) {
    let rf = Math.log(Math.max(odds, 1)) / LOG_MAX;
    rf = Math.max(0, Math.min(1, rf));
    w *= Math.pow(L, 1 + rf);
  }
  return w;
}

function getChances(L) {
  const weights = streamers.map(s => weight(s.odds, L));
  const total = weights.reduce((a, b) => a + b, 0);
  const byRarity = { Common: 0, Rare: 0, Epic: 0, Legendary: 0, Mythic: 0 };
  streamers.forEach((s, i) => { byRarity[s.rarity] += weights[i] / total; });
  return byRarity;
}

// Player luck: 0, 100, 200, ... 2000. With Case 7 (2.5): mult = 1 + luck/20/100 + 2.5 = 3.5 + luck/2000
// Also show "Rare or better", "Epic or better", etc.
console.log("Luck mult | Common  | Rare   | Epic    | Legendary | Mythic   | Rare+   | Epic+   | Leg+");
console.log("---------|---------|--------|---------|-----------|----------|---------|--------|------");

for (const L of [1, 1.5, 2, 2.5, 3, 3.55, 4, 5, 6, 8, 10, 15, 20, 30, 50]) {
  const c = getChances(L);
  const rarePlus = c.Rare + c.Epic + c.Legendary + c.Mythic;
  const epicPlus = c.Epic + c.Legendary + c.Mythic;
  const legPlus = c.Legendary + c.Mythic;
  console.log(
    L.toFixed(2).padStart(8) + " | " +
    (c.Common * 100).toFixed(1).padStart(6) + "% | " +
    (c.Rare * 100).toFixed(1).padStart(5) + "% | " +
    (c.Epic * 100).toFixed(2).padStart(6) + "% | " +
    (c.Legendary * 100).toFixed(3).padStart(8) + "% | " +
    (c.Mythic * 100).toFixed(4).padStart(7) + "% | " +
    (rarePlus * 100).toFixed(1).padStart(6) + "% | " +
    (epicPlus * 100).toFixed(2).padStart(6) + "% | " +
    (legPlus * 100).toFixed(3).padStart(5) + "%"
  );
}

console.log("\n--- Player luck (with Case 7 = 250% crate) ---");
console.log("Player luck | Total mult | Common  | Rare+   | Epic+    | Leg+");
for (const luck of [0, 100, 200, 300, 400, 500, 600, 800, 1000, 1500, 2000, 3000, 5000]) {
  const playerPercent = Math.floor(luck / 20) / 100;
  const L = 1 + playerPercent + 2.5;
  const c = getChances(L);
  const rarePlus = (c.Rare + c.Epic + c.Legendary + c.Mythic) * 100;
  const epicPlus = (c.Epic + c.Legendary + c.Mythic) * 100;
  const legPlus = (c.Legendary + c.Mythic) * 100;
  console.log(
    String(luck).padStart(11) + " | " + L.toFixed(2).padStart(10) + " | " +
    (c.Common * 100).toFixed(1).padStart(6) + "% | " +
    rarePlus.toFixed(1).padStart(6) + "% | " +
    epicPlus.toFixed(2).padStart(7) + "% | " +
    legPlus.toFixed(3).padStart(6) + "%"
  );
}
