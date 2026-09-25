# AtlasLootHD

AtlasLoot Enhanced v5.11.04 for WoW 3.3.5 (Wrath of the Lich King), with the loot browser redesigned to match the layout of modern AtlasLoot.

## What's different

The standalone browser (`/al`) now has:

- Select Module and Select Subcategory dropdowns
- The loot table under the boss name, with item icons bordered in their quality color
- Items missing from the client's cache are queried from the server automatically, once, when their page is shown (no Query Server button needed)
- A difficulty list (Normal/Heroic, 10/25 Man) that stays selected as you move between bosses
- A scrolling boss list
- A quick access list for the wishlist, the last search and QuickLooks 1-4 (right-click a QuickLook to save the current loot table)

The loot view inside Atlas is unchanged.

## Install

Copy these folders into `World of Warcraft/Interface/AddOns/`:

- `AtlasLoot`
- `AtlasLootFu`
- `AtlasLoot_BurningCrusade`
- `AtlasLoot_Crafting`
- `AtlasLoot_OriginalWoW`
- `AtlasLoot_WorldEvents`
- `AtlasLoot_WrathoftheLichKing`

## Versioning

The AtlasLootHD version is the `## Version:` line in `AtlasLoot/AtlasLoot.toc`. It shows in the browser's title bar, the options panel and the minimap button tooltip. The upstream AtlasLoot Enhanced version it's based on is kept in `## X-Upstream-Version:`.

A pre-commit hook bumps the patch number on every commit (1.0.0, 1.0.1, 1.0.2, ...). Enable it once after cloning:

```sh
git config core.hooksPath .githooks
```

For a bigger release, edit the TOC by hand (for example to `1.1.0`); the next commit becomes `1.1.1`. Use `git commit --no-verify` to commit without a bump.

## Credits and license

AtlasLoot Enhanced is by Hegarol, Daviesh and the AtlasLoot team. This fork is released under the same GPL v2 license; see [AtlasLoot/Documentation/LICENSE.txt](AtlasLoot/Documentation/LICENSE.txt).
