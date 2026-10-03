# Changelog

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
