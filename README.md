# AH Upgrade Check

A small WoW Forever addon that scans the Auction House for gear upgrades over what you
currently have equipped, and shows each one as a plain upgrade percentage.

It leans on [GearQuest Forever](https://www.curseforge.com/wow/addons/gearquest)'s own
stat-weight scoring (`GQ.Compare:ScoreItemLinkStats`) to score items, so the percentage you
see here reflects the same stat priorities GearQuest Forever uses elsewhere.

## What it does

- Opens automatically next to the Auction House frame when you open it (`/ahup` also
  toggles it manually).
- **Scan Now** pages through the current Auction House browse listings and scores every
  buyout-able, equippable item against whatever you have in that slot right now.
- Lists every match, sorted by upgrade % (downgrades included, empty slots show as `NEW`),
  with item name, slot, buyout price, and a **Go** button.
- **Go** re-runs a Browse search for that item so you can select it and finish the
  bid/buyout yourself on the normal Blizzard Auction House UI — this addon never buys
  anything for you.

## Requirements

- WoW Forever client.
- [GearQuest Forever](https://www.curseforge.com/wow/addons/gearquest) installed and
  enabled — AH Upgrade Check reads its global `GearQuest` table for scoring and won't do
  anything useful without it.

Auctionator is **not** required. AH Upgrade Check talks to the Auction House directly
through Blizzard's own legacy AH API and doesn't depend on any other Auction House addon.

## Install

1. Download the latest release zip from the
   [Releases page](https://github.com/DanielGarciaGuillen/AHUpgradeCheck/releases).
2. Extract it so the `AHUpgradeCheck` folder lands directly inside your `Interface/AddOns/`
   folder (i.e. you should end up with `Interface/AddOns/AHUpgradeCheck/AHUpgradeCheck.toc`).
3. Make sure `GearQuestForever` is also installed under `Interface/AddOns/`.
4. Enable both addons on the character select screen's AddOns list.

## Using it

1. Visit an auctioneer and open the Auction House.
2. The AH Upgrade Check window appears next to it automatically.
3. Click **Scan Now**. This can take a little while on a large Auction House — it's
   paging through every current listing, one page at a time.
4. Sort is automatic (best upgrade first). Hover a row for the item tooltip, click **Go**
   to jump to it on the Browse tab and buy it yourself.

## How the upgrade % is calculated

For each equipment slot, your current score is `GQ.Compare:ScoreItemLinkStats(equippedLink,
slotName)` — for rings and trinkets (which have two slots), the weaker of your two equipped
items is used as the baseline, matching GearQuest Forever's own convention. Every scanned
AH item's score is compared against that baseline:

```
pct = (candidateScore - baselineScore) / baselineScore * 100
```

An empty slot (baseline score of `0`) shows any item found as `NEW` rather than dividing by
zero.

## Why no Auction House tab?

Auctionator doesn't expose a documented/supported way to add a tab to its own frame, and
reading its live search results would mean relying on its undocumented internals — those
can change without warning on any Auctionator update. AH Upgrade Check avoids that
entirely by being its own small standalone window, driven only by Blizzard's own AH API,
so it keeps working regardless of whether Auctionator is installed, updated, or absent.

## License

No license file yet — treat as all-rights-reserved by default until one is added.
