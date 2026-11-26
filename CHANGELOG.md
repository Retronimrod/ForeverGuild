# ForeverGuild v0.9.61

- New guild-wide recipe search in auction-house style: Guild professions now opens "By recipe" by default ("By crafter" keeps the previous overview; the choice is remembered).
- Collapsible category navigation (weapons, armor by type and slot, jewelry, containers, consumables, trade goods, enchantments by slot, miscellaneous) with result counts; empty categories are greyed out.
- Combinable filters: profession, slot, quality, character level, item level, required skill, crafter, online status and binding, plus "Reset filters".
- Smarter search: several terms are combined and understand common German and English synonyms and abbreviations ("schneider armschienen", "alchi heiltrank", "schmied zweihandschwert"). Unknown terms are reported instead of being ignored.
- Each item appears once with crafter and online counts; recipe variants are merged. The detail view lists variants, materials and all crafters (class, level, skill, status, last sync) with Whisper and Place order, which opens the existing order dialog with item and crafter preselected.
- Only synced recipes count; members without synced data are shown separately and never treated as unable to craft. The search runs on a local index and sends no extra addon messages.

# ForeverGuild v0.9.60

- Bulletin board fix: the crafter of a claimed order now sees "Ready for handoff" and "Release" again. The requester stores the crafter's name in its own spelling (e.g. with surname), which was not recognized as the own character.

# ForeverGuild v0.9.59

- Roles & permissions: the guild master configures a base profile and three additional roles and assigns them to characters. Moderators can hide board posts and restore them later from the new "Hidden posts" window on the bulletin board. Old moderation records and assignments of former members are cleaned up automatically.
- The guild master can choose which guild ranks count as officers; the permissions window shows whether officers can still publish announcements.
- Partner guilds: guild masters exchange connection codes; the link becomes active once both relays have confirmed each other and can be disconnected by either side. A twink on the same account can act as relay. Unanswered probes back off up to 10 minutes and their "player not online" messages are hidden. Silent partnerships are shown as inactive, all guild members can see the partner list, and a different realm is pointed out.
- Dungeon events can be shared with partner guilds ("Also for partner guilds"). They appear read-only on the partner's board; sign up by whispering the organizer.
- The guild member list shows total and online members, the guild master and officers, and who still runs an older ForeverGuild version.
- New `/fguild partnertest <character>` to check that messages arrive between two characters.
- Internal: UI text now goes through a central localization catalog (Locale.lua).
- The whole guild should update together so all clients respect roles, hidden posts and shared events.
