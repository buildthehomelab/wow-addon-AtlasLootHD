--[[
AtlaslootDefaultFrame.lua
The standalone loot browser, laid out like the modern AtlasLoot:
module and subcategory dropdowns along the top, the loot table on the left,
and the difficulty, boss and quick access lists on the right.

Functions:
AtlasLootDefaultFrame_OnLoad(frame)
AtlasLootDefaultFrame_OnShow()
AtlasLootDefaultFrame_OnHide()
AtlasLootDefaultFrame_Refresh(dataID)
AtlasLootDefaultFrame_UpdateSidePanels()
AtlasLoot_DewdropRegister()
AtlasLoot_SetNewStyle(style)
]]

--Include all needed libraries
local AL = LibStub("AceLocale-3.0"):GetLocale("AtlasLoot");

--Load the dewdrop menus
AtlasLoot_Dewdrop = AceLibrary("Dewdrop-2.0");
AtlasLoot_DewdropSubMenu = AceLibrary("Dewdrop-2.0");

AtlasLoot_Data["AtlasLootFallback"] = {
    EmptyInstance = {};
};

--Frame layout
local FRAME_WIDTH, FRAME_HEIGHT = 900, 602;
local PAD = 10;
local LOOT_WIDTH, LOOT_HEIGHT, LOOT_TOP = 600, 516, -76;
local SIDE_WIDTH = FRAME_WIDTH - LOOT_WIDTH - 3 * PAD;
local HEADER_HEIGHT = 26;
local ITEM_TOP, ITEM_HEIGHT = -30, 30;
local ITEM_WIDTH = (LOOT_WIDTH - 12) / 2;
local ICON_SIZE = 26;
local LINE_HEIGHT = 18;
local DIFFICULTY_LINES, BOSS_LINES, EXTRA_LINES = 4, 18, 6;

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8";
local GOLD_DOT = "Interface\\AddOns\\AtlasLoot\\Images\\gold";
local SILVER_DOT = "Interface\\AddOns\\AtlasLoot\\Images\\silver";

--Where loot tables are anchored in the browser.  Kept in the global pFrame too,
--because the search and wishlist code read it from there.
local LOOT_ANCHOR = { "TOPLEFT", "AtlasLootDefaultFrame_LootBackground", "TOPLEFT", "2", "-2" };

local PANEL_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
};

--HeroicMode, Bigraid and BigraidHeroic profile flags for each difficulty
local DIFFICULTY_FLAGS = {
    normal = { false, false, false },
    heroic = { true, false, false },
    raid25 = { false, true, false },
    raid25heroic = { false, false, true },
};

--What the browser is showing.  module and sub index the module list,
--bosses is the list on the right and boss the selected entry in it.
local state = { bosses = {} };
local modules;

local lootBackground, moduleBox, subBox;
local difficultyLines, bossLines, extraLines = {}, {}, {};
local bossScroll, searchBox, searchPlaceholder;
local itemsLayoutModern, backButtonWidth;

--[[
Widget helpers
]]
local function SolidTexture(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer);
    texture:SetTexture(WHITE_TEXTURE);
    texture:SetVertexColor(r, g, b, a);
    return texture;
end

local function SkinPanel(frame, alpha)
    frame:SetBackdrop(PANEL_BACKDROP);
    frame:SetBackdropColor(0, 0, 0, alpha);
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1);
end

local function CreatePanel(parent, height)
    local panel = CreateFrame("Frame", nil, parent);
    panel:SetWidth(SIDE_WIDTH);
    panel:SetHeight(height);
    SkinPanel(panel, 0.6);
    return panel;
end

local function StripText(text)
    text = AtlasLoot_FixText(text or "");
    text = gsub(text, "|c%x%x%x%x%x%x%x%x", "");
    text = gsub(text, "|r", "");
    text = gsub(text, "|T.-|t", "");
    return strtrim(text);
end

local function ShowTooltip(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT");
    GameTooltip:AddLine(title);
    for i = 1, select("#", ...) do
        GameTooltip:AddLine((select(i, ...)), 1, 1, 1);
    end
    GameTooltip:Show();
end

local function HideTooltip()
    GameTooltip:Hide();
end

--A text-only button for the title bar
local function CreateFlatButton(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent);
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    label:SetPoint("CENTER");
    label:SetText(text);
    button:SetWidth(label:GetStringWidth() + 16);
    button:SetHeight(18);
    local highlight = SolidTexture(button, "HIGHLIGHT", 1, 1, 1, 0.12);
    highlight:SetAllPoints();
    button:SetScript("OnClick", onClick);
    return button;
end

--A row in one of the lists on the right
local function CreateLine(parent, index, onClick)
    local line = CreateFrame("Button", nil, parent);
    line:SetWidth(SIDE_WIDTH - 10);
    line:SetHeight(LINE_HEIGHT);
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5 - (index - 1) * LINE_HEIGHT);
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp");

    line.selected = SolidTexture(line, "BACKGROUND", 1, 1, 1, 1);
    line.selected:SetAllPoints();
    line.selected:SetGradientAlpha("HORIZONTAL", 0.9, 0.7, 0.1, 0.9, 0.5, 0.35, 0.05, 0.5);
    line.selected:Hide();

    local highlight = SolidTexture(line, "HIGHLIGHT", 1, 1, 1, 1);
    highlight:SetAllPoints();
    highlight:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.3, 1, 0.82, 0, 0);

    line.dot = line:CreateTexture(nil, "OVERLAY");
    line.dot:SetWidth(14);
    line.dot:SetHeight(14);
    line.dot:SetPoint("RIGHT", line, "RIGHT", -2, 0);

    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    line.text:SetPoint("LEFT", line, "LEFT", 3, 0);
    line.text:SetPoint("RIGHT", line.dot, "LEFT", -2, 0);
    line.text:SetJustifyH("LEFT");

    line:SetScript("OnClick", onClick);
    return line;
end

local function SetLine(line, text, selected, enabled)
    line.text:SetText(text);
    if selected then
        line.selected:Show();
        line.text:SetTextColor(1, 1, 1);
        line.dot:SetTexture(GOLD_DOT);
    else
        line.selected:Hide();
        if enabled == false then
            line.text:SetTextColor(0.5, 0.5, 0.5);
        else
            line.text:SetTextColor(1, 0.82, 0);
        end
        line.dot:SetTexture(SILVER_DOT);
    end
    line:Show();
end

--A "Select Module" style dropdown: a dark box with the choice and a yellow arrow
local function ToggleDropdown(box)
    if AtlasLoot_Dewdrop:IsOpen(box) then
        AtlasLoot_Dewdrop:Close();
    else
        AtlasLoot_Dewdrop:Open(box);
    end
end

local function CreateDropdown(parent, label, width)
    local box = CreateFrame("Button", nil, parent);
    box:SetWidth(width);
    box:SetHeight(24);
    SkinPanel(box, 0.8);

    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    box.label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 2, 1);
    box.label:SetText(label);

    box.arrow = CreateFrame("Button", nil, box);
    box.arrow:SetWidth(22);
    box.arrow:SetHeight(22);
    box.arrow:SetPoint("RIGHT", box, "RIGHT", -2, 0);
    box.arrow:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up");
    box.arrow:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down");
    box.arrow:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled");
    box.arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");

    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    box.text:SetPoint("LEFT", box, "LEFT", 8, 0);
    box.text:SetPoint("RIGHT", box.arrow, "LEFT", -4, 0);
    box.text:SetJustifyH("RIGHT");

    local highlight = SolidTexture(box, "HIGHLIGHT", 1, 1, 1, 0.06);
    highlight:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4);
    highlight:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 4);

    box:SetScript("OnClick", function() ToggleDropdown(box) end);
    box.arrow:SetScript("OnClick", function() ToggleDropdown(box) end);
    return box;
end

local function SetDropdownEnabled(box, enabled)
    if enabled then
        box:Enable();
        box.arrow:Enable();
        box.text:SetTextColor(1, 1, 1);
    else
        box:Disable();
        box.arrow:Disable();
        box.text:SetTextColor(0.5, 0.5, 0.5);
    end
end

--[[
Navigation data
The module list is built from AtlasLoot_DewDropDown.  Instance modules list
their instances as subcategories, while menu modules (Crafting, PvP, ...) use
the entries of their menu page.
]]

--Loot tables with a difficulty or faction suffix share one boss entry
local function BaseID(dataID)
    dataID = gsub(dataID, "_H", "");
    dataID = gsub(dataID, "_A", "");
    dataID = gsub(dataID, "HEROIC", "");
    dataID = gsub(dataID, "25Man", "");
    return dataID;
end

local function IsMenu(dataID)
    return AtlasLoot_TableNames[dataID] and AtlasLoot_TableNames[dataID][2] == "Menu";
end

local function MenuEntries(menuID)
    local entries = {};
    for _, entry in ipairs(AtlasLoot_Data[menuID] or {}) do
        if entry[2] and entry[2] ~= "" then
            tinsert(entries, entry);
        end
    end
    sort(entries, function(a, b) return a[1] < b[1] end);
    for i, entry in ipairs(entries) do
        local text, extra = StripText(entry[4]), StripText(entry[5]);
        if extra ~= "" then
            text = text.." - "..extra;
        end
        entries[i] = { text = text, id = entry[2] };
    end
    return entries;
end

--The pages of a loot table: menu entries, or every page of a multi-page table
local function PageEntries(dataID)
    if not AtlasLoot_IsLootTableAvailable(dataID) then
        return {};
    end
    if IsMenu(dataID) then
        return MenuEntries(dataID);
    end
    local entries, seen, count = {}, {}, {};
    local page = dataID;
    while page and not seen[page] and AtlasLoot_Data[page] and AtlasLoot_TableNames[page] do
        seen[page] = true;
        local text = StripText(AtlasLoot_TableNames[page][1]);
        count[text] = (count[text] or 0) + 1;
        tinsert(entries, { text = text, id = page });
        page = AtlasLoot_Data[page].Next;
    end
    --Number the pages of tables that share one title
    local numbered = {};
    for _, entry in ipairs(entries) do
        if count[entry.text] > 1 then
            numbered[entry.text] = (numbered[entry.text] or 0) + 1;
            entry.text = entry.text.." ("..numbered[entry.text]..")";
        end
    end
    return entries;
end

local function SubmenuEntries(subTableID)
    local entries = {};
    for _, entry in ipairs(AtlasLoot_DewDropDown_SubTables[subTableID] or {}) do
        local text = entry[1];
        if text == "" and AtlasLoot_TableNames[entry[2]] then
            text = AtlasLoot_TableNames[entry[2]][1];
        end
        tinsert(entries, { text = StripText(text ~= "" and text or entry[2]), id = entry[2] });
    end
    return entries;
end

local function AddSub(subs, text, id, kind, indent)
    tinsert(subs, { text = text, id = id, kind = kind, indent = indent });
end

local function GetModules()
    if modules then
        return modules;
    end
    modules = {};
    for _, entry in ipairs(AtlasLoot_DewDropDown) do
        if type(entry[1]) == "table" and type(entry[1][1]) == "string" then
            --A single loot table, submenu or menu page
            local text, id, kind = entry[1][1], entry[1][2], entry[1][3];
            local module = { text = text, subs = {} };
            if kind == "Table" and IsMenu(id) then
                for _, sub in ipairs(MenuEntries(id)) do
                    AddSub(module.subs, sub.text, sub.id, "Table");
                end
            else
                AddSub(module.subs, text, id, kind);
            end
            tinsert(modules, module);
        else
            --A list of instances, some of them grouped (Dire Maul, Auchindoun, ...)
            for name, instances in pairs(entry) do
                local module = { text = name, subs = {} };
                for _, instance in ipairs(instances) do
                    if type(instance[1]) == "table" and type(instance[1][1]) == "string" then
                        AddSub(module.subs, instance[1][1], instance[1][2], instance[1][3]);
                    else
                        for group, members in pairs(instance) do
                            AddSub(module.subs, group);
                            for _, member in ipairs(members) do
                                AddSub(module.subs, member[1], member[2], member[3], true);
                            end
                        end
                    end
                end
                tinsert(modules, module);
            end
        end
    end
    return modules;
end

--The loot table on screen, with difficulty and faction resolved
local function CurrentPage(requested)
    if requested and IsMenu(requested) then
        return requested;
    end
    local refresh = AtlasLootItemsFrame.refresh;
    if refresh and refresh[1] == "FilterList" then
        refresh = AtlasLootItemsFrame.refreshOri;
    end
    return refresh and refresh[1] or requested;
end

--[[
Navigation
]]
local function UpdateDropdowns()
    local module = state.module and GetModules()[state.module];
    if module then
        moduleBox.text:SetText(module.text);
    else
        moduleBox.text:SetText(AL["Choose Table ..."]);
    end
    local sub = module and module.subs[state.sub];
    subBox.text:SetText(sub and sub.text or "");

    local choices = 0;
    if module then
        for _, entry in ipairs(module.subs) do
            if entry.id then
                choices = choices + 1;
            end
        end
    end
    SetDropdownEnabled(subBox, choices > 1);
end

local function ShowPage(dataID, text)
    pFrame = LOOT_ANCHOR;
    AtlasLoot.db.profile.LastBoss = dataID;
    AtlasLoot_ShowBossLoot(dataID, text or "", LOOT_ANCHOR);
end

local function SelectBoss(index)
    local entry = state.bosses[index];
    if entry then
        state.boss = index;
        ShowPage(entry.id, entry.text);
    end
end

local function SelectSub(index)
    local module = GetModules()[state.module];
    local sub = module and module.subs[index];
    if not (sub and sub.id) then
        return;
    end
    state.sub = index;
    state.boss = nil;
    if sub.kind == "Submenu" then
        state.bosses = SubmenuEntries(sub.id);
    else
        state.bosses = PageEntries(sub.id);
    end
    bossScroll.offset = 0;
    getglobal(bossScroll:GetName().."ScrollBar"):SetValue(0);
    UpdateDropdowns();
    if #state.bosses > 0 then
        SelectBoss(1);
    else
        ShowPage(sub.id, sub.text);
    end
end

local function SelectModule(index)
    state.module = index;
    state.sub = nil;
    for i, sub in ipairs(GetModules()[index].subs) do
        if sub.id then
            SelectSub(i);
            return;
        end
    end
    UpdateDropdowns();
end

--[[
Side panels
]]
local function UpdateDifficulties()
    local page = state.page;
    local entries = {};
    if page and page ~= "SearchResult" and page ~= "WishList" and AtlasLoot_TableNames[page] and not IsMenu(page) then
        local normal, heroic, normal25, heroic25 = AtlasLoot_GetLoottableHeroic(page);
        local raid = normal25 or heroic25;
        if normal then
            tinsert(entries, { id = normal, flags = "normal", text = raid and AL["10 Man"] or AL["Normal"] });
        end
        if heroic then
            tinsert(entries, { id = heroic, flags = "heroic", text = raid and (AL["10 Man"].." "..AL["Heroic"]) or AL["Heroic"] });
        end
        if normal25 then
            tinsert(entries, { id = normal25, flags = "raid25", text = AL["25 Man"] });
        end
        if heroic25 then
            tinsert(entries, { id = heroic25, flags = "raid25heroic", text = AL["25 Man"].." "..AL["Heroic"] });
        end
    end
    for i, line in ipairs(difficultyLines) do
        local entry = entries[i];
        if entry then
            line.entry = entry;
            SetLine(line, entry.text, entry.id == page);
            line.dot:Hide();
        else
            line:Hide();
        end
    end
end

local function UpdateBossList()
    FauxScrollFrame_Update(bossScroll, #state.bosses, BOSS_LINES, LINE_HEIGHT);
    local offset = FauxScrollFrame_GetOffset(bossScroll);
    local width = SIDE_WIDTH - (bossScroll:IsShown() and 30 or 10);
    for i, line in ipairs(bossLines) do
        local index = offset + i;
        local entry = state.bosses[index];
        if entry then
            line.index = index;
            line:SetWidth(width);
            SetLine(line, entry.text, index == state.boss);
        else
            line:Hide();
        end
    end
end

local function QuickLookName(quicklook)
    if quicklook[3] and quicklook[3] ~= "" then
        return quicklook[3];
    elseif AtlasLoot_TableNames[quicklook[1]] then
        return StripText(AtlasLoot_TableNames[quicklook[1]][1]);
    end
    return quicklook[1];
end

local function UpdateExtraList()
    local page = state.page;
    local charDB = AtlasLootCharDB or {};
    local results = charDB["SearchResult"];
    SetLine(extraLines[1], AL["Wishlist"], page == "WishList");
    SetLine(extraLines[2], AL["Last Result"], page == "SearchResult", results ~= nil and #results > 0);
    for i = 1, 4 do
        local quicklook = charDB["QuickLooks"] and charDB["QuickLooks"][i];
        local line = extraLines[i + 2];
        if quicklook and quicklook[1] then
            SetLine(line, "|cff808080"..i..".|r "..QuickLookName(quicklook), page and BaseID(quicklook[1]) == BaseID(page));
        else
            SetLine(line, AL["QuickLook"].." "..i, false, false);
        end
    end
end

function AtlasLootDefaultFrame_UpdateSidePanels()
    if not bossScroll then
        return;
    end
    UpdateDifficulties();
    UpdateBossList();
    UpdateExtraList();
end

local function OnDifficultyClick(line)
    local entry = line.entry;
    local profile = AtlasLoot.db.profile;
    local flags = DIFFICULTY_FLAGS[entry.flags];
    profile.HeroicMode, profile.Bigraid, profile.BigraidHeroic = flags[1], flags[2], flags[3];
    AtlasLoot.db.profile.LastBoss = entry.id;
    local refresh = AtlasLootItemsFrame.refresh;
    AtlasLoot_ShowItemsFrame(entry.id, refresh and refresh[2] or "", "", LOOT_ANCHOR);
end

local function OnBossClick(line)
    SelectBoss(line.index);
end

local function OnQuickLookClick(line, button)
    local i = line:GetID();
    local quicklooks = AtlasLootCharDB["QuickLooks"];
    if button == "RightButton" then
        --Assign the loot table on screen, like the old "Add to QuickLooks" button
        local ori = AtlasLootItemsFrame.refreshOri;
        if ori and ori[1] == state.page then
            quicklooks[i] = { ori[1], ori[2], ori[3], ori[4] };
            AtlasLoot_RefreshQuickLookButtons();
        end
    elseif quicklooks[i] and quicklooks[i][1] and AtlasLoot_IsLootTableAvailable(quicklooks[i][1]) then
        state.boss = nil;
        pFrame = LOOT_ANCHOR;
        AtlasLoot_AnchorFrame = LOOT_ANCHOR;
        AtlasLoot_ShowItemsFrame(quicklooks[i][1], quicklooks[i][2], quicklooks[i][3], LOOT_ANCHOR);
    end
end

local function OnExtraClick(line, button)
    if line:GetID() > 0 then
        OnQuickLookClick(line, button);
    elseif line == extraLines[1] then
        state.boss = nil;
        AtlasLoot_ShowWishListDropDown("", "", "", "", "", line, true);
    elseif #(AtlasLootCharDB["SearchResult"] or {}) > 0 then
        state.boss = nil;
        AtlasLoot:ShowSearchResult();
    end
end

local function OnQuickLookEnter(line)
    ShowTooltip(line, AL["QuickLook"].." "..line:GetID(),
        AL["Left-click: Show this loot table"],
        AL["Right-click: Assign the current loot table"]);
end

--[[
Items frame layout
AtlasLootItemsFrame is shared with Atlas, so it is restyled while it sits in
the loot browser and put back the way the XML defines it when it leaves.
]]
local function StyleItemButton(name, modern)
    local button = getglobal(name);
    local icon, unsafe = getglobal(name.."_Icon"), getglobal(name.."_Unsafe");
    local highlight = button:GetHighlightTexture();
    icon:ClearAllPoints();
    unsafe:ClearAllPoints();
    if modern then
        button:SetWidth(ITEM_WIDTH);
        button:SetHeight(ITEM_HEIGHT);
        icon:SetWidth(ICON_SIZE);
        icon:SetHeight(ICON_SIZE);
        icon:SetPoint("LEFT", button, "LEFT", 2, 0);
        unsafe:SetWidth(ICON_SIZE + 2);
        unsafe:SetHeight(ICON_SIZE + 2);
        unsafe:SetPoint("CENTER", icon, "CENTER");
        getglobal(name.."_Name"):SetWidth(ITEM_WIDTH - ICON_SIZE - 10);
        getglobal(name.."_Extra"):SetWidth(ITEM_WIDTH - ICON_SIZE - 10);
        highlight:SetTexture(WHITE_TEXTURE);
        highlight:SetBlendMode("BLEND");
        highlight:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.3, 1, 0.82, 0, 0);
        if not button.qualityBorder then
            button.qualityBorder = button:CreateTexture(nil, "BACKGROUND");
            button.qualityBorder:SetTexture(WHITE_TEXTURE);
            button.qualityBorder:SetWidth(ICON_SIZE + 2);
            button.qualityBorder:SetHeight(ICON_SIZE + 2);
            button.qualityBorder:SetPoint("CENTER", icon, "CENTER");
            button.qualityBorder:Hide();
        end
    else
        button:SetWidth(236);
        button:SetHeight(28);
        icon:SetWidth(25);
        icon:SetHeight(25);
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1);
        unsafe:SetWidth(27);
        unsafe:SetHeight(27);
        unsafe:SetPoint("TOPLEFT", button, "TOPLEFT");
        getglobal(name.."_Name"):SetWidth(205);
        getglobal(name.."_Extra"):SetWidth(205);
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight");
        highlight:SetBlendMode("ADD");
        highlight:SetVertexColor(1, 1, 1, 1);
        if button.qualityBorder then
            button.qualityBorder:Hide();
        end
    end
end

local function SetItemsFrameLayout(modern)
    for i = 1, 30 do
        StyleItemButton("AtlasLootItem_"..i, modern);
        StyleItemButton("AtlasLootMenuItem_"..i, modern);
    end
    local frame = AtlasLootItemsFrame;
    for _, button in ipairs({ AtlasLootItem_1, AtlasLootMenuItem_1, AtlasLoot_BossName, AtlasLootItemsFrame_PREV,
            AtlasLootItemsFrame_NEXT, AtlasLootItemsFrame_BACK, AtlasLootServerQueryButton, AtlasLootFilterCheck }) do
        button:ClearAllPoints();
    end
    backButtonWidth = backButtonWidth or AtlasLootItemsFrame_BACK:GetWidth();
    if modern then
        AtlasLootItemsFrame_BACK:SetWidth(80);
        AtlasLootItem_1:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, ITEM_TOP);
        AtlasLootMenuItem_1:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, ITEM_TOP);
        AtlasLoot_BossName:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, 0);
        AtlasLoot_BossName:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, 0);
        AtlasLoot_BossName:SetHeight(HEADER_HEIGHT);
        AtlasLootItemsFrame_PREV:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 1);
        AtlasLootItemsFrame_NEXT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 1);
        AtlasLootItemsFrame_BACK:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 40, 6);
        AtlasLootFilterCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 330, 4);
        AtlasLootServerQueryButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 6);
        AtlasLootServerQueryButton:SetWidth(110);
        AtlasLootServerQueryButton:SetHeight(22);
    else
        frame:SetWidth(510);
        frame:SetHeight(510);
        AtlasLootItem_1:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -35);
        AtlasLootMenuItem_1:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -35);
        AtlasLoot_BossName:SetPoint("TOP", frame, "TOP");
        AtlasLoot_BossName:SetWidth(512);
        AtlasLoot_BossName:SetHeight(30);
        AtlasLootItemsFrame_PREV:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 8);
        AtlasLootItemsFrame_NEXT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5);
        AtlasLootItemsFrame_BACK:SetPoint("BOTTOM", frame, "BOTTOM", 0, 4);
        AtlasLootItemsFrame_BACK:SetWidth(backButtonWidth);
        AtlasLootFilterCheck:SetPoint("BOTTOM", frame, "BOTTOM", 85, 27);
        AtlasLootServerQueryButton:SetPoint("BOTTOM", frame, "BOTTOM", 120, 4);
        AtlasLootServerQueryButton:SetWidth(160);
        AtlasLootServerQueryButton:SetHeight(23);
        if AtlasLoot.db and AtlasLoot.db.profile.Opaque then
            AtlasLootItemsFrame_Back:SetTexture(0, 0, 0, 1);
        else
            AtlasLootItemsFrame_Back:SetTexture(0, 0, 0, 0.65);
        end
    end
    itemsLayoutModern = modern;
end

--Runs after AtlasLoot_SetItemInfoFrame has anchored the items frame
local function UpdateItemsFrameLayout()
    if AtlasLootItemsFrame:GetParent() == lootBackground then
        if not itemsLayoutModern then
            SetItemsFrameLayout(true);
        end
        AtlasLootItemsFrame:ClearAllPoints();
        AtlasLootItemsFrame:SetAllPoints(lootBackground);
        AtlasLootItemsFrame_Back:SetTexture(0, 0, 0, 0);
        searchBox:SetFrameLevel(AtlasLootItemsFrame:GetFrameLevel() + 3);
    elseif itemsLayoutModern then
        SetItemsFrameLayout(false);
    end
end

local function UpdateQualityBorders()
    for i = 1, 30 do
        local button = getglobal("AtlasLootItem_"..i);
        local quality;
        if button:IsShown() and not getglobal("AtlasLootItem_"..i.."_Unsafe"):IsShown() then
            local itemID = button.itemID;
            if type(itemID) == "string" and strsub(itemID, 1, 1) == "s" then
                itemID = button.spellitemID;
            end
            itemID = tonumber(itemID);
            if itemID and itemID ~= 0 then
                quality = select(3, GetItemInfo(itemID));
            end
        end
        --The border only exists once the modern layout has been applied
        local border = button.qualityBorder;
        if border and quality then
            local r, g, b = GetItemQualityColor(quality);
            border:SetVertexColor(r, g, b, 1);
            border:Show();
        elseif border then
            border:Hide();
        end
    end
end

--[[
AtlasLootDefaultFrame_Refresh(dataID):
Runs after every AtlasLoot_ShowItemsFrame call and brings the browser in line
with the loot table on screen
]]
function AtlasLootDefaultFrame_Refresh(dataID)
    if AtlasLootItemsFrame:GetParent() ~= lootBackground then
        return;
    end
    --The difficulty and quick access lists replace these
    AtlasLootItemsFrame_Heroic:Hide();
    AtlasLoot10Man25ManSwitch:Hide();
    AtlasLoot_QuickLooks:Hide();
    AtlasLootQuickLooksButton:Hide();

    state.page = CurrentPage(dataID);
    --Follow the page in the boss list, unless the selected entry already shows it
    if state.page then
        local base = BaseID(state.page);
        local selected = state.bosses[state.boss];
        if not (selected and BaseID(selected.id) == base) then
            for i, entry in ipairs(state.bosses) do
                if BaseID(entry.id) == base then
                    state.boss = i;
                    break;
                end
            end
        end
    end
    UpdateQualityBorders();
    AtlasLootDefaultFrame_UpdateSidePanels();
end

hooksecurefunc("AtlasLoot_SetItemInfoFrame", UpdateItemsFrameLayout);
hooksecurefunc("AtlasLoot_ShowItemsFrame", AtlasLootDefaultFrame_Refresh);

--[[
Frame construction
]]
local function UpdateSearchPlaceholder()
    if searchBox:GetText() == "" and not searchBox.hasFocus then
        searchPlaceholder:Show();
    else
        searchPlaceholder:Hide();
    end
end

local function CreateSearch()
    searchBox = CreateFrame("EditBox", "AtlasLootDefaultFrameSearchBox", lootBackground, "InputBoxTemplate");
    searchBox:SetWidth(160);
    searchBox:SetHeight(20);
    searchBox:SetPoint("BOTTOMLEFT", lootBackground, "BOTTOMLEFT", 130, 7);
    searchBox:SetAutoFocus(false);
    searchBox:SetMaxLetters(100);
    searchBox:SetTextInsets(0, 8, 0, 0);

    searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisable");
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0);
    searchPlaceholder:SetText(AL["Search"]);

    searchBox:SetScript("OnEnterPressed", function(self)
        state.boss = nil;
        AtlasLoot:Search(self:GetText());
        self:ClearFocus();
    end);
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("");
        self:ClearFocus();
    end);
    searchBox:SetScript("OnEditFocusGained", function(self)
        self.hasFocus = true;
        self:HighlightText();
        UpdateSearchPlaceholder();
    end);
    searchBox:SetScript("OnEditFocusLost", function(self)
        self.hasFocus = nil;
        self:HighlightText(0, 0);
        UpdateSearchPlaceholder();
    end);
    searchBox:SetScript("OnTextChanged", UpdateSearchPlaceholder);

    local options = CreateFrame("Button", "AtlasLootDefaultFrameSearchOptionsButton", searchBox);
    options:SetWidth(24);
    options:SetHeight(24);
    options:SetPoint("LEFT", searchBox, "RIGHT", 2, 0);
    options:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up");
    options:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down");
    options:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");
    options:SetScript("OnClick", function(self) AtlasLoot:ShowSearchOptions(self) end);
    options:SetScript("OnEnter", function(self) ShowTooltip(self, AL["Search on"]) end);
    options:SetScript("OnLeave", HideTooltip);
end

local function CreateSidePanels(frame)
    local difficultyPanel = CreatePanel(frame, DIFFICULTY_LINES * LINE_HEIGHT + 10);
    difficultyPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -32);
    for i = 1, DIFFICULTY_LINES do
        difficultyLines[i] = CreateLine(difficultyPanel, i, OnDifficultyClick);
    end

    local extraPanel = CreatePanel(frame, EXTRA_LINES * LINE_HEIGHT + 10);
    extraPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD);
    for i = 1, EXTRA_LINES do
        local line = CreateLine(extraPanel, i, OnExtraClick);
        --QuickLook lines carry their QuickLook number as ID
        line:SetID(math.max(i - 2, 0));
        if i > 2 then
            line:SetScript("OnEnter", OnQuickLookEnter);
            line:SetScript("OnLeave", HideTooltip);
        end
        extraLines[i] = line;
    end

    local bossPanel = CreateFrame("Frame", nil, frame);
    bossPanel:SetPoint("TOPLEFT", difficultyPanel, "BOTTOMLEFT", 0, -6);
    bossPanel:SetPoint("BOTTOMRIGHT", extraPanel, "TOPRIGHT", 0, 6);
    SkinPanel(bossPanel, 0.6);

    bossScroll = CreateFrame("ScrollFrame", "AtlasLootDefaultFrameBossScroll", bossPanel, "FauxScrollFrameTemplate");
    bossScroll:SetPoint("TOPLEFT", bossPanel, "TOPLEFT", 5, -5);
    bossScroll:SetPoint("BOTTOMRIGHT", bossPanel, "BOTTOMRIGHT", -26, 5);
    bossScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, LINE_HEIGHT, UpdateBossList);
    end);
    for i = 1, BOSS_LINES do
        bossLines[i] = CreateLine(bossPanel, i, OnBossClick);
        bossLines[i]:SetFrameLevel(bossScroll:GetFrameLevel() + 2);
    end
end

local function CreateLootPanel(frame)
    lootBackground = CreateFrame("Frame", "AtlasLootDefaultFrame_LootBackground", frame);
    lootBackground:SetWidth(LOOT_WIDTH);
    lootBackground:SetHeight(LOOT_HEIGHT);
    lootBackground:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, LOOT_TOP);
    lootBackground:SetBackdrop({ bgFile = WHITE_TEXTURE });
    lootBackground:SetBackdropColor(0, 0, 0, 0.5);

    --Red boss name header, the name itself is AtlasLoot_BossName in the items frame
    local header = SolidTexture(lootBackground, "ARTWORK", 1, 1, 1, 1);
    header:SetPoint("TOPLEFT");
    header:SetPoint("TOPRIGHT");
    header:SetHeight(HEADER_HEIGHT);
    header:SetGradientAlpha("VERTICAL", 0.4, 0.06, 0.06, 1, 0.6, 0.12, 0.12, 1);

    local bar = SolidTexture(lootBackground, "ARTWORK", 1, 1, 1, 0.05);
    bar:SetPoint("BOTTOMLEFT");
    bar:SetPoint("BOTTOMRIGHT");
    bar:SetHeight(34);
    local barLine = SolidTexture(lootBackground, "ARTWORK", 1, 1, 1, 0.12);
    barLine:SetPoint("BOTTOMLEFT", bar, "TOPLEFT");
    barLine:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT");
    barLine:SetHeight(1);
end

local function CreateTitleBar(frame)
    local bar = SolidTexture(frame, "BORDER", 0.12, 0.12, 0.12, 1);
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4);
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4);
    bar:SetHeight(22);
    frame.titleBar = bar;

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    title:SetPoint("CENTER", bar, "CENTER");
    title:SetText(AL["AtlasLoot"]);

    local close = CreateFrame("Button", "AtlasLootDefaultFrame_CloseButton", frame, "UIPanelCloseButton");
    close:SetWidth(26);
    close:SetHeight(26);
    close:SetPoint("RIGHT", bar, "RIGHT", 2, 0);
    close:SetScript("OnClick", function() AtlasLootDefaultFrame:Hide() end);

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
    version:SetPoint("RIGHT", close, "LEFT", -2, 0);
    version:SetText(strmatch(ATLASLOOT_VERSION, "v[%d%.]+") or "");

    local options = CreateFlatButton(frame, AL["Options"], AtlasLootOptions_Toggle);
    options:SetPoint("LEFT", bar, "LEFT", 4, 0);
    local loadModules = CreateFlatButton(frame, AL["Load Modules"], AtlasLoot_LoadAllModules);
    loadModules:SetPoint("LEFT", options, "RIGHT", 2, 0);
end

--[[
AtlasLootDefaultFrame_OnLoad(frame):
Builds the loot browser
]]
function AtlasLootDefaultFrame_OnLoad(frame)
    frame:SetWidth(FRAME_WIDTH);
    frame:SetHeight(FRAME_HEIGHT);
    frame:RegisterForDrag("LeftButton");

    CreateTitleBar(frame);

    local dropdownWidth = (LOOT_WIDTH - PAD) / 2;
    moduleBox = CreateDropdown(frame, AL["Select Module"], dropdownWidth);
    moduleBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -44);
    subBox = CreateDropdown(frame, AL["Select Subcategory"], dropdownWidth);
    subBox:SetPoint("LEFT", moduleBox, "RIGHT", PAD, 0);

    CreateLootPanel(frame);
    CreateSearch();
    CreateSidePanels(frame);

    UpdateDropdowns();
    AtlasLoot_SetNewStyle("new");
end

--[[
AtlasLootDefaultFrame_OnShow:
Called whenever the loot browser is shown and sets up buttons and loot tables
]]
function AtlasLootDefaultFrame_OnShow()
    pFrame = LOOT_ANCHOR;
    --Having the Atlas and loot browser frames shown at the same time would
    --cause conflicts, so I hide the Atlas frame when the loot browser appears
    if AtlasFrame then
        AtlasFrame:Hide();
    end
    --Remove the selection of a loot table in Atlas
    AtlasLootItemsFrame.activeBoss = nil;
    --Set the item table to the loot table
    AtlasLoot_SetItemInfoFrame(LOOT_ANCHOR);
    --Show the last displayed loot table
    if AtlasLoot_IsLootTableAvailable(AtlasLoot.db.profile.LastBoss) then
        AtlasLoot_ShowBossLoot(AtlasLoot.db.profile.LastBoss, "", LOOT_ANCHOR);
    else
        AtlasLoot_ShowBossLoot("EmptyTable", AL["Select a Loot Table..."], LOOT_ANCHOR);
    end
    UpdateDropdowns();
    UpdateSearchPlaceholder();
end

--[[
AtlasLootDefaultFrame_OnHide:
When we close the loot browser, re-bind the item table to Atlas
and close all Dewdrop menus
]]
function AtlasLootDefaultFrame_OnHide()
    if AtlasFrame then
        AtlasLoot_SetupForAtlas();
    end
    AtlasLoot_Dewdrop:Close(1);
end

--[[
AtlasLoot_DewdropRegister:
Registers the module and subcategory dropdown menus
]]
function AtlasLoot_DewdropRegister()
    local point = function() return "TOPRIGHT", "BOTTOMRIGHT" end;

    AtlasLoot_Dewdrop:Register(moduleBox,
        'point', point,
        'children', function(level)
            if level ~= 1 then return end
            for i, module in ipairs(GetModules()) do
                AtlasLoot_Dewdrop:AddLine(
                    'text', module.text,
                    'textR', 1, 'textG', 0.82, 'textB', 0,
                    'func', SelectModule,
                    'arg1', i,
                    'checked', state.module == i,
                    'isRadio', true,
                    'closeWhenClicked', true
                );
            end
        end,
        'dontHook', true
    );

    AtlasLoot_Dewdrop:Register(subBox,
        'point', point,
        'children', function(level)
            local module = state.module and GetModules()[state.module];
            if level ~= 1 or not module then return end
            for i, sub in ipairs(module.subs) do
                if sub.id then
                    AtlasLoot_Dewdrop:AddLine(
                        'text', sub.indent and ("   "..sub.text) or sub.text,
                        'textR', 1, 'textG', 0.82, 'textB', 0,
                        'func', SelectSub,
                        'arg1', i,
                        'checked', state.sub == i,
                        'isRadio', true,
                        'closeWhenClicked', true
                    );
                else
                    AtlasLoot_Dewdrop:AddLine(
                        'text', sub.text,
                        'isTitle', true
                    );
                end
            end
        end,
        'dontHook', true
    );
end

--[[
AtlasLoot_SetNewStyle(style):
Sets the loot browser background
	style = "new": dark
	style = "old": parchment with a gold border
]]
function AtlasLoot_SetNewStyle(style)
    local frame = AtlasLootDefaultFrame;
    if style == "old" then
        frame:SetBackdrop({
            bgFile = "Interface\\AchievementFrame\\UI-Achievement-AchievementBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        });
        frame:SetBackdropColor(1, 1, 1, 1);
        frame:SetBackdropBorderColor(1, 0.675, 0.125, 1);
        frame.titleBar:SetVertexColor(0.2, 0.12, 0.05, 0.9);
    else
        frame:SetBackdrop(PANEL_BACKDROP);
        frame:SetBackdropColor(0.05, 0.05, 0.05, 0.94);
        frame:SetBackdropBorderColor(0.45, 0.45, 0.45, 1);
        frame.titleBar:SetVertexColor(0.12, 0.12, 0.12, 1);
    end
end
