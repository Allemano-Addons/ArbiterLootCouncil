# Changelog

## 0.3.1-beta
- Fix: the loot window failed to open for the loot master when the boss name was a "secret" text (WoW Forever hides some names). The name is now only used when it is readable; otherwise the zone names the loot.

- Votes, answers and awards now travel in the fast lane of the addon messages, so they no longer wait behind big messages; and your own vote shows at once.
- Trade: with auto trade on, the trade window opens with the winner as soon as you award (when they are near). A winner who is too far away is asked by whisper to come. The trade is also noticed when the game sends no "Trade complete" message (the offered items left your bags).
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
