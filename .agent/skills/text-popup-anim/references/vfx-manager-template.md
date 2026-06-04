# VFX 管理器完整骨架代码

> 可直接复制到项目中，按需裁剪不需要的特效类型。
> 依赖 `Tween.lua`（仅 damp 插值）和 NanoVG 渲染上下文。

## 完整模块骨架

```lua
-- ============================================================================
-- VFXManager.lua — 通用弹字/粒子/屏幕效果管理器
-- 使用方式:
--   local VFX = require "game.VFXManager"
--   VFX.setContext(vg, logicalW, logicalH, gameTime)  -- 每帧渲染前调用
--   VFX.update(dt)                                     -- 每帧逻辑更新
--   VFX.draw()                                         -- 在 NanoVGRender 中调用
-- ============================================================================

local M = {}

-- ── 渲染上下文（每帧由 setContext 设置）──────────────────────────────────────
local vg = nil
local logicalW, logicalH = 0, 0
local gameTime = 0

function M.setContext(_vg, _logicalW, _logicalH, _gameTime)
    vg        = _vg
    logicalW  = _logicalW
    logicalH  = _logicalH
    gameTime  = _gameTime
end

-- ── 缓动函数 ────────────────────────────────────────────────────────────────

local function easeOutElastic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local c4 = (2 * math.pi) / 3
    return (2 ^ (-10 * t)) * math.sin((t * 10 - 0.75) * c4) + 1
end

local function easeOutBack(t)
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * ((t - 1) ^ 3) + c1 * ((t - 1) ^ 2)
end

local function easeInQuad(t)  return t * t end
local function easeOutQuad(t) local u = 1 - t; return 1 - u * u end
local function lerp(a, b, t)  return a + (b - a) * t end

-- ── RGB ↔ HSV 转换 ──────────────────────────────────────────────────────────

local function rgbToHsv(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local d   = max - min
    local h   = 0
    if d > 0 then
        if     max == r then h = ((g - b) / d) % 6
        elseif max == g then h = (b - r) / d + 2
        else                 h = (r - g) / d + 4
        end
        h = h * 60
    end
    return h, (max > 0 and d / max or 0), max
end

local function hsvToRgb(h, s, v)
    h = h % 360
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b = 0, 0, 0
    if     h < 60  then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else                r, g, b = c, 0, x
    end
    return math.floor((r + m) * 255), math.floor((g + m) * 255), math.floor((b + m) * 255)
end

--- 同色系暖偏阴影色：色相 -30°（偏暖），高饱和，中暗亮度
local function shadowColor(r, g, b, alpha)
    local h, s, _ = rgbToHsv(r, g, b)
    h = (h - 30 + 360) % 360
    s = math.max(0.85, s * 1.05)
    local v = 0.50
    local sr, sg, sb = hsvToRgb(h, s, v)
    return nvgRGBA(sr, sg, sb, alpha)
end

M.shadowColor = shadowColor

-- ── UTF-8 字符分割 ──────────────────────────────────────────────────────────

local function utf8Split(str)
    local chars = {}
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local len = (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or (b >= 0xC0 and 2) or 1
        chars[#chars + 1] = str:sub(i, i + len - 1)
        i = i + len
    end
    return chars
end

-- ── 4 层浮雕文字渲染 ────────────────────────────────────────────────────────
--- 调用前需已设置 nvgFontFace / nvgFontSize / nvgTextAlign
---@param x number   绘制中心 X
---@param y number   绘制中心 Y
---@param text string
---@param r number   主色 R (0-255)
---@param g number   主色 G
---@param b number   主色 B
---@param alpha number  整体不透明度 (0.0-1.0)
function M.drawLayeredText(x, y, text, r, g, b, alpha)
    -- 层1: 同色系暖偏阴影
    nvgFillColor(vg, shadowColor(r, g, b, math.floor(alpha * 200)))
    nvgText(vg, x + 2.5, y + 3.5, text, nil)
    -- 层2: 同色系内描边 (65% 亮度)
    nvgFillColor(vg, nvgRGBA(
        math.floor(r * 0.65), math.floor(g * 0.65), math.floor(b * 0.65),
        math.floor(alpha * 160)))
    nvgText(vg, x + 1.0, y + 1.5, text, nil)
    -- 层3: 主色
    nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(alpha * 255)))
    nvgText(vg, x, y, text, nil)
    -- 层4: 白色高光
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 85)))
    nvgText(vg, x - 1.0, y - 1.5, text, nil)
end

-- ════════════════════════════════════════════════════════════════════════════
-- §1  屏幕抖动 (Screen Shake)
-- ════════════════════════════════════════════════════════════════════════════

local shake = {
    offsetX = 0, offsetY = 0,
    intensity = 0, duration = 0,
    timer = 0, frequency = 25,
}

--- 触发屏幕抖动（叠加式：取更强值）
---@param intensity number  抖动振幅（像素）
---@param duration number   持续时长（秒）
---@param frequency number? 频率（默认 25）
function M.triggerShake(intensity, duration, frequency)
    shake.intensity = math.max(shake.intensity, intensity)
    shake.duration  = math.max(shake.duration, duration)
    shake.timer     = 0
    shake.frequency = frequency or 25
end

local function updateShake(dt)
    if shake.intensity <= 0 then
        shake.offsetX = 0; shake.offsetY = 0; return
    end
    shake.timer = shake.timer + dt
    local progress = shake.timer / shake.duration
    if progress >= 1.0 then
        shake.intensity = 0; shake.offsetX = 0; shake.offsetY = 0; return
    end
    local decay = (1.0 - progress) ^ 1.5
    local amp   = shake.intensity * decay
    local t     = shake.timer * shake.frequency
    -- 双正弦叠加 → 自然手感
    shake.offsetX = math.sin(t * 2.17 + 0.3) * amp + math.sin(t * 3.51) * amp * 0.3
    shake.offsetY = math.cos(t * 1.73 + 0.7) * amp + math.cos(t * 2.89) * amp * 0.3
end

--- 获取当前帧的抖动偏移，用于 nvgTranslate
function M.getShakeOffset() return shake.offsetX, shake.offsetY end

-- ════════════════════════════════════════════════════════════════════════════
-- §2  分数弹字 (Score Popup) — 4 段动画
-- ════════════════════════════════════════════════════════════════════════════

local scorePopups = {}

--- 从文本中提取数字（用于滚动效果）
local function parseNumText(text)
    local prefix = text:match("^([+%-]?)") or ""
    local numStr = text:match("[%d]+")
    local suffix = numStr and text:match("%d+(.*)") or ""
    if numStr then return prefix, tonumber(numStr), suffix end
    return nil, nil, nil
end

--- 生成分数弹字
---@param text string   显示文本（如 "+100"）
---@param x number      屏幕 X
---@param y number      屏幕 Y
---@param r number?     主色 R (默认 255)
---@param g number?     主色 G (默认 255)
---@param b number?     主色 B (默认 100)
---@param scale number? 缩放倍率 (默认 1.0)
function M.spawnPopup(text, x, y, r, g, b, scale)
    local prefix, numVal, suffix = parseNumText(text)
    scorePopups[#scorePopups + 1] = {
        text    = text,
        prefix  = prefix,
        numVal  = numVal,
        suffix  = suffix,
        x = x, y = y,
        timer   = 0,
        maxTime = 1.25,
        r = r or 255, g = g or 255, b = b or 100,
        scale   = scale or 1.0,
    }
end

local function updatePopups(dt)
    for i = #scorePopups, 1, -1 do
        local p = scorePopups[i]
        p.timer = p.timer + dt
        if p.timer >= p.maxTime then table.remove(scorePopups, i) end
    end
end

local function drawOnePopup(p)
    local progress = p.timer / p.maxTime
    local baseScale = p.scale
    local curX, curY = p.x, p.y
    local curScale, alpha, rotation = baseScale, 1.0, 0.0

    -- Phase 1: 0~0.15   弹出 (easeOutElastic, scale 0→2.0)
    -- Phase 2: 0.15~0.30 回弹 (easeInQuad, scale 2.0→1.0)
    -- Phase 3: 0.30~0.75 浮动 (sin 漂移 + 数字滚动)
    -- Phase 4: 0.75~1.00 飞出 (向上 80px + 淡出 + 幽灵拖尾)
    if progress < 0.15 then
        local t = progress / 0.15
        curScale = baseScale * easeOutElastic(t) * 2.0
        alpha    = math.min(1.0, t * 8)
    elseif progress < 0.30 then
        local t = (progress - 0.15) / 0.15
        curScale = baseScale * lerp(2.0, 1.0, easeInQuad(t))
    elseif progress < 0.75 then
        local t = (progress - 0.30) / 0.45
        curY     = curY - math.sin(t * math.pi * 2.5) * 3.5
        rotation = math.sin(t * math.pi * 2.0) * 5.0
    else
        local t = (progress - 0.75) / 0.25
        alpha    = 1.0 - easeOutQuad(t)
        curY     = curY - 85 * easeOutQuad(t)
        curScale = baseScale * (1.0 + t * 0.25)
        rotation = 8 * t
    end
    if alpha <= 0.01 then return end

    -- 数字滚动
    local displayText = p.text
    if p.numVal and progress >= 0.30 and progress < 0.68 then
        local t = (progress - 0.30) / 0.38
        if t < 0.75 then
            local base  = math.floor(p.numVal * t)
            local noise = math.floor(math.abs(math.sin(p.timer * 47.3 + 1.7)) * p.numVal * 0.45)
            local shown = math.min(base + noise, p.numVal + math.floor(p.numVal * 0.3))
            displayText = (p.prefix or "") .. tostring(shown) .. (p.suffix or "")
        end
    end

    -- 幽灵拖尾 (Phase 4)
    if progress >= 0.75 then
        local t = (progress - 0.75) / 0.25
        for gi = 1, 3 do
            local ghostT = t - gi * 0.06
            if ghostT >= 0 then
                local ghostOff = -85 * easeOutQuad(ghostT)
                local ghostA   = alpha * (0.35 - gi * 0.10)
                if ghostA > 0.01 then
                    nvgSave(vg)
                    nvgTranslate(vg, curX, p.y + ghostOff)
                    nvgScale(vg, curScale * 0.92, curScale * 0.92)
                    nvgFontFace(vg, "sans")  -- ← 替换为你的字体
                    nvgFontSize(vg, 26)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(ghostA * 255)))
                    nvgText(vg, 0, 0, displayText, nil)
                    nvgRestore(vg)
                end
            end
        end
    end

    -- 主体绘制
    nvgSave(vg)
    nvgTranslate(vg, curX, curY)
    nvgScale(vg, curScale, curScale)
    nvgRotate(vg, rotation * math.pi / 180)

    -- 光晕背景
    if alpha > 0.3 then
        local glowR = 28 + 14 * (curScale / baseScale)
        local glow = nvgRadialGradient(vg, 0, 0, 0, glowR,
            nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 90)),
            nvgRGBA(p.r, p.g, p.b, 0))
        nvgBeginPath(vg)
        nvgRect(vg, -glowR, -glowR, glowR * 2, glowR * 2)
        nvgFillPaint(vg, glow); nvgFill(vg)
    end

    -- 4 层浮雕文字
    nvgFontFace(vg, "sans")  -- ← 替换为你的字体
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    M.drawLayeredText(0, 0, displayText, p.r, p.g, p.b, alpha)

    nvgRestore(vg)
end

function M.drawPopups()
    for _, p in ipairs(scorePopups) do drawOnePopup(p) end
end

-- ════════════════════════════════════════════════════════════════════════════
-- §3  行动横幅 (Action Banner) — 逐字错时弹入
-- ════════════════════════════════════════════════════════════════════════════

local banners = {}

--- 生成逐字弹入横幅
---@param text string    显示文本
---@param r number?      主色 R (默认 255)
---@param g number?      主色 G (默认 255)
---@param b number?      主色 B (默认 255)
---@param size number?   字号 (默认 32)
---@param duration number? 持续时间 (默认 1.5)
function M.spawnBanner(text, r, g, b, size, duration)
    local chars = utf8Split(text)
    banners[#banners + 1] = {
        chars   = chars,
        text    = text,
        timer   = 0,
        maxTime = duration or 1.5,
        r = r or 255, g = g or 255, b = b or 255,
        size    = size or 32,
    }
end

local function updateBanners(dt)
    for i = #banners, 1, -1 do
        local b = banners[i]
        b.timer = b.timer + dt
        if b.timer >= b.maxTime + (#b.chars - 1) * 0.055 + 0.1 then
            table.remove(banners, i)
        end
    end
end

local function charDisplayWidth(ch, size)
    local b = ch:byte(1)
    return (b >= 0x80) and (size * 0.92) or (size * 0.52)
end

function M.drawBanners()
    local cx = logicalW / 2
    local baseY = logicalH / 2 + 38
    local STAGGER    = 0.055
    local ENTRY_DUR  = 0.18
    local SETTLE_DUR = 0.12
    local FADE_START = 0.70

    for idx, banner in ipairs(banners) do
        local nChars = #banner.chars
        local totalStagger = (nChars - 1) * STAGGER
        local effectiveMax = banner.maxTime + totalStagger
        local progress     = banner.timer / effectiveMax

        -- 全局淡出
        local globalAlpha = 1.0
        if progress > FADE_START then
            globalAlpha = math.max(0, 1.0 - (progress - FADE_START) / (1.0 - FADE_START))
        end
        globalAlpha = easeOutQuad(globalAlpha)

        -- 淡出阶段向上飘
        local globalOffY = 0
        if progress > FADE_START then
            globalOffY = -35 * easeOutQuad((progress - FADE_START) / (1.0 - FADE_START))
        end

        -- 计算总宽度用于居中
        local totalW = 0
        local charW  = {}
        for ci, ch in ipairs(banner.chars) do
            charW[ci] = charDisplayWidth(ch, banner.size)
            totalW    = totalW + charW[ci]
        end

        local rowY = baseY - (idx - 1) * (banner.size * 1.3) + globalOffY

        -- 背景光晕
        if globalAlpha > 0.05 then
            local hW = totalW * 0.65 + banner.size
            local hH = banner.size * 0.7
            local glow = nvgRadialGradient(vg, cx, rowY, 0, math.max(hW, hH) * 1.4,
                nvgRGBA(banner.r, banner.g, banner.b, math.floor(globalAlpha * 38)),
                nvgRGBA(banner.r, banner.g, banner.b, 0))
            nvgBeginPath(vg)
            nvgRect(vg, cx - hW * 1.4, rowY - hH * 1.4, hW * 2.8, hH * 2.8)
            nvgFillPaint(vg, glow); nvgFill(vg)
        end

        -- 逐字绘制
        local curX = cx - totalW / 2
        for ci, ch in ipairs(banner.chars) do
            local delay  = (ci - 1) * STAGGER
            local localT = banner.timer - delay

            local cAlpha, cY = globalAlpha, rowY
            local cScaleX, cScaleY = 1.0, 1.0

            if localT < 0 then
                curX = curX + charW[ci]
                goto continue_char
            elseif localT < ENTRY_DUR then
                local t  = localT / ENTRY_DUR
                local es = easeOutBack(t)
                cY      = cY + lerp(28, 0, easeOutQuad(t))
                cAlpha  = globalAlpha * math.min(1.0, t * 5)
                cScaleX = lerp(0.4, 1.0, es)
                cScaleY = lerp(1.6, 1.0, easeOutBack(math.min(1, t * 1.2))) * (0.8 + 0.2 * es)
            elseif localT < ENTRY_DUR + SETTLE_DUR then
                local t  = (localT - ENTRY_DUR) / SETTLE_DUR
                cScaleY = lerp(0.88, 1.0, easeOutQuad(t))
                cScaleX = lerp(1.12, 1.0, easeOutQuad(t))
            else
                local wave = math.sin(gameTime * 3.2 + ci * 0.9) * 2.5
                cY      = cY + wave
                cScaleY = 1.0 + math.sin(gameTime * 2.8 + ci * 0.7) * 0.018
            end

            if cAlpha > 0.01 then
                local cx_char = curX + charW[ci] * 0.5
                nvgSave(vg)
                nvgTranslate(vg, cx_char, cY)
                nvgScale(vg, cScaleX, cScaleY)
                nvgFontFace(vg, "bold")  -- ← 替换为你的字体
                nvgFontSize(vg, banner.size)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                M.drawLayeredText(0, 0, ch, banner.r, banner.g, banner.b, cAlpha)
                nvgRestore(vg)
            end

            curX = curX + charW[ci]
            ::continue_char::
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════════
-- §4  阶段过渡文字 (Phase Transition)
-- ════════════════════════════════════════════════════════════════════════════

local transition = { text = "", timer = 0, duration = 1.2, r = 180, g = 120, b = 255 }

--- 显示阶段过渡文字（单例，新调用覆盖旧调用）
function M.showTransition(text, r, g, b)
    transition.text  = text
    transition.timer = transition.duration
    transition.r     = r or 180
    transition.g     = g or 120
    transition.b     = b or 255
end

local function updateTransition(dt)
    if transition.timer > 0 then transition.timer = transition.timer - dt end
end

function M.drawTransition()
    if transition.timer <= 0 then return end
    local progress = 1.0 - transition.timer / transition.duration
    local alpha, scale = 0, 1.0
    if progress < 0.25 then
        local t = progress / 0.25
        alpha = t; scale = easeOutBack(t)
    elseif progress < 0.72 then
        alpha = 1.0; scale = 1.0
    else
        local t = (progress - 0.72) / 0.28
        alpha = 1.0 - easeOutQuad(t); scale = 1.0 + t * 0.08
    end
    if alpha <= 0.01 then return end

    local cx, cy = logicalW / 2, logicalH / 2
    nvgSave(vg)
    nvgTranslate(vg, cx, cy); nvgScale(vg, scale, scale)
    nvgFontFace(vg, "bold")  -- ← 替换为你的字体
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    M.drawLayeredText(0, 0, transition.text, transition.r, transition.g, transition.b, alpha)
    nvgRestore(vg)
end

-- ════════════════════════════════════════════════════════════════════════════
-- §5  筹码/粒子飞行 (Chip Particles)
-- ════════════════════════════════════════════════════════════════════════════

local chipParticles = {}

--- 生成粒子飞行（贝塞尔曲线轨迹）
---@param sx number   起点 X
---@param sy number   起点 Y
---@param tx number   终点 X
---@param ty number   终点 Y
---@param count number? 粒子数 (默认 12)
---@param r number?   颜色 R (默认 255)
---@param g number?   颜色 G (默认 215)
---@param b number?   颜色 B (默认 0)
function M.spawnChips(sx, sy, tx, ty, count, r, g, b)
    count = count or 12
    r = r or 255; g = g or 215; b = b or 0
    for i = 1, count do
        local delay    = (i - 1) * 0.03 + math.random() * 0.05
        local duration = 0.4 + math.random() * 0.3
        chipParticles[#chipParticles + 1] = {
            sx = sx, sy = sy, tx = tx, ty = ty,
            midOffX = (math.random() - 0.5) * 80,
            midOffY = -30 - math.random() * 40,
            timer = -delay, duration = duration,
            r = r, g = g, b = b,
            size    = 3 + math.random() * 3,
            sparkle = math.random() * math.pi * 2,
        }
    end
end

local function updateChips(dt)
    for i = #chipParticles, 1, -1 do
        local p = chipParticles[i]
        p.timer = p.timer + dt
        if p.timer >= p.duration then table.remove(chipParticles, i) end
    end
end

function M.drawChips()
    for _, p in ipairs(chipParticles) do
        if p.timer <= 0 then goto skip end
        local t   = math.min(1.0, p.timer / p.duration)
        local et  = t * t
        local midX = (p.sx + p.tx) / 2 + p.midOffX
        local midY = (p.sy + p.ty) / 2 + p.midOffY
        local omt  = 1 - et
        local px   = omt * omt * p.sx + 2 * omt * et * midX + et * et * p.tx
        local py   = omt * omt * p.sy + 2 * omt * et * midY + et * et * p.ty
        local alpha = t < 0.7 and 1.0 or (1.0 - (t - 0.7) / 0.3)
        local size  = p.size * (1.0 - t * 0.3)
        local sa    = 0.7 + 0.3 * math.sin(gameTime * 15 + p.sparkle)

        -- 光晕
        local glow = nvgRadialGradient(vg, px, py, 0, size * 3,
            nvgRGBA(p.r, p.g, p.b, math.floor(alpha * sa * 60)),
            nvgRGBA(p.r, p.g, p.b, 0))
        nvgBeginPath(vg); nvgCircle(vg, px, py, size * 3)
        nvgFillPaint(vg, glow); nvgFill(vg)
        -- 粒子实体
        nvgBeginPath(vg); nvgCircle(vg, px, py, size)
        nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(alpha * sa * 240)))
        nvgFill(vg)
        ::skip::
    end
end

-- ════════════════════════════════════════════════════════════════════════════
-- §6  统一更新 / 绘制 / 重置
-- ════════════════════════════════════════════════════════════════════════════

--- 每帧逻辑更新（在 HandleUpdate 中调用）
function M.update(dt)
    updateShake(dt)
    updatePopups(dt)
    updateBanners(dt)
    updateTransition(dt)
    updateChips(dt)
end

--- 每帧绘制（在 NanoVGRender 事件中调用）
--- 推荐调用顺序：粒子 → 弹字 → 横幅 → 过渡
function M.draw()
    M.drawChips()
    M.drawPopups()
    M.drawBanners()
    M.drawTransition()
end

--- 清空所有活跃特效
function M.reset()
    scorePopups   = {}
    banners       = {}
    chipParticles = {}
    transition.timer = 0
    shake.intensity  = 0
    shake.offsetX    = 0
    shake.offsetY    = 0
end

return M
```

## 集成到游戏的最小示例

```lua
local VFX = require "game.VFXManager"

function Start()
    -- ... 初始化 NanoVG、字体等 ...
    SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    VFX.update(dt)
end

function HandleNanoVGRender(eventType, eventData)
    local dpr = graphics:GetDPR()
    local physW, physH = graphics:GetWidth(), graphics:GetHeight()
    local logicalW, logicalH = physW / dpr, physH / dpr

    VFX.setContext(vg, logicalW, logicalH, time:GetElapsedTime())

    nvgBeginFrame(vg, physW, physH, dpr)

    -- 应用屏幕抖动
    local sx, sy = VFX.getShakeOffset()
    nvgTranslate(vg, sx, sy)

    -- 绘制游戏内容 ...

    -- 绘制所有特效
    VFX.draw()

    nvgEndFrame(vg)
end

-- 使用示例:
-- VFX.spawnPopup("+100", 400, 300, 255, 215, 0)
-- VFX.spawnBanner("完美\!", 255, 200, 50, 36, 2.0)
-- VFX.showTransition("第 2 回合", 180, 120, 255)
-- VFX.triggerShake(8, 0.3)
-- VFX.spawnChips(100, 100, 400, 50, 15, 255, 215, 0)
```
