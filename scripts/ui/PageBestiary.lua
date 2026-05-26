-- ============================================================================
-- PageBestiary.lua - 怪物图鉴
-- 展示所有 3 种怪物的矢量绘制状态 + 属性信息
-- 动效：面板 easeOutBack 弹入 + 卡片 stagger easeOutBack 从右侧滑入
-- ============================================================================

local Tween      = require "lib.Tween"
local Theme      = require "ui.Theme"
local Components = require "ui.Components"
local EnemyMgr   = require "game.EnemyManager"

local M = {}

local W_, H_ = 0, 0
local age_   = 0  -- 用于怪物动画

local backBtnRect_ = nil

-- 怪物信息定义
local MONSTERS = {
    {
        id       = "scout",
        name     = "迷雾鬼",
        nameEN   = "Fog Wraith",
        desc     = "飘忽不定的毛球，单发低伤弹幕",
        drawFunc = "drawFogWraithStatic",
        color    = { 0.85, 0.6, 0.1 },
    },
    {
        id       = "heavy",
        name     = "噩梦猫",
        nameEN   = "Nightmare Cat",
        desc     = "毛茸茸的紫色恶猫，扇形三连弹",
        drawFunc = "drawNightmareCatStatic",
        color    = { 0.6, 0.2, 0.8 },
    },
    {
        id       = "sniper",
        name     = "幽灵眼",
        nameEN   = "Ghost Eye",
        desc     = "冰冷的注视者，高伤精准狙击",
        drawFunc = "drawGhostEyeStatic",
        color    = { 0.9, 0.15, 0.3 },
    },
}

-- ═══ 动画状态 ═══
local anim_ = {
    panelScale = 0,
    panelY     = 0,
    titleAlpha = 0,
    backAlpha  = 0,
    backScale  = 0,
}

-- 每个卡片独立动画
local cardAnims_ = {}

function M.init(W, H)
    W_ = W
    H_ = H
    age_ = 0
end

function M.show()
    age_ = 0

    -- 重置动画
    anim_.panelScale = 0
    anim_.panelY     = 25
    anim_.titleAlpha = 0
    anim_.backAlpha  = 0
    anim_.backScale  = 0

    Tween.cancelTarget(anim_)

    -- 面板弹入
    Tween.to(anim_, { panelScale = 1, panelY = 0 }, 0.45, {
        easing = Tween.Easing.easeOutBack,
    })

    -- 标题淡入
    Tween.to(anim_, { titleAlpha = 1 }, 0.3, {
        delay = 0.15,
        easing = Tween.Easing.easeOutCubic,
    })

    -- 卡片 stagger 从右侧滑入 (easeOutBack)
    cardAnims_ = {}
    for i = 1, #MONSTERS do
        local ca = { alpha = 0, slideX = 50, scale = 0.85 }
        cardAnims_[i] = ca
        Tween.to(ca, { alpha = 1, slideX = 0, scale = 1.0 }, 0.5, {
            delay = 0.15 + (i - 1) * 0.1,
            easing = Tween.Easing.easeOutBack,
        })
    end

    -- 返回按钮
    Tween.to(anim_, { backAlpha = 1, backScale = 1 }, 0.35, {
        delay = 0.5,
        easing = Tween.Easing.easeOutBack,
    })
end

function M.update(dt)
    age_ = age_ + dt
end

function M.draw(vg, W, H)
    W_ = W
    H_ = H

    -- 全屏绿色背景
    Components.drawBackground(vg, W, H)

    if anim_.panelScale < 0.01 then return end

    -- 主面板 (缩放)
    local panelW = math.min(380, W * 0.92)
    local panelH = math.min(440, H * 0.85)

    local scl = anim_.panelScale
    nvgSave(vg)
    nvgTranslate(vg, W * 0.5, H * 0.5 + anim_.panelY)
    nvgScale(vg, scl, scl)
    nvgTranslate(vg, -panelW * 0.5, -panelH * 0.5)

    Components.drawPanel(vg, 0, 0, panelW, panelH)

    -- 标题
    if anim_.titleAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.titleAlpha)
        Components.drawTitle(vg, panelW * 0.5, 32, "BESTIARY", Theme.font.title)
        nvgGlobalAlpha(vg, 1.0)
    end

    -- 怪物卡片区域
    local cardStartY = 65
    local cardH = 90
    local cardGap = 10
    local cardW = panelW - 40
    local cardX = 20

    local types = EnemyMgr.getEnemyTypes()

    for i, monster in ipairs(MONSTERS) do
        local ca = cardAnims_[i]
        if ca and ca.alpha > 0.01 then
            nvgGlobalAlpha(vg, ca.alpha)

            local cy = cardStartY + (i - 1) * (cardH + cardGap)
            local cx = cardX + ca.slideX

            -- 卡片微缩放
            nvgSave(vg)
            local cardCX = cx + (cardW - ca.slideX) * 0.5
            local cardCY = cy + cardH * 0.5
            nvgTranslate(vg, cardCX, cardCY)
            nvgScale(vg, ca.scale, ca.scale)
            nvgTranslate(vg, -cardCX, -cardCY)

            drawMonsterCard(vg, cx, cy, cardW - ca.slideX, cardH, monster, types[monster.id])

            nvgRestore(vg)
            nvgGlobalAlpha(vg, 1.0)
        end
    end

    -- 返回按钮
    if anim_.backAlpha > 0.01 then
        nvgGlobalAlpha(vg, anim_.backAlpha)
        local backY = panelH - 35

        -- 基于世界坐标检测 hover
        local backHov = backBtnRect_ and Components.isPointerInRect(
            backBtnRect_.x, backBtnRect_.y, backBtnRect_.w, backBtnRect_.h)

        nvgSave(vg)
        nvgTranslate(vg, panelW * 0.5, backY)
        nvgScale(vg, anim_.backScale, anim_.backScale)
        nvgTranslate(vg, -panelW * 0.5, -backY)

        Components.drawButton(vg, panelW * 0.5, backY, "BACK", {
            variant = "dark",
            w = 100,
            hovered = backHov,
        })
        nvgRestore(vg)
        nvgGlobalAlpha(vg, 1.0)
    end

    -- 存储返回按钮世界坐标
    local worldBackY = (H * 0.5 + anim_.panelY) - panelH * 0.5 * scl + (panelH - 35) * scl
    backBtnRect_ = {
        x = W * 0.5 - 50 * scl,
        y = worldBackY - Theme.button.height * 0.5 * scl,
        w = 100 * scl,
        h = Theme.button.height * scl,
    }

    nvgRestore(vg)
end

function drawMonsterCard(vg, x, y, w, h, monster, cfg)
    local cr = Theme.card.cornerRadius
    local bw = Theme.card.borderWidth

    -- 卡片背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    nvgFillColor(vg, nvgRGBAf(0.98, 0.95, 0.88, 1.0))
    nvgFill(vg)

    -- hover 高亮（卡片内坐标直接检测即可，因为外层有transform但父级已做缩放）
    -- 使用稍微不同的视觉效果：边缘内发光
    local isHov = Components.isPointerInRect(x, y, w, h)
    if isHov then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, cr)
        nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.cardHover)))
        nvgFill(vg)
    end

    -- 描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    nvgStrokeColor(vg, nvgRGBAf(Theme.c(Theme.colors.panelBorder)))
    nvgStrokeWidth(vg, bw)
    nvgStroke(vg)

    -- 左侧怪物绘制
    local drawRadius = h * 0.32
    local drawCX = x + h * 0.5
    local drawCY = y + h * 0.5

    -- 绘制区深色圆底
    nvgBeginPath(vg)
    nvgCircle(vg, drawCX, drawCY, drawRadius + 8)
    nvgFillColor(vg, nvgRGBAf(0.12, 0.14, 0.20, 0.8))
    nvgFill(vg)

    -- 调用绘制函数
    local drawFn = EnemyMgr[monster.drawFunc]
    if drawFn then
        drawFn(vg, drawCX, drawCY, drawRadius, age_)
    end

    -- 右侧文字
    local textX = x + h + 8
    local textW = w - h - 16

    -- 名称
    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, Theme.font.button + 1)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.titleText)))
    nvgText(vg, textX, y + 20, monster.name)

    -- 英文名
    nvgFontSize(vg, Theme.font.small)
    nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.mutedText)))
    nvgText(vg, textX, y + 35, monster.nameEN)

    -- 描述
    nvgFontSize(vg, Theme.font.small + 1)
    nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.bodyText)))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgTextBox(vg, textX, y + 48, textW, monster.desc)

    -- 属性标签
    if cfg then
        local tagY = y + h - 18
        local tagX = textX
        Components.drawBadge(vg, tagX + 18, tagY, "HP:" .. cfg.hp, Theme.colors.accent)
        Components.drawBadge(vg, tagX + 68, tagY, "x" .. cfg.bulletCount, Theme.colors.energyCyan)
        Components.drawBadge(vg, tagX + 118, tagY, "SPD:" .. cfg.speed, Theme.colors.accentGreen)
    end
end

--- 点击处理
function M.onClick(x, y)
    if Components.hitTest(backBtnRect_, x, y) then
        return "back"
    end
    return nil
end

return M
