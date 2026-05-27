-- ============================================================================
-- VFX.lua - 视觉特效系统 v2
-- 屏幕抖动 / 行动飘字(逐字错时) / 筹码粒子 / 底池脉冲 / 分数弹出(4段) /
-- 融合特效 / 对手融合动画 / 阶段过渡
-- 来源：jieyuyou 项目，已移除 Card/补牌 特效依赖
-- ============================================================================

local Tween = require "lib.Tween"
local Pool  = require "lib.Pool"

local M = {}

-- 高频特效对象池
local hitPool_   = Pool.new(32)   -- 命中特效
local sparkPool_ = Pool.new(64)   -- 擦弹火花
local chipPool_  = Pool.new(48)   -- 筹码粒子
local popupPool_ = Pool.new(16)   -- 分数弹出
local healPool_  = Pool.new(16)   -- 回血特效

-- 渲染上下文（每帧由 setContext 设置）
local vg = nil
local logicalW, logicalH = 0, 0
local gameTime = 0

function M.setContext(_vg, _logicalW, _logicalH, _gameTime)
    vg = _vg
    logicalW = _logicalW
    logicalH = _logicalH
    gameTime = _gameTime
end

-- ============================================================================
-- 缓动函数
-- ============================================================================

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

-- RGB → HSV
local function rgbToHsv(r, g, b)
    r, g, b = r/255, g/255, b/255
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

-- HSV → RGB (0-255)
local function hsvToRgb(h, s, v)
    h = h % 360
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b = 0, 0, 0
    if     h < 60  then r,g,b = c,x,0
    elseif h < 120 then r,g,b = x,c,0
    elseif h < 180 then r,g,b = 0,c,x
    elseif h < 240 then r,g,b = 0,x,c
    elseif h < 300 then r,g,b = x,0,c
    else               r,g,b = c,0,x
    end
    return math.floor((r+m)*255), math.floor((g+m)*255), math.floor((b+m)*255)
end

-- 同色系加深阴影：色相偏转 -30°（保持色系感），高饱和，中暗亮度
-- 金色→深橙影，紫色→深蓝紫影，自然插画风，不对撞
local function shadowColor(r, g, b, alpha)
    local h, s, _ = rgbToHsv(r, g, b)
    h = (h - 30 + 360) % 360      -- 向暖侧偏转 30°，保持同色系
    s = math.max(0.85, s * 1.05)  -- 拉高饱和度，让阴影更鲜
    local v = 0.50                 -- 中暗亮度：作为阴影够深，颜色依然可见
    local sr, sg, sb = hsvToRgb(h, s, v)
    return nvgRGBA(sr, sg, sb, alpha)
end

-- 暴露给外部模块使用（ATK显示等静态文字也用同款渲染方案）
M.shadowColor = shadowColor

--- 4层文字渲染辅助：深影 → 内描 → 主色 → 白色高光
--- 调用前需已设置好 nvgFontFace / nvgFontSize / nvgTextAlign
---@param x number  绘制中心 X（相对当前变换）
---@param y number  绘制中心 Y
---@param text string
---@param r number  主色 R (0-255)
---@param g number  主色 G
---@param b number  主色 B
---@param alpha number  整体不透明度 (0.0-1.0)
function M.drawLayeredText(x, y, text, r, g, b, alpha)
    -- 层1：同色系深影
    nvgFillColor(vg, shadowColor(r, g, b, math.floor(alpha * 200)))
    nvgText(vg, x + 2.5, y + 3.5, text, nil)
    -- 层2：同色系内描
    nvgFillColor(vg, nvgRGBA(
        math.floor(r * 0.65), math.floor(g * 0.65), math.floor(b * 0.65),
        math.floor(alpha * 160)))
    nvgText(vg, x + 1.0, y + 1.5, text, nil)
    -- 层3：主色
    nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(alpha * 255)))
    nvgText(vg, x, y, text, nil)
    -- 层4：白色高光
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 85)))
    nvgText(vg, x - 1.0, y - 1.5, text, nil)
end

-- ============================================================================
-- UTF-8 字符分割
-- ============================================================================

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

-- ============================================================================
-- 屏幕抖动 (Screen Shake)
-- ============================================================================

local shake = {
    offsetX = 0, offsetY = 0,
    intensity = 0, duration = 0,
    timer = 0, frequency = 25,
}

function M.triggerShake(intensity, duration, frequency)
    shake.intensity = math.max(shake.intensity, intensity)
    shake.duration  = math.max(shake.duration, duration)
    shake.timer     = 0
    shake.frequency = frequency or 25
end

local function updateShake(dt)
    if shake.intensity <= 0 then shake.offsetX = 0; shake.offsetY = 0; return end
    shake.timer = shake.timer + dt
    local progress = shake.timer / shake.duration
    if progress >= 1.0 then shake.intensity = 0; shake.offsetX = 0; shake.offsetY = 0; return end
    local decay = (1.0 - progress) ^ 1.5
    local amp   = shake.intensity * decay
    local t     = shake.timer * shake.frequency
    shake.offsetX = math.sin(t * 2.17 + 0.3) * amp + math.sin(t * 3.51) * amp * 0.3
    shake.offsetY = math.cos(t * 1.73 + 0.7) * amp + math.cos(t * 2.89) * amp * 0.3
end

function M.getShakeOffset() return shake.offsetX, shake.offsetY end

-- ============================================================================
-- 行动飘字 v2 — 逐字错时弹入 + 光晕背景
-- ============================================================================

local actionBanners = {}

function M.spawnBanner(text, r, g, b, size, duration)
    if #actionBanners >= 6 then return end  -- 安全上限
    local chars = utf8Split(text)
    actionBanners[#actionBanners + 1] = {
        chars    = chars,
        text     = text,
        timer    = 0,
        maxTime  = duration or 1.5,
        r = r or 255, g = g or 255, b = b or 255,
        size     = size or 32,
    }
end

local function updateBanners(dt)
    for i = #actionBanners, 1, -1 do
        local b = actionBanners[i]
        b.timer = b.timer + dt
        -- 最后一个字的 stagger + maxTime 之后才删除
        if b.timer >= b.maxTime + (#b.chars - 1) * 0.055 + 0.1 then
            table.remove(actionBanners, i)
        end
    end
end

-- 估算单字符显示宽度（用于居中）
local function charDisplayWidth(ch, size)
    local b = ch:byte(1)
    return (b >= 0x80) and (size * 0.92) or (size * 0.52)
end

function M.drawBanners()
    local cx   = logicalW / 2
    -- transition 占据屏幕正中央，banner 下移避免重叠
    local baseY = logicalH / 2 + 38
    local STAGGER   = 0.055   -- 每字延迟
    local ENTRY_DUR = 0.18    -- 弹入时长
    local SETTLE_DUR = 0.12   -- 回弹时长
    local FADE_START = 0.70   -- 相对 maxTime 的比例：何时开始淡出

    for idx, banner in ipairs(actionBanners) do
        local nChars = #banner.chars
        local totalStagger = (nChars - 1) * STAGGER
        local effectiveMax = banner.maxTime + totalStagger
        local progress     = banner.timer / effectiveMax

        -- 全局淡出（最后 30% 时间）
        local globalAlpha = 1.0
        local fadeFrom = FADE_START
        if progress > fadeFrom then
            globalAlpha = math.max(0, 1.0 - (progress - fadeFrom) / (1.0 - fadeFrom))
        end
        globalAlpha = easeOutQuad(globalAlpha)  -- 让淡出更平滑

        -- 全局纵向偏移（淡出阶段向上飘）
        local globalOffY = 0
        if progress > fadeFrom then
            globalOffY = -35 * easeOutQuad((progress - fadeFrom) / (1.0 - fadeFrom))
        end

        -- 计算总宽度，用于居中
        local totalW = 0
        local charW  = {}
        for ci, ch in ipairs(banner.chars) do
            charW[ci] = charDisplayWidth(ch, banner.size)
            totalW    = totalW + charW[ci]
        end

        local rowY = baseY - (idx - 1) * (banner.size * 1.3) + globalOffY

        -- ── 背景光晕 ──────────────────────────────────────────────────────
        if globalAlpha > 0.05 then
            local hW = totalW * 0.65 + banner.size
            local hH = banner.size * 0.7
            local glow = nvgRadialGradient(vg, cx, rowY, 0, math.max(hW, hH) * 1.4,
                nvgRGBA(banner.r, banner.g, banner.b, math.floor(globalAlpha * 38)),
                nvgRGBA(banner.r, banner.g, banner.b, 0))
            nvgBeginPath(vg)
            nvgRect(vg, cx - hW * 1.4, rowY - hH * 1.4, hW * 2.8, hH * 2.8)
            nvgFillPaint(vg, glow)
            nvgFill(vg)
        end

        -- ── 逐字绘制 ───────────────────────────────────────────────────────
        local curX = cx - totalW / 2
        for ci, ch in ipairs(banner.chars) do
            local delay  = (ci - 1) * STAGGER
            local localT = banner.timer - delay   -- 该字的本地时间

            local cAlpha  = globalAlpha
            local cY      = rowY
            local cScaleX = 1.0
            local cScaleY = 1.0

            if localT < 0 then
                -- 还未开始：跳过（但占位）
                curX = curX + charW[ci]
                goto continue_char
            elseif localT < ENTRY_DUR then
                -- 弹入：从上方掉入，弹性放大
                local t  = localT / ENTRY_DUR
                local es = easeOutBack(t)
                cY     = cY + lerp(28, 0, easeOutQuad(t))
                cAlpha = globalAlpha * math.min(1.0, t * 5)
                -- x 方向轻微挤压感
                cScaleX = lerp(0.4, 1.0, es)
                cScaleY = lerp(1.6, 1.0, easeOutBack(math.min(1, t * 1.2))) * (0.8 + 0.2 * es)
            elseif localT < ENTRY_DUR + SETTLE_DUR then
                -- 回弹：轻微竖向压扁
                local t = (localT - ENTRY_DUR) / SETTLE_DUR
                cScaleY = lerp(0.88, 1.0, easeOutQuad(t))
                cScaleX = lerp(1.12, 1.0, easeOutQuad(t))
            else
                -- 悬停：轻微 sin 浮动（每字相位不同）
                local wave = math.sin(gameTime * 3.2 + ci * 0.9) * 2.5
                cY = cY + wave
                cScaleY = 1.0 + math.sin(gameTime * 2.8 + ci * 0.7) * 0.018
            end

            if cAlpha > 0.01 then
                local cx_char = curX + charW[ci] * 0.5
                nvgSave(vg)
                nvgTranslate(vg, cx_char, cY)
                nvgScale(vg, cScaleX, cScaleY)

                nvgFontFace(vg, "bold")
                nvgFontSize(vg, banner.size)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

                -- 对比色投影（HSV旋转155°）
                nvgFillColor(vg, shadowColor(banner.r, banner.g, banner.b,
                    math.floor(cAlpha * 200)))
                nvgText(vg, 2.5, 3.5, ch, nil)

                -- 近距内描（同色系略暗，增加立体感）
                nvgFillColor(vg, nvgRGBA(
                    math.floor(banner.r * 0.65),
                    math.floor(banner.g * 0.65),
                    math.floor(banner.b * 0.65),
                    math.floor(cAlpha * 160)))
                nvgText(vg, 1.0, 1.5, ch, nil)

                -- 主色
                nvgFillColor(vg, nvgRGBA(banner.r, banner.g, banner.b, math.floor(cAlpha * 255)))
                nvgText(vg, 0, 0, ch, nil)

                -- 白色高光（左上角，浅色背景下适当减弱）
                nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(cAlpha * 85)))
                nvgText(vg, -1, -1.2, ch, nil)

                nvgRestore(vg)
            end

            curX = curX + charW[ci]
            ::continue_char::
        end
    end
end

-- ============================================================================
-- 筹码粒子 (Chip Particles) — 不变
-- ============================================================================

local chipParticles = {}

function M.spawnChips(sx, sy, tx, ty, count, r, g, b)
    count = count or 12
    r = r or 255; g = g or 215; b = b or 0
    for i = 1, count do
        local delay    = (i - 1) * 0.03 + math.random() * 0.05
        local duration = 0.4 + math.random() * 0.3
        local p = chipPool_:get()
        p.sx = sx; p.sy = sy; p.tx = tx; p.ty = ty
        p.midOffX = (math.random() - 0.5) * 80
        p.midOffY = -30 - math.random() * 40
        p.timer = -delay; p.duration = duration
        p.r = r; p.g = g; p.b = b
        p.size = 3 + math.random() * 3
        p.sparkle = math.random() * math.pi * 2
        chipParticles[#chipParticles + 1] = p
    end
end

local function updateChips(dt)
    for i = #chipParticles, 1, -1 do
        local p = chipParticles[i]
        p.timer = p.timer + dt
        if p.timer >= p.duration then
            chipPool_:release(p)
            table.remove(chipParticles, i)
        end
    end
end

function M.drawChips()
    for _, p in ipairs(chipParticles) do
        if p.timer <= 0 then goto skip_chip end
        local t   = math.min(1.0, p.timer / p.duration)
        local et  = t * t
        local midX = (p.sx + p.tx) / 2 + p.midOffX
        local midY = (p.sy + p.ty) / 2 + p.midOffY
        local omt  = 1 - et
        local px   = omt*omt*p.sx + 2*omt*et*midX + et*et*p.tx
        local py   = omt*omt*p.sy + 2*omt*et*midY + et*et*p.ty
        local alpha = t < 0.7 and 1.0 or (1.0 - (t-0.7)/0.3)
        local size  = p.size * (1.0 - t*0.3)
        local sa    = 0.7 + 0.3 * math.sin(gameTime*15 + p.sparkle)

        local glow = nvgRadialGradient(vg, px, py, 0, size*3,
            nvgRGBA(p.r,p.g,p.b, math.floor(alpha*sa*60)),
            nvgRGBA(p.r,p.g,p.b, 0))
        nvgBeginPath(vg); nvgCircle(vg, px, py, size*3)
        nvgFillPaint(vg, glow); nvgFill(vg)

        nvgBeginPath(vg); nvgCircle(vg, px, py, size)
        nvgFillColor(vg, nvgRGBA(p.r,p.g,p.b, math.floor(alpha*sa*240)))
        nvgFill(vg)
        ::skip_chip::
    end
end

-- ============================================================================
-- 底池脉冲 (Pot Pulse) — 不变
-- ============================================================================

local potPulse = { active=false, timer=0, duration=0.6, intensity=1.0 }

function M.triggerPotPulse(intensity)
    potPulse.active = true; potPulse.timer = 0; potPulse.intensity = intensity or 1.0
end

local function updatePotPulse(dt)
    if not potPulse.active then return end
    potPulse.timer = potPulse.timer + dt
    if potPulse.timer >= potPulse.duration then potPulse.active = false end
end

function M.getPotPulseState()
    if not potPulse.active then return 1.0, 0, 0 end
    local t        = potPulse.timer / potPulse.duration
    local envelope = math.sin(t * math.pi)
    local intensity = potPulse.intensity
    return 1.0 + 0.15*envelope*intensity, envelope*intensity,
           math.floor(40*envelope*intensity)
end

-- ============================================================================
-- 分数弹出 v2 — 4段动画 + 数字滚动 + 运动拖影
-- ============================================================================

local scorePopups = {}

-- 从文本中提取数字信息（用于滚动效果）
local function parseNumText(text)
    local prefix = text:match("^([+%-]?)")  or ""
    local numStr = text:match("[%d]+")
    local suffix = numStr and text:match("%d+(.*)")  or ""
    if numStr then
        return prefix, tonumber(numStr), suffix
    end
    return nil, nil, nil
end

function M.spawnPopup(text, x, y, r, g, b, scale)
    if #scorePopups >= 40 then return end  -- 安全上限
    local prefix, numVal, suffix = parseNumText(text)
    local p = popupPool_:get()
    p.text = text
    p.prefix = prefix
    p.numVal = numVal
    p.suffix = suffix
    p.x = x; p.y = y
    p.timer = 0
    p.maxTime = 1.25
    p.r = r or 255; p.g = g or 255; p.b = b or 100
    p.scale = scale or 1.0
    p.trailPositions = {}
    scorePopups[#scorePopups + 1] = p
end

local function updatePopups(dt)
    for i = #scorePopups, 1, -1 do
        local p = scorePopups[i]
        p.timer = p.timer + dt
        if p.timer >= p.maxTime then
            popupPool_:release(p)
            table.remove(scorePopups, i)
        end
    end
end

-- 绘制单个 popup（含拖影）
local function drawOnePopup(p)
    local progress = p.timer / p.maxTime
    local baseScale = p.scale

    -- ── 4段时序 ─────────────────────────────────────────────────────────────
    -- Phase 1: 0~0.15  弹出  easeOutElastic, scale 0→2.0
    -- Phase 2: 0.15~0.30  回弹  easeInQuad, scale 2.0→1.0
    -- Phase 3: 0.30~0.75  浮动  sin漂移 + 数字滚动
    -- Phase 4: 0.75~1.00  飞出  向上80px + 淡出 + 拖影

    local curX, curY = p.x, p.y
    local curScale   = baseScale
    local alpha      = 1.0
    local rotation   = 0.0      -- 度数

    if progress < 0.15 then
        local t  = progress / 0.15
        curScale = baseScale * easeOutElastic(t) * 1.4
        alpha    = math.min(1.0, t * 8)   -- 快速淡入
    elseif progress < 0.30 then
        local t  = (progress - 0.15) / 0.15
        curScale = baseScale * lerp(1.4, 1.0, easeInQuad(t))
    elseif progress < 0.75 then
        local t  = (progress - 0.30) / 0.45
        curScale = baseScale
        curY     = curY - math.sin(t * math.pi * 2.5) * 3.5
        rotation = math.sin(t * math.pi * 2.0) * 5.0
    else
        local t  = (progress - 0.75) / 0.25
        alpha    = 1.0 - easeOutQuad(t)
        curY     = curY - 60 * easeOutQuad(t)
        curScale = baseScale * (1.0 + t * 0.25)
        rotation = 8 * t   -- 轻微旋转漂移
    end

    if alpha <= 0.01 then return end

    -- ── 数字滚动文本 ─────────────────────────────────────────────────────────
    local displayText = p.text
    if p.numVal and progress >= 0.30 and progress < 0.68 then
        local t = (progress - 0.30) / 0.38
        if t < 0.75 then
            -- 快速跳动：用 sin 产生伪随机跳动值
            local base  = math.floor(p.numVal * t)
            local noise = math.floor(math.abs(math.sin(p.timer * 47.3 + 1.7)) * p.numVal * 0.45)
            local shown = math.min(base + noise, p.numVal + math.floor(p.numVal * 0.3))
            displayText = (p.prefix or "") .. tostring(shown) .. (p.suffix or "")
        end
    end

    -- ── 拖影（phase 4 专用）─────────────────────────────────────────────────
    if progress >= 0.75 then
        local t = (progress - 0.75) / 0.25
        local baseOffY = -60 * easeOutQuad(t)
        local ghostCount = 3
        for gi = 1, ghostCount do
            local ghostT   = t - gi * 0.06
            if ghostT < 0 then goto skip_ghost end
            local ghostOff = -60 * easeOutQuad(ghostT)
            local ghostA   = alpha * (0.35 - gi * 0.10)
            if ghostA <= 0.01 then goto skip_ghost end

            nvgSave(vg)
            nvgTranslate(vg, curX, p.y + ghostOff)
            nvgScale(vg, curScale * 0.92, curScale * 0.92)
            nvgFontFace(vg, "pixel")
            nvgFontSize(vg, 20)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(ghostA * 255)))
            nvgText(vg, 0, 0, displayText, nil)
            nvgRestore(vg)
            ::skip_ghost::
        end
    end

    -- ── 主体绘制 ─────────────────────────────────────────────────────────────
    nvgSave(vg)
    nvgTranslate(vg, curX, curY)
    nvgScale(vg, curScale, curScale)
    nvgRotate(vg, rotation * math.pi / 180)

    -- 光晕（在文字背后）
    if alpha > 0.3 then
        local glowR = 28 + 14 * (curScale / baseScale)
        local glow = nvgRadialGradient(vg, 0, 0, 0, glowR,
            nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 90)),
            nvgRGBA(p.r, p.g, p.b, 0))
        nvgBeginPath(vg)
        nvgRect(vg, -glowR, -glowR, glowR*2, glowR*2)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
    end

    -- pixel 字体，四层渲染
    nvgFontFace(vg, "pixel")
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 对比色投影（HSV旋转155°）
    nvgFillColor(vg, shadowColor(p.r, p.g, p.b, math.floor(alpha * 210)))
    nvgText(vg, 2, 3, displayText, nil)

    -- 近距内描（同色系略暗，增加立体感）
    nvgFillColor(vg, nvgRGBA(
        math.floor(p.r * 0.65),
        math.floor(p.g * 0.65),
        math.floor(p.b * 0.65),
        math.floor(alpha * 160)))
    nvgText(vg, 1, 1.5, displayText, nil)

    -- 主色
    nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 255)))
    nvgText(vg, 0, 0, displayText, nil)

    -- 白色高光（左上角，浅色背景下减弱）
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 90)))
    nvgText(vg, -1, -1.5, displayText, nil)

    nvgRestore(vg)
end

function M.drawPopups()
    for _, p in ipairs(scorePopups) do
        drawOnePopup(p)
    end
end

-- ============================================================================
-- 融合特效 (Fuse Effects) — 不变
-- ============================================================================

local fuseEffects = {}

function M.spawnFuseEffect(x, y, label)
    local particles = {}
    for i = 1, 24 do
        local angle = math.random() * math.pi * 2
        local speed = 30 + math.random() * 80
        local life  = 0.5 + math.random() * 0.8
        particles[i] = {
            x = 0, y = 0,
            vx = math.cos(angle)*speed, vy = math.sin(angle)*speed,
            life = life, maxLife = life,
            size = 2 + math.random() * 4,
            hue  = math.random() * 60 + 30,
        }
    end
    fuseEffects[#fuseEffects + 1] = {
        x = x, y = y,
        timer = 0, duration = 1.8,
        particles = particles,
        label = label,
        ringScale = 0,
    }
end

local function hueToRgb(h)
    h = h % 360
    local c = 1.0
    local x = c * (1 - math.abs((h/60)%2 - 1))
    local m = 0
    local r, g, b = 0, 0, 0
    if h < 60 then r,g,b=c,x,0 elseif h < 120 then r,g,b=x,c,0
    elseif h < 180 then r,g,b=0,c,x elseif h < 240 then r,g,b=0,x,c
    elseif h < 300 then r,g,b=x,0,c else r,g,b=c,0,x end
    return math.floor((r+m)*255), math.floor((g+m)*255), math.floor((b+m)*255)
end

local function updateFuseEffects(dt)
    for i = #fuseEffects, 1, -1 do
        local fx = fuseEffects[i]
        fx.timer     = fx.timer + dt
        fx.ringScale = math.min(1.0, fx.timer / 0.3)
        for _, p in ipairs(fx.particles) do
            p.x = p.x + p.vx * dt; p.y = p.y + p.vy * dt
            p.vy = p.vy + 20*dt;   p.life = p.life - dt
        end
        if fx.timer >= fx.duration then table.remove(fuseEffects, i) end
    end
end

function M.drawFuseEffects()
    for _, fx in ipairs(fuseEffects) do
        local progress = fx.timer / fx.duration
        local alpha    = progress < 0.7 and 1.0 or (1.0 - (progress-0.7)/0.3)
        nvgSave(vg)
        nvgTranslate(vg, fx.x, fx.y)

        local ringR = fx.ringScale * 40
        if ringR > 0 then
            nvgBeginPath(vg); nvgCircle(vg, 0, 0, ringR)
            nvgStrokeColor(vg, nvgRGBA(255,215,0, math.floor(alpha*180*(1-fx.ringScale*0.3))))
            nvgStrokeWidth(vg, 2.5*(1-progress*0.5)); nvgStroke(vg)
            local glow = nvgRadialGradient(vg,0,0,0,ringR*0.8,
                nvgRGBA(255,230,100,math.floor(alpha*60)),nvgRGBA(255,200,50,0))
            nvgBeginPath(vg); nvgCircle(vg,0,0,ringR*0.8)
            nvgFillPaint(vg,glow); nvgFill(vg)
        end

        for _, p in ipairs(fx.particles) do
            if p.life > 0 then
                local pa = (p.life/p.maxLife)*alpha
                local r,g,b = hueToRgb(p.hue)
                nvgBeginPath(vg); nvgCircle(vg,p.x,p.y,p.size*pa)
                nvgFillColor(vg,nvgRGBA(r,g,b,math.floor(pa*220))); nvgFill(vg)
            end
        end

        if fx.label and alpha > 0.1 then
            local labelY = -50 * fx.ringScale
            nvgFontFace(vg,"sans"); nvgFontSize(vg,14)
            nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(vg,nvgRGBA(255,240,180,math.floor(alpha*240)))
            nvgText(vg,0,labelY,fx.label,nil)
        end
        nvgRestore(vg)
    end
end

-- ============================================================================
-- 对手融合动画 — 不变
-- ============================================================================

local opponentFuseAnim = {}

function M.setOpponentFuseAnim(anim) opponentFuseAnim = anim end
function M.getOpponentFuseAnim()    return opponentFuseAnim end

local function updateOpponentFuseAnim(dt)
    if opponentFuseAnim.phase == "active" then
        opponentFuseAnim.timer = opponentFuseAnim.timer + dt
        if opponentFuseAnim.timer >= opponentFuseAnim.duration then
            opponentFuseAnim.phase = "done"
        end
    end
end

function M.drawOpponentFuseAnim()
    if opponentFuseAnim.phase ~= "active" then return end
    local progress = opponentFuseAnim.timer / opponentFuseAnim.duration
    local alpha    = progress < 0.7 and math.min(1, progress/0.2)
                     or (1.0 - (progress-0.7)/0.3)
    local cx, cy   = logicalW/2, 45

    nvgSave(vg)
    for i = 1, opponentFuseAnim.count do
        local offsetX    = (i - (opponentFuseAnim.count+1)/2) * 50
        local pulseScale = 1.0 + 0.2*math.sin(progress*math.pi*4+i)
        local glow = nvgRadialGradient(vg,cx+offsetX,cy,0,25*pulseScale,
            nvgRGBA(200,150,255,math.floor(alpha*150)),nvgRGBA(150,100,200,0))
        nvgBeginPath(vg); nvgCircle(vg,cx+offsetX,cy,25*pulseScale)
        nvgFillPaint(vg,glow); nvgFill(vg)
        nvgBeginPath(vg); nvgRoundedRect(vg,cx+offsetX-15,cy-20,30,40,4)
        nvgStrokeColor(vg,nvgRGBA(200,150,255,math.floor(alpha*120)))
        nvgStrokeWidth(vg,1.5); nvgStroke(vg)
        nvgFontFace(vg,"sans"); nvgFontSize(vg,16)
        nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
        nvgFillColor(vg,nvgRGBA(200,150,255,math.floor(alpha*180)))
        nvgText(vg,cx+offsetX,cy,"?",nil)
    end
    nvgFontFace(vg,"sans"); nvgFontSize(vg,11)
    nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_TOP)
    nvgFillColor(vg,nvgRGBA(200,150,255,math.floor(alpha*200)))
    nvgText(vg,cx,cy+30,"对手融合了 "..opponentFuseAnim.count.." 组...",nil)
    nvgRestore(vg)
end

-- ============================================================================
-- 阶段过渡 — 不变
-- ============================================================================

local phaseTrans = { text="", timer=0, duration=1.2, r=180, g=120, b=255 }

function M.showTransition(text, r, g, b)
    phaseTrans.text  = text
    phaseTrans.timer = phaseTrans.duration
    phaseTrans.r     = r or 180
    phaseTrans.g     = g or 120
    phaseTrans.b     = b or 255
end

local function updateTransition(dt)
    if phaseTrans.timer > 0 then phaseTrans.timer = phaseTrans.timer - dt end
end

function M.drawTransition()
    if phaseTrans.timer <= 0 then return end
    local progress = 1.0 - phaseTrans.timer / phaseTrans.duration
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

    local tr, tg, tb = phaseTrans.r, phaseTrans.g, phaseTrans.b
    local cx, cy = logicalW / 2, logicalH / 2

    nvgSave(vg)
    nvgTranslate(vg, cx, cy); nvgScale(vg, scale, scale)
    nvgFontFace(vg, "bold"); nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 对比色投影（HSV旋转155°）
    nvgFillColor(vg, shadowColor(tr, tg, tb, math.floor(alpha * 210)))
    nvgText(vg, 2.5, 3.5, phaseTrans.text, nil)

    -- 近距内描（同色系略暗，增加立体感）
    nvgFillColor(vg, nvgRGBA(
        math.floor(tr * 0.65), math.floor(tg * 0.65), math.floor(tb * 0.65),
        math.floor(alpha * 160)))
    nvgText(vg, 1, 1.5, phaseTrans.text, nil)

    -- 主色
    nvgFillColor(vg, nvgRGBA(tr, tg, tb, math.floor(alpha * 255)))
    nvgText(vg, 0, 0, phaseTrans.text, nil)

    -- 白色高光
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 85)))
    nvgText(vg, -1, -1.5, phaseTrans.text, nil)

    nvgRestore(vg)
end

-- ============================================================================
-- 补牌特效 (Reshuffle Effect) — 不变
-- ============================================================================

local reshuffleCards = {}
local deckGlow = { active=false, timer=0, duration=0.8, intensity=0 }

function M.triggerReshuffle(cardCount)
    cardCount   = cardCount or 8
    local count = math.min(cardCount, 14)
    M.spawnBanner("补牌！", 120, 200, 255, 32, 2.0)
    M.triggerShake(3, 0.25, 30)
    -- 与 drawDeckAndDiscard 卡背堆位置对齐
    local sx = logicalW - 36; local sy = 180   -- 弃牌堆中心
    local tx = logicalW - 36; local ty = 80    -- 牌库堆中心
    for i = 1, count do
        local delay    = (i-1)*0.04 + math.random()*0.03
        local duration = 0.45 + math.random()*0.25
        reshuffleCards[#reshuffleCards+1] = {
            sx = sx+(math.random()-0.5)*20, sy = sy+(math.random()-0.5)*14,
            tx = tx+(math.random()-0.5)*8,  ty = ty+(math.random()-0.5)*8,
            arcOffX = -30-math.random()*50, arcOffY = -20-math.random()*30,
            delay=delay, duration=duration, timer=-delay,
            hue = 200+math.random()*60, arrived=false,
        }
    end
    local lastArrival = (count-1)*0.04 + 0.55
    deckGlow.active   = false
    deckGlow._pending = lastArrival
    deckGlow._pendingT = 0
end

function M.getDeckGlowState()
    if not deckGlow.active then return 0 end
    local t = deckGlow.timer / deckGlow.duration
    return math.sin(t*math.pi) * deckGlow.intensity
end

local function updateReshuffle(dt)
    if deckGlow._pending and deckGlow._pending > 0 then
        deckGlow._pendingT = deckGlow._pendingT + dt
        if deckGlow._pendingT >= deckGlow._pending then
            deckGlow.active = true; deckGlow.timer = 0
            deckGlow.intensity = 1.0; deckGlow._pending = nil
        end
    end
    if deckGlow.active then
        deckGlow.timer = deckGlow.timer + dt
        if deckGlow.timer >= deckGlow.duration then deckGlow.active = false end
    end
    for i = #reshuffleCards, 1, -1 do
        local p = reshuffleCards[i]
        p.timer = p.timer + dt
        if p.timer >= p.duration then table.remove(reshuffleCards, i) end
    end
end

function M.drawReshuffleEffect()
    if #reshuffleCards == 0 then return end
    for _, p in ipairs(reshuffleCards) do
        if p.timer <= 0 then goto skip_rc end
        local t   = math.min(1.0, p.timer/p.duration)
        local mx  = (p.sx+p.tx)/2 + p.arcOffX
        local my  = (p.sy+p.ty)/2 + p.arcOffY
        local omt = 1-t
        local px  = omt*omt*p.sx + 2*omt*t*mx + t*t*p.tx
        local py  = omt*omt*p.sy + 2*omt*t*my + t*t*p.ty
        local alpha = t<0.15 and t/0.15 or (t>0.75 and (1-t)/0.25 or 1.0)
        alpha = math.max(0, math.min(1, alpha))
        local scale = 0.38*(1.0-t*0.25)
        local r,g,b = hueToRgb(p.hue + t*30)
        local tanX = 2*(1-t)*(mx-p.sx) + 2*t*(p.tx-mx)
        local tanY = 2*(1-t)*(my-p.sy) + 2*t*(p.ty-my)
        local angle = math.atan(tanY,tanX)
        local cw,ch,cr = 90*scale, 130*scale, 8*scale

        nvgSave(vg)
        nvgTranslate(vg,px,py); nvgRotate(vg,angle)
        local glow = nvgRadialGradient(vg,0,0,0,cw*1.4,
            nvgRGBA(r,g,b,math.floor(alpha*60)),nvgRGBA(r,g,b,0))
        nvgBeginPath(vg); nvgRect(vg,-cw*1.4,-ch*1.4,cw*2.8,ch*2.8)
        nvgFillPaint(vg,glow); nvgFill(vg)
        nvgGlobalAlpha(vg, alpha)
        nvgScale(vg, scale, scale)
        -- Card 相关依赖已移除：用简单圆角矩形替代
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -cw*0.5, -ch*0.5, cw, ch, cr)
        nvgFillColor(vg, nvgRGBAf(r/255, g/255, b/255, 0.6))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBAf(r/255, g/255, b/255, 0.9))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        nvgRestore(vg)
        ::skip_rc::
    end
end

-- ============================================================================
-- 音乐牌特效: 波形圆圈 + 音符粒子
-- ============================================================================

local musicCardEffects = {}

-- 矢量音符绘制：noteType 0=四分音符, 1=八分音符, 2=十六分音符
local function drawNoteVector(x, y, size, noteType, r, g, b, alpha)
    local a    = math.floor(alpha * 255)
    local sa   = math.floor(alpha * 85)
    local hw   = size * 0.26   -- 音符头半宽（修长）
    local hh   = size * 0.17   -- 音符头半高（扁平椭圆）
    local sw   = size * 0.052  -- 杆宽（纤细）
    local sh   = size * 1.10   -- 杆高（长杆）
    local tilt = -0.52         -- 音符头倾斜角度

    nvgSave(vg)
    nvgTranslate(vg, x, y)

    -- 阴影
    nvgSave(vg)
    nvgTranslate(vg, 1.2, 1.8)
    nvgRotate(vg, tilt)
    nvgBeginPath(vg)
    nvgEllipse(vg, 0, 0, hw, hh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, sa))
    nvgFill(vg)
    nvgRestore(vg)

    -- 音符头（倾斜椭圆）
    nvgSave(vg)
    nvgRotate(vg, tilt)
    nvgBeginPath(vg)
    nvgEllipse(vg, 0, 0, hw, hh)
    nvgFillColor(vg, nvgRGBA(r, g, b, a))
    nvgFill(vg)
    nvgRestore(vg)

    -- 竖杆
    local stemX = hw * 0.90
    nvgBeginPath(vg)
    nvgRect(vg, stemX - sw * 0.5, -sh, sw, sh)
    nvgFillColor(vg, nvgRGBA(r, g, b, a))
    nvgFill(vg)

    -- 旗子（bezier 曲线）
    local numFlags = noteType == 2 and 2 or (noteType == 1 and 1 or 0)
    if numFlags > 0 then
        nvgLineCap(vg, NVG_ROUND)
        nvgStrokeColor(vg, nvgRGBA(r, g, b, a))
        nvgStrokeWidth(vg, sw * 0.88)
        for fi = 0, numFlags - 1 do
            local fy0 = -sh + fi * size * 0.28
            nvgBeginPath(vg)
            nvgMoveTo(vg, stemX + sw * 0.3, fy0)
            nvgBezierTo(vg,
                stemX + size * 0.38, fy0 + size * 0.11,
                stemX + size * 0.30, fy0 + size * 0.32,
                stemX + size * 0.04, fy0 + size * 0.44)
            nvgStroke(vg)
        end
    end

    nvgRestore(vg)
end

--- 在指定位置生成音乐牌特效（波形圆圈 + 浮动音符）
---@param cx number  卡牌中心 X（逻辑坐标）
---@param cy number  卡牌中心 Y（逻辑坐标）
---@param r number   乐队主色 R (0-255)
---@param g number   乐队主色 G
---@param b number   乐队主色 B
---@param dur number 持续时间（秒，默认 8.0）
function M.spawnMusicCardEffect(cx, cy, r, g, b, dur)
    dur = dur or 8.0
    local notes = {}
    for i = 1, 10 do
        notes[i] = {
            x        = cx + (math.random() - 0.5) * 30,
            y        = cy + (math.random() - 0.5) * 20,
            vx       = (math.random() - 0.5) * 24,
            vy       = -(22 + math.random() * 16),
            noteType = math.random(0, 2),
            delay    = math.random() * 2.5,
            life     = 0,
            maxLife  = 2.0 + math.random() * 1.0,
            size     = 13 + math.random() * 8,
        }
    end
    musicCardEffects[#musicCardEffects + 1] = {
        cx    = cx, cy = cy,
        r     = r,  g  = g,  b = b,
        timer = 0,  dur = dur,
        notes = notes,
    }
end

local function updateMusicCardEffects(dt)
    for i = #musicCardEffects, 1, -1 do
        local e = musicCardEffects[i]
        e.timer = e.timer + dt
        if e.timer >= e.dur then
            table.remove(musicCardEffects, i)
        else
            for _, n in ipairs(e.notes) do
                n.delay = n.delay - dt
                if n.delay <= 0 then
                    n.life = n.life + dt
                    n.x    = n.x + n.vx * dt
                    n.y    = n.y + n.vy * dt
                    n.vx   = n.vx + math.sin(n.life * 3.1 + n.size) * 12 * dt
                    n.vy   = n.vy + 6 * dt  -- 轻微重力
                    if n.life >= n.maxLife then
                        -- 重置粒子（重新从卡牌附近冒出）
                        n.x        = e.cx + (math.random() - 0.5) * 30
                        n.y        = e.cy + (math.random() - 0.5) * 20
                        n.vx       = (math.random() - 0.5) * 24
                        n.vy       = -(22 + math.random() * 16)
                        n.noteType = math.random(0, 2)
                        n.delay    = math.random() * 1.5
                        n.life     = 0
                        n.maxLife  = 2.0 + math.random() * 1.0
                        n.size     = 13 + math.random() * 8
                    end
                end
            end
        end
    end
end

function M.drawMusicCardEffects()
    if #musicCardEffects == 0 then return end

    local RING_CYCLE  = 2.2   -- 秒/圈，环从中心向外扩散一个周期
    local MIN_RADIUS  = 22
    local MAX_RADIUS  = 105

    for _, e in ipairs(musicCardEffects) do
        -- 全局淡入/淡出
        local gFade = 1.0
        if e.timer < 0.4 then
            gFade = e.timer / 0.4
        elseif e.dur - e.timer < 0.6 then
            gFade = (e.dur - e.timer) / 0.6
        end
        gFade = math.max(0, math.min(1, gFade))

        local cx, cy = e.cx, e.cy

        -- ── 核心辉光 ──────────────────────────────────────────────
        local coreR = nvgRadialGradient(vg, cx, cy, 0, 30,
            nvgRGBA(e.r, e.g, e.b, math.floor(gFade * 60)),
            nvgRGBA(e.r, e.g, e.b, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, 30)
        nvgFillPaint(vg, coreR)
        nvgFill(vg)

        -- ── 3 道波形圆圈（相位各差 1/3 周期） ────────────────────
        for ri = 1, 3 do
            local phaseOff = (ri - 1) / 3.0 * RING_CYCLE
            local cycleT   = (gameTime + phaseOff) % RING_CYCLE
            local t        = cycleT / RING_CYCLE   -- 0..1
            local radius   = MIN_RADIUS + t * (MAX_RADIUS - MIN_RADIUS)

            -- 环的透明度：快速淡入，保持，淡出
            local rAlpha
            if t < 0.15 then
                rAlpha = t / 0.15
            elseif t > 0.70 then
                rAlpha = (1.0 - t) / 0.30
            else
                rAlpha = 1.0
            end
            rAlpha = rAlpha * gFade

            if rAlpha > 0.01 then
                -- 波形变形：在圆周上叠加 2 组正弦，模拟声波
                local segments = 40
                nvgBeginPath(vg)
                for si = 0, segments do
                    local angle = si / segments * math.pi * 2
                    local wave  = math.sin(angle * 6 + gameTime * 5.5) * 5.5
                               + math.sin(angle * 3 + gameTime * 3.0) * 2.5
                    local r2 = radius + wave
                    local px = cx + math.cos(angle) * r2
                    local py = cy + math.sin(angle) * r2
                    if si == 0 then nvgMoveTo(vg, px, py)
                    else            nvgLineTo(vg, px, py) end
                end
                nvgClosePath(vg)
                nvgStrokeWidth(vg, math.max(0.6, 2.0 - t * 1.2))
                nvgStrokeColor(vg, nvgRGBA(e.r, e.g, e.b, math.floor(rAlpha * 210)))
                nvgStroke(vg)
            end
        end

        -- ── 音符粒子（矢量绘制） ──────────────────────────────────
        for _, n in ipairs(e.notes) do
            if n.delay <= 0 and n.life > 0 then
                local lt     = n.life / n.maxLife
                local nAlpha = gFade * math.sin(lt * math.pi)
                if nAlpha > 0.01 then
                    local sc = 1.0 + math.sin(n.life * 4.5) * 0.08
                    nvgSave(vg)
                    nvgScale(vg, sc, sc)
                    drawNoteVector(n.x / sc, n.y / sc, n.size, n.noteType, e.r, e.g, e.b, nAlpha)
                    nvgRestore(vg)
                end
            end
        end
    end
end

-- ============================================================================
-- 子弹命中特效 (Hit Flash)
-- 扩散环 + 径向 spark 线段 + 白色闪点
-- ============================================================================

local hitEffects = {}

--- 生成命中特效
---@param x number 命中位置 X
---@param y number 命中位置 Y
---@param r number 颜色 R (0-255)
---@param g number 颜色 G
---@param b number 颜色 B
---@param scale number|nil 缩放倍率（默认 1.0）
function M.spawnHit(x, y, r, g, b, scale)
    if not x or not y then return end
    scale = scale or 1.0
    local sparkCount = math.random(5, 7)
    local sparks = {}
    for i = 1, sparkCount do
        local angle = (i - 1) * (2 * math.pi / sparkCount) + (math.random() - 0.5) * 0.6
        local len = (12 + math.random() * 10) * scale
        local spd = (120 + math.random() * 80) * scale
        sparks[i] = { angle = angle, len = len, dist = 0, speed = spd }
    end
    local h = hitPool_:get()
    h.x = x; h.y = y
    h.r = r; h.g = g; h.b = b
    h.scale = scale
    h.age = 0
    h.duration = 0.25
    h.ringRadius = 4 * scale
    h.ringMaxRadius = 28 * scale
    h.sparks = sparks
    h.flashRadius = 6 * scale
    hitEffects[#hitEffects + 1] = h
end

local function updateHitEffects(dt)
    for i = #hitEffects, 1, -1 do
        local h = hitEffects[i]
        h.age = h.age + dt
        if h.age >= h.duration then
            hitPool_:release(h)
            table.remove(hitEffects, i)
        else
            local t = h.age / h.duration  -- 0..1
            -- 环扩张 (ease-out)
            h.ringRadius = lerp(4 * h.scale, h.ringMaxRadius, easeOutQuad(t))
            -- spark 向外移动
            for _, sp in ipairs(h.sparks) do
                sp.dist = sp.dist + sp.speed * dt
                sp.len = sp.len * (1 - dt * 6)  -- 快速缩短
                if sp.len < 1 then sp.len = 1 end
            end
        end
    end
end

function M.drawHitEffects()
    for _, h in ipairs(hitEffects) do
        if not h.x then goto continue_hit end
        local t = h.age / h.duration
        local alpha = 1.0 - easeInQuad(t)  -- 渐隐

        -- 1. 白色闪点（前 30% 时间内）
        if t < 0.3 then
            local fa = 1.0 - (t / 0.3)
            local fr = h.flashRadius * (0.6 + 0.4 * (1 - fa))
            nvgBeginPath(vg)
            nvgCircle(vg, h.x, h.y, fr)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(fa * 220)))
            nvgFill(vg)
        end

        -- 2. 扩散环
        nvgBeginPath(vg)
        nvgCircle(vg, h.x, h.y, h.ringRadius)
        nvgStrokeColor(vg, nvgRGBA(h.r, h.g, h.b, math.floor(alpha * 200)))
        nvgStrokeWidth(vg, math.max(1.5, 3.5 * (1 - t)))
        nvgStroke(vg)

        -- 3. 径向 spark 线段
        nvgLineCap(vg, NVG_ROUND)
        for _, sp in ipairs(h.sparks) do
            local sx = h.x + math.cos(sp.angle) * sp.dist
            local sy = h.y + math.sin(sp.angle) * sp.dist
            local ex = h.x + math.cos(sp.angle) * (sp.dist + sp.len)
            local ey = h.y + math.sin(sp.angle) * (sp.dist + sp.len)
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx, sy)
            nvgLineTo(vg, ex, ey)
            nvgStrokeColor(vg, nvgRGBA(h.r, h.g, h.b, math.floor(alpha * 180)))
            nvgStrokeWidth(vg, math.max(1.5, 3.0 * (1 - t)))
            nvgStroke(vg)
        end
        ::continue_hit::
    end
end

-- ============================================================================
-- 擦弹火花 (Graze Spark)
-- 子弹掠过玩家时，垂直于弹道方向喷出短线条
-- ============================================================================

local grazeSparks = {}

--- 生成擦弹火花
---@param bx number 子弹 X
---@param by number 子弹 Y
---@param px number 玩家 X
---@param py number 玩家 Y
function M.spawnGraze(bx, by, px, py)
    -- 从子弹到玩家的方向，取垂直方向作为喷射轴
    local dx, dy = px - bx, py - by
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.01 then return end
    -- 垂直方向（两侧）
    local perpX, perpY = -dy / dist, dx / dist
    local count = math.random(3, 5)
    -- 火花生成在子弹与玩家之间靠近子弹侧
    local spawnX = bx + dx * 0.3
    local spawnY = by + dy * 0.3
    for i = 1, count do
        local side = (i % 2 == 0) and 1 or -1
        local spread = (math.random() - 0.5) * 0.8  -- 角度偏移
        local dirX = perpX * side + dx / dist * spread
        local dirY = perpY * side + dy / dist * spread
        local spd = 80 + math.random() * 60
        local s = sparkPool_:get()
        s.x = spawnX + (math.random() - 0.5) * 4
        s.y = spawnY + (math.random() - 0.5) * 4
        s.vx = dirX * spd
        s.vy = dirY * spd
        s.len = 6 + math.random() * 5
        s.age = 0
        s.duration = 0.18
        grazeSparks[#grazeSparks + 1] = s
    end
end

local function updateGrazeSparks(dt)
    for i = #grazeSparks, 1, -1 do
        local s = grazeSparks[i]
        s.age = s.age + dt
        if s.age >= s.duration then
            sparkPool_:release(s)
            table.remove(grazeSparks, i)
        else
            s.x = s.x + s.vx * dt
            s.y = s.y + s.vy * dt
            s.len = s.len * (1 - dt * 8)
        end
    end
end

function M.drawGrazeSparks()
    nvgLineCap(vg, NVG_ROUND)
    for _, s in ipairs(grazeSparks) do
        local t = s.age / s.duration
        local alpha = 1.0 - t
        local nx, ny = s.vx, s.vy
        local d = math.sqrt(nx * nx + ny * ny)
        if d > 0.01 then
            nx, ny = nx / d, ny / d
        end
        local ex = s.x + nx * s.len
        local ey = s.y + ny * s.len
        nvgBeginPath(vg)
        nvgMoveTo(vg, s.x, s.y)
        nvgLineTo(vg, ex, ey)
        nvgStrokeColor(vg, nvgRGBA(180, 240, 255, math.floor(alpha * 220)))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)
    end
end

-- ============================================================================
-- 子弹时间全屏闪光 (Bullet Time Flash)
-- ============================================================================

local btFlash = { alpha = 0, active = false }

--- 触发子弹时间闪光
function M.triggerBTFlash()
    btFlash.alpha = 0.35
    btFlash.active = true
end

local function updateBTFlash(dt)
    if btFlash.active then
        btFlash.alpha = btFlash.alpha - dt * 2.5  -- ~0.14s 消退
        if btFlash.alpha <= 0 then
            btFlash.alpha = 0
            btFlash.active = false
        end
    end
end

--- 绘制全屏闪光（应在 UI 层之前、shake 之外调用）
function M.drawBTFlash()
    if btFlash.active then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logicalW, logicalH)
        nvgFillColor(vg, nvgRGBA(200, 240, 255, math.floor(btFlash.alpha * 255)))
        nvgFill(vg)
    end
end

-- ============================================================================
-- 回血特效 (Heal Rise)
-- 角色脚底向上飘起的绿色线条
-- ============================================================================

local healEffects = {}

--- 生成回血特效（跟随角色移动）
---@param target table 需要有 x, y 字段的对象（如 Player.getData()）
---@param radius number|nil 角色半径，决定线条散布范围（默认 20）
function M.spawnHeal(target, radius)
    radius = radius or 20
    local count = math.random(5, 7)
    for i = 1, count do
        local offsetX = (math.random() - 0.5) * radius * 1.8
        local len = 10 + math.random() * 8
        local speed = 60 + math.random() * 40
        local delay = (i - 1) * 0.04 + math.random() * 0.03  -- 错时生成
        local h = healPool_:get()
        h.target = target
        h.offsetX = offsetX
        h.riseY = 0
        h.startOffsetY = radius * 0.4
        h.len = len
        h.speed = speed
        h.drift = (math.random() - 0.5) * 15
        h.age = -delay
        h.duration = 0.55
        healEffects[#healEffects + 1] = h
    end
end

local function updateHealEffects(dt)
    for i = #healEffects, 1, -1 do
        local h = healEffects[i]
        h.age = h.age + dt
        if h.age >= h.duration then
            healPool_:release(h)
            table.remove(healEffects, i)
        elseif h.age > 0 then
            h.riseY = h.riseY + h.speed * dt
            h.offsetX = h.offsetX + h.drift * dt
        end
    end
end

function M.drawHealEffects()
    nvgLineCap(vg, NVG_ROUND)
    for _, h in ipairs(healEffects) do
        if h.age > 0 then
            local t = h.age / h.duration
            local alpha
            if t < 0.2 then
                alpha = t / 0.2
            else
                alpha = 1.0 - ((t - 0.2) / 0.8)
            end
            local curLen = h.len * (1.0 - t * 0.6)

            -- 基于目标实时位置
            local sx = h.target.x + h.offsetX
            local sy = h.target.y + h.startOffsetY - h.riseY
            local ey = sy - curLen

            nvgBeginPath(vg)
            nvgMoveTo(vg, sx, sy)
            nvgLineTo(vg, sx, ey)
            nvgStrokeColor(vg, nvgRGBA(80, 220, 100, math.floor(alpha * 200)))
            nvgStrokeWidth(vg, 3.0)
            nvgStroke(vg)
        end
    end
end

-- ============================================================================
-- AOE 爆炸特效 (Mortar Explosion)
-- 多边形扩散环 + 碎片粒子 + 地面焦痕
-- ============================================================================

local aoeExplosions = {}
local aoePool_ = Pool.new(8)

--- 生成 AOE 爆炸特效
---@param x number 爆炸中心 X
---@param y number 爆炸中心 Y
---@param radius number AOE 半径（用于视觉范围指示）
---@param damage number 伤害值（仅用于 popup 显示）
function M.spawnAOE(x, y, radius, damage)
    radius = radius or 60
    -- 余烬粒子（圆点，无多边形）
    local fragCount = math.random(10, 15)
    local frags = {}
    for i = 1, fragCount do
        local angle = (i - 1) / fragCount * math.pi * 2 + (math.random() - 0.5) * 0.5
        local spd = 100 + math.random() * 150
        frags[i] = {
            x = 0, y = 0,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            size = 2.5 + math.random() * 3.5,  -- 圆点半径
        }
    end
    -- 放射爆裂线
    local burstCount = math.random(8, 11)
    local bursts = {}
    for i = 1, burstCount do
        local angle = (i - 1) / burstCount * math.pi * 2 + (math.random() - 0.5) * 0.3
        bursts[i] = {
            angle = angle,
            len = 20 + math.random() * 25,   -- 线段长度
            dist = 8 + math.random() * 6,    -- 初始离中心距离
            spd = 180 + math.random() * 100, -- 向外扩散速度
        }
    end
    local e = aoePool_:get()
    e.x = x; e.y = y
    e.radius = radius
    e.damage = damage or 1
    e.age = 0
    e.duration = 0.5
    e.frags = frags
    e.bursts = bursts
    e.ringRadius = 0
    e.angleOff = math.random() * math.pi * 2  -- 虚线环旋转偏移
    aoeExplosions[#aoeExplosions + 1] = e
end

local function updateAOEExplosions(dt)
    for i = #aoeExplosions, 1, -1 do
        local e = aoeExplosions[i]
        e.age = e.age + dt
        if e.age >= e.duration then
            aoePool_:release(e)
            table.remove(aoeExplosions, i)
        else
            local t = e.age / e.duration
            -- 冲击波环扩张
            e.ringRadius = e.radius * easeOutQuad(math.min(1, t * 2.2))
            -- 余烬运动（重力 + 阻力）
            for _, f in ipairs(e.frags) do
                f.x = f.x + f.vx * dt
                f.y = f.y + f.vy * dt
                f.vy = f.vy + 260 * dt  -- 重力
                f.vx = f.vx * 0.94
                f.vy = f.vy * 0.97
            end
            -- 爆裂线向外扩张
            for _, b in ipairs(e.bursts) do
                b.dist = b.dist + b.spd * dt
                b.spd = b.spd * 0.92  -- 快速减速
            end
        end
    end
end

function M.drawAOEExplosions()
    for _, e in ipairs(aoeExplosions) do
        local t = e.age / e.duration
        local alpha = 1.0 - easeInQuad(t)

        -- 1. 残留焦痕（虚线弧段环，慢淡出 — 与预警圈风格统一）
        local scorchAlpha = math.max(0, 1.0 - t * 0.7)
        if scorchAlpha > 0.02 then
            local scorchR = e.radius * 0.85
            local segments = 10
            local arcPer = (math.pi * 2) / segments
            local gapRatio = 0.3
            nvgLineCap(vg, NVG_ROUND)
            nvgStrokeColor(vg, nvgRGBA(60, 30, 5, math.floor(scorchAlpha * 90)))
            nvgStrokeWidth(vg, 2.5)
            for si = 0, segments - 1 do
                local a0 = e.angleOff + si * arcPer
                local a1 = a0 + arcPer * (1.0 - gapRatio)
                nvgBeginPath(vg)
                nvgArc(vg, e.x, e.y, scorchR, a0, a1, NVG_CW)
                nvgStroke(vg)
            end
        end

        -- 2. 冲击波虚线环（向外扩张，虚线弧段 — 核心视觉）
        if e.ringRadius > 4 then
            local ringAlpha = alpha * 0.95
            local segments = 10
            local arcPer = (math.pi * 2) / segments
            local gapRatio = 0.35
            nvgLineCap(vg, NVG_ROUND)
            nvgStrokeColor(vg, nvgRGBA(255, 180, 50, math.floor(ringAlpha * 220)))
            nvgStrokeWidth(vg, math.max(1.5, 3.5 * (1 - t)))
            for si = 0, segments - 1 do
                local a0 = e.angleOff + si * arcPer + t * 0.8  -- 轻微旋转
                local a1 = a0 + arcPer * (1.0 - gapRatio)
                nvgBeginPath(vg)
                nvgArc(vg, e.x, e.y, e.ringRadius, a0, a1, NVG_CW)
                nvgStroke(vg)
            end
        end

        -- 3. 放射爆裂线（从中心射出的短线段，星爆感）
        if alpha > 0.05 then
            local burstAlpha = alpha * 0.9
            nvgLineCap(vg, NVG_ROUND)
            nvgStrokeColor(vg, nvgRGBA(255, 210, 80, math.floor(burstAlpha * 200)))
            nvgStrokeWidth(vg, math.max(1.5, 3.0 * (1 - t * 0.7)))
            for _, b in ipairs(e.bursts) do
                local cos_a = math.cos(b.angle)
                local sin_a = math.sin(b.angle)
                local innerD = b.dist
                local outerD = b.dist + b.len * math.max(0.2, 1.0 - t * 1.5)
                nvgBeginPath(vg)
                nvgMoveTo(vg, e.x + cos_a * innerD, e.y + sin_a * innerD)
                nvgLineTo(vg, e.x + cos_a * outerD, e.y + sin_a * outerD)
                nvgStroke(vg)
            end
        end

        -- 4. 中心闪光（双层：白热核心 + 橙色光晕，前 30%）
        if t < 0.3 then
            local flashT = t / 0.3
            local flashA = 1.0 - easeInQuad(flashT)
            -- 外层橙色光晕
            local haloR = 18 + 30 * flashT
            local halo = nvgRadialGradient(vg, e.x, e.y, 0, haloR,
                nvgRGBA(255, 140, 30, math.floor(flashA * 120)),
                nvgRGBA(255, 80, 10, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, haloR)
            nvgFillPaint(vg, halo)
            nvgFill(vg)
            -- 内层白热核心
            local coreR = 8 + 10 * flashT
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, coreR)
            nvgFillColor(vg, nvgRGBA(255, 245, 220, math.floor(flashA * 240)))
            nvgFill(vg)
        end

        -- 5. 余烬粒子（双层圆点：外层辉光 + 内层亮核，无描边）
        for _, f in ipairs(e.frags) do
            local fragAlpha = alpha * 0.9
            if fragAlpha < 0.03 then goto skip_frag end
            local fx = e.x + f.x
            local fy = e.y + f.y
            local sz = f.size * math.max(0.3, 1.0 - t * 0.8)
            -- 颜色从白热→亮橙→暗红
            local cr = math.floor(lerp(255, 200, t))
            local cg = math.floor(lerp(200, 50, t))
            local cb = math.floor(lerp(80, 10, t))
            -- 外层辉光（放大 2.2x，低透明度）
            nvgBeginPath(vg)
            nvgCircle(vg, fx, fy, sz * 2.2)
            nvgFillColor(vg, nvgRGBA(cr, cg, cb, math.floor(fragAlpha * 60)))
            nvgFill(vg)
            -- 内层亮核（实际大小，高透明度）
            nvgBeginPath(vg)
            nvgCircle(vg, fx, fy, sz)
            nvgFillColor(vg, nvgRGBA(cr, cg, cb, math.floor(fragAlpha * 220)))
            nvgFill(vg)
            ::skip_frag::
        end

        -- 6. 外圈扩散辉光（径向渐变，柔和收尾）
        if alpha > 0.1 then
            local glowR = e.ringRadius * 1.2
            local glow = nvgRadialGradient(vg, e.x, e.y, e.ringRadius * 0.3, glowR,
                nvgRGBA(255, 100, 20, math.floor(alpha * 35)),
                nvgRGBA(255, 60, 10, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, glowR)
            nvgFillPaint(vg, glow)
            nvgFill(vg)
        end
    end
end

--- 获取活跃 AOE 爆炸列表（供碰撞检测使用）
function M.getActiveAOEs()
    return aoeExplosions
end

-- ============================================================================
-- 统一 update / reset
-- ============================================================================

function M.updateAll(dt)
    updateShake(dt)
    updateBanners(dt)
    updateChips(dt)
    updatePotPulse(dt)
    updatePopups(dt)
    updateFuseEffects(dt)
    updateOpponentFuseAnim(dt)
    updateTransition(dt)
    updateReshuffle(dt)
    updateMusicCardEffects(dt)
    updateHitEffects(dt)
    updateGrazeSparks(dt)
    updateBTFlash(dt)
    updateHealEffects(dt)
    updateAOEExplosions(dt)
end

function M.resetAll()
    shake.intensity = 0; shake.offsetX = 0; shake.offsetY = 0
    actionBanners  = {}
    chipPool_:drain(chipParticles); chipParticles = {}
    potPulse.active = false
    popupPool_:drain(scorePopups); scorePopups = {}
    fuseEffects    = {}
    opponentFuseAnim = {}
    phaseTrans.timer = 0
    reshuffleCards = {}
    deckGlow.active = false
    musicCardEffects = {}
    hitPool_:drain(hitEffects); hitEffects = {}
    sparkPool_:drain(grazeSparks); grazeSparks = {}
    btFlash = { alpha = 0, active = false }
    healPool_:drain(healEffects); healEffects = {}
    aoePool_:drain(aoeExplosions); aoeExplosions = {}
end

return M
