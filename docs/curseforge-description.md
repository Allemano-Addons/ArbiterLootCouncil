# Arbiter Loot Council

**Run a loot council in WoW Forever without the spreadsheet.** ALC takes an item from the boss's corpse to the raider who deserves it: the loot master starts a session, every raider answers in a small window, the council votes, one click awards the item and the trade is queued and logged.

> **Beta (0.3.3-beta).** ALC is new and being tested in real raids. **Everybody in the raid who should answer or vote needs the same version**, and this version cannot talk to 0.1.x. If someone has another version the addon says so in chat.

## How a loot decision works in ALC

1. **Loot is detected.** Items from bosses that meet your quality threshold (epic by default) are added to the loot master's list automatically. You can also add an item by hand with `/alc add [item link]`.
2. **The loot master starts a session** for one item, or with **Start all** for up to 30 items in one session.
3. **Every raider answers** in a small "Loot response" window, one row per item: **BiS, Upgrade, Minor, Offspec** or **Pass**. They can add a short note ("replaces my trinket"). You can change the buttons: 2 to 8 custom answers, with your own names and colors.
4. **The council votes.** The council window shows every candidate with their answer, note, **guild rank** and the **equipped items the new one would replace** (sent with the response, so the council can compare), and lets you sort by response or rank. Vote with one click; the votes are shared with the council as they come in.
5. **The loot master awards** the item to the winner. Awarded items that still have to be handed over wait in a **Trade Queue** tab (`/alc trades`), so nothing is forgotten after the boss.
6. **Everything is logged.** The **History** tab (`/alc history`) keeps who got what, with which answer and label, so you can look back at any raid.

*Example:* Tier boss drops three items. You click **Start all**, the raid answers in a minute, the council goes through the item strip on the left of the window one item at a time, and you award each one. The session ends with the last item.

## What makes it practical

- **Multi-item sessions:** an item strip (item icons) to the left of the council window; click an icon to see that item's candidates, votes and award. Each item is awarded on its own.
- **Loot master aware:** the loot master is the master looter if master loot is on, otherwise the raid leader. If the loot master reloads the UI during a session, ALC recovers the session.
- **Council setup:** add council members by name once (`/alc council add <First Last>`) and they stay in your settings. Candidates' answers and votes are sent to the council only.
- **Right-click menu** on a candidate: vote, award, change response, remove (counts as pass). **Show passed** brings the passes back into the list.
- **Stop or cancel a session** safely (Stop session asks for a second click).
- **Version check:** `/alc debug versions` shows who has the addon and which version, so you find the raider who forgot to update before the boss, not after.
- **Try it alone:** `/alc test` runs a session with test items (`/alc test 5` uses the five best items in your bags), so you can practice the flow before raid night.

## Settings
`/alc settings` (or the square button by the minimap, or the launcher): who is on the council, loot quality threshold, custom answer buttons, font and more. The settings are split into four tabs: Everyone, Council, Loot master and Buttons.

## Commands
- `/alc` lists all commands, `/alc menu` opens the window menu
- `/alc council add <First Last>` adds a council member
- `/alc add [item link]` adds an item to the loot list
- `/alc vote` opens the voting window
- `/alc history` shows the awards so far, `/alc trades` shows items still to be traded
- `/alc debug log` and `/alc debug versions` for troubleshooting

## Installing manually (WoW Forever)
ALC is made for WoW Forever (interface 16001). If the CurseForge app does not install it into the right folder, download the file from the **Files** tab and unzip it so that the folder is `World of Warcraft\_classic_beta_\Interface\AddOns\ArbiterLootCouncil`. **Restart the game completely** (a `/reload` does not find a new addon). Everybody in the raid who should answer needs the addon.

## Something wrong?
Tell us what you did and send the lines from `/alc debug log`, any error text from BugSack, and a screenshot if something looks wrong. Source code and issues will be at the GitHub page of Allemano Addons.

Part of **Allemano Addons**. Uses the Ace3 libraries (embedded), which have their own licenses.
