Arbiter Loot Council (ALC) 0.3.4-beta - test build
NOTE: this version cannot talk to 0.1.x. Everybody in the raid needs the same version;
a player with the old one is named in chat when the addon notices.
Part of Allemano Addons. For WoW Forever.

INSTALL
  Unzip so that the folder "ArbiterLootCouncil" ends up in
  ...\World of Warcraft\_classic_beta_\Interface\AddOns\
  Restart the game (a /reload does not find a new addon). Everybody in the
  raid who should answer needs the addon.

QUICK START
  Loot master:
    /alc council add <First Last>   who is on the council (once, before raid)
    /alc add [item link]            put an item in the loot list (loot from bosses is added by itself)
    Click Start on an item in the loot window, or Start all for one session with every
    waiting item (up to 30). The council window then shows the items as icons to the left:
    click one to see its candidates. Each item is awarded on its own; the session ends
    with the last one, or with Stop session / Cancel session.
  Everybody: answer in the "Loot response" window (BiS, Upgrade, Minor, Offspec, Pass), one row per item.
  Council: vote in the council window (/alc vote). Loot master: Award.
  Solo test: /alc test         (/alc test 5 uses the five best items in your bags)

USEFUL
  /alc            list all commands
  /alc menu       window menu (also the square button by the minimap)
  /alc settings   council list, loot quality, font, and more
  /alc history    awards so far        /alc trades   items still to be traded
  /alc debug versions   see who has the addon and which version

SOMETHING WRONG?
  Tell us what you did and send:
    1. /alc debug log   (and copy the lines)
    2. any error text from BugSack
    3. a screenshot if something looks wrong
