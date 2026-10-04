# Changelog

## 0.5.2-beta
- Fix: "Trade complete." could cause a Lua error ("attempt to compare ... a secret string value") when the game hid the message as a secret text, and the trade was then not marked as delivered in the Trade Queue. The message is now only compared when it is readable.

## 0.5.1-beta
- Tells Allemano Hub what the session is doing (when the Hub is installed): a session started or ended, an award given or taken back, a pause, the answer timer running out, items added. The lines show up under "Recent activity" in the Hub's problem report, so a bug report says what happened before. Nothing changes when the Hub is not installed.

## 0.5.0-beta
- **Arbiter Context.** Click a candidate in the Council window and a box opens beside the window (to the right, or to the left when the screen is too narrow); click the same row again, or the × in the box, to close it. It shows:
  - what is on the row, in full: rank, answer, roll, votes (and who voted), the whole note;
  - the item, its slot and level, what the player wears in that slot and the level difference (or that the slot is empty);
  - **the same slot**, in an amber panel: if the item is a weapon and the player has been awarded a weapon before, it says which, when and with what answer (the red "Has already won this item" when it is the very same item, and green when there is no loot in that slot yet);
  - the **loot history**, newest first, each award with its item, the answer the player gave, the zone and a tag: **TONIGHT** (the same raid night: awards less than four hours apart), **this week** or the date, with **same slot** and **same item** marked, and a summary (awards in 7, 14 and 30 days);
  - a line from the addon the session runs in, when it has one (Soft Reserve: "Reserved this item: Yes (SR, one of 3)").
  Items the game has not got in memory yet (loot from an older raid) show "Loading..." for a moment and fill in by themselves. The loot master reads the history from the award log; a council member asks the loot master for it (a new message, HISTORY, the latest 30 awards of one player), so every council member needs this version to see the history. Disenchant awards and awards taken back are not counted. (For addons built on ALC: `ALC.RegisterContextProvider` adds lines to the box, which is where attendance from OXM can go later.)
- **Arbiter Compare.** Hold Ctrl and click a second row and the box turns into two columns, one per player, with one line per fact: answer, roll, votes, note, what is worn, the upgrade in item levels, the same slot, loot tonight / in 7 / in 30 days / in all, lines from the addon the session runs in (Soft Reserve) and the latest loot. The higher roll, the higher vote count and an empty or upgraded slot are shown in green. Ctrl-click one of the two again to let it go; the × goes back to the single box.
- **Settings is easier to take in.** The long Loot master tab is split in two: **Loot** (the council list, loot threshold, loot window, auto loot, auto trade, the disenchanter) and **Session** (random rolls, the warning about players without the addon, recent awards, the answer timer, the award log and Soft Reserve's settings). Five tabs now.
- **Show passed** and **Compact rows** in the Council window's footer are smaller and further apart, with switches drawn with corners that fit their size.
- **The award log can be trimmed and you are reminded before it gets long.** Settings, Loot master: "Remind me to export the award log at" (never, 500, 1000 or 2000 awards; 1000 by default) and "Keep the newest 500 awards" (click twice). The older awards go to the same backup a cleared history uses, so Award history can restore them. `/alc log` says how many awards there are and `/alc log trim <n>` keeps the newest n.

## 0.4.5-beta
- **A Results button in the Loot Response window.** Every player can open the results from the window they answer in. With Arbiter Soft Reserve it opens its results of the last sessions; without, ALC's own Result window with the rolls of the running session. (For addons built on ALC: `ALC.RegisterResultsViewer` and `ALC.OpenResults`.)
- **A warning about players without the addon.** When you start a session, ALC asks the group who has it and, a few seconds later, the chat says which players did not reply ("Kaelis Moo did not reply to the version check. They may not have Arbiter Loot Council, so they cannot answer."). Settings, Loot master: "Warn about players without the addon" (on by default). Nothing is said when you are alone.
- **The Loot window shows what an addon knows about an item.** An addon built on ALC can give its start mode an `info` function: Soft Reserve's "SR x3" now sits on the item's line (in purple), and its **Start SR** button gets an amber frame, so it is clear which items go as soft reserve.
- **"Your roll" in the player's Loot Response window.** After the loot master's addon has rolled (Soft Reserve), the row of an item shows what you rolled and who leads ("Your roll: 23. Allemano Moo won with 87."), "You won! Your roll: 87 (Soft reserve)", "You passed." or "You did not answer: no roll." instead of the answer buttons, which are closed by then. A reopened item gets its buttons back.
- Other addons can add a section to the Settings window (API 5: `ALC.RegisterSettingsSection`): a heading in their colour and rows drawn in ALC's own style (switches, choices of buttons and action buttons, with an optional "click again" question), on the Everyone or the Loot master tab. Arbiter Soft Reserve uses it. Without such an addon the Settings window is unchanged.

## 0.4.4-beta
- Fix: in a Soft Reserve session the mark in the Loot Response window was purple all over. It is now like the Soft Reserve mark: only the lower part of the A is purple and the upper part stays white. (A new picture, Media/Logo/alc_mark_accent_64.tga, made by Tools/make_accent.lua, holds the part that is tinted.)

## 0.4.3-beta
- When every item of a session has been awarded the Loot window says "All awarded. The session closes by itself." instead of "In session": the session stays open for 90 seconds so that an award can be undone, which made it look as if it was still running.

## 0.4.2-beta
- **An item a winner gives back can go in the list again.** When a player you awarded an item to trades it back to you (you are the loot master), the Loot window shows a bar: "<name> gave back <item>" with **Add** (puts it in the list as a new waiting item) and **x** (leave it). It only reacts to an item that player was awarded in the last week, once per award, and the chat tells you too. No command needed.
- Windows are more compact: the title row of every window is lower (40 px, the voting window 46 px), the voting window's title is one line, the Settings window is shorter (the council list shows three names and scrolls) and the winner's name in the Loot window has its class colour.
- The Result window says when an item was handed to a player for disenchanting: that player's row says "Disenchanted", and the item's line reads "Disenchanted by <name>" instead of "Nobody". It is a new optional flag on a result row, which versions without it ignore (they show the row as a Pass). Arbiter Soft Reserve sends it.

## 0.4.1-beta
- **Start LC and Start SR.** When Arbiter Soft Reserve is installed, every item in the Loot window gets two buttons: **Start LC** (a normal Loot Council session, as always) and **Start SR** (a soft reserve session). The footer has **Start all LC** and **Start all SR** in the same way. Without Arbiter Soft Reserve the window looks and works exactly as before ("Start", "Start all").
- A session started by Arbiter Soft Reserve now looks like it: the Loot Response window the players see says "SOFT RESERVE RESPONSE" with the purple mark, and the item in the loot master's Loot window gets a purple frame while it is in session. Players with an older version, or without Arbiter Soft Reserve, see the name and colour too (they travel with the session); a normal Loot Council session is unchanged.
- The Result window can show a player who reserved an item and never answered ("Did not answer", no roll). Such a row travels as a Pass with a new flag, so versions without it show "Passed".
- The window menu of the minimap button can hold the rows of other addons, under a heading of their own (Arbiter Soft Reserve adds Results, Session and Import list). Without such an addon the menu is unchanged.
- For addons built on ALC (API 5): `ALC.RegisterLauncherEntry` adds a row to the window menu, and `ALC.RegisterStartMode` adds a way to start a session to the Loot window, and `Sessions:StartItems` takes `modeName` and `modeColor` next to `mode`.

## 0.4.0-beta
- A small API for other addons to build on Arbiter Loot Council. Arbiter Soft Reserve is the first. **A normal Loot Council session works exactly as before**; everything below only appears when an addon built on ALC uses it.
- Such an addon can start a session with its own answer buttons and attach a short tag and data to each item. The response window shows the tag (Soft Reserve: "SR" in front of the items you reserved). A session started this way does not open the voting window by itself (it can still be opened from the menu).
- A new Result window (`/alc results`) shows everybody the outcome of items decided by rolls: every player's answer, roll and result, so the ones who lose can see it was fair. It opens by itself for the players when the first result arrives.
- "Award all": one question that hands out a whole list of winners, one after the other, with the usual announcement, history and trade queue.
- Players with an older version can still answer as before; they just do not see the new windows or tags.
- No change to the protocol version: the new message is ignored by older versions.

## 0.3.4-beta
- Credits and licenses added (a CREDITS.md in the addon, and the Ace3 license text next to the libraries). No changes to the addon itself: it works exactly as 0.3.3.

## 0.3.3-beta
- Trade: from a stack (two Shadowgems, say) only one item is put into the trade for each award, not the whole stack.
- The loot window no longer shows the box with the last chat announcement.
- Fix: rows made in the background showed up as empty white boxes under the loot window; they now stay hidden until they have something to show.
- Fix: "script ran too long" when a window was opened the first time. The loot, response and voting windows now make only the rows they need at once (a handful) and the rest of their rows a few at a time in the background, instead of everything in one long script.

## 0.3.2-beta
- Fix: messages from the loot master could overtake each other on the way (an award passing a vote count, say) and the later-numbered one then made the earlier be thrown away. That is likely why council members did not see an award ("Awarded to ...") or the end of the session, and why their history stayed empty. A number is now accepted once while it is near the newest, and an old count never replaces a newer one.
- The game's own loot threshold (the one on the player frame) now follows ALC's threshold when the group leader changes it.
- Auto loot: when you open a corpse as master looter, the items at or above the threshold can be given to yourself so they are in your bags before the session starts. A box asks "Loot all N item(s) for yourself?" first. Settings > Loot master has a checkbox for auto loot (on by default) and one for the question (on by default).
- Much tighter Compact windows: lower rows in the loot, response and voting windows, and the History shows one tight line per award. Settings > Everyone has a new Window size (70, 80, 90 or 100%) that scales every window.
- Voting window: the item panel at the top is about 30 px lower (smaller icon, the buttons Disenchant, Pause and Stop session in one row, the answer counter and bar beneath them).
- Loot window: a thin countdown bar along each Bind-on-Pickup item shows how much of its trade window is left (the text is shorter: "BoP 3h 52m").
- Fix: the answer counter ("3/4 responded") counted yourself twice in a raid, so it said 3/4 in a raid of three.
- The BoP trade window is 4 hours (it was 2). The time left is now read from the item's own tooltip in your bags, so it counts from when the item was looted (not from when it was listed). An item that is not in your bags has no timer yet.
- The trade queue now notices a delivery also when the game gives no accept events or "Trade complete" message: it compares your bags before and after the trade. Everything about a trade goes to /alc debug log.
- The History tab says that only the council sees the history.
- The BoP trade timer also works for items added by hand, as long as they are in your bags.

## 0.3.1-beta
- Fix: the loot window failed to open for the loot master when the boss name was a "secret" text (WoW Forever hides some names). The name is now only used when it is readable; otherwise the zone names the loot.

- Votes, answers and awards now travel in the fast lane of the addon messages, so they no longer wait behind big messages; and your own vote shows at once.
- Trade: with auto trade on, the trade window opens with the winner as soon as you award (when they are near). A winner who is too far away is asked by whisper to come. The trade is also noticed when the game sends no "Trade complete" message (the offered items left your bags).
- BoP timer: a looted Bind-on-Pickup item shows how long it can still be traded to the raid (2 hours), in the loot window and the trade queue; orange under 30 minutes, red under 10.
- The loot threshold offers only Uncommon, Rare and Epic (the qualities that drop). An older saved Poor, Common or Legendary becomes the nearest one.
- Settings > Council shows who is on the council (this session, or the last one). The trade queue tells council members that it is for the loot master only.
- Council window: players in the group who have not answered an item yet are listed last, greyed, as "Waiting", so the council sees who is missing.
- The loot window no longer shows the boss name in its title.
- Every trade that goes through is named in the chat ("[Item] handed to Name", to the raid or party when announcing is on) and noted in the award log, also when the trade queue did not hold the item. An item handed out by the game itself is noted too.
- History: council members now keep the history too (what the loot master awards is logged on their side, and an undo marks it).

## 0.3.0-beta
Everybody in the raid who answers or votes should update to this version together.

New for the loot master
- Answer timer: the response window can close by itself after a set time (Settings > Loot master, 30-300 seconds).
- Won items are put into the trade window automatically when you trade with the winner (can be turned off).
- Undo award: take back an award for 90 seconds after it, and the trade queue follows.
- Pause / Resume a session (`/alc pause`).
- Random rolls: the loot master can add a roll to every response, shown as a column in the council window.
- Award to Disenchant (a button, `/alc de`, and a setting for who disenchants).
- Announce awards in raid or party chat can be turned on or off, with clearer text.
- "Clear done" in the loot window.

New for the council
- Recent awards column: see what each player has already won (hover for the list). The window can show 7, 14, 30 or 90 days.
- Session-running dot on the minimap button and the launcher.
- Compact windows: one setting for the loot, response and council windows.

History
- A date list with search, Export to a copyable text (CSV), and Clear per date with a backup you can bring back
  (`/alc history restore`).
- Filter by All / 7 / 14 / 30 / 90 days.

Other
- `/alc versions` opens a window that shows who in the raid has which version of ALC.
- `/alc test [items] [players]` starts a session with made-up players, for trying the windows alone.
- Launcher button and addon-list icon match the other Allemano addons.
- A note field for every item in the response window; the note is sent when you leave the field.
- Fix: the council window did not load in the game on some builds (too many variables in one function).

## 0.2.0-alpha2
First public test build: loot sessions, responses, council voting, awards, trade queue and history.
