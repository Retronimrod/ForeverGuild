# ForeverGuild v0.9.59

- Roles & permissions: the guild master configures a base profile and three additional roles and assigns them to characters. Moderators can hide board posts and restore them later from the new "Hidden posts" window on the bulletin board. Old moderation records and assignments of former members are cleaned up automatically.
- The guild master can choose which guild ranks count as officers; the permissions window shows whether officers can still publish announcements.
- Partner guilds: guild masters exchange connection codes; the link becomes active once both relays have confirmed each other and can be disconnected by either side. A twink on the same account can act as relay. Unanswered probes back off up to 10 minutes and their "player not online" messages are hidden. Silent partnerships are shown as inactive, all guild members can see the partner list, and a different realm is pointed out.
- Dungeon events can be shared with partner guilds ("Also for partner guilds"). They appear read-only on the partner's board; sign up by whispering the organizer.
- The guild member list shows total and online members, the guild master and officers, and who still runs an older ForeverGuild version.
- New `/fguild partnertest <character>` to check that messages arrive between two characters.
- Internal: UI text now goes through a central localization catalog (Locale.lua).
- The whole guild should update together so all clients respect roles, hidden posts and shared events.
