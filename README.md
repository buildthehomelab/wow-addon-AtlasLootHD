# AtlasLootHD

AtlasLoot Enhanced v5.11.04 for WoW 3.3.5 (Wrath of the Lich King), with the loot browser redesigned to match the layout of modern AtlasLoot.

## What's different

The standalone browser (`/al`) now has:

- A modern theme built from stock 3.3.5 art: a dark metal frame, and the loot table on a parchment page like a spellbook, with item colors darkened to stay readable. The Loot Browser Style option switches the page back to dark (Classic Style).
- Select Module and Select Subcategory dropdowns, and a search box beside them
- The loot table under the boss name, with item icons framed in their quality color and a page counter for tables split over several pages
- Items missing from the client's cache are queried from the server automatically, once, when their page is shown (no Query Server button needed)
- A right-hand column with Difficulty (Normal/Heroic, 10/25 Man, which stays selected as you move between bosses), a scrolling Bosses list, and Quick Access to the wishlist, the last search and QuickLooks 1-4 (right-click a QuickLook to save the current loot table)

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

The version keeps a `v` prefix (`v1.0.2`). Atlas compares module versions as plain strings and disables AtlasLoot if its version sorts below `5.11.03`; a leading `v` sorts after any digit, so the check always passes.

A pre-commit hook bumps the patch number on every commit (v1.0.2, v1.0.3, ...) and refuses the commit if the version would fail the Atlas check. Enable it once after cloning:

```sh
git config core.hooksPath .githooks
```

For a bigger release, edit the TOC by hand (for example to `v1.1.0`); the next commit becomes `v1.1.1`. Use `git commit --no-verify` to commit without a bump.

[CHANGELOG.md](CHANGELOG.md) lists every version. A post-commit hook adds each commit's subject under its version and amends the changelog into that commit, so write subjects that read well there. Rebases, cherry-picks and merges are left out.

## Credits and license

AtlasLoot Enhanced is by Hegarol, Daviesh and the AtlasLoot team. This fork is released under the same GPL v2 license; see [AtlasLoot/Documentation/LICENSE.txt](AtlasLoot/Documentation/LICENSE.txt).
