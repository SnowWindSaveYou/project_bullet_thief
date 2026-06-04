-- ============================================================================
-- DebugChenxiPanel.lua - 晨曦调试面板（PC 端按 0 切换显示）
-- 管理：cx_slash/cx_finisher 形态等级、能量手动设置、段位预览
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
    slideX    = 1,   -- 0=完全展开, 1=完全收起(左侧)
    maskAlpha = 0,
}

-- ═══ Dropdown 状态管理 ═══
local dropdowns_ = {}
local openDropdown_ = nil

-- ═══ 能量滑块状态 ═══
local energySlider_ = { dragging = false, value = 0 }

-- 点击缓存
local clickTargets_ = {}

-- ═══ 槽位定义 ═══
local SLOT_SECTIONS = {
    { key = "cx_slash_lv",  axis = "cx_slash",    type = "level",  label = "斩击 Lv",  color = { 1.00, 0.75, 0.20, 1.0 } },
    { key = "cx_slash_fm",  axis = "cx_slash",    type = "form",   label = "斩击形态", color = { 1.00, 0.75, 0.20, 1.0 } },
    { key = "cx_fin_lv",    axis = "cx_finisher", type = "level",  label = "收尾 Lv",  color = { 1.00, 0.45, 0.30, 1.0 } },
    { key = "cx_fin_fm",    axis = "cx_finisher", type = "form",   label = "收尾形态", color = { 1.00, 0.45, 0.30, 1.0 } },
}

-- ═══ 初始化 ═══

function M.init(W, H)
    W_ = W
    H_ = H
    visible_ = false
    openDropdown_ = nil
    anim_.slideX = 1
    anim_.maskAlpha = 0
    M.rebuildDropdowns()
end

--- 根据 SkillState 重建 dropdown items 和 selectedIdx
function M.rebuildDropdowns()
    dropdowns_ = {}
    for _, sec in ipairs(SLOT_SECTIONS) do
        local items = {}
        local selIdx = 1

        if sec.type == "level" then
            local maxLv = SkillState.MAX_LEVELS[sec.axis] or 4
            for lv = 1, maxLv do
                items[#items + 1] = "Lv " .. lv
            end
            local curLv = SkillState.getLevel(sec.axis)
            selIdx = math.max(1, curLv)
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
    -- 同步能量滑块
    local ChenxiCtrl = require("game.characters.ChenxiController")
    energySlider_.value = ChenxiCtrl.getEnergy() / ChenxiCtrl.getEnergyMax()

    Tween.cancelTarget(anim_)
    anim_.slideX = 1
    anim_.maskAlpha = 0
    Tween.to(anim_, { slideX = 0 }, 0.35, { easing = Tween.Easing.easeOutCubic })
    Tween.to(anim_, { maskAlpha = 1 }, 0.25, { easing = Tween.Easing.easeOutCubic })
    print("[DebugChenxi] Panel opened")
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
    print("[DebugChenxi] Panel closed")
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

    -- 面板尺寸（从左侧滑入）
    local panelW = math.min(260, W * 0.52)
    local panelX = 10 - anim_.slideX * (panelW + 20)
    local panelY = 10

    -- 计算面板高度
    local rowH = 28
    local sectionH = #SLOT_SECTIONS * rowH
    -- 能量滑块区: 标题(22) + 滑块(30) + 段位显示(20) + 间距(12)
    local energyAreaH = 22 + 30 + 20 + 12
    -- 状态信息区: 标题(22) + 4行信息(20*4) + 间距(12)
    local infoAreaH = 22 + 20 * 4 + 12
    -- 面板总高 = 标题(44) + 槽位区 + 间距(14) + 能量区 + 间距(10) + 信息区 + 底部按钮(50)
    local panelH = 44 + sectionH + 14 + energyAreaH + 10 + infoAreaH + 50

    -- 面板背景
    Components.drawPanel(vg, panelX, panelY, panelW, panelH, { dark = true })

    -- 标题
    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(1.0, 0.75, 0.2, 1.0))
    nvgText(vg, panelX + panelW * 0.5, panelY + 20, "DEBUG · CHENXI")

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
    local ddW = 100
    local ddH = 22

    local deferDraw = nil

    for _, sec in ipairs(SLOT_SECTIONS) do
        local dd = dropdowns_[sec.key]
        if not dd then goto continue_slot end

        local ddX = padX + innerW - ddW
        local ddY = curY + (rowH - ddH) * 0.5

        -- 标签
        nvgFontFace(vg, Theme.font.family)
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(Theme.c(sec.color)))
        nvgText(vg, padX, curY + rowH * 0.5, sec.label)

        -- Dropdown
        if dd.open then
            deferDraw = { sec = sec, dd = dd, x = ddX, y = ddY, w = ddW, h = ddH }
        else
            local result = Components.drawDropdown(vg, ddX, ddY, ddW, ddH, dd, { accentColor = sec.color })
            clickTargets_[#clickTargets_ + 1] = { type = "dropdown", key = sec.key, result = result }
        end

        curY = curY + rowH
        ::continue_slot::
    end

    -- 展开的 dropdown 最后绘制
    if deferDraw then
        nvgSave(vg)
        local result = Components.drawDropdown(vg, deferDraw.x, deferDraw.y, deferDraw.w, deferDraw.h, deferDraw.dd, { accentColor = deferDraw.sec.color })
        clickTargets_[#clickTargets_ + 1] = { type = "dropdown", key = deferDraw.sec.key, result = result, zTop = true }
        nvgRestore(vg)
    end

    -- ═══ 分隔线: 能量区域 ═══
    curY = sepY + 8 + sectionH + 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 10, curY)
    nvgLineTo(vg, panelX + panelW - 10, curY)
    nvgStrokeColor(vg, nvgRGBAf(1, 1, 1, 0.12))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 能量区标题
    curY = curY + 4
    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(0.7, 0.7, 0.8, 0.8))
    nvgText(vg, padX, curY + 10, "ENERGY")

    -- 当前数值
    local ChenxiCtrl = require("game.characters.ChenxiController")
    local curEnergy = ChenxiCtrl.getEnergy()
    local maxEnergy = ChenxiCtrl.getEnergyMax()
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(1.0, 0.85, 0.3, 0.9))
    nvgText(vg, padX + innerW, curY + 10, string.format("%.0f%%", curEnergy / maxEnergy * 100))
    curY = curY + 22

    -- 能量滑块
    local sliderX = padX
    local sliderY = curY + 8
    local sliderW = innerW
    local sliderH = 14
    energySlider_.value = curEnergy / maxEnergy

    -- 滑块背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderX, sliderY, sliderW, sliderH, 4)
    nvgFillColor(vg, nvgRGBAf(0.15, 0.15, 0.2, 0.8))
    nvgFill(vg)

    -- 段位背景色块（30%、60%分界线）
    local seg30x = sliderX + sliderW * 0.3
    local seg60x = sliderX + sliderW * 0.6

    -- 衰减段（0~30%）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderX, sliderY, sliderW * 0.3, sliderH, 4)
    nvgFillColor(vg, nvgRGBAf(0.7, 0.4, 0.1, 0.2))
    nvgFill(vg)

    -- 标准段（30~60%）
    nvgBeginPath(vg)
    nvgRect(vg, seg30x, sliderY, sliderW * 0.3, sliderH)
    nvgFillColor(vg, nvgRGBAf(0.9, 0.6, 0.15, 0.2))
    nvgFill(vg)

    -- 满能段（60~100%）
    nvgBeginPath(vg)
    nvgRect(vg, seg60x, sliderY, sliderW * 0.4, sliderH)
    nvgFillColor(vg, nvgRGBAf(1.0, 0.75, 0.2, 0.2))
    nvgFill(vg)

    -- 填充条
    local fillW = sliderW * energySlider_.value
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderX, sliderY, fillW, sliderH, 4)
    nvgFillColor(vg, nvgRGBAf(1.0, 0.8, 0.2, 0.7))
    nvgFill(vg)

    -- 滑块手柄
    local handleX = sliderX + fillW
    nvgBeginPath(vg)
    nvgCircle(vg, handleX, sliderY + sliderH * 0.5, 7)
    nvgFillColor(vg, nvgRGBAf(1.0, 0.9, 0.4, 1.0))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBAf(0.8, 0.6, 0.1, 1.0))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 分界线标记
    nvgBeginPath(vg)
    nvgMoveTo(vg, seg30x, sliderY - 2)
    nvgLineTo(vg, seg30x, sliderY + sliderH + 2)
    nvgStrokeColor(vg, nvgRGBAf(1, 1, 1, 0.4))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, seg60x, sliderY - 2)
    nvgLineTo(vg, seg60x, sliderY + sliderH + 2)
    nvgStroke(vg)

    clickTargets_[#clickTargets_ + 1] = {
        type = "slider",
        rect = { x = sliderX, y = sliderY - 4, w = sliderW, h = sliderH + 8 },
    }

    curY = sliderY + sliderH + 4

    -- 段位显示
    local segName, segMult, segCost = ChenxiCtrl.getEnergySegment()
    local segLabel = segName == "full" and "满能 x" .. segMult
        or segName == "normal" and "标准 x" .. segMult
        or "衰减 x" .. segMult
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(0.8, 0.8, 0.9, 0.7))
    nvgText(vg, padX, curY + 10, "段位: " .. segLabel .. "  耗能: " .. segCost)
    curY = curY + 20

    -- ═══ 分隔线: 状态信息区 ═══
    curY = curY + 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 10, curY)
    nvgLineTo(vg, panelX + panelW - 10, curY)
    nvgStrokeColor(vg, nvgRGBAf(1, 1, 1, 0.12))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    curY = curY + 4
    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(0.7, 0.7, 0.8, 0.8))
    nvgText(vg, padX, curY + 10, "STATUS")
    curY = curY + 22

    -- 状态行
    local cxState = ChenxiCtrl.getState()
    local infoLines = {
        string.format("BT: %s  斩击数: %d", cxState.btActive and "ON" or "OFF", cxState.btSlashCount),
        string.format("连击: %d  目标: %s", cxState.comboCount, cxState.comboTarget or "-"),
        string.format("形态倍率: x%.2f", ChenxiCtrl.getSlashFormMult()),
        string.format("灼痕点: %d  Active: %s", #cxState.burnPaths, tostring(cxState.burnPathActive)),
    }

    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBAf(0.75, 0.85, 0.95, 0.8))
    for _, line in ipairs(infoLines) do
        nvgText(vg, padX, curY + 10, line)
        curY = curY + 20
    end

    -- ═══ 底部按钮 ═══
    local btnY = panelY + panelH - 42

    -- 切换到晨曦按钮
    local switchRect = Components.drawButton(vg, panelX + panelW * 0.2, btnY, "Switch", { variant = "accent", w = 60 })
    clickTargets_[#clickTargets_ + 1] = { type = "btn_switch", rect = switchRect }

    -- 充满能量
    local fillRect = Components.drawButton(vg, panelX + panelW * 0.5, btnY, "Fill", { variant = "accent", w = 50 })
    clickTargets_[#clickTargets_ + 1] = { type = "btn_fill", rect = fillRect }

    -- 关闭按钮
    local closeRect = Components.drawButton(vg, panelX + panelW * 0.78, btnY, "Close", { variant = "dark", w = 54 })
    clickTargets_[#clickTargets_ + 1] = { type = "btn_close", rect = closeRect }
end

-- ═══ 点击处理 ═══

function M.onClick(x, y)
    if not visible_ then return false end

    -- 优先处理展开的 dropdown
    for i = #clickTargets_, 1, -1 do
        local ct = clickTargets_[i]

        if ct.type == "dropdown" and ct.result then
            local result = ct.result
            local key = ct.key
            local dd = dropdowns_[key]

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

            -- trigger 点击
            if Components.hitTest(result.triggerRect, x, y) then
                M.toggleDropdown(key)
                return true
            end
        end

        if ct.type == "slider" and ct.rect then
            local r = ct.rect
            if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
                -- 点击滑块 → 设置能量
                local ratio = math.max(0, math.min(1, (x - r.x) / r.w))
                local ChenxiCtrl = require("game.characters.ChenxiController")
                ChenxiCtrl.setEnergy(ratio * ChenxiCtrl.getEnergyMax())
                energySlider_.value = ratio
                print(string.format("[DebugChenxi] Energy set to %.0f%%", ratio * 100))
                return true
            end
        end

        if ct.type == "btn_switch" and ct.rect and Components.hitTest(ct.rect, x, y) then
            local Player = require("game.Player")
            Player.unlockChenxi()
            Player.switchCharacter()
            return true
        end

        if ct.type == "btn_fill" and ct.rect and Components.hitTest(ct.rect, x, y) then
            local ChenxiCtrl = require("game.characters.ChenxiController")
            ChenxiCtrl.setEnergy(ChenxiCtrl.getEnergyMax())
            energySlider_.value = 1.0
            print("[DebugChenxi] Energy filled to max")
            return true
        end

        if ct.type == "btn_close" and ct.rect and Components.hitTest(ct.rect, x, y) then
            M.hide()
            return true
        end
    end

    -- 点击面板外关闭展开的 dropdown
    if openDropdown_ then
        openDropdown_ = nil
        for _, dd in pairs(dropdowns_) do dd.open = false end
        return true
    end

    return false
end

-- ═══ 拖拽滑块支持 ═══

function M.onMouseMove(x, y)
    if not visible_ then return false end
    if energySlider_.dragging then
        -- 找到滑块 rect
        for _, ct in ipairs(clickTargets_) do
            if ct.type == "slider" and ct.rect then
                local r = ct.rect
                local ratio = math.max(0, math.min(1, (x - r.x) / r.w))
                local ChenxiCtrl = require("game.characters.ChenxiController")
                ChenxiCtrl.setEnergy(ratio * ChenxiCtrl.getEnergyMax())
                energySlider_.value = ratio
                return true
            end
        end
    end
    return false
end

function M.onMouseDown(x, y)
    if not visible_ then return false end
    -- 检查是否点击在滑块上
    for _, ct in ipairs(clickTargets_) do
        if ct.type == "slider" and ct.rect then
            local r = ct.rect
            if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
                energySlider_.dragging = true
                return true
            end
        end
    end
    return false
end

function M.onMouseUp()
    energySlider_.dragging = false
end

-- ═══ Dropdown 操作 ═══

function M.toggleDropdown(key)
    for k, dd in pairs(dropdowns_) do
        if k ~= key then dd.open = false end
    end

    local dd = dropdowns_[key]
    if dd then
        dd.open = not dd.open
        openDropdown_ = dd.open and key or nil
    end
end

function M.onDropdownSelect(key, idx)
    local dd = dropdowns_[key]
    if not dd then return end
    dd.selectedIdx = idx
    dd.open = false
    openDropdown_ = nil

    -- 应用到 SkillState
    for _, sec in ipairs(SLOT_SECTIONS) do
        if sec.key == key then
            if sec.type == "level" then
                SkillState.setLevel(sec.axis, idx)
                print(string.format("[DebugChenxi] %s level → %d", sec.axis, idx))
            elseif sec.type == "form" then
                SkillState.setForm(sec.axis, idx)
                print(string.format("[DebugChenxi] %s form → %d (%s)", sec.axis, idx, SkillState.getFormName(sec.axis, idx)))
            end
            break
        end
    end
end

return M
