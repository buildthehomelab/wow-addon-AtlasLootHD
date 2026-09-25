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
local HEADER_HEIGHT = 36;
local ITEM_TOP, ITEM_HEIGHT = -46, 29;
local ITEM_WIDTH = (LOOT_WIDTH - 12) / 2;
local ICON_SIZE = 26;
local LINE_HEIGHT = 18;
local SECTION_HEADER_HEIGHT = 20;
local DIFFICULTY_LINES, BOSS_LINES, EXTRA_LINES = 4, 15, 6;

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8";
local GOLD_DOT = "Interface\\AddOns\\AtlasLoot\\Images\\gold";
local SILVER_DOT = "Interface\\AddOns\\AtlasLoot\\Images\\silver";
--Stock 3.3.5 art: the achievement row parchment and the quest greeting divider
local PARCHMENT_TEXTURE = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal";
local DIVIDER_TEXTURE = "Interface\\QuestFrame\\UI-HorizontalBreak";

--Theme colors: a dark metal frame around a parchment loot page
local INK = { 0.22, 0.14, 0.06 };
local INK_LIGHT = { 0.38, 0.29, 0.18 };
local BRONZE = { 0.55, 0.44, 0.26 };
local EDGE = { 0.3, 0.25, 0.17 };

--Where loot tables are anchored in the browser.  Kept in the global pFrame too,
--because the search and wishlist code read it from there.
local LOOT_ANCHOR = { "TOPLEFT", "AtlasLootDefaultFrame_LootBackground", "TOPLEFT", "2", "-2" };

--Flat panels with a 1px border
local PANEL_BACKDROP = { bgFile = WHITE_TEXTURE, edgeFile = WHITE_TEXTURE, edgeSize = 1 };

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
local bossScrollBar, searchBox, searchPlaceholder, pageCounter;
local itemsLayoutModern, backButtonWidth;
--The "New Style" loot page is parchment, "Classic Style" keeps it dark
local parchment = true;
local pageTextures = { parchment = {}, dark = {} };

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
    frame:SetBackdropColor(0.04, 0.04, 0.04, alpha);
    frame:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], 1);
end

--A 1px line around the inside of a frame, used to build the beveled metal edge
local function AddBorder(frame, inset, r, g, b, a)
    local top = SolidTexture(frame, "BORDER", r, g, b, a);
    top:SetPoint("TOPLEFT", inset, -inset);
    top:SetPoint("TOPRIGHT", -inset, -inset);
    top:SetHeight(1);
    local bottom = SolidTexture(frame, "BORDER", r, g, b, a);
    bottom:SetPoint("BOTTOMLEFT", inset, inset);
    bottom:SetPoint("BOTTOMRIGHT", -inset, inset);
    bottom:SetHeight(1);
    local left = SolidTexture(frame, "BORDER", r, g, b, a);
    left:SetPoint("TOPLEFT", inset, -inset);
    left:SetPoint("BOTTOMLEFT", inset, inset);
    left:SetWidth(1);
    local right = SolidTexture(frame, "BORDER", r, g, b, a);
    right:SetPoint("TOPRIGHT", -inset, -inset);
    right:SetPoint("BOTTOMRIGHT", -inset, inset);
    right:SetWidth(1);
end

--A section of the right-hand column: a dark header bar with a gold title, then its lines
local function CreateSection(parent, title, height)
    local section = CreateFrame("Frame", nil, parent);
    section:SetWidth(SIDE_WIDTH - 8);
    section:SetHeight(height);
    local header = SolidTexture(section, "ARTWORK", 1, 1, 1, 1);
    header:SetPoint("TOPLEFT");
    header:SetPoint("TOPRIGHT");
    header:SetHeight(SECTION_HEADER_HEIGHT);
    header:SetGradientAlpha("HORIZONTAL", 0.24, 0.2, 0.13, 1, 0.1, 0.09, 0.07, 1);
    local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    label:SetPoint("LEFT", header, "LEFT", 8, 0);
    label:SetText(title);
    return section;
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
    line:SetWidth(SIDE_WIDTH - 16);
    line:SetHeight(LINE_HEIGHT);
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -SECTION_HEADER_HEIGHT - 2 - (index - 1) * LINE_HEIGHT);
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp");

    line.selected = SolidTexture(line, "BACKGROUND", 1, 1, 1, 1);
    line.selected:SetAllPoints();
    line.selected:SetGradientAlpha("HORIZONTAL", 0.8, 0.62, 0.12, 0.8, 0.8, 0.62, 0.12, 0);
    line.selected:Hide();

    local highlight = SolidTexture(line, "HIGHLIGHT", 1, 1, 1, 1);
    highlight:SetAllPoints();
    highlight:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.2, 1, 0.82, 0, 0);

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
    SkinPanel(box, 0.9);

    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    box.label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 2, 1);
    box.label:SetText(label);

    --Not called "arrow": Dewdrop treats a parent with an arrow field as one of its own menu buttons
    box.arrowButton = CreateFrame("Button", nil, box);
    box.arrowButton:SetWidth(22);
    box.arrowButton:SetHeight(22);
    box.arrowButton:SetPoint("RIGHT", box, "RIGHT", -2, 0);
    box.arrowButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up");
    box.arrowButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down");
    box.arrowButton:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled");
    box.arrowButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");

    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    box.text:SetPoint("LEFT", box, "LEFT", 8, 0);
    box.text:SetPoint("RIGHT", box.arrowButton, "LEFT", -4, 0);
    box.text:SetJustifyH("RIGHT");

    local highlight = SolidTexture(box, "HIGHLIGHT", 1, 1, 1, 0.06);
    highlight:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1);
    highlight:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1);

    box:SetScript("OnClick", function() ToggleDropdown(box) end);
    box.arrowButton:SetScript("OnClick", function() ToggleDropdown(box) end);
    return box;
end

local function SetDropdownEnabled(box, enabled)
    if enabled then
        box:Enable();
        box.arrowButton:Enable();
        box.text:SetTextColor(1, 1, 1);
    else
        box:Disable();
        box.arrowButton:Disable();
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
    state.bossOffset = 0;
    bossScrollBar:SetValue(0);
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
    local maxOffset = math.max(#state.bosses - BOSS_LINES, 0);
    local offset = math.min(state.bossOffset or 0, maxOffset);
    state.bossOffset = offset;
    bossScrollBar:SetMinMaxValues(0, maxOffset);
    bossScrollBar:SetValue(offset);
    if maxOffset > 0 then
        bossScrollBar:Show();
    else
        bossScrollBar:Hide();
    end
    local width = SIDE_WIDTH - (maxOffset > 0 and 28 or 16);
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
    if not bossScrollBar then
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
    local nameText, extraText = getglobal(name.."_Name"), getglobal(name.."_Extra");
    local highlight = button:GetHighlightTexture();
    icon:ClearAllPoints();
    unsafe:ClearAllPoints();
    if modern then
        button:SetWidth(ITEM_WIDTH);
        button:SetHeight(ITEM_HEIGHT);
        icon:SetWidth(ICON_SIZE);
        icon:SetHeight(ICON_SIZE);
        icon:SetPoint("LEFT", button, "LEFT", 3, 0);
        unsafe:SetWidth(ICON_SIZE + 2);
        unsafe:SetHeight(ICON_SIZE + 2);
        unsafe:SetPoint("CENTER", icon, "CENTER");
        nameText:SetWidth(ITEM_WIDTH - ICON_SIZE - 12);
        extraText:SetWidth(ITEM_WIDTH - ICON_SIZE - 12);
        highlight:SetTexture(WHITE_TEXTURE);
        highlight:SetBlendMode("BLEND");
        --Uncached items are queried automatically, so the unsafe marker only means "loading" now
        if parchment then
            unsafe:SetTexture(INK_LIGHT[1], INK_LIGHT[2], INK_LIGHT[3], 1);
            nameText:SetTextColor(INK[1], INK[2], INK[3]);
            extraText:SetTextColor(INK_LIGHT[1], INK_LIGHT[2], INK_LIGHT[3]);
            nameText:SetShadowColor(0, 0, 0, 0);
            extraText:SetShadowColor(0, 0, 0, 0);
            highlight:SetGradientAlpha("HORIZONTAL", 0.45, 0.28, 0.08, 0.3, 0.45, 0.28, 0.08, 0);
        else
            unsafe:SetTexture(0.4, 0.4, 0.4, 1);
            nameText:SetTextColor(1, 0.82, 0);
            extraText:SetTextColor(1, 0.82, 0);
            nameText:SetShadowColor(0, 0, 0, 1);
            extraText:SetShadowColor(0, 0, 0, 1);
            highlight:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.3, 1, 0.82, 0, 0);
        end
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
        unsafe:SetTexture(1, 0, 0, 1);
        nameText:SetWidth(205);
        extraText:SetWidth(205);
        nameText:SetTextColor(1, 0.82, 0);
        extraText:SetTextColor(1, 0.82, 0);
        nameText:SetShadowColor(0, 0, 0, 1);
        extraText:SetShadowColor(0, 0, 0, 1);
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
        AtlasLoot_BossName:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -4);
        AtlasLoot_BossName:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -4);
        AtlasLoot_BossName:SetHeight(HEADER_HEIGHT - 4);
        --Page arrows sit together at the bottom right, next to the page counter
        AtlasLootItemsFrame_NEXT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 2);
        AtlasLootItemsFrame_PREV:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 2);
        AtlasLootItemsFrame_BACK:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 7);
        AtlasLootFilterCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 96, 5);
        --Pages query their uncached items on their own in the browser
        AtlasLootServerQueryButton:Hide();
        if parchment then
            AtlasLoot_BossName:SetFontObject(GameFontNormalHuge);
            AtlasLoot_BossName:SetJustifyH("LEFT");
            AtlasLoot_BossName:SetTextColor(INK[1], INK[2], INK[3]);
            AtlasLoot_BossName:SetShadowColor(0, 0, 0, 0);
            AtlasLootFilterCheckText:SetTextColor(INK[1], INK[2], INK[3]);
            AtlasLootFilterCheckText:SetShadowColor(0, 0, 0, 0);
        else
            AtlasLoot_BossName:SetFontObject(GameFontHighlightLarge);
            AtlasLoot_BossName:SetJustifyH("CENTER");
            AtlasLoot_BossName:SetTextColor(1, 1, 1);
            AtlasLoot_BossName:SetShadowColor(0, 0, 0, 1);
            AtlasLootFilterCheckText:SetTextColor(1, 0.82, 0);
            AtlasLootFilterCheckText:SetShadowColor(0, 0, 0, 1);
        end
    else
        AtlasLoot_BossName:SetFontObject(GameFontHighlightLarge);
        AtlasLoot_BossName:SetJustifyH("CENTER");
        AtlasLoot_BossName:SetTextColor(1, 1, 1);
        AtlasLoot_BossName:SetShadowColor(0, 0, 0, 1);
        AtlasLootFilterCheckText:SetTextColor(1, 0.82, 0);
        AtlasLootFilterCheckText:SetShadowColor(0, 0, 0, 1);
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
        AtlasLootServerQueryButton:Show();
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
    elseif itemsLayoutModern then
        SetItemsFrameLayout(false);
    end
end

--The item a loot button shows, or the item a crafting recipe makes
local function ButtonItemID(button)
    local itemID = button.itemID;
    if type(itemID) == "string" and strsub(itemID, 1, 1) == "s" then
        itemID = button.spellitemID;
    end
    itemID = tonumber(itemID);
    if itemID and itemID > 0 then
        return itemID;
    end
end

local function UpdateQualityBorders()
    for i = 1, 30 do
        local button = getglobal("AtlasLootItem_"..i);
        local loading = getglobal("AtlasLootItem_"..i.."_Unsafe"):IsShown();
        local quality;
        if button:IsShown() and not loading then
            local itemID = ButtonItemID(button);
            if itemID then
                quality = select(3, GetItemInfo(itemID));
            end
        end
        --The border only exists once the modern layout has been applied.
        --On parchment every icon gets a frame, bronze until its quality is known.
        local border = button.qualityBorder;
        if border and quality then
            local r, g, b = GetItemQualityColor(quality);
            border:SetVertexColor(r, g, b, 1);
            border:Show();
        elseif border and parchment and button:IsShown() and not loading then
            border:SetVertexColor(EDGE[1], EDGE[2], EDGE[3], 1);
            border:Show();
        elseif border then
            border:Hide();
        end
    end
end

--[[
Parchment text
Item names and descriptions carry color codes meant for a dark background.
Light ones are darkened so they stay readable on parchment: white and grey
become ink, other colors keep their hue. Colors that are already dark are left
alone, so darkening the same text twice changes nothing.
]]
local function ParchmentColor(alpha, hex)
    local r = tonumber(strsub(hex, 1, 2), 16) / 255;
    local g = tonumber(strsub(hex, 3, 4), 16) / 255;
    local b = tonumber(strsub(hex, 5, 6), 16) / 255;
    local luminance = 0.299 * r + 0.587 * g + 0.114 * b;
    if luminance <= 0.4 then
        return "|c"..alpha..hex;
    end
    if math.max(r, g, b) - math.min(r, g, b) < 0.15 then
        --White and grey: the lighter the color, the darker the ink
        local fade = (1 - luminance) * 0.6;
        r, g, b = INK[1] + fade, INK[2] + fade, INK[3] + fade;
    else
        local scale = 0.32 / luminance;
        r, g, b = r * scale, g * scale, b * scale;
    end
    return format("|c%s%02x%02x%02x", alpha, floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5));
end

local function DarkenText(fontString)
    local text = fontString:GetText();
    if text then
        fontString:SetText((gsub(text, "|c(%x%x)(%x%x%x%x%x%x)", ParchmentColor)));
    end
end

local function DarkenPageText()
    for i = 1, 30 do
        for _, prefix in ipairs({ "AtlasLootItem_", "AtlasLootMenuItem_" }) do
            if getglobal(prefix..i):IsShown() then
                DarkenText(getglobal(prefix..i.."_Name"));
                DarkenText(getglobal(prefix..i.."_Extra"));
            end
        end
    end
end

--"Page 2/3" for loot tables split over pages that share a title. Next and Prev
--also link separate bosses, which have different titles and are not counted.
local function UpdatePageCounter(page)
    local names = page and AtlasLoot_TableNames[page];
    local data = page and AtlasLoot_Data[page];
    if not (names and data) or IsMenu(page) then
        pageCounter:Hide();
        return;
    end
    local title = names[1];
    local function SamePage(id)
        return id and AtlasLoot_Data[id] and AtlasLoot_TableNames[id] and AtlasLoot_TableNames[id][1] == title;
    end
    local index, total, seen = 1, 1, { [page] = true };
    local id = data.Prev;
    while SamePage(id) and not seen[id] do
        seen[id] = true;
        index, total = index + 1, total + 1;
        id = AtlasLoot_Data[id].Prev;
    end
    id = data.Next;
    while SamePage(id) and not seen[id] do
        seen[id] = true;
        total = total + 1;
        id = AtlasLoot_Data[id].Next;
    end
    if total > 1 then
        pageCounter:SetText(format(AL["Page %d/%d"], index, total));
        pageCounter:Show();
    else
        pageCounter:Hide();
    end
end

--[[
Item cache
Items missing from the client's item cache are queried from the server when
their page is shown, a few at a time, and the page is redrawn as they arrive.
The client keeps its item cache between sessions, so each item is only
queried once and every page is not queried up front.
]]
local QUERY_INTERVAL, QUERY_CHECK_INTERVAL, QUERY_TIMEOUT = 0.05, 0.5, 5;
local queried, queryQueue, queryWaiting = {}, {}, {};
local queryTooltip = CreateFrame("GameTooltip", "AtlasLootHDQueryTooltip", UIParent, "GameTooltipTemplate");
local queryFrame = CreateFrame("Frame");
queryFrame:Hide();

local function RedrawPage()
    if not AtlasLootDefaultFrame:IsShown() or AtlasLootItemsFrame:GetParent() ~= lootBackground then
        return;
    end
    local refresh = AtlasLootItemsFrame.refresh;
    if ATLASLOOT_FILTER_ENABLE then
        refresh = AtlasLootItemsFrame.refreshOri;
    end
    if refresh then
        AtlasLoot_ShowItemsFrame(refresh[1], refresh[2], refresh[3], refresh[4]);
    end
end

queryFrame:SetScript("OnUpdate", function(self, elapsed)
    self.sinceQuery = self.sinceQuery + elapsed;
    if #queryQueue > 0 and self.sinceQuery >= QUERY_INTERVAL then
        self.sinceQuery = 0;
        local itemID = tremove(queryQueue, 1);
        tinsert(queryWaiting, itemID);
        queryTooltip:SetOwner(WorldFrame, "ANCHOR_NONE");
        queryTooltip:SetHyperlink("item:"..itemID..":0:0:0:0:0:0:0");
        self.deadline = GetTime() + QUERY_TIMEOUT;
    end

    self.sinceCheck = self.sinceCheck + elapsed;
    if self.sinceCheck < QUERY_CHECK_INTERVAL then
        return;
    end
    self.sinceCheck = 0;
    local arrived;
    for i = #queryWaiting, 1, -1 do
        if GetItemInfo(queryWaiting[i]) then
            tremove(queryWaiting, i);
            arrived = true;
        end
    end
    if #queryQueue == 0 and (#queryWaiting == 0 or GetTime() > self.deadline) then
        --Whatever has not arrived by now does not exist on this server
        queryWaiting = {};
        self:Hide();
    end
    if arrived then
        RedrawPage();
    end
end);

local function QueryPage()
    for i = 1, 30 do
        local button = getglobal("AtlasLootItem_"..i);
        local itemID = button:IsShown() and ButtonItemID(button);
        if itemID and not queried[itemID] and not GetItemInfo(itemID) then
            queried[itemID] = true;
            tinsert(queryQueue, itemID);
        end
    end
    if #queryQueue > 0 and not queryFrame:IsShown() then
        queryFrame.sinceQuery, queryFrame.sinceCheck = QUERY_INTERVAL, 0;
        queryFrame.deadline = GetTime() + QUERY_TIMEOUT;
        queryFrame:Show();
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
    if parchment then
        DarkenPageText();
    end
    UpdatePageCounter(state.page);
    UpdateQualityBorders();
    QueryPage();
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

local function CreateSearch(frame, width)
    --A flat box like the dropdowns, rather than the stock silver InputBoxTemplate
    searchBox = CreateFrame("EditBox", "AtlasLootDefaultFrameSearchBox", frame);
    searchBox:SetWidth(width);
    searchBox:SetHeight(24);
    searchBox:SetPoint("LEFT", subBox, "RIGHT", 8, 0);
    SkinPanel(searchBox, 0.9);
    searchBox:SetFontObject(GameFontHighlightSmall);
    searchBox:EnableMouse(true);
    searchBox:SetAutoFocus(false);
    searchBox:SetMaxLetters(100);
    searchBox:SetTextInsets(8, 8, 0, 0);

    searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 8, 0);
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

    --Search options use the same yellow arrow as the dropdowns
    local options = CreateFrame("Button", "AtlasLootDefaultFrameSearchOptionsButton", searchBox);
    options:SetWidth(22);
    options:SetHeight(22);
    options:SetPoint("LEFT", searchBox, "RIGHT", 2, 0);
    options:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up");
    options:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down");
    options:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");
    options:SetScript("OnClick", function(self) AtlasLoot:ShowSearchOptions(self) end);
    options:SetScript("OnEnter", function(self) ShowTooltip(self, AL["Search on"]) end);
    options:SetScript("OnLeave", HideTooltip);
end

local function CreateSidePanels(frame)
    --One dark column holding three titled sections, like a settings category list
    local column = CreateFrame("Frame", nil, frame);
    column:SetWidth(SIDE_WIDTH);
    column:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -32);
    column:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD);
    SkinPanel(column, 0.75);

    local difficultyPanel = CreateSection(column, AL["Difficulty"], SECTION_HEADER_HEIGHT + DIFFICULTY_LINES * LINE_HEIGHT + 6);
    difficultyPanel:SetPoint("TOPLEFT", column, "TOPLEFT", 4, -4);
    for i = 1, DIFFICULTY_LINES do
        difficultyLines[i] = CreateLine(difficultyPanel, i, OnDifficultyClick);
    end

    local extraPanel = CreateSection(column, AL["Quick Access"], SECTION_HEADER_HEIGHT + EXTRA_LINES * LINE_HEIGHT + 6);
    extraPanel:SetPoint("BOTTOMLEFT", column, "BOTTOMLEFT", 4, 4);
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

    local bossPanel = CreateSection(column, AL["Bosses"], 0);
    bossPanel:SetPoint("TOPLEFT", difficultyPanel, "BOTTOMLEFT", 0, -6);
    bossPanel:SetPoint("BOTTOMRIGHT", extraPanel, "TOPRIGHT", 0, 6);

    for i = 1, BOSS_LINES do
        bossLines[i] = CreateLine(bossPanel, i, OnBossClick);
    end

    --A plain slider rather than FauxScrollFrameTemplate, whose scripts differ between clients
    bossScrollBar = CreateFrame("Slider", "AtlasLootDefaultFrameBossScrollBar", bossPanel);
    bossScrollBar:SetWidth(6);
    bossScrollBar:SetPoint("TOPRIGHT", bossPanel, "TOPRIGHT", -4, -SECTION_HEADER_HEIGHT - 4);
    bossScrollBar:SetPoint("BOTTOMRIGHT", bossPanel, "BOTTOMRIGHT", -4, 4);
    bossScrollBar:SetOrientation("VERTICAL");
    bossScrollBar:SetValueStep(1);
    bossScrollBar:SetMinMaxValues(0, 0);
    bossScrollBar:SetValue(0);
    bossScrollBar:EnableMouse(true);
    bossScrollBar:SetThumbTexture(WHITE_TEXTURE);
    local thumb = bossScrollBar:GetThumbTexture();
    thumb:SetVertexColor(1, 0.82, 0, 0.7);
    thumb:SetWidth(6);
    thumb:SetHeight(24);
    local track = SolidTexture(bossScrollBar, "BACKGROUND", 1, 1, 1, 0.08);
    track:SetAllPoints();
    bossScrollBar:SetScript("OnValueChanged", function(self, value)
        local offset = floor(value + 0.5);
        if offset ~= state.bossOffset then
            state.bossOffset = offset;
            UpdateBossList();
        end
    end);
    bossScrollBar:Hide();

    bossPanel:EnableMouseWheel(true);
    bossPanel:SetScript("OnMouseWheel", function(self, delta)
        bossScrollBar:SetValue(bossScrollBar:GetValue() - delta * 3);
    end);
end

local function CreateLootPanel(frame)
    lootBackground = CreateFrame("Frame", "AtlasLootDefaultFrame_LootBackground", frame);
    lootBackground:SetWidth(LOOT_WIDTH);
    lootBackground:SetHeight(LOOT_HEIGHT);
    lootBackground:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, LOOT_TOP);
    lootBackground:SetBackdrop({ edgeFile = WHITE_TEXTURE, edgeSize = 1 });
    lootBackground:SetBackdropBorderColor(0.08, 0.06, 0.04, 1);

    --New Style: a parchment page, darker towards its edges, with an ornate
    --divider under the boss name (AtlasLoot_BossName in the items frame)
    local page = pageTextures.parchment;
    local paper = lootBackground:CreateTexture(nil, "BACKGROUND");
    paper:SetTexture(PARCHMENT_TEXTURE);
    paper:SetPoint("TOPLEFT", 1, -1);
    paper:SetPoint("BOTTOMRIGHT", -1, 1);
    tinsert(page, paper);
    --Each edge: two anchors, then the gradient's alpha from bottom to top or left to right
    local edges = {
        { "TOPLEFT", 1, -1, "TOPRIGHT", -1, -1, "VERTICAL", 0, 0.35 },
        { "BOTTOMLEFT", 1, 1, "BOTTOMRIGHT", -1, 1, "VERTICAL", 0.35, 0 },
        { "TOPLEFT", 1, -1, "BOTTOMLEFT", 1, 1, "HORIZONTAL", 0.35, 0 },
        { "TOPRIGHT", -1, -1, "BOTTOMRIGHT", -1, 1, "HORIZONTAL", 0, 0.35 },
    };
    for _, edge in ipairs(edges) do
        local shade = SolidTexture(lootBackground, "BORDER", 1, 1, 1, 1);
        shade:SetPoint(edge[1], edge[2], edge[3]);
        shade:SetPoint(edge[4], edge[5], edge[6]);
        if edge[7] == "VERTICAL" then
            shade:SetHeight(40);
        else
            shade:SetWidth(40);
        end
        shade:SetGradientAlpha(edge[7], 0.25, 0.14, 0.04, edge[8], 0.25, 0.14, 0.04, edge[9]);
        tinsert(page, shade);
    end
    local divider = lootBackground:CreateTexture(nil, "ARTWORK");
    divider:SetTexture(DIVIDER_TEXTURE);
    divider:SetPoint("TOPLEFT", 6, -28);
    divider:SetPoint("TOPRIGHT", -6, -28);
    divider:SetHeight(20);
    tinsert(page, divider);

    --Classic Style: a dark page with a faint header band and gold rule
    local dark = pageTextures.dark;
    local shadow = SolidTexture(lootBackground, "BACKGROUND", 0, 0, 0, 0.5);
    shadow:SetPoint("TOPLEFT", 1, -1);
    shadow:SetPoint("BOTTOMRIGHT", -1, 1);
    tinsert(dark, shadow);
    local header = SolidTexture(lootBackground, "ARTWORK", 1, 1, 1, 0.04);
    header:SetPoint("TOPLEFT", 1, -1);
    header:SetPoint("TOPRIGHT", -1, -1);
    header:SetHeight(HEADER_HEIGHT);
    tinsert(dark, header);
    local ruleLeft = SolidTexture(lootBackground, "ARTWORK", 1, 1, 1, 1);
    ruleLeft:SetPoint("TOPLEFT", header, "BOTTOMLEFT");
    ruleLeft:SetPoint("TOPRIGHT", header, "BOTTOM");
    ruleLeft:SetHeight(1);
    ruleLeft:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0, 1, 0.82, 0, 0.8);
    tinsert(dark, ruleLeft);
    local ruleRight = SolidTexture(lootBackground, "ARTWORK", 1, 1, 1, 1);
    ruleRight:SetPoint("TOPLEFT", header, "BOTTOM");
    ruleRight:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT");
    ruleRight:SetHeight(1);
    ruleRight:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.8, 1, 0.82, 0, 0);
    tinsert(dark, ruleRight);

    pageCounter = lootBackground:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    pageCounter:SetPoint("RIGHT", lootBackground, "BOTTOMRIGHT", -78, 18);
    pageCounter:Hide();
end

local function CreateTitleBar(frame)
    local bar = SolidTexture(frame, "ARTWORK", 1, 1, 1, 1);
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3);
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3);
    bar:SetHeight(22);
    bar:SetGradientAlpha("VERTICAL", 0.05, 0.05, 0.05, 1, 0.13, 0.12, 0.1, 1);
    local barLine = SolidTexture(frame, "ARTWORK", BRONZE[1], BRONZE[2], BRONZE[3], 0.6);
    barLine:SetPoint("TOPLEFT", bar, "BOTTOMLEFT");
    barLine:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT");
    barLine:SetHeight(1);

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    title:SetPoint("CENTER", bar, "CENTER");
    title:SetText(AL["AtlasLoot"]);

    local close = CreateFrame("Button", "AtlasLootDefaultFrame_CloseButton", frame, "UIPanelCloseButton");
    close:SetWidth(26);
    close:SetHeight(26);
    close:SetPoint("RIGHT", bar, "RIGHT", 2, 0);
    close:SetScript("OnClick", function() AtlasLootDefaultFrame:Hide() end);

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
    version:SetPoint("RIGHT", close, "LEFT", -2, 0);
    version:SetText("v"..ATLASLOOT_VERSION_NUMBER);

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

    --Dark metal frame: black outline, a bronze highlight, then a dark inner line
    frame:SetBackdrop(PANEL_BACKDROP);
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.96);
    frame:SetBackdropBorderColor(0, 0, 0, 1);
    AddBorder(frame, 1, BRONZE[1], BRONZE[2], BRONZE[3], 1);
    AddBorder(frame, 2, 0.12, 0.1, 0.07, 1);

    CreateTitleBar(frame);

    --Module and subcategory dropdowns, then the search box, above the loot page
    local dropdownWidth, searchWidth = 210, LOOT_WIDTH - 2 * 210 - 2 * 8 - 24;
    moduleBox = CreateDropdown(frame, AL["Select Module"], dropdownWidth);
    moduleBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -44);
    subBox = CreateDropdown(frame, AL["Select Subcategory"], dropdownWidth);
    subBox:SetPoint("LEFT", moduleBox, "RIGHT", 8, 0);

    CreateLootPanel(frame);
    CreateSearch(frame, searchWidth);
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
Sets the loot page style, from the Loot Browser Style option
	style = "new": parchment, like a spellbook page
	style = "old": dark
]]
function AtlasLoot_SetNewStyle(style)
    parchment = style ~= "old";
    for _, texture in ipairs(pageTextures.parchment) do
        if parchment then texture:Show() else texture:Hide() end
    end
    for _, texture in ipairs(pageTextures.dark) do
        if parchment then texture:Hide() else texture:Show() end
    end
    if parchment then
        pageCounter:SetTextColor(INK[1], INK[2], INK[3]);
        pageCounter:SetShadowColor(0, 0, 0, 0);
    else
        pageCounter:SetTextColor(1, 0.82, 0);
        pageCounter:SetShadowColor(0, 0, 0, 1);
    end
    --Restyle the loot rows and redraw the page in the new colors
    if itemsLayoutModern then
        SetItemsFrameLayout(true);
        RedrawPage();
    end
end
