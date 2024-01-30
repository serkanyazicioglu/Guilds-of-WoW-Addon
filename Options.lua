local addonName, addon = ...
local GOW = GuildsOfWow;

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local optionsTable = {
    type = "group",
    name = "Guilds of WoW",
    args = {
        BagSettings = {
            type = "group",
            inline = true,
            name = "Settings",
            width = "full",
            args = {
                ShowMinimap = {
                    type = "toggle",
                    order = 1,
                    name = "Show minimap icon",
                    get = function(info) return not GOW.DB.profile.minimap.hide end,
                    set = function(info, value)
                        GOW.DB.profile.minimap.hide = not value;
                        if GOW.DB.profile.minimap.hide then
                            GOW.LDBIcon:Hide("gowicon");
                        else
                            GOW.LDBIcon:Show("gowicon");
                        end
                    end,
                }
            }
        }
    }
  }

AceConfig:RegisterOptionsTable(addonName, optionsTable, nil);
AceConfigDialog:AddToBlizOptions(addonName, "Guilds of WoW");
