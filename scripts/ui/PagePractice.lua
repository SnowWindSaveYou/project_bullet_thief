-- ============================================================================
-- PagePractice.lua - 练习模式页面
-- 功能：选择敌人类型 + 数量调整 + 召唤按钮 + 返回
-- 场地为空，玩家按需召唤指定类型/数量的敌人
-- 设计：面板可收起/展开，收起时只显示小浮动按钮
-- ============================================================================

local Tween      = require "lib.Tween"
local Theme      = require "ui.Theme"
local Components = require "ui.Components"

local M = {}

local W_, H_ = 0, 0

-- 可选敌人类型
local ENEMY_OPTIONS = {
    { id = "scout",  label = "SCOUT",  desc = "轻型",  color = { 0.85, 0.6, 0.1 } },
    { id = "heavy",  label = "HEAVY",  desc = "重型",  color = { 0.6, 0.2, 0.8 } },
    { id = "sniper", label = "SNIPER", desc = "狙击",  color = { 0.9, 0.15, 0.3 } },
    { id = "laser",  label = "LASER",  desc = "激光",  color = { 0.7, 0.0, 0.1 } },
    { id = "boss",   label = "BOSS",   desc = "首领",  color = { 0.3, 0.0, 0.5 } },
}

-- 选中状态 & 数量
local selected_ = {}    -- { scout = true, heavy = false, ... }
local counts_   = {}    -- { scout = 3, heavy = 2, ... }
local MIN_COUNT = 1
local MAX_COUNT = 10

-- 面板展开/收起状态
local panelOpen_ = true

-- 按钮矩形缓存
local typeBtnRects_   = {}   -- [i] = { x, y, w, h }
local plusBtnRects_   = {}   -- [i] = { x, y, w, h }
local minusBtnRects_  = {}   -- [i] = { x, y, w, h }
local summonBtnRect_  = nil
local backBtnRect_    = nil
local toggleBtnRect_  = nil  -- 收起时的小按钮

-- 动画
local anim_ = {
    panelScale = 0,
    panelY     = 0,
    titleAlpha = 0,
    listAlpha  = 0,
    listScale  = 0,
    btnAlpha   = 0,
    btnScale   = 0,
    toggleAlpha = 0,  -- 小按钮透明度
}

function M.init(W, H)
    W_ = W
    H_ = H
    -- 默认选中 scout，数量 3
    for _, opt in ipairs(ENEMY_OPTIONS) do
        selected_[opt.id] = (opt.id == "scout")
        counts_[opt.id]   = 3
    end
end

--- 显示面板（进入练习模式时调用）
function M.show()
    panelOpen_ = true
    M.openPanel()
end

--- 展开面板动画
function M.openPanel()
    panelOpen_ = true
    Tween.cancelTarget(anim_)
    anim_.panelScale = 0
    anim_.panelY     = 25
    anim_.titleAlpha = 0
    anim_.listAlpha  = 0
    anim_.listScale  = 0
    anim_.btnAlpha   = 0
    anim_.btnScale   = 0
    anim_.toggleAlpha = 0

    -- 面板弹入
    Tween.to(anim_, { panelScale = 1, panelY = 0 }, 0.45, {
        easing = Tween.Easing.easeOutBack,
    })
    Tween.to(anim_, { titleAlpha = 1 }, 0.3, {
        delay = 0.1, easing = Tween.Easing.easeOutCubic,
    })
    Tween.to(anim_, { listAlpha = 1, listScale = 1 }, 0.4, {
        delay = 0.2, easing = Tween.Easing.easeOutBack,
    })
    Tween.to(anim_, { btnAlpha = 1, btnScale = 1 }, 0.4, {
        delay = 0.35, easing = Tween.Easing.easeOutBack,
    })
end

--- 收起面板动画
function M.closePanel()
    panelOpen_ = false
    Tween.cancelTarget(anim_)

    -- 面板缩小消失
    Tween.to(anim_, { panelScale = 0, btnAlpha = 0, listAlpha = 0, titleAlpha = 0 }, 0.25, {
        easing = Tween.Easing.easeInCubic,
    })
    -- 小按钮淡入
    Tween.to(anim_, { toggleAlpha = 1 }, 0.3, {
        delay = 0.2, easing = Tween.Easing.easeOutCubic,
    })
end

function M.update(dt)
    -- Tween 全局 update 在 main.lua
end

function M.draw(vg, W, H)
    W_ = W
    H_ = H

    -- ═══ 收起状态：只画小浮动按钮 ═══
    if not panelOpen_ then
        if anim_.toggleAlpha > 0.01 then
            nvgGlobalAlpha(vg, anim_.toggleAlpha)

            local tbW = 100
            local tbH = 36
            local tbX = W - tbW - 12
            local tbY = 12

            -- 按钮背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tbX, tbY, tbW, tbH, Theme.button.cornerRadius)
            nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.panelBg)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBAf(Theme.c(Theme.colors.accentGreen)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            -- 按钮文字
            nvgFontFace(vg, Theme.font.family)
            nvgFontSize(vg, Theme.font.button)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.accentGreen)))
            nvgText(vg, tbX + tbW * 0.5, tbY + tbH * 0.5, "SUMMON+")

            toggleBtnRect_ = { x = tbX, y = tbY, w = tbW, h = tbH }
            nvgGlobalAlpha(vg, 1.0)
        end
        return
    end

    -- ═══ 展开状态：半透明遮罩 + 面板 ═══
    -- 半透明背景遮罩（不完全覆盖，玩家可看到场地）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBAf(0.0, 0.0, 0.0, 0.5))
    nvgFill(vg)

    if anim_.panelScale < 0.01 then return end

    local panelW = math.min(340, W * 0.85)
    local panelH = math.min(420, H * 0.82)
    local scl = anim_.panelScale

    nvgSave(vg)
    nvgTranslate(vg, W * 0.5, H * 0.5 + anim_.panelY)
    nvgScale(vg, scl, scl)
    nvgTranslate(vg, -panelW * 0.5, -panelH * 0.5)

    Components.drawPanel(vg, 0, 0, panelW, panelH)

    -- 标题
    if anim_.titleAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.titleAlpha)
        Components.drawTitle(vg, panelW * 0.5, 32, "PRACTICE", Theme.font.title)
        nvgFontFace(vg, Theme.font.family)
        nvgFontSize(vg, Theme.font.small)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.mutedText)))
        nvgText(vg, panelW * 0.5, 55, "选择敌人类型和数量，随时召唤")
        nvgGlobalAlpha(vg, 1.0)
    end

    -- 敌人列表
    if anim_.listAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.listAlpha)
        local listY = 75
        local rowH = 48
        local rowPad = 14

        for i, opt in ipairs(ENEMY_OPTIONS) do
            local ry = listY + (i - 1) * rowH
            local isOn = selected_[opt.id]

            -- 行背景（选中时高亮）
            local rowBg = isOn and Theme.colors.cardSelected or Theme.colors.panelBgDark
            nvgBeginPath(vg)
            nvgRoundedRect(vg, rowPad, ry, panelW - rowPad * 2, rowH - 5, 8)
            nvgFillColor(vg, nvgRGBAf(Theme.c(rowBg)))
            nvgFill(vg)

            -- 左侧色块标识
            nvgBeginPath(vg)
            nvgRoundedRect(vg, rowPad, ry, 5, rowH - 5, 3)
            nvgFillColor(vg, nvgRGBAf(opt.color[1], opt.color[2], opt.color[3], isOn and 1.0 or 0.4))
            nvgFill(vg)

            -- 类型名称
            nvgFontFace(vg, Theme.font.family)
            nvgFontSize(vg, Theme.font.button)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local textAlpha = isOn and 1.0 or 0.5
            nvgFillColor(vg, nvgRGBAf(Theme.ca(Theme.colors.lightText, textAlpha)))
            nvgText(vg, rowPad + 14, ry + (rowH - 5) * 0.5, opt.label)

            -- 描述
            nvgFontSize(vg, Theme.font.small)
            nvgFillColor(vg, nvgRGBAf(Theme.ca(Theme.colors.mutedText, textAlpha)))
            nvgText(vg, rowPad + 76, ry + (rowH - 5) * 0.5, opt.desc)

            -- 数量控制（右侧）: [-] 数字 [+]
            local ctrlX = panelW - rowPad - 90
            local ctrlY = ry + (rowH - 5) * 0.5

            -- [-] 按钮
            local minusBtnW = 24
            local minusBtnH = 24
            local mx = ctrlX
            local my = ctrlY - minusBtnH * 0.5
            nvgBeginPath(vg)
            nvgRoundedRect(vg, mx, my, minusBtnW, minusBtnH, 5)
            nvgFillColor(vg, nvgRGBAf(Theme.c(isOn and Theme.colors.panelBg or Theme.colors.cardDisabled)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBAf(Theme.c(Theme.colors.panelBorder)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
            nvgFontSize(vg, Theme.font.button + 2)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(Theme.c(isOn and Theme.colors.lightText or Theme.colors.mutedText)))
            nvgText(vg, mx + minusBtnW * 0.5, ctrlY, "-")

            -- 数字
            nvgFontSize(vg, Theme.font.button)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(Theme.ca(Theme.colors.accentYellow, textAlpha)))
            nvgText(vg, ctrlX + 44, ctrlY, tostring(counts_[opt.id]))

            -- [+] 按钮
            local px = ctrlX + 64
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px, my, minusBtnW, minusBtnH, 5)
            nvgFillColor(vg, nvgRGBAf(Theme.c(isOn and Theme.colors.panelBg or Theme.colors.cardDisabled)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBAf(Theme.c(Theme.colors.panelBorder)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
            nvgFontSize(vg, Theme.font.button + 2)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(Theme.c(isOn and Theme.colors.lightText or Theme.colors.mutedText)))
            nvgText(vg, px + minusBtnW * 0.5, ctrlY, "+")

            -- 存储世界坐标矩形
            local worldOX = W * 0.5 - panelW * 0.5 * scl
            local worldOY = (H * 0.5 + anim_.panelY) - panelH * 0.5 * scl

            -- 类型按钮（整行左半部分作为选择区域）
            typeBtnRects_[i] = {
                x = worldOX + rowPad * scl,
                y = worldOY + ry * scl,
                w = (ctrlX - rowPad) * scl,
                h = (rowH - 5) * scl,
            }
            -- [-] 按钮
            minusBtnRects_[i] = {
                x = worldOX + mx * scl,
                y = worldOY + my * scl,
                w = minusBtnW * scl,
                h = minusBtnH * scl,
            }
            -- [+] 按钮
            plusBtnRects_[i] = {
                x = worldOX + px * scl,
                y = worldOY + my * scl,
                w = minusBtnW * scl,
                h = minusBtnH * scl,
            }
        end

        nvgGlobalAlpha(vg, 1.0)
    end

    -- 底部按钮
    if anim_.btnAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.btnAlpha)
        local btnRow = panelH - 50

        -- SUMMON 按钮
        local summonHov = summonBtnRect_ and Components.isPointerInRect(
            summonBtnRect_.x, summonBtnRect_.y, summonBtnRect_.w, summonBtnRect_.h)

        nvgSave(vg)
        local ss = anim_.btnScale
        nvgTranslate(vg, panelW * 0.35, btnRow)
        nvgScale(vg, ss, ss)
        nvgTranslate(vg, -panelW * 0.35, -btnRow)

        Components.drawButton(vg, panelW * 0.35, btnRow, "SUMMON", {
            variant = "accent",
            w = 110,
            hovered = summonHov,
        })
        nvgRestore(vg)

        -- BACK 按钮
        local backHov = backBtnRect_ and Components.isPointerInRect(
            backBtnRect_.x, backBtnRect_.y, backBtnRect_.w, backBtnRect_.h)

        nvgSave(vg)
        nvgTranslate(vg, panelW * 0.7, btnRow)
        nvgScale(vg, ss, ss)
        nvgTranslate(vg, -panelW * 0.7, -btnRow)

        Components.drawButton(vg, panelW * 0.7, btnRow, "BACK", {
            variant = "dark",
            w = 90,
            hovered = backHov,
        })
        nvgRestore(vg)

        -- 世界坐标
        local worldOX = W * 0.5 - panelW * 0.5 * scl
        local worldOY = (H * 0.5 + anim_.panelY) - panelH * 0.5 * scl

        summonBtnRect_ = {
            x = worldOX + (panelW * 0.35 - 55) * scl,
            y = worldOY + (btnRow - Theme.button.height * 0.5) * scl,
            w = 110 * scl,
            h = Theme.button.height * scl,
        }
        backBtnRect_ = {
            x = worldOX + (panelW * 0.7 - 45) * scl,
            y = worldOY + (btnRow - Theme.button.height * 0.5) * scl,
            w = 90 * scl,
            h = Theme.button.height * scl,
        }

        nvgGlobalAlpha(vg, 1.0)
    end

    nvgRestore(vg)
end

--- 点击处理
--- 返回: "summon" / "back" / "toggle" / nil
function M.onClick(x, y)
    -- 收起状态：只检测小按钮
    if not panelOpen_ then
        if Components.hitTest(toggleBtnRect_, x, y) then
            M.openPanel()
            return nil  -- 只是展开面板，不触发其他动作
        end
        return nil
    end

    -- 展开状态：检测面板内按钮

    -- 类型切换
    for i, opt in ipairs(ENEMY_OPTIONS) do
        if Components.hitTest(typeBtnRects_[i], x, y) then
            selected_[opt.id] = not selected_[opt.id]
            return nil
        end
    end

    -- [-] 按钮
    for i, opt in ipairs(ENEMY_OPTIONS) do
        if Components.hitTest(minusBtnRects_[i], x, y) then
            if counts_[opt.id] > MIN_COUNT then
                counts_[opt.id] = counts_[opt.id] - 1
            end
            return nil
        end
    end

    -- [+] 按钮
    for i, opt in ipairs(ENEMY_OPTIONS) do
        if Components.hitTest(plusBtnRects_[i], x, y) then
            if counts_[opt.id] < MAX_COUNT then
                counts_[opt.id] = counts_[opt.id] + 1
            end
            return nil
        end
    end

    -- SUMMON 按钮
    if Components.hitTest(summonBtnRect_, x, y) then
        M.closePanel()  -- 收起面板
        return "summon"
    end

    -- BACK 按钮
    if Components.hitTest(backBtnRect_, x, y) then
        return "back"
    end

    return nil
end

--- 获取当前选中的敌人召唤列表
--- 返回: { { type = "scout", count = 3 }, { type = "heavy", count = 2 }, ... }
function M.getSpawnList()
    local list = {}
    for _, opt in ipairs(ENEMY_OPTIONS) do
        if selected_[opt.id] then
            list[#list + 1] = { type = opt.id, count = counts_[opt.id] }
        end
    end
    return list
end

--- 面板当前是否展开
function M.isOpen()
    return panelOpen_
end

return M
