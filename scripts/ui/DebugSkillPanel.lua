-- ============================================================================
-- DebugSkillPanel.lua - 调试技能面板（PC 端按 9 切换显示）
-- 使用 Dropdown 替换槽位 + Tag 管理可叠加 buff
-- ============================================================================

local Tween      = require "lib.Tween"
local Theme      = require "ui.Theme"
local Components = require "ui.Components"
local SkillState = require "game.SkillState"

local M = {}

local W_, H_ = 0, 0
local visible_ = false

-- ═══ 动画状态 ═══
local anim_ = {
    slideX    = 1,   -- 0=完全展开, 1=完全收起(右侧)
    maskAlpha = 0,
}

-- ═══ Dropdown 状态管理 ═══
-- 每个 dropdown 的 state: { open, selectedIdx, items }
local dropdowns_ = {}
local openDropdown_ = nil  -- 当前展开的 dropdown key (互斥)

-- ═══ Buff 标签管理 ═══
local BUFF_DEFS = {
    { id = "orbit_dmg",    name = "穿甲弹芯",  color = { 0.30, 0.80, 1.00, 1.0 } },
    { id = "orbit_layers", name = "扩编轨道",  color = { 0.30, 0.80, 1.00, 1.0 } },
    { id = "bt_cap",       name = "深渊容器",  color = { 0.80, 0.40, 1.00, 1.0 } },
    { id = "bt_regen",     name = "量子充能",  color = { 0.80, 0.40, 1.00, 1.0 } },
    { id = "bt_cost",      name = "节能模式",  color = { 0.80, 0.40, 1.00, 1.0 } },
    { id = "bt_graze",     name = "危险舞者",  color = { 0.80, 0.40, 1.00, 1.0 } },
    { id = "hp_up",        name = "钢铁意志",  color = { 1.00, 0.40, 0.40, 1.0 } },
    { id = "hp_regen",     name = "生命脉动",  color = { 1.00, 0.40, 0.40, 1.0 } },
}

-- buffCounts_[id] = count
local buffCounts_ = {}

-- "添加buff" 下拉菜单状态
local addBuffDropdown_ = { open = false, selectedIdx = 1, items = {} }

-- 点击缓存
local clickTargets_ = {}  -- { type, key, ... }

-- ═══ 槽位定义 ═══
local SLOT_SECTIONS = {
    { key = "shot_lv",  axis = "shot",  type = "level",  label = "射击 Lv",  color = { 1.00, 0.70, 0.20, 1.0 } },
    { key = "shot_fm",  axis = "shot",  type = "form",   label = "射击形态", color = { 1.00, 0.70, 0.20, 1.0 } },
    { key = "orbit_lv", axis = "orbit", type = "level",  label = "轨道 Lv",  color = { 1.00, 0.70, 0.20, 1.0 } },
    { key = "orbit_fm", axis = "orbit", type = "form",   label = "轨道形态", color = { 1.00, 0.70, 0.20, 1.0 } },
    { key = "qte_lv",   axis = "qte",   type = "level",  label = "QTE Lv",   color = { 1.00, 0.70, 0.20, 1.0 } },
    { key = "qte_fm",   axis = "qte",   type = "form",   label = "QTE形态",  color = { 1.00, 0.70, 0.20, 1.0 } },
    { key = "steal_lv", axis = "steal", type = "level",  label = "偷取 Lv",  color = { 0.30, 1.00, 0.60, 1.0 } },
    { key = "mine_lv",  axis = "mine",  type = "level",  label = "诡雷 Lv",  color = { 1.00, 0.40, 0.50, 1.0 } },
    { key = "link_lv",  axis = "link",  type = "level",  label = "连线 Lv",  color = { 0.40, 0.70, 1.00, 1.0 } },
}

-- ═══ 初始化 ═══

function M.init(W, H)
    W_ = W
    H_ = H
    visible_ = false
    openDropdown_ = nil
    buffCounts_ = {}
    anim_.slideX = 1
    anim_.maskAlpha = 0

    -- 初始化所有 dropdown 状态
    M.rebuildDropdowns()

    -- 初始化 buff 添加菜单
    addBuffDropdown_.items = {}
    for _, def in ipairs(BUFF_DEFS) do
        addBuffDropdown_.items[#addBuffDropdown_.items + 1] = def.name
    end
end

--- 根据 SkillState 重建 dropdown items 和 selectedIdx
function M.rebuildDropdowns()
    dropdowns_ = {}
    for _, sec in ipairs(SLOT_SECTIONS) do
        local items = {}
        local selIdx = 1

        if sec.type == "level" then
            local maxLv = SkillState.MAX_LEVELS[sec.axis] or 5
            -- B/C/D 线从 0 开始（0=未解锁）
            local startLv = (sec.axis == "steal" or sec.axis == "mine" or sec.axis == "link") and 0 or 1
            for lv = startLv, maxLv do
                items[#items + 1] = "Lv " .. lv
            end
            local curLv = SkillState.getLevel(sec.axis)
            selIdx = curLv - startLv + 1
        elseif sec.type == "form" then
            local maxF = SkillState.MAX_FORMS[sec.axis] or 1
            for f = 1, maxF do
                local name = SkillState.getFormName(sec.axis, f)
                items[#items + 1] = f .. ":" .. name
            end
            selIdx = SkillState.getForm(sec.axis)
        end

        dropdowns_[sec.key] = {
            open = false,
            selectedIdx = math.max(1, math.min(selIdx, #items)),
            items = items,
        }
    end
end

-- ═══ 显示/隐藏 ═══

function M.toggle()
    if visible_ then M.hide() else M.show() end
end

function M.show()
    visible_ = true
    openDropdown_ = nil
    M.rebuildDropdowns()

    Tween.cancelTarget(anim_)
    anim_.slideX = 1
    anim_.maskAlpha = 0
    Tween.to(anim_, { slideX = 0 }, 0.35, { easing = Tween.Easing.easeOutCubic })
    Tween.to(anim_, { maskAlpha = 1 }, 0.25, { easing = Tween.Easing.easeOutCubic })
    print("[DebugSkill] Panel opened")
end

function M.isVisible()
    return visible_
end

function M.hide()
    openDropdown_ = nil
    Tween.cancelTarget(anim_)
    Tween.to(anim_, { slideX = 1, maskAlpha = 0 }, 0.25, {
        easing = Tween.Easing.easeInCubic,
        onComplete = function() visible_ = false end,
    })
    print("[DebugSkill] Panel closed")
end

-- ═══ buff 重算系统 ═══

--- 将当前 buffCounts_ 应用到 Player（从基础值重算）
function M.reapplyBuffs()
    local Player = require("game.Player")
    local p = Player.getData()

    -- 重置到基础值
    p.orbitDamage     = 1
    p.maxOrbitBullets = 12
    p.energyMaxMult   = 1.0
    p.energyRegenMult = 1.0
    p.energyCostMult  = 1.0
    p.grazeEnergyMult = 1.0
    p.stealHeal       = 0
    -- HP: 重算 maxHp（基础100），hp 按比例保留
    local hpRatio = (p.maxHp > 0) and (p.hp / p.maxHp) or 1.0
    p.maxHp = 100

    -- 叠加 buff
    for id, count in pairs(buffCounts_) do
        for _ = 1, count do
            if id == "orbit_dmg"    then p.orbitDamage = p.orbitDamage + 1
            elseif id == "orbit_layers" then p.maxOrbitBullets = (p.maxOrbitBullets or 12) + 4
            elseif id == "bt_cap"       then p.energyMaxMult = p.energyMaxMult * 1.3
            elseif id == "bt_regen"     then p.energyRegenMult = p.energyRegenMult * 1.4
            elseif id == "bt_cost"      then p.energyCostMult = p.energyCostMult * 0.75
            elseif id == "bt_graze"     then p.grazeEnergyMult = p.grazeEnergyMult * 1.5
            elseif id == "hp_up"        then p.maxHp = p.maxHp + 20
            elseif id == "hp_regen"     then p.stealHeal = p.stealHeal + 1
            end
        end
    end

    p.hp = math.min(p.maxHp, math.floor(hpRatio * p.maxHp))
    print("[DebugSkill] Buffs reapplied:", M.getBuffSummary())
end

function M.getBuffSummary()
    local parts = {}
    for id, count in pairs(buffCounts_) do
        if count > 0 then
            parts[#parts + 1] = id .. "x" .. count
        end
    end
    return table.concat(parts, ", ")
end

-- ═══ 绘制 ═══

function M.draw(vg, W, H)
    if not visible_ and anim_.slideX >= 0.99 then return end

    W_ = W
    H_ = H
    clickTargets_ = {}

    -- 半透明遮罩
    if anim_.maskAlpha > 0.01 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        nvgFillColor(vg, nvgRGBAf(0.06, 0.08, 0.14, 0.35 * anim_.maskAlpha))
        nvgFill(vg)
    end

    -- 面板尺寸
    local panelW = math.min(260, W * 0.52)
    local panelX = W - panelW - 10 + anim_.slideX * (panelW + 20)
    local panelY = 10

    -- 计算面板高度
    local rowH = 28
    local sectionH = #SLOT_SECTIONS * rowH
    -- buff 区域：标题(22) + 每个buff tag(28) + 添加dropdown(28) + 间距(12)
    local buffCount = 0
    for _, c in pairs(buffCounts_) do if c > 0 then buffCount = buffCount + 1 end end
    local buffAreaH = 22 + buffCount * 28 + 28 + 12
    -- 面板总高 = 标题(44) + 槽位区 + 分隔间距(14) + buff区 + 底部按钮区(50)
    local panelH = 44 + sectionH + 14 + buffAreaH + 50

    -- 面板背景
    Components.drawPanel(vg, panelX, panelY, panelW, panelH, { dark = true })

    -- 标题
    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.accentYellow)))
    nvgText(vg, panelX + panelW * 0.5, panelY + 20, "DEBUG · SKILLS")

    -- 分隔线
    local sepY = panelY + 36
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 10, sepY)
    nvgLineTo(vg, panelX + panelW - 10, sepY)
    nvgStrokeColor(vg, nvgRGBAf(1, 1, 1, 0.12))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ═══ 槽位区：Dropdown 行列表 ═══
    local curY = sepY + 8
    local padX = panelX + 10
    local innerW = panelW - 20
    local ddW = 90  -- dropdown 宽度
    local ddH = 22  -- dropdown 高度

    -- 先绘制所有非展开的（展开的最后绘制以确保在最上层）
    local deferDraw = nil

    for _, sec in ipairs(SLOT_SECTIONS) do
        local dd = dropdowns_[sec.key]
        if not dd then goto continue_slot end

        local labelW = 60
        local ddX = padX + innerW - ddW
        local ddY = curY + (rowH - ddH) * 0.5

        -- 标签
        nvgFontFace(vg, Theme.font.family)
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(Theme.c(sec.color)))
        nvgText(vg, padX, curY + rowH * 0.5, sec.label)

        -- Dropdown (展开的延迟绘制)
        if dd.open then
            deferDraw = { sec = sec, dd = dd, x = ddX, y = ddY, w = ddW, h = ddH, curY = curY }
        else
            local result = Components.drawDropdown(vg, ddX, ddY, ddW, ddH, dd, { accentColor = sec.color })
            clickTargets_[#clickTargets_ + 1] = { type = "dropdown", key = sec.key, result = result }
        end

        curY = curY + rowH
        ::continue_slot::
    end

    -- 展开中的 dropdown 最后绘制（z-order 最高）
    if deferDraw then
        local sec = deferDraw.sec
        local dd = deferDraw.dd
        nvgSave(vg)
        local result = Components.drawDropdown(vg, deferDraw.x, deferDraw.y, deferDraw.w, deferDraw.h, dd, { accentColor = sec.color })
        clickTargets_[#clickTargets_ + 1] = { type = "dropdown", key = sec.key, result = result, zTop = true }
        nvgRestore(vg)
    end

    -- ═══ 分隔线: buff 区域 ═══
    curY = sepY + 8 + sectionH + 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 10, curY)
    nvgLineTo(vg, panelX + panelW - 10, curY)
    nvgStrokeColor(vg, nvgRGBAf(1, 1, 1, 0.12))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 区域标题
    curY = curY + 4
    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(0.7, 0.7, 0.8, 0.8))
    nvgText(vg, padX, curY + 10, "BUFFS")
    curY = curY + 22

    -- 已有的 buff tags
    for _, def in ipairs(BUFF_DEFS) do
        local count = buffCounts_[def.id] or 0
        if count > 0 then
            local tagResult = Components.drawTag(vg, padX, curY, def.name, count, def.color)
            clickTargets_[#clickTargets_ + 1] = { type = "tag_minus", buffId = def.id, rect = tagResult.minusRect }
            clickTargets_[#clickTargets_ + 1] = { type = "tag_plus",  buffId = def.id, rect = tagResult.plusRect }
            curY = curY + 28
        end
    end

    -- "添加 buff" dropdown
    local addDdX = padX
    local addDdY = curY + 2
    local addDdW = ddW + 20
    if addBuffDropdown_.open then
        nvgSave(vg)
    end
    local addResult = Components.drawDropdown(vg, addDdX, addDdY, addDdW, ddH, addBuffDropdown_, {
        accentColor = Theme.colors.accentGreen,
    })
    clickTargets_[#clickTargets_ + 1] = { type = "dropdown", key = "__addBuff", result = addResult }
    if addBuffDropdown_.open then
        nvgRestore(vg)
    end

    -- ═══ 底部按钮 ═══
    local btnY = panelY + panelH - 42
    -- 重置全部按钮
    local resetRect = Components.drawButton(vg, panelX + panelW * 0.35, btnY, "Reset All", { variant = "accent", w = 80 })
    clickTargets_[#clickTargets_ + 1] = { type = "btn_reset", rect = resetRect }

    -- 关闭按钮
    local closeRect = Components.drawButton(vg, panelX + panelW * 0.72, btnY, "Close", { variant = "dark", w = 60 })
    clickTargets_[#clickTargets_ + 1] = { type = "btn_close", rect = closeRect }
end

-- ═══ 点击处理 ═══

function M.onClick(x, y)
    if not visible_ then return false end

    -- 优先处理展开的 dropdown 的 item 点击（z-order 最高）
    for i = #clickTargets_, 1, -1 do
        local ct = clickTargets_[i]

        if ct.type == "dropdown" and ct.result then
            local result = ct.result
            local key = ct.key

            -- 如果该 dropdown 是展开状态，先检查 item 点击
            local dd = (key == "__addBuff") and addBuffDropdown_ or dropdowns_[key]
            if dd and dd.open then
                for idx, itemRect in ipairs(result.itemRects) do
                    if Components.hitTest(itemRect, x, y) then
                        M.onDropdownSelect(key, idx)
                        return true
                    end
                end
                -- 点击展开区域外 → 关闭
                dd.open = false
                openDropdown_ = nil
                return true
            end

            -- trigger 点击 → 切换展开
            if Components.hitTest(result.triggerRect, x, y) then
                M.toggleDropdown(key)
                return true
            end
        end

        if ct.type == "tag_minus" and ct.rect and Components.hitTest(ct.rect, x, y) then
            M.removeBuff(ct.buffId)
            return true
        end

        if ct.type == "tag_plus" and ct.rect and Components.hitTest(ct.rect, x, y) then
            M.addBuff(ct.buffId)
            return true
        end

        if ct.type == "btn_reset" and ct.rect and Components.hitTest(ct.rect, x, y) then
            M.resetAll()
            return true
        end

        if ct.type == "btn_close" and ct.rect and Components.hitTest(ct.rect, x, y) then
            M.hide()
            return true
        end
    end

    -- 点击面板外区域 → 关闭展开的 dropdown
    if openDropdown_ then
        openDropdown_ = nil
        for _, dd in pairs(dropdowns_) do dd.open = false end
        addBuffDropdown_.open = false
        return true
    end

    return false
end

-- ═══ Dropdown 操作 ═══

function M.toggleDropdown(key)
    -- 关闭其他所有 dropdown
    for k, dd in pairs(dropdowns_) do
        if k ~= key then dd.open = false end
    end
    if key ~= "__addBuff" then
        addBuffDropdown_.open = false
    else
        for _, dd in pairs(dropdowns_) do dd.open = false end
    end

    local dd = (key == "__addBuff") and addBuffDropdown_ or dropdowns_[key]
    if dd then
        dd.open = not dd.open
        openDropdown_ = dd.open and key or nil
    end
end

function M.onDropdownSelect(key, idx)
    if key == "__addBuff" then
        -- 添加选中的 buff
        addBuffDropdown_.open = false
        openDropdown_ = nil
        local def = BUFF_DEFS[idx]
        if def then
            M.addBuff(def.id)
        end
        return
    end

    -- 槽位 dropdown 选中
    local dd = dropdowns_[key]
    if not dd then return end
    dd.selectedIdx = idx
    dd.open = false
    openDropdown_ = nil

    -- 应用到 SkillState
    for _, sec in ipairs(SLOT_SECTIONS) do
        if sec.key == key then
            if sec.type == "level" then
                local startLv = (sec.axis == "steal" or sec.axis == "mine" or sec.axis == "link") and 0 or 1
                local newLv = startLv + idx - 1
                SkillState.setLevel(sec.axis, newLv)
                print(string.format("[DebugSkill] %s level → %d", sec.axis, newLv))
            elseif sec.type == "form" then
                SkillState.setForm(sec.axis, idx)
                print(string.format("[DebugSkill] %s form → %d (%s)", sec.axis, idx, SkillState.getFormName(sec.axis, idx)))
            end
            break
        end
    end
end

-- ═══ Buff 操作 ═══

function M.addBuff(id)
    buffCounts_[id] = (buffCounts_[id] or 0) + 1
    M.reapplyBuffs()
end

function M.removeBuff(id)
    local cur = buffCounts_[id] or 0
    if cur <= 1 then
        buffCounts_[id] = nil
    else
        buffCounts_[id] = cur - 1
    end
    M.reapplyBuffs()
end

function M.resetAll()
    -- 重置技能树
    SkillState.reset()
    M.rebuildDropdowns()
    -- 重置 buff
    buffCounts_ = {}
    M.reapplyBuffs()
    openDropdown_ = nil
    print("[DebugSkill] All reset")
end

return M
