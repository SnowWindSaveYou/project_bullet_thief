# 卡牌视觉特效完整参考

> 本文档包含卡牌渲染管线中所有视觉特效的完整 NanoVG 实现代码。

---

## 目录

1. [渲染变换管线](#1-渲染变换管线)
2. [卡牌阴影](#2-卡牌阴影)
3. [翻牌效果](#3-翻牌效果)
4. [倾斜高光](#4-倾斜高光)
5. [暗淡过渡](#5-暗淡过渡)
6. [全息闪光](#6-全息闪光)
7. [卡背装饰动画](#7-卡背装饰动画)
8. [插入指示线](#8-插入指示线)
9. [查阅遮罩](#9-查阅遮罩)

---

## 1. 渲染变换管线

每张卡牌渲染时的完整变换顺序：

```lua
function drawCard(vg, card, time)
    nvgSave(vg)

    -- 1. 位移到卡牌中心
    nvgTranslate(vg, card.x, card.y)

    -- 2. 旋转（含拖拽惯性）
    nvgRotate(vg, math.rad(card.rotation + (card.dragTilt or 0)))

    -- 3. 翻牌 X 轴缩放（flipProgress 驱动）
    local flipScale = 1.0
    if card.flipping and card.flipProgress > 0 then
        flipScale = math.cos(card.flipProgress * math.pi)
    end

    -- 4. 统一缩放
    nvgScale(vg, math.abs(flipScale) * card.scale, card.scale)

    -- 5. 倾斜视差（skew 模拟 3D）
    if math.abs(card.tiltX) > 0.01 or math.abs(card.tiltY) > 0.01 then
        nvgSkewX(vg, math.rad(card.tiltY * 0.6))
        nvgSkewY(vg, math.rad(card.tiltX * 0.6))
    end

    -- 6. 暗淡透明度（不可用卡牌）
    local dimAlpha = card._dimOpacity or 1.0
    nvgGlobalAlpha(vg, dimAlpha * (card.opacity / 255))

    -- 以下在卡牌局部坐标系绘制 (-W/2, -H/2) 到 (W/2, H/2)
    local hw, hh = CARD_W / 2, CARD_H / 2

    -- 绘制阴影
    drawShadow(vg, hw, hh)

    -- 绘制正面或背面
    local showFace = (not card.flipping) and card.faceUp
    if card.flipping then
        showFace = flipScale < 0  -- 0.5 之后显示正面
    end

    if showFace then
        drawFace(vg, card, hw, hh, time)
    else
        drawBack(vg, card, hw, hh, time)
    end

    -- 绘制倾斜高光
    drawTiltShine(vg, card, hw, hh)

    -- 绘制全息效果（特殊卡牌）
    if card.holoEnabled then
        drawHolographic(vg, card, hw, hh, time)
    end

    nvgRestore(vg)
end
```

---

## 2. 卡牌阴影

使用 `nvgBoxGradient` 创建偏移柔和阴影：

```lua
function drawShadow(vg, hw, hh)
    local cornerR = 8
    local blur = 12
    local offsetX, offsetY = 2, 4

    local shadowPaint = nvgBoxGradient(vg,
        -hw + offsetX, -hh + offsetY,
        hw * 2, hh * 2,
        cornerR, blur,
        nvgRGBA(0, 0, 0, 80),    -- 内色（阴影中心）
        nvgRGBA(0, 0, 0, 0))     -- 外色（渐隐）

    nvgBeginPath(vg)
    nvgRect(vg,
        -hw + offsetX - blur,
        -hh + offsetY - blur,
        hw * 2 + blur * 2,
        hh * 2 + blur * 2)
    nvgFillPaint(vg, shadowPaint)
    nvgFill(vg)
end
```

---

## 3. 翻牌效果

基于 `flipProgress` (0→1) 的 cosine 缩放实现翻牌：

```lua
-- flipProgress 0→0.5: cos(0→π/2) = 1→0  → 背面缩小消失
-- flipProgress 0.5→1: cos(π/2→π) = 0→-1 → 正面从0展开
-- 用 abs(flipScale) 做 X 缩放，符号决定正反面

local flipScale = math.cos(card.flipProgress * math.pi)
local absFlip = math.abs(flipScale)

-- 0.5 附近加一个最小值避免完全消失
local renderScaleX = math.max(0.02, absFlip) * card.scale

-- 在 nvgScale 中应用
nvgScale(vg, renderScaleX, card.scale)

-- 判断显示哪面
if flipScale > 0 then
    drawBack(vg, card)   -- 尚未翻过
else
    drawFace(vg, card)   -- 已翻过来
end
```

---

## 4. 倾斜高光

悬停时基于倾斜方向的径向渐变高光：

```lua
function drawTiltShine(vg, card, hw, hh)
    local tiltMag = math.sqrt(card.tiltX^2 + card.tiltY^2)
    if tiltMag < 0.1 then return end

    local intensity = math.min(1.0, tiltMag / 6)
    local shineX = card.tiltY * 8   -- 高光跟随倾斜方向
    local shineY = card.tiltX * 8

    local shinePaint = nvgRadialGradient(vg,
        shineX, shineY,          -- 中心跟随倾斜
        0,                       -- 内圆半径
        hw * 1.4,                -- 外圆半径
        nvgRGBA(255, 255, 255, math.floor(intensity * 60)),   -- 中心亮度
        nvgRGBA(255, 255, 255, 0))                             -- 边缘消失

    nvgBeginPath(vg)
    -- 用椭圆让高光更自然
    nvgEllipse(vg, shineX, shineY, hw * 1.2, hh * 1.0)
    nvgFillPaint(vg, shinePaint)
    nvgFill(vg)
end
```

---

## 5. 暗淡过渡

不可用卡牌平滑过渡到暗淡状态：

```lua
-- 每帧更新
if card.dimmed then
    card._dimOpacity = card._dimOpacity - 0.15  -- 线性步进
    card._dimOpacity = math.max(0.35, card._dimOpacity)
else
    card._dimOpacity = card._dimOpacity + 0.15
    card._dimOpacity = math.min(1.0, card._dimOpacity)
end

-- 在渲染时
nvgGlobalAlpha(vg, card._dimOpacity)
```

---

## 6. 全息闪光

特殊卡牌的彩虹条纹 + 随机闪点 + 径向发光效果：

```lua
function drawHolographic(vg, card, hw, hh, time)
    local phase = time * 0.8 + (card.holoPhase or 0)
    local tiltMag = math.sqrt(card.tiltX^2 + card.tiltY^2)
    local intensity = 0.3 + tiltMag / 6 * 0.5  -- 倾斜越大越亮

    -- 呼吸效果
    local breathe = 0.85 + 0.15 * math.sin(time * 2.0 + card.holoPhase)

    -- 1) 彩虹条纹（7条斜线渐变）
    local stripeColors = {
        {255, 80, 80},    -- 红
        {255, 160, 40},   -- 橙
        {255, 240, 60},   -- 黄
        {80, 255, 80},    -- 绿
        {60, 200, 255},   -- 蓝
        {140, 80, 255},   -- 靛
        {220, 80, 255},   -- 紫
    }

    nvgSave(vg)
    -- 裁剪到卡牌区域
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, hw*2, hh*2, 8)
    nvgClip(vg)

    -- 旋转条纹方向
    nvgRotate(vg, math.rad(30 + math.sin(phase) * 15))

    local stripeW = hh * 0.5
    for i, col in ipairs(stripeColors) do
        local offset = (i - 4) * stripeW + math.sin(phase + i * 0.3) * stripeW * 0.3
        local alpha = math.floor(intensity * breathe * 35)
        nvgBeginPath(vg)
        nvgRect(vg, offset - stripeW/2, -hh * 2, stripeW, hh * 4)
        nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], alpha))
        nvgFill(vg)
    end
    nvgRestore(vg)

    -- 2) 随机闪点（6个）
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, hw*2, hh*2, 8)
    nvgClip(vg)

    for si = 1, 6 do
        local seed = card.holoPhase + si * 17.3
        local sx = math.sin(seed * 3.7 + time * 1.2) * hw * 0.8
        local sy = math.cos(seed * 2.3 + time * 0.9) * hh * 0.8
        local sparkle = (math.sin(time * 4.0 + seed) * 0.5 + 0.5)
        local sa = math.floor(sparkle * intensity * 180)
        if sa > 10 then
            local radius = 1.5 + sparkle * 2.0
            local glow = nvgRadialGradient(vg, sx, sy, 0, radius * 3,
                nvgRGBA(255, 255, 255, sa),
                nvgRGBA(255, 255, 255, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, radius * 3)
            nvgFillPaint(vg, glow)
            nvgFill(vg)
            -- 实心中心
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, radius)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.min(255, sa + 60)))
            nvgFill(vg)
        end
    end
    nvgRestore(vg)

    -- 3) 径向柔光
    local glowAlpha = math.floor(intensity * breathe * 25)
    local glowPaint = nvgRadialGradient(vg, 0, 0, 0, hw * 1.2,
        nvgRGBA(255, 255, 255, glowAlpha),
        nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, hw*2, hh*2, 8)
    nvgFillPaint(vg, glowPaint)
    nvgFill(vg)
end
```

---

## 7. 卡背装饰动画

卡背的呼吸光环、动态波纹、虹彩微光：

```lua
function drawCardBack(vg, hw, hh, time)
    -- 背景渐变（马卡龙色系）
    local bgPaint = nvgLinearGradient(vg, -hw, -hh, hw, hh,
        nvgRGBA(255, 220, 230, 255),   -- 粉白
        nvgRGBA(200, 220, 255, 255))   -- 蓝白
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, hw*2, hh*2, 8)
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)

    -- 同心扩散波纹（8层）
    local rippleSpeed = 0.5
    for ri = 1, 8 do
        local phase = (time * rippleSpeed + ri * 0.12) % 1.0
        local radius = phase * math.max(hw, hh) * 1.5
        local alpha = math.floor((1.0 - phase) * 30)
        if alpha > 2 then
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, radius)
            nvgStrokeColor(vg, nvgRGBA(180, 140, 200, alpha))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)
        end
    end

    -- 中心呼吸光晕
    local breathe = 0.7 + 0.3 * math.sin(time * 2.0)
    local glowR = hw * 0.5 * breathe
    local glowPaint = nvgRadialGradient(vg, 0, 0, 0, glowR,
        nvgRGBA(255, 200, 240, math.floor(breathe * 60)),
        nvgRGBA(255, 200, 240, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, glowR)
    nvgFillPaint(vg, glowPaint)
    nvgFill(vg)

    -- 虹彩微光条
    local shimmerX = math.sin(time * 1.5) * hw * 0.6
    local shimmerPaint = nvgLinearGradient(vg,
        shimmerX - 20, -hh, shimmerX + 20, hh,
        nvgRGBA(255, 255, 255, 0),
        nvgRGBA(255, 255, 255, 25))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, hw*2, hh*2, 8)
    nvgFillPaint(vg, shimmerPaint)
    nvgFill(vg)
end
```

---

## 8. 插入指示线

拖拽换位时的金色指示线 + 箭头：

```lua
function drawInsertIndicator(vg, insertX, lineY, lineH)
    -- 垂直线
    nvgBeginPath(vg)
    nvgMoveTo(vg, insertX, lineY)
    nvgLineTo(vg, insertX, lineY + lineH)
    nvgStrokeColor(vg, nvgRGBA(255, 215, 0, 150))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 顶部三角箭头
    nvgBeginPath(vg)
    nvgMoveTo(vg, insertX - 6, lineY)
    nvgLineTo(vg, insertX + 6, lineY)
    nvgLineTo(vg, insertX, lineY + 8)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 215, 0, 150))
    nvgFill(vg)
end
```

---

## 9. 查阅遮罩

放大查看卡牌时的暗色遮罩：

```lua
-- inspectOverlayAlpha 通过 Tween.damp 平滑过渡
-- 打开时 → target 180, 关闭时 → target 0, speed = 8~10

if inspectOverlayAlpha > 1 then
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(inspectOverlayAlpha)))
    nvgFill(vg)

    -- 在遮罩上方绘制放大的卡牌
    inspectCard:draw(vg, time)

    -- 底部提示文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 160, 160, 140))
    nvgText(vg, screenW/2, screenH - 30, "点击任意位置关闭", nil)
end
```
