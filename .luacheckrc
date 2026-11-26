-- Luacheck-Konfiguration fuer ForeverGuild (WoW Forever, Interface 16001, Lua 5.1).
-- Globals wurden aus den tatsaechlich im Code referenzierten Namen abgeleitet
-- (luacheck-Lauf vom 2026-11-25), nicht geraten.
std = "lua51"

exclude_files = {
    "tools/test_*.lua",
    ".git/**",
    ".claude-context/**",
}

-- Blizzard-WoW-API und Lua-Erweiterungen, die dieses Addon lesend verwendet.
read_globals = {
    "C_AddOns", "C_ChatInfo", "C_GuildInfo", "C_Item", "C_PartyInfo",
    "C_PlayerInteractionManager", "C_Spell", "C_SpellBook", "C_Timer", "C_TradeSkillUI",
    "ChatFontNormal", "ChatFrame_SendTell", "CreateColor", "CreateFrame", "Enum",
    "ChatFrame_AddMessageEventFilter", "ChatFrameUtil", "ERR_CHAT_PLAYER_NOT_FOUND_S", "GameFontDisable", "GameFontDisableSmall", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge",
    "GameTooltip", "GetBuildInfo", "GetCurrentGuildBankTab", "GetGuildBankItemInfo",
    "GetGuildBankItemLink", "GetGuildBankMoney", "GetGuildBankTabInfo", "GetGuildInfo",
    "GetGuildRosterInfo", "GetGuildRosterLastOnline", "GetItemClassInfo", "GetItemInfo",
    "GetItemInfoInstant", "GetItemSubClassInfo", "GetLocale", "GetNormalizedRealmName",
    "GetNumGuildBankTabs", "GetNumGuildMembers", "GetProfessionInfo", "GetProfessions",
    "GetServerTime", "GetTalentTabInfo", "GetTime", "GuildBankFrame", "ITEM_QUALITY_COLORS",
    "InCombatLockdown", "InviteUnit", "IsInGuild", "LoadAddOn", "MAX_GUILDBANK_SLOTS_PER_TAB",
    "Minimap", "QueryGuildBankTab", "RAID_CLASS_COLORS", "CLASS_ICON_TCOORDS","SetCurrentGuildBankTab", "UIParent",
    "UISpecialFrames", "UnitAffectingCombat", "UnitClass", "UnitFactionGroup", "UnitFullName",
    "date", "geterrorhandler", "strlower", "time",
}

-- Vom Addon selbst gesetzte globale Namen (SavedVariables, Slash-Befehle).
globals = {
    "ForeverGuildBackgroundScan", "ForeverGuildBankCache", "ForeverGuildBankGold",
    "ForeverGuildBoard", "ForeverGuildBoardNotes", "ForeverGuildBoardRights", "ForeverGuildPartners", "ForeverGuildCharacter", "ForeverGuildDB",
    "ForeverGuildDiagnostics", "ForeverGuildDiscoveredRecipes", "ForeverGuildItemCache",
    "ForeverGuildLog", "ForeverGuildOrderRelays", "ForeverGuildOrderSequence",
    "ForeverGuildOrders", "ForeverGuildOwnRoles", "ForeverGuildRoleRecords",
    "ForeverGuildRoles", "ForeverGuildSettings", "ForeverGuildSetupShown",
    "SLASH_FOREVERGUILD1",
}

-- Rezeptkataloge: generierte Datentabellen, lange Zeilen sind hier kein Stilproblem.
files["ForeverGuild/RecipeCatalog.lua"] = { max_line_length = false }
files["ForeverGuild/RecipeOutputs.lua"] = { max_line_length = false }

-- Translation catalog: long lines from translated strings are unavoidable.
files["ForeverGuild/Locale.lua"] = { max_line_length = false }
