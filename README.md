<p align="center">
  <img src="https://guildsofwow.com/assets/images/guilds-of-wow-logo.png" width="170" height="200" />
</p>

[![Guilds of WoW on Discord](https://img.shields.io/static/v1?label=Discord&message=GoW&color=7289DA)](https://discord.gg/guildsofwow)
[![Guilds of WoW on Patreon](https://img.shields.io/static/v1?label=Patreon&message=GoW&color=f96854)](https://www.patreon.com/guildsofwow)

# Guilds of WoW Addon

Welcome to [Guilds of WoW](https://gow.gg) in-game addon.

This project is in-game addon of Guilds of WoW. It is aiming to help guilds who use Guilds of WoW with additional in-game functionalities.

## HOW TO USE

In order to use this addon your guild must be registered on Guilds of WoW.

https://guildsofwow.com/my-guilds

If you are not the guild master then ask from your GM to give you related permissions for event and/or recruitment management. Later you should visit addon page on management and download the sync client. Sync client will automatically install and update the in-game addon.

https://guildsofwow.com/manage/addon

## FEATURES

- In-game event generation and inviting characters within rules.

- Team bound events and only inviting characters within that team.

- Exposes up to 3 upcoming events through an addon-to-addon data channel, enabling integration with WeakAuras or custom event-driven addons.

- Exporting attendance data to Guilds of WoW for attendance reports and syncing RSVPs bidirectional.

- Easier in-game recruitment management for inviting to guild, adding as friend or whispering.

- Syncing back your guild's Mythic+ keystones to GoW and Discord (Requires 'Astral Keys' and/or 'Details' addons).

- Personal and guild-wide item wishlists with loot drop alerts, browser interface, and team filtering.

- RCLootCouncil integration displaying wishlist priorities and stat gains during loot distribution.

## EVENTS

When you access events section of your guild management, at least one upcoming event should be existing. After your guild's upcoming events are generated sync client will migrate your event data to in game addon database.

https://guildsofwow.com/manage/events

### Event Messaging

- **Prefix**: `GuildsOfWoW`
- **Channel**: `GUILD`
- **Frequency**: Every 300 seconds (or on initial login if event data exists)
- **Library**: AceComm-3.0

### Message Structure

Each message sent is a **single event** serialized as a `key=value` string with `&` delimiters.

### Example Message:

    title=Mythic Progression&minLevel=60&maxLevel=80&minItemLevel=300&eventDate=1751137200&durationText=3 hours&webUrl=https://gow.gg/event/123456&team=Core Team&

### Fields

| Key            | Type   | Description                        |
| -------------- | ------ | ---------------------------------- |
| `title`        | string | Title of the event                 |
| `minLevel`     | number | Minimum level to attend            |
| `maxLevel`     | number | Maximum level                      |
| `minItemLevel` | number | Minimum gear level to attend       |
| `eventDate`    | number | Unix timestamp (UTC) of start time |
| `durationText` | string | Friendly duration (e.g. "3 hours") |
| `webUrl`       | string | Link to the event on GoW site      |
| `team`         | string | Team name (e.g. "Mythic Roster")   |

---

### WA Trigger Setup

- **Event Type**: `Addon Message` (TSU)
- **Prefix**: `GuildsOfWoW`

### Trigger Function Example

    function(event, prefix, message, channel, sender)
        if prefix ~= "GuildsOfWoW" then return false end

        local events = aura_env.events or {}
        local parsed = {}

        for pair in string.gmatch(message, "([^&]+)") do
            local k, v = string.match(pair, "([^=]+)=([^=]+)")
            if k and v then parsed[k] = v end
        end

        if parsed.title and parsed.eventDate then
            table.insert(events, parsed)
            aura_env.events = events
            return true
        end

        return false
    end

### Notes

- Messages are **not compressed** or encoded — they're human-readable.
- Each WA client independently collects events as they arrive.
- If no addon user is online, **data may become stale** until another update is sent.
- You can extend your WA with custom options like "Show locked events" or "Max # of events to display".

## WISHLISTS

The Wishlist system lets you track desired items for your character and view what your entire guild wants from current content. Wishlist data is synced via the GoW Sync App.

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

The wishlist column is sortable with intelligent priority ordering:

1.  **By Priority Tier**: BiS > Need > Greed > Minor > Offspec > Transmog
2.  **By Stat Gain**: Higher percentage gains rank higher
3.  **Tiebreaker**: Higher gain percentage wins ties

### Configuration

- **Enable/Disable**: Toggle via `showRCLCWishlist` in addon profile settings
- **Display Mode**: Saved per-character and persists across sessions

Guilds of WoW website: https://guildsofwow.com

Guilds of WoW support: https://guildsofwow.com/feedback

Discord: https://discord.gg/guildsofwow

Twitter: https://twitter.com/guildsofwow
