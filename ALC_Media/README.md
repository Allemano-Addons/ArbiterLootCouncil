# ALC Media

Logo and icons for Arbiter Loot Council. Allemano style: white triangle + green chevron (`#45C97E`).

## Folders

- `Media/` goes into the addon: `ArbiterLootCouncil/Media/...`
  - `Icons/*.tga`: 64×64, white on transparent. Tint them in Lua.
  - `Logo/alc_mark_{64,128,256}.tga`: two-color mark.
  - `Logo/alc_mark_white_*.tga`: all-white mark, for tinting.
  - `Logo/alc_minimap.tga`: round minimap button, 64×64.
- `PNG/`: for CurseForge, Discord and the site. `logo/alc_curseforge_400.png` is the project avatar.
- `Source/`: SVG originals. Change these and re-export.

All TGA files are 32-bit with alpha, uncompressed, and power-of-two sizes.

## Usage in Lua

```lua
local MEDIA = "Interface\\AddOns\\ArbiterLootCouncil\\Media\\"
local GREEN = { 0.271, 0.788, 0.494 } -- #45C97E

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetSize(16, 16)
icon:SetTexture(MEDIA .. "Icons\\history")   -- no file extension

-- inactive tab
icon:SetVertexColor(0.91, 0.91, 0.89)
-- active tab
icon:SetVertexColor(unpack(GREEN))
```

Use the icons at 16–20 px in the UI. The 64 px texture scales down cleanly.

## Icons

council, history, summary, trade, settings, vote, award, loot, blind_vote, quorum, note, disenchant, revote, bank, addon_check, warning
