# Rojo Sync Troubleshooting

If you pulled the latest code but **don't see the new changes in Roblox Studio**, follow these steps in order.

## 1. Confirm files on disk

- Open the project folder in File Explorer.
- Check that `src/client/controllers/HoldController.lua` exists.
- If it’s missing, run `git pull` again from the project root.

## 2. Restart Rojo (important)

Rojo often doesn’t pick up **new files** until it’s restarted.

1. In the terminal where `rojo serve` is running, stop it with **Ctrl+C**.
2. Go to the project root (the folder that contains `default.project.json`).
3. Start Rojo again:
   ```bash
   rojo serve
   ```
4. Wait until you see something like: `Rojo is listening on 127.0.0.1:34872`.

## 3. Resync in Roblox Studio

1. In Roblox Studio, open the **Rojo** plugin.
2. If it says "Connected", click **Disconnect**.
3. Click **Connect** again and choose the correct server (e.g. `127.0.0.1:34872`).
4. Wait for the sync to finish.

## 4. Check where things synced

- **StarterPlayer → StarterPlayerScripts** should contain `Main.client.lua` and a `controllers` folder.
- Inside `controllers` you should see **HoldController** (and the other controllers).

If HoldController (or other new scripts) are still missing after this, try:

- Closing the place in Studio and opening it again (or creating a new Baseplate and connecting Rojo to that).
- Making sure no other Rojo server is running (only one terminal with `rojo serve`).
- Running `rojo serve` from the **exact folder** that contains `default.project.json`.

## Quick checklist

- [ ] `git pull` was run.
- [ ] Rojo was **restarted** after pulling (Ctrl+C, then `rojo serve`).
- [ ] Rojo was started from the project root (where `default.project.json` is).
- [ ] In Studio, Rojo was disconnected then reconnected.
- [ ] You’re looking at the same place that Rojo is syncing into.
