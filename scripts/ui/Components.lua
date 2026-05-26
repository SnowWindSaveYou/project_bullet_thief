-- ============================================================================
-- Components.lua - 复古卡通风格通用 NanoVG UI 组件
-- 所有组件使用 Theme.lua 的配色
-- ============================================================================

local Theme = require "ui.Theme"

local M = {}

-- ═══ 全局 Hover 追踪 ═══
local hoverX_, hoverY_ = -9999, -9999  -- 当前鼠标/触摸位置

--- 由 main.lua 在 MouseMove / TouchMove 时调用
function M.setPointer(x, y)
    hoverX_ = x
    hoverY_ = y
end

--- 检测当前指针是否在矩形内
function M.isPointerInRect(x, y, w, h)
    return hoverX_ >= x and hoverX_ <= x + w
       and hoverY_ >= y and hoverY_ <= y + h
end

--- 检测当前指针是否在圆形内
function M.isPointerInCircle(cx, cy, r)
    local dx = hoverX_ - cx
    local dy = hoverY_ - cy
    return (dx * dx + dy * dy) <= r * r
end

-- ═══════════════════════════════════════════
-- 背景：全屏暗绿 + 十字星花纹
-- ═══════════════════════════════════════════
function M.drawBackground(vg, W, H)
    -- 底色
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.bgGreen)))
    nvgFill(vg)

    -- 星形/十字花纹
    M.drawStarPattern(vg, 0, 0, W, H)
end

--- 绘制十字星花纹（装饰背景用）
function M.drawStarPattern(vg, ox, oy, w, h)
    local spacing = 48
    local size = 6
    local cr, cg, cb, ca = Theme.c(Theme.colors.bgPattern)

    nvgStrokeColor(vg, nvgRGBAf(cr, cg, cb, ca))
    nvgStrokeWidth(vg, 1.2)

    local cols = math.ceil(w / spacing)
    local rows = math.ceil(h / spacing)

    for row = 0, rows do
        for col = 0, cols do
            local cx = ox + col * spacing + ((row % 2 == 0) and 0 or spacing * 0.5)
            local cy = oy + row * spacing

            if cx >= ox and cx <= ox + w and cy >= oy and cy <= oy + h then
                -- 小十字形
                nvgBeginPath(vg)
                nvgMoveTo(vg, cx - size, cy)
                nvgLineTo(vg, cx + size, cy)
                nvgMoveTo(vg, cx, cy - size)
                nvgLineTo(vg, cx, cy + size)
                nvgStroke(vg)
            end
        end
    end
end

-- ═══════════════════════════════════════════
-- 面板：米黄底 + 深蓝圆角描边
-- opts: { dark=bool, borderColor={r,g,b,a}, noBorder=bool }
-- ═══════════════════════════════════════════
function M.drawPanel(vg, x, y, w, h, opts)
    opts = opts or {}
    local cr = Theme.panel.cornerRadius
    local bw = Theme.panel.borderWidth

    -- 阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + 3, y + 4, w, h, cr)
    nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.shadow)))
    nvgFill(vg)

    -- 背景
    local bgColor = opts.dark and Theme.colors.panelBgDark or Theme.colors.panelBg
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    nvgFillColor(vg, nvgRGBAf(Theme.c(bgColor)))
    nvgFill(vg)

    -- 描边
    if not opts.noBorder then
        local bc = opts.borderColor or Theme.colors.panelBorder
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, cr)
        nvgStrokeColor(vg, nvgRGBAf(Theme.c(bc)))
        nvgStrokeWidth(vg, bw)
        nvgStroke(vg)
    end
end

-- ═══════════════════════════════════════════
-- 按钮：圆角 + 描边 + 文字
-- opts: { variant="primary"|"accent"|"dark"|"disabled", selected=bool, w=num }
-- 返回 { x, y, w, h } 用于点击检测
-- ═══════════════════════════════════════════
function M.drawButton(vg, cx, cy, text, opts)
    opts = opts or {}
    local variant = opts.variant or "primary"
    local bh = Theme.button.height
    local cr = Theme.button.cornerRadius
    local bw = Theme.button.borderWidth

    -- 计算文字宽度以确定按钮宽度
    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, Theme.font.button)
    local tw = nvgTextBounds(vg, 0, 0, text)
    local bwid = opts.w or (tw + Theme.button.paddingH * 2)

    local bx = cx - bwid * 0.5
    local by = cy - bh * 0.5

    -- 选择颜色
    local bgColor, borderColor, textColor
    if variant == "primary" then
        bgColor     = Theme.colors.accentGreen
        borderColor = Theme.colors.accentGreenDark
        textColor   = Theme.colors.white
    elseif variant == "accent" then
        bgColor     = Theme.colors.accent
        borderColor = { 0.70, 0.25, 0.25, 1.0 }
        textColor   = Theme.colors.white
    elseif variant == "dark" then
        bgColor     = Theme.colors.panelBgDark
        borderColor = Theme.colors.panelBorder
        textColor   = Theme.colors.lightText
    elseif variant == "disabled" then
        bgColor     = Theme.colors.cardDisabled
        borderColor = { 0.60, 0.60, 0.60, 1.0 }
        textColor   = Theme.colors.mutedText
    end

    -- 选中态覆盖
    if opts.selected then
        bgColor = Theme.colors.cardSelected
        borderColor = { 0.25, 0.42, 0.28, 1.0 }
        textColor = Theme.colors.white
    end

    -- 阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx + 2, by + 3, bwid, bh, cr)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.2))
    nvgFill(vg)

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, bwid, bh, cr)
    nvgFillColor(vg, nvgRGBAf(Theme.c(bgColor)))
    nvgFill(vg)

    -- 描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, bwid, bh, cr)
    nvgStrokeColor(vg, nvgRGBAf(Theme.c(borderColor)))
    nvgStrokeWidth(vg, bw)
    nvgStroke(vg)

    -- 棋盘格（选中态附加）
    if opts.selected then
        M.drawCheckered(vg, bx, by, bwid, bh, cr, Theme.colors.cardSelected)
    end

    -- Hover 高亮叠加（支持外部传入 hovered 状态，用于变换上下文内的按钮）
    local isHovered = opts.hovered
    if isHovered == nil then
        isHovered = M.isPointerInRect(bx, by, bwid, bh)
    end
    if isHovered and variant ~= "disabled" then
        -- 内部高亮层
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bwid, bh, cr)
        nvgFillColor(vg, nvgRGBAf(1, 1, 1, 0.18))
        nvgFill(vg)
        -- 顶部光泽条
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx + 2, by + 1, bwid - 4, bh * 0.35, cr - 1)
        nvgFillColor(vg, nvgRGBAf(1, 1, 1, 0.10))
        nvgFill(vg)
    end

    -- 文字
    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, Theme.font.button)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(Theme.c(textColor)))
    nvgText(vg, cx, cy, text)

    return { x = bx, y = by, w = bwid, h = bh, hovered = isHovered }
end

-- ═══════════════════════════════════════════
-- 棋盘格填充（用于选中态覆盖）
-- ═══════════════════════════════════════════
function M.drawCheckered(vg, x, y, w, h, cornerRadius, color)
    local cellSize = 8
    local cr, cg, cb = color[1], color[2], color[3]

    nvgSave(vg)
    -- 裁剪到圆角矩形内
    nvgIntersectScissor(vg, x, y, w, h)

    for row = 0, math.ceil(h / cellSize) do
        for col = 0, math.ceil(w / cellSize) do
            if (row + col) % 2 == 0 then
                local cx = x + col * cellSize
                local cy = y + row * cellSize
                nvgBeginPath(vg)
                nvgRect(vg, cx, cy, cellSize, cellSize)
                nvgFillColor(vg, nvgRGBAf(cr + 0.08, cg + 0.08, cb + 0.08, 0.3))
                nvgFill(vg)
            end
        end
    end

    nvgRestore(vg)
end

-- ═══════════════════════════════════════════
-- 进度条
-- opts: { bgColor, borderColor, label }
-- ═══════════════════════════════════════════
function M.drawProgressBar(vg, x, y, w, h, ratio, fillColor, opts)
    opts = opts or {}
    h = h or Theme.bar.height
    local cr = Theme.bar.cornerRadius
    local bw = Theme.bar.borderWidth
    ratio = math.max(0, math.min(1, ratio))

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    nvgFillColor(vg, nvgRGBAf(1.0, 1.0, 1.0, 0.9))
    nvgFill(vg)

    -- 填充
    if ratio > 0.01 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + 1, y + 1, (w - 2) * ratio, h - 2, cr - 1)
        nvgFillColor(vg, nvgRGBAf(Theme.c(fillColor)))
        nvgFill(vg)
    end

    -- 描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    nvgStrokeColor(vg, nvgRGBAf(Theme.c(opts.borderColor or Theme.colors.panelBorder)))
    nvgStrokeWidth(vg, bw)
    nvgStroke(vg)

    -- 标签
    if opts.label then
        nvgFontFace(vg, Theme.font.family)
        nvgFontSize(vg, Theme.font.small)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.titleText)))
        nvgText(vg, x, y - 10, opts.label)
    end
end

-- ═══════════════════════════════════════════
-- 胶囊标签 Badge
-- ═══════════════════════════════════════════
function M.drawBadge(vg, x, y, text, bgColor, textColor)
    bgColor   = bgColor or Theme.colors.accent
    textColor = textColor or Theme.colors.white

    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, Theme.font.badge)
    local tw = nvgTextBounds(vg, 0, 0, text)
    local pw = tw + 12
    local ph = 16
    local bx = x - pw * 0.5
    local by = y - ph * 0.5

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, pw, ph, ph * 0.5)
    nvgFillColor(vg, nvgRGBAf(Theme.c(bgColor)))
    nvgFill(vg)

    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(Theme.c(textColor)))
    nvgText(vg, x, y, text)
end

-- ═══════════════════════════════════════════
-- 标题文字（带描边阴影）
-- ═══════════════════════════════════════════
function M.drawTitle(vg, x, y, text, fontSize, color)
    fontSize = fontSize or Theme.font.title
    color = color or Theme.colors.titleText

    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 描边阴影（偏移）
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.15))
    nvgText(vg, x + 1.5, y + 2, text)

    -- 主色
    nvgFillColor(vg, nvgRGBAf(Theme.c(color)))
    nvgText(vg, x, y, text)
end

-- ═══════════════════════════════════════════
-- 圆形动作按钮（HUD 用）
-- ═══════════════════════════════════════════
function M.drawCircleButton(vg, cx, cy, r, label, opts)
    opts = opts or {}
    local isActive = opts.active or false
    local fillRatio = opts.fillRatio or 0
    local cr, cg, cb = Theme.c(opts.arcColor or Theme.colors.energyCyan)

    -- 阴影
    nvgBeginPath(vg)
    nvgCircle(vg, cx + 2, cy + 3, r)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.25))
    nvgFill(vg)

    -- 背景（米黄）
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r)
    nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.panelBg)))
    nvgFill(vg)

    -- 能量弧
    if fillRatio > 0.01 then
        local arc = fillRatio * math.pi * 2
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, r - 5, -math.pi * 0.5, -math.pi * 0.5 + arc, NVG_CW)
        local alpha = isActive and 1.0 or 0.7
        nvgStrokeColor(vg, nvgRGBAf(cr, cg, cb, alpha))
        nvgStrokeWidth(vg, 4)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    end

    -- 外描边
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r)
    local bAlpha = isActive and 1.0 or 0.7
    nvgStrokeColor(vg, nvgRGBAf(Theme.ca(Theme.colors.panelBorder, bAlpha)))
    nvgStrokeWidth(vg, isActive and 2.5 or 2.0)
    nvgStroke(vg)

    -- Hover 高亮
    if M.isPointerInCircle(cx, cy, r) then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r)
        nvgFillColor(vg, nvgRGBAf(1, 1, 1, 0.15))
        nvgFill(vg)
        -- 外环发光
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r + 2)
        nvgStrokeColor(vg, nvgRGBAf(1, 1, 1, 0.20))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)
    end

    -- 图标或文字标签
    if opts.icon and opts.icon > 0 then
        -- 绘制图标（居中，铺满按钮内圈）
        local iconSize = r * 1.3
        local ix = cx - iconSize * 0.5
        local iy = cy - iconSize * 0.5
        local iconAlpha = isActive and 1.0 or 0.8
        local paint = nvgImagePattern(vg, ix, iy, iconSize, iconSize, 0, opts.icon, iconAlpha)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r - 6)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        nvgFontFace(vg, Theme.font.family)
        nvgFontSize(vg, Theme.font.hud + 1)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(Theme.c(Theme.colors.titleText)))
        nvgText(vg, cx, cy, label)
    end
end

-- ═══════════════════════════════════════════
-- 点击检测辅助
-- ═══════════════════════════════════════════
function M.hitTest(rect, x, y)
    if not rect then return false end
    return x >= rect.x and x <= rect.x + rect.w
       and y >= rect.y and y <= rect.y + rect.h
end

function M.hitTestCircle(cx, cy, r, x, y)
    local dx = x - cx
    local dy = y - cy
    return (dx * dx + dy * dy) <= r * r
end

return M
