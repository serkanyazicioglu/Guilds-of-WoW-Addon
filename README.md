<p align="center">
  <img src="https://guildsofwow.com/assets/images/guilds-of-wow-logo.png" width="170" height="200" />
</p>

[![Guilds of WoW on Discord](https://img.shields.io/static/v1?label=Discord&logo=discord&message=GoW&color=7289DA)](https://discord.gg/guildsofwow)
[![Guilds of WoW on Patreon](https://img.shields.io/static/v1?label=Patreon&logo=patreon&message=GoW&color=f96854)](https://www.patreon.com/guildsofwow)

# Guilds of WoW Addon

Welcome to the [Guilds of WoW](https://gow.gg) in-game addon.

The Guilds of WoW addon extends your guild management experience with additional in-game functionality, including events, recruitment, attendance, Mythic+ keystones, wishlists, and loot management.

## HOW TO USE

To use the addon, you must install the GoW Desktop App.

https://guildsofwow.com/addon

## FEATURES

- Create in-game events and invite eligible characters based on event rules.

- Support team-based events and invite only characters from the selected team.

- Export attendance data to Guilds of WoW for attendance reports and sync RSVPs bidirectionally.

- Manage recruitment in-game by inviting applicants to your guild, adding them as friends, or whispering them.

- Sync your guild's Mythic+ keystones with Guilds of WoW and Discord. Supports AstralKeys and LibOpenRaid/Details.

- Manage personal and guild-wide item wishlists with loot drop alerts, a browser interface, and team filtering.

- Integrate with RCLootCouncil to display wishlist priorities and stat gains during loot distribution.

## EVENTS

Create and manage your guild events on Guilds of WoW. Upcoming events are synced to the in-game addon through the GoW Desktop App, allowing you to create events and invite eligible characters in-game.

At least one upcoming event must be available for event data to be synced.

https://guildsofwow.com/manage/events

## WISHLISTS

The Wishlist system lets you track desired items for your characters and see what your entire guild wants from current content. Wishlist data is synced through the GoW Desktop App.

### Slash Commands

| Command     | Description                                      |
| ----------- | ------------------------------------------------ |
| `/gow loot` | Open wishlist browser (Personal and Roster tabs) |

### Personal Wishlists

Track items you want from content with priority tagging:

- **Priority Tags**: BiS (Best in Slot), Need, Greed, Minor Upgrade, Offspec, Transmog
- **Stat Gains**: View projected upgrade percentages (e.g., "+4.2% DPS")
- **Difficulty Filtering**: Filter by Normal, Heroic, Mythic, or LFR
- **Slot Filtering**: Filter by equipment slot (Head, Shoulders, etc.)

### Guild Wishlists (Roster View)

See aggregated wishlist data across your entire guild:

- **Member Counts**: See how many guild members want each item
- **Team Filtering**: Filter by specific raid rosters/teams
- **Average Gains**: View average stat upgrade across all members wanting an item
- **Officer Notes**: View officer notes and personal notes per member

### Loot Alerts

When a wishlisted item drops during a raid, you'll receive an automatic popup notification:

- **Trigger**: Activates on `START_LOOT_ROLL` events in raid instances
- **Display**: Shows item icon, name, difficulty, priority tag, source boss, and stat gain
- **Auto-Dismiss**: Alerts fade after 60 seconds or can be manually closed
- **Toggle**: Enable/disable via addon settings (`showLootAlerts`)

## RCLC INTEGRATION

The addon integrates with [RCLootCouncil](https://www.curseforge.com/wow/addons/rclootcouncil) to enhance loot distribution decisions by displaying wishlist data directly in the voting interface.

> **Requirement**: RCLootCouncil addon must be installed for this feature to work.

### Voting Column

Adds a wishlist column to the RC Loot Council voting table showing:

- **Priority Tag**: BiS, Need, Greed, Minor, Offspec, or Transmog (color-coded)
- **Stat Gain**: Percentage upgrade (e.g., "4.2%") or raw stat value (e.g., "127 DPS")
- **Difficulty**: Matching raid difficulty for the wishlist entry

### Display Modes

Click the column header to cycle between three display modes:

| Mode    | Shows                             |
| ------- | --------------------------------- |
| Percent | Percentage stat gain (e.g., 4.2%) |
| Value   | Raw stat value (e.g., 127 DPS)    |
| Tag     | Priority category (e.g., BiS)     |

### Sorting

The wishlist column sorting depends on the active display mode:

- **Percent / Value modes**: Items are sorted primarily by stat gain (higher percent/value first). When gains are equal, priority tier (BiS > Need > Greed > Minor > Offspec > Transmog) is used as a secondary ordering.
- **Tag mode**: Items are sorted primarily by priority tier (BiS > Need > Greed > Minor > Offspec > Transmog). Within the same tier, items with higher stat gain are shown first.

### Configuration

- **Enable/Disable**: Toggle via `showRCLCWishlist` in addon profile settings
- **Display Mode**: Saved in your addon profile and persists across sessions

Guilds of WoW website: https://guildsofwow.com
Guilds of WoW support: https://guildsofwow.com/feedback

[![Guilds of WoW on Discord](https://img.shields.io/static/v1?label=&logo=discord&message=GoW&color=7289DA)](https://discord.gg/guildsofwow)
[![Guilds of WoW on Discord](https://img.shields.io/static/v1?label=&logo=x&message=GoW&color=000000)](https://x.com/guildsofwow)