-- ============================================================================
-- PagePreLevel.lua - 关卡前页面
-- 功能：难度选择(x1.0/x1.5/x2.0) + 最高分展示 + 开始按钮 + 图鉴入口
-- 动效：面板 easeOutBack 弹入 + 按钮 stagger + 难度切换 bounce
-- ============================================================================

local Tween      = require "lib.Tween"
local Theme      = require "ui.Theme"
local Components = require "ui.Components"

local M = {}

local W_, H_ = 0, 0

-- 难度选项
local DIFFICULTIES = {
    { mult = 1.0, label = "x1.0", desc = "标准" },
    { mult = 1.5, label = "x1.5", desc = "困难" },
    { mult = 2.0, label = "x2.0", desc = "噩梦" },
}

local selectedDifficulty_ = 1  -- 默认选第一个
local highScore_ = 0
local difficultyMult_ = 1.0

-- 按钮矩形缓存（点击检测）
local btnRects_ = {}
local startBtnRect_ = nil
local bestiaryBtnRect_ = nil
local practiceBtnRect_ = nil

-- ═══ 动画状态 ═══
local anim_ = {
    panelScale  = 0,   -- 面板缩放 0→1 (easeOutBack)
    panelY      = 0,   -- 面板Y偏移
    titleAlpha  = 0,   -- 标题透明度
    scoreAlpha  = 0,   -- 分数透明度
    diffAlpha   = 0,   -- 难度按钮透明度
    diffScale   = 0,   -- 难度按钮缩放
    startAlpha  = 0,   -- 开始按钮透明度
    startScale  = 0,   -- 开始按钮缩放
    bestAlpha   = 0,   -- 图鉴按钮透明度
    bestScale   = 0,   -- 图鉴按钮缩放
    practAlpha  = 0,   -- 练习按钮透明度
    practScale  = 0,   -- 练习按钮缩放
}

-- 难度切换 bounce 动画
local diffBounce_ = { scale = 1.0 }

function M.init(W, H)
    W_ = W
    H_ = H
    selectedDifficulty_ = 1
    difficultyMult_ = 1.0
    btnRects_ = {}
    startBtnRect_ = nil
    bestiaryBtnRect_ = nil
    practiceBtnRect_ = nil
end

function M.show(highScore)
    highScore_ = highScore or 0

    -- 重置动画状态
    anim_.panelScale = 0
    anim_.panelY     = 30
    anim_.titleAlpha = 0
    anim_.scoreAlpha = 0
    anim_.diffAlpha  = 0
    anim_.diffScale  = 0
    anim_.startAlpha = 0
    anim_.startScale = 0
    anim_.bestAlpha  = 0
    anim_.bestScale  = 0
    anim_.practAlpha = 0
    anim_.practScale = 0

    -- 取消之前的动画
    Tween.cancelTarget(anim_)

    -- 面板弹入 (easeOutBack)
    Tween.to(anim_, { panelScale = 1, panelY = 0 }, 0.45, {
        easing = Tween.Easing.easeOutBack,
    })

    -- 标题淡入 (稍延迟)
    Tween.to(anim_, { titleAlpha = 1 }, 0.3, {
        delay = 0.12,
        easing = Tween.Easing.easeOutCubic,
    })

    -- 分数淡入
    Tween.to(anim_, { scoreAlpha = 1 }, 0.3, {
        delay = 0.2,
        easing = Tween.Easing.easeOutCubic,
    })

    -- 难度按钮弹出 (easeOutBack, stagger)
    Tween.to(anim_, { diffAlpha = 1, diffScale = 1 }, 0.4, {
        delay = 0.28,
        easing = Tween.Easing.easeOutBack,
    })

    -- START 按钮 (easeOutBack, 较大延迟)
    Tween.to(anim_, { startAlpha = 1, startScale = 1 }, 0.4, {
        delay = 0.4,
        easing = Tween.Easing.easeOutBack,
    })

    -- BESTIARY 按钮
    Tween.to(anim_, { bestAlpha = 1, bestScale = 1 }, 0.35, {
        delay = 0.5,
        easing = Tween.Easing.easeOutBack,
    })

    -- PRACTICE 按钮
    Tween.to(anim_, { practAlpha = 1, practScale = 1 }, 0.35, {
        delay = 0.58,
        easing = Tween.Easing.easeOutBack,
    })
end

function M.getSelectedDifficulty()
    return difficultyMult_
end

function M.update(dt)
    -- Tween 全局 update 在 main.lua 中已调用
end

function M.draw(vg, W, H)
    W_ = W
    H_ = H

    -- 全屏绿色背景 + 花纹
    Components.drawBackground(vg, W, H)

    if anim_.panelScale < 0.01 then return end

    -- 主面板
    local panelW = math.min(340, W * 0.85)
    local panelH = math.min(420, H * 0.80)
    local panelX = (W - panelW) * 0.5
    local panelY = (H - panelH) * 0.5 + anim_.panelY

    -- 面板缩放动画
    local scl = anim_.panelScale
    nvgSave(vg)
    nvgTranslate(vg, W * 0.5, H * 0.5 + anim_.panelY)
    nvgScale(vg, scl, scl)
    nvgTranslate(vg, -panelW * 0.5, -panelH * 0.5)

    Components.drawPanel(vg, 0, 0, panelW, panelH)

    -- 标题 (有自己的 alpha)
    if anim_.titleAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.titleAlpha)
        Components.drawTitle(vg, panelW * 0.5, 35, "BULLET THIEF", Theme.font.title)
        nvgGlobalAlpha(vg, 1.0)
    end

    -- 最高分
    if anim_.scoreAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.scoreAlpha)
        local scoreY = 75
        nvgFontFace(vg, Theme.font.family)
        nvgFontSize(vg, Theme.font.body)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.mutedText)))
        nvgText(vg, panelW * 0.5, scoreY, "BEST SCORE")

        nvgFontSize(vg, Theme.font.subtitle + 4)
        nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.accentYellow)))
        nvgText(vg, panelW * 0.5, scoreY + 22, tostring(highScore_))
        nvgGlobalAlpha(vg, 1.0)
    end

    -- 难度选择
    if anim_.diffAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.diffAlpha)

        local diffTitleY = 130
        nvgFontFace(vg, Theme.font.family)
        nvgFontSize(vg, Theme.font.body)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.titleText)))
        nvgText(vg, panelW * 0.5, diffTitleY, "DIFFICULTY")

        -- 难度按钮行 (带缩放动画)
        local btnY = diffTitleY + 30
        local btnGap = 12
        local btnW = 80
        local totalBtnsW = #DIFFICULTIES * btnW + (#DIFFICULTIES - 1) * btnGap
        local btnStartX = (panelW - totalBtnsW) * 0.5 + btnW * 0.5

        for i, diff in ipairs(DIFFICULTIES) do
            local bx = btnStartX + (i - 1) * (btnW + btnGap)
            local isSelected = (i == selectedDifficulty_)
            local variant = isSelected and "primary" or "dark"

            -- 每个按钮的微小交错缩放
            local btnScale = anim_.diffScale
            if isSelected then
                btnScale = btnScale * diffBounce_.scale
            end

            -- 基于上一帧世界坐标检测 hover
            local isHov = btnRects_[i] and Components.isPointerInRect(
                btnRects_[i].x, btnRects_[i].y, btnRects_[i].w, btnRects_[i].h)

            nvgSave(vg)
            nvgTranslate(vg, bx, btnY)
            nvgScale(vg, btnScale, btnScale)
            nvgTranslate(vg, -bx, -btnY)

            local rect = Components.drawButton(vg, bx, btnY, diff.label, {
                variant = variant,
                w = btnW,
                selected = isSelected,
                hovered = isHov,
            })

            nvgRestore(vg)

            -- 存储世界坐标用于点击检测
            -- 需要转换回屏幕坐标
            local worldBx = W * 0.5 - panelW * 0.5 * scl + bx * scl
            local worldBy = (H * 0.5 + anim_.panelY) - panelH * 0.5 * scl + btnY * scl
            btnRects_[i] = {
                x = worldBx - btnW * 0.5 * scl,
                y = worldBy - Theme.button.height * 0.5 * scl,
                w = btnW * scl,
                h = Theme.button.height * scl,
            }

            -- 描述文字
            nvgFontSize(vg, Theme.font.small)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local descColor = isSelected and Theme.colors.accentGreen or Theme.colors.mutedText
            nvgFillColor(vg, nvgRGBAf(Theme.c(descColor)))
            nvgText(vg, bx, btnY + 26, diff.desc)
        end

        nvgGlobalAlpha(vg, 1.0)
    end

    -- START 按钮
    if anim_.startAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.startAlpha)
        local startY = 230

        local startHov = startBtnRect_ and Components.isPointerInRect(
            startBtnRect_.x, startBtnRect_.y, startBtnRect_.w, startBtnRect_.h)

        nvgSave(vg)
        local ss = anim_.startScale
        nvgTranslate(vg, panelW * 0.5, startY)
        nvgScale(vg, ss, ss)
        nvgTranslate(vg, -panelW * 0.5, -startY)

        Components.drawButton(vg, panelW * 0.5, startY, "START", {
            variant = "accent",
            w = 160,
            hovered = startHov,
        })

        nvgRestore(vg)

        -- 世界坐标
        local worldStartY = (H * 0.5 + anim_.panelY) - panelH * 0.5 * scl + startY * scl
        startBtnRect_ = {
            x = W * 0.5 - 80 * scl,
            y = worldStartY - Theme.button.height * 0.5 * scl,
            w = 160 * scl,
            h = Theme.button.height * scl,
        }

        nvgGlobalAlpha(vg, 1.0)
    end

    -- BESTIARY 和 PRACTICE 按钮（并排）
    if anim_.bestAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.bestAlpha)
        local rowY = 285

        -- BESTIARY 按钮（左侧）
        local bestBtnX = panelW * 0.32
        local bestHov = bestiaryBtnRect_ and Components.isPointerInRect(
            bestiaryBtnRect_.x, bestiaryBtnRect_.y, bestiaryBtnRect_.w, bestiaryBtnRect_.h)

        nvgSave(vg)
        local bs = anim_.bestScale
        nvgTranslate(vg, bestBtnX, rowY)
        nvgScale(vg, bs, bs)
        nvgTranslate(vg, -bestBtnX, -rowY)

        Components.drawButton(vg, bestBtnX, rowY, "BESTIARY", {
            variant = "dark",
            w = 110,
            hovered = bestHov,
        })

        nvgRestore(vg)

        -- 世界坐标
        local worldBestY = (H * 0.5 + anim_.panelY) - panelH * 0.5 * scl + rowY * scl
        local worldBestX = W * 0.5 - panelW * 0.5 * scl + bestBtnX * scl
        bestiaryBtnRect_ = {
            x = worldBestX - 55 * scl,
            y = worldBestY - Theme.button.height * 0.5 * scl,
            w = 110 * scl,
            h = Theme.button.height * scl,
        }

        nvgGlobalAlpha(vg, 1.0)
    end

    -- PRACTICE 按钮（右侧）
    if anim_.practAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.practAlpha)
        local rowY = 285
        local practBtnX = panelW * 0.68

        local practHov = practiceBtnRect_ and Components.isPointerInRect(
            practiceBtnRect_.x, practiceBtnRect_.y, practiceBtnRect_.w, practiceBtnRect_.h)

        nvgSave(vg)
        local ps = anim_.practScale
        nvgTranslate(vg, practBtnX, rowY)
        nvgScale(vg, ps, ps)
        nvgTranslate(vg, -practBtnX, -rowY)

        Components.drawButton(vg, practBtnX, rowY, "PRACTICE", {
            variant = "dark",
            w = 110,
            hovered = practHov,
        })

        nvgRestore(vg)

        -- 世界坐标
        local worldPractY = (H * 0.5 + anim_.panelY) - panelH * 0.5 * scl + rowY * scl
        local worldPractX = W * 0.5 - panelW * 0.5 * scl + practBtnX * scl
        practiceBtnRect_ = {
            x = worldPractX - 55 * scl,
            y = worldPractY - Theme.button.height * 0.5 * scl,
            w = 110 * scl,
            h = Theme.button.height * scl,
        }

        nvgGlobalAlpha(vg, 1.0)
    end

    nvgRestore(vg)
end

--- 点击处理，返回动作 "start" / "bestiary" / nil
function M.onClick(x, y)
    -- 难度选择
    for i, rect in ipairs(btnRects_) do
        if Components.hitTest(rect, x, y) then
            if selectedDifficulty_ ~= i then
                selectedDifficulty_ = i
                difficultyMult_ = DIFFICULTIES[i].mult

                -- Bounce 反馈动画
                Tween.cancelTarget(diffBounce_)
                diffBounce_.scale = 1.25
                Tween.to(diffBounce_, { scale = 1.0 }, 0.35, {
                    easing = Tween.Easing.easeOutElastic,
                })
            end
            return nil
        end
    end

    -- 开始
    if Components.hitTest(startBtnRect_, x, y) then
        return "start"
    end

    -- 图鉴
    if Components.hitTest(bestiaryBtnRect_, x, y) then
        return "bestiary"
    end

    -- 练习
    if Components.hitTest(practiceBtnRect_, x, y) then
        return "practice"
    end

    return nil
end

return M
