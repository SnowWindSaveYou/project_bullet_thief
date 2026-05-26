-- ============================================================================
-- DebugPanel.lua - 调试面板（PC 端按 0 切换显示）
-- 浮层模式，不暂停游戏
-- 动效：从右侧 easeOutCubic 滑入，easeInCubic 滑出
-- ============================================================================

local Tween      = require "lib.Tween"
local Theme      = require "ui.Theme"
local Components = require "ui.Components"

local M = {}

local W_, H_ = 0, 0
local visible_ = false

-- 按钮矩形缓存
local btnRects_ = {}

-- 调试动作列表
local DEBUG_ACTIONS = {
    { id = "shop",     label = "Open Shop" },
    { id = "heal",     label = "Full Heal" },
    { id = "energy",   label = "Max Energy" },
    { id = "kill100",  label = "+100 Kills" },
    { id = "godmode",  label = "God Mode" },
}

-- ═══ 动画状态 ═══
local anim_ = {
    slideX   = 1,   -- 0=完全展开, 1=完全收起(右侧)
    maskAlpha = 0,  -- 遮罩透明度
}

-- 每个按钮独立动画
local btnAnims_ = {}

function M.init(W, H)
    W_ = W
    H_ = H
    visible_ = false
    btnRects_ = {}
    anim_.slideX = 1
    anim_.maskAlpha = 0
end

function M.toggle()
    if visible_ then
        M.hide()
    else
        M.showPanel()
    end
end

function M.showPanel()
    visible_ = true

    Tween.cancelTarget(anim_)
    anim_.slideX = 1
    anim_.maskAlpha = 0

    -- 面板从右侧滑入 (easeOutCubic)
    Tween.to(anim_, { slideX = 0 }, 0.35, {
        easing = Tween.Easing.easeOutCubic,
    })

    -- 遮罩淡入
    Tween.to(anim_, { maskAlpha = 1 }, 0.25, {
        easing = Tween.Easing.easeOutCubic,
    })

    -- 按钮 stagger 出现 (easeOutBack)
    btnAnims_ = {}
    for i = 1, #DEBUG_ACTIONS do
        local ba = { alpha = 0, slideX = 30, scale = 0.8 }
        btnAnims_[i] = ba
        Tween.to(ba, { alpha = 1, slideX = 0, scale = 1.0 }, 0.35, {
            delay = 0.1 + (i - 1) * 0.06,
            easing = Tween.Easing.easeOutBack,
        })
    end

    print("[Debug] Panel opened")
end

function M.isVisible()
    return visible_
end

function M.hide()
    Tween.cancelTarget(anim_)

    -- 滑出动画 (easeInCubic)
    Tween.to(anim_, { slideX = 1, maskAlpha = 0 }, 0.25, {
        easing = Tween.Easing.easeInCubic,
        onComplete = function()
            visible_ = false
        end,
    })

    -- 按钮快速消失
    for _, ba in ipairs(btnAnims_) do
        Tween.cancelTarget(ba)
        Tween.to(ba, { alpha = 0 }, 0.15, {
            easing = Tween.Easing.easeInCubic,
        })
    end

    print("[Debug] Panel closed")
end

function M.draw(vg, W, H)
    if not visible_ and anim_.slideX >= 0.99 then return end

    W_ = W
    H_ = H

    -- 半透明遮罩（带色调）
    if anim_.maskAlpha > 0.01 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        local or_, og, ob = Theme.c(Theme.colors.overlay)
        nvgFillColor(vg, nvgRGBAf(or_, og, ob, 0.35 * anim_.maskAlpha))
        nvgFill(vg)
    end

    -- 面板（从右侧滑入）
    local panelW = math.min(180, W * 0.4)
    local panelH = #DEBUG_ACTIONS * 46 + 60
    local panelX = W - panelW - 12 + anim_.slideX * (panelW + 20)
    local panelY = 12

    Components.drawPanel(vg, panelX, panelY, panelW, panelH, { dark = true })

    -- 标题
    local titleY = panelY + 22
    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, Theme.font.body)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.accentYellow)))
    nvgText(vg, panelX + panelW * 0.5, titleY, "DEBUG")

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 12, titleY + 14)
    nvgLineTo(vg, panelX + panelW - 12, titleY + 14)
    nvgStrokeColor(vg, nvgRGBAf(1, 1, 1, 0.15))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 按钮列表 (带独立动画)
    btnRects_ = {}
    local btnStartY = titleY + 32
    local btnCX = panelX + panelW * 0.5

    for i, action in ipairs(DEBUG_ACTIONS) do
        local ba = btnAnims_[i]
        local btnAlpha = ba and ba.alpha or 1
        local btnSlide = ba and ba.slideX or 0
        local btnScale = ba and ba.scale or 1

        if btnAlpha > 0.01 then
            nvgGlobalAlpha(vg, btnAlpha)

            local by = btnStartY + (i - 1) * 46
            local bx = btnCX + btnSlide

            nvgSave(vg)
            nvgTranslate(vg, bx, by)
            nvgScale(vg, btnScale, btnScale)
            nvgTranslate(vg, -bx, -by)

            local rect = Components.drawButton(vg, bx, by, action.label, {
                variant = (i == 1) and "accent" or "primary",
                w = panelW - 30,
            })

            nvgRestore(vg)
            nvgGlobalAlpha(vg, 1.0)

            btnRects_[i] = { rect = rect, id = action.id }
        end
    end
end

--- 点击处理，返回动作 ID 或 nil
function M.onClick(x, y)
    if not visible_ then return nil end

    for _, btn in ipairs(btnRects_) do
        if btn.rect and Components.hitTest(btn.rect, x, y) then
            return btn.id
        end
    end

    return nil
end

return M
