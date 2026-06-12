---
name: text-popup-anim
description: >
  NanoVG 弹字动效系统完整集成指南：得分弹字、逐字横幅、阶段过渡文字、
  4层浮雕文字渲染、数字滚动、幽灵拖尾、屏幕震动等游戏反馈动效。
  Use when users need to (1) 实现得分/伤害/奖励弹字效果,
  (2) 逐字入场横幅/公告动画,
  (3) 阶段/回合过渡文字,
  (4) 浮雕/描边/多层文字渲染,
  (5) 数字滚动/翻滚效果,
  (6) 屏幕震动反馈,
  (7) 粒子飞行（筹码/星星/金币）,
  (8) 用户提到 popup、弹字、floating text、score animation、damage number,
  (9) 需要游戏中的文字反馈和视觉冲击效果。
---

# 弹字动效系统 — Text Popup Animation System

基于 NanoVG 的游戏文字反馈动效方案，覆盖得分弹字、公告横幅、阶段过渡三大核心场景。
**纯渲染层**——不依赖具体游戏逻辑，通过 spawn 函数触发，内部管理生命周期和粒子池。

---

## 架构概览

```
┌─────────────────────────────────────────────────┐
│  VFX Manager (统一管理器)                         │
│  ├── ScorePopups[]   — 得分弹字池                 │
│  ├── ActionBanners[] — 逐字横幅池                 │
│  ├── PhaseTransition — 阶段过渡（单例）            │
│  ├── ScreenShake     — 屏幕震动                   │
│  └── ChipParticles[] — 粒子飞行池                 │
│                                                   │
│  每帧调用 updateAll(dt) + drawXxx() 系列函数       │
└─────────────────────────────────────────────────┘
```

**调用方式**：

```lua
-- 触发
VFX.spawnPopup("+100", x, y, 255, 215, 0)       -- 金色得分弹字
VFX.spawnBanner("Perfect\!", 255, 80, 120, 32)    -- 红色大字横幅
VFX.showTransition("Round 3", 100, 200, 255)     -- 蓝色阶段过渡
VFX.triggerShake(5, 0.3, 30)                     -- 屏幕震动

-- 每帧
VFX.updateAll(dt)

-- 渲染（在 NanoVGRender 事件中）
VFX.drawPopups()
VFX.drawBanners()
VFX.drawTransition()
```

---

## 核心组件：4 层浮雕文字渲染

所有弹字效果共用的文字渲染基础——4 层偏移叠加产生浮雕/立体感：

```lua
--- 4层文字渲染：深影 → 内描 → 主色 → 白色高光
--- 调用前需已设置好 nvgFontFace / nvgFontSize / nvgTextAlign
function drawLayeredText(vg, x, y, text, r, g, b, alpha)
    -- 层1：暖色深影（色相偏转-30度，饱和度拉高，亮度0.5）
    nvgFillColor(vg, shadowColor(r, g, b, math.floor(alpha * 200)))
    nvgText(vg, x + 2.5, y + 3.5, text, nil)

    -- 层2：同色系内描（主色 * 0.65）
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
```

**层次分解**：

| 层 | 偏移 (x, y) | 颜色 | Alpha 系数 | 作用 |
|----|-------------|------|-----------|------|
| 1 深影 | +2.5, +3.5 | 色相-30度, 饱和度↑, 亮度0.5 | alpha×200/255 | 投影，暖色偏转 |
| 2 内描 | +1.0, +1.5 | 主色×0.65 | alpha×160/255 | 深色描边 |
| 3 主色 | 0, 0 | r, g, b | alpha×255/255 | 主体颜色 |
| 4 高光 | -1.0, -1.5 | 白色 | alpha×85/255 | 左上高光 |

**阴影色计算**（色相暖偏）：

```lua
function shadowColor(r, g, b, alpha)
    local h, s, v = rgbToHsv(r, g, b)
    h = (h - 30 + 360) % 360      -- 向暖侧偏转30度
    s = math.max(0.85, s * 1.05)   -- 拉高饱和度
    v = 0.50                       -- 固定中暗亮度
    local sr, sg, sb = hsvToRgb(h, s, v)
    return nvgRGBA(sr, sg, sb, alpha)
end
```

> **设计理念**：暖色阴影比纯黑阴影更有质感；偏转30度让蓝色文字的阴影偏紫，红色偏橙，视觉更丰富。

---

## 动效 1：得分弹字（Score Popup）

### 生命周期：1.25 秒，4 阶段动画

```
 弹出(0-15%)  回弹(15-30%)  浮动+数字滚(30-75%)  飞出+拖尾(75-100%)
 ┌──────────┬──────────┬────────────────────┬─────────────────┐
 │ elastic  │ quad回缩  │ sin微漂 + 数字乱跳  │ 上飞85px+淡出   │
 │ scale 0→2│ scale 2→1│ rot±5° y±3.5px     │ +3层幽灵拖尾    │
 └──────────┴──────────┴────────────────────┴─────────────────┘
```

### 数据结构

```lua
local popup = {
    text    = "+100",          -- 显示文本
    prefix  = "+",             -- 解析出的前缀
    numVal  = 100,             -- 解析出的数值（用于数字滚动）
    suffix  = "",              -- 后缀
    x = 400, y = 300,          -- 屏幕位置
    timer   = 0,               -- 已过时间
    maxTime = 1.25,            -- 总生命周期
    r = 255, g = 215, b = 0,  -- 颜色
    scale   = 1.0,             -- 基础缩放
}
```

### 4 阶段实现

```lua
function drawPopup(vg, p)
    local progress = p.timer / p.maxTime
    local baseScale = p.scale
    local curX, curY = p.x, p.y
    local curScale = baseScale
    local alpha = 1.0
    local rotation = 0.0

    if progress < 0.15 then
        ---- 阶段1：弹性弹出 ----
        local t = progress / 0.15
        curScale = baseScale * easeOutElastic(t) * 2.0
        alpha = math.min(1.0, t * 8)   -- 快速淡入

    elseif progress < 0.30 then
        ---- 阶段2：回弹归位 ----
        local t = (progress - 0.15) / 0.15
        curScale = baseScale * lerp(2.0, 1.0, easeInQuad(t))

    elseif progress < 0.75 then
        ---- 阶段3：浮动 + 数字滚动 ----
        local t = (progress - 0.30) / 0.45
        curY = curY - math.sin(t * math.pi * 2.5) * 3.5   -- 正弦微漂
        rotation = math.sin(t * math.pi * 2.0) * 5.0       -- 摆动±5度

    else
        ---- 阶段4：飞出 + 淡出 ----
        local t = (progress - 0.75) / 0.25
        alpha = 1.0 - easeOutQuad(t)
        curY = curY - 85 * easeOutQuad(t)              -- 上飞85px
        curScale = baseScale * (1.0 + t * 0.25)        -- 轻微放大
        rotation = 8 * t                                -- 旋转飘走
    end

    if alpha <= 0.01 then return end

    ---- 数字滚动效果 ----
    local displayText = p.text
    if p.numVal and progress >= 0.30 and progress < 0.68 then
        local t = (progress - 0.30) / 0.38
        if t < 0.75 then
            local base = math.floor(p.numVal * t)
            local noise = math.floor(
                math.abs(math.sin(p.timer * 47.3 + 1.7)) * p.numVal * 0.45)
            local shown = math.min(base + noise, p.numVal + math.floor(p.numVal * 0.3))
            displayText = (p.prefix or "") .. tostring(shown) .. (p.suffix or "")
        end
    end

    ---- 幽灵拖尾（阶段4 独有）----
    if progress >= 0.75 then
        local t = (progress - 0.75) / 0.25
        for gi = 1, 3 do
            local ghostT = t - gi * 0.06
            if ghostT >= 0 then
                local ghostOff = -85 * easeOutQuad(ghostT)
                local ghostA = alpha * (0.35 - gi * 0.10)
                if ghostA > 0.01 then
                    nvgSave(vg)
                    nvgTranslate(vg, curX, p.y + ghostOff)
                    nvgScale(vg, curScale * 0.92, curScale * 0.92)
                    nvgFontFace(vg, "pixel")
                    nvgFontSize(vg, 26)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(ghostA * 255)))
                    nvgText(vg, 0, 0, displayText, nil)
                    nvgRestore(vg)
                end
            end
        end
    end

    ---- 主体渲染 ----
    nvgSave(vg)
    nvgTranslate(vg, curX, curY)
    nvgScale(vg, curScale, curScale)
    nvgRotate(vg, rotation * math.pi / 180)

    -- 背景光晕
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

    -- 4层文字
    nvgFontFace(vg, "pixel")
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    drawLayeredText(vg, 0, 0, displayText, p.r, p.g, p.b, alpha)

    nvgRestore(vg)
end
```

### 缓动函数

```lua
function easeOutElastic(t)
    if t == 0 or t == 1 then return t end
    return 2^(-10 * t) * math.sin((t * 10 - 0.75) * 2 * math.pi / 3) + 1
end

function easeInQuad(t) return t * t end
function easeOutQuad(t) return 1 - (1 - t)^2 end
function lerp(a, b, t) return a + (b - a) * t end
```

### 触发示例

```lua
-- 得分
VFX.spawnPopup("+100", cardX, cardY - 30, 255, 215, 0, 1.2)

-- 伤害
VFX.spawnPopup("-50 HP", enemyX, enemyY - 20, 255, 80, 80, 1.0)

-- 奖励
VFX.spawnPopup("+3 bonus", screenW/2, screenH/2, 100, 255, 150, 1.5)

-- 非数字文本（无数字滚动）
VFX.spawnPopup("Miss\!", targetX, targetY, 180, 180, 180, 0.9)
```

---

## 动效 2：逐字横幅（Action Banner）

### 生命周期：~1.5 秒，逐字交错入场

```
  字1    字2    字3    字4
  ┌──┐   ┌──┐   ┌──┐   ┌──┐
  │弹│   │弹│   │弹│   │弹│ ← stagger 0.055s
  │回│   │回│   │回│   │回│ ← easeOutBack 弹入
  │浮│   │浮│   │浮│   │浮│ ← sin 微浮
  └──┘   └──┘   └──┘   └──┘
         ──── 整体淡出上飘 ────
```

### 数据结构

```lua
local banner = {
    chars   = {"P","e","r","f","e","c","t","\!"},  -- UTF-8 逐字拆分
    text    = "Perfect\!",
    timer   = 0,
    maxTime = 1.5,             -- 基础时长（实际 += 字数*stagger）
    r = 255, g = 80, b = 120,  -- 颜色
    size    = 32,               -- 字号
}
```

### 逐字动画参数

| 参数 | 值 | 说明 |
|------|-----|------|
| STAGGER | 0.055s | 相邻字符入场延迟 |
| ENTRY_DUR | 0.18s | 弹入阶段时长 |
| SETTLE_DUR | 0.12s | 回弹稳定时长 |
| FADE_START | 0.70 | 开始淡出的进度比例 |

### 逐字渲染实现

```lua
function drawBanner(vg, banner, screenW, screenH, bannerIndex)
    local cx = screenW / 2
    local baseY = screenH / 2 + 38   -- 屏幕中偏下
    local STAGGER, ENTRY_DUR, SETTLE_DUR = 0.055, 0.18, 0.12
    local FADE_START = 0.70

    local nChars = #banner.chars
    local totalStagger = (nChars - 1) * STAGGER
    local effectiveMax = banner.maxTime + totalStagger
    local progress = banner.timer / effectiveMax

    -- 全局淡出
    local globalAlpha = 1.0
    if progress > FADE_START then
        globalAlpha = easeOutQuad(
            math.max(0, 1.0 - (progress - FADE_START) / (1.0 - FADE_START)))
    end

    -- 全局上飘
    local globalOffY = 0
    if progress > FADE_START then
        globalOffY = -35 * easeOutQuad((progress - FADE_START) / (1.0 - FADE_START))
    end

    -- 多横幅堆叠偏移
    local rowY = baseY - (bannerIndex - 1) * (banner.size * 1.3) + globalOffY

    -- 计算总宽度用于居中
    local totalW = 0
    local charWidths = {}
    for ci, ch in ipairs(banner.chars) do
        charWidths[ci] = estimateCharWidth(ch, banner.size)
        totalW = totalW + charWidths[ci]
    end

    -- 背景光晕
    if globalAlpha > 0.05 then
        local hW = totalW * 0.65 + banner.size
        local glow = nvgRadialGradient(vg, cx, rowY, 0, hW * 1.4,
            nvgRGBA(banner.r, banner.g, banner.b, math.floor(globalAlpha * 38)),
            nvgRGBA(banner.r, banner.g, banner.b, 0))
        nvgBeginPath(vg)
        nvgRect(vg, cx - hW*1.4, rowY - hW, hW*2.8, hW*2)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
    end

    -- 逐字绘制
    local curX = cx - totalW / 2
    for ci, ch in ipairs(banner.chars) do
        local delay = (ci - 1) * STAGGER
        local localT = banner.timer - delay

        local cAlpha, cY = globalAlpha, rowY
        local cScaleX, cScaleY = 1.0, 1.0

        if localT < 0 then
            -- 尚未入场
            curX = curX + charWidths[ci]
            goto continue
        elseif localT < ENTRY_DUR then
            -- 弹入：从下方弹起，X挤压，Y拉伸
            local t = localT / ENTRY_DUR
            local es = easeOutBack(t)
            cY = cY + lerp(28, 0, easeOutQuad(t))    -- 从下方28px弹起
            cAlpha = globalAlpha * math.min(1.0, t * 5)
            cScaleX = lerp(0.4, 1.0, es)              -- X从0.4拉宽
            cScaleY = lerp(1.6, 1.0, easeOutBack(math.min(1, t * 1.2))) * (0.8 + 0.2 * es)
        elseif localT < ENTRY_DUR + SETTLE_DUR then
            -- 回弹稳定：轻微果冻效果
            local t = (localT - ENTRY_DUR) / SETTLE_DUR
            cScaleY = lerp(0.88, 1.0, easeOutQuad(t))
            cScaleX = lerp(1.12, 1.0, easeOutQuad(t))
        else
            -- 空闲浮动：sin 波微漂
            local wave = math.sin(gameTime * 3.2 + ci * 0.9) * 2.5
            cY = cY + wave
            cScaleY = 1.0 + math.sin(gameTime * 2.8 + ci * 0.7) * 0.018
        end

        if cAlpha > 0.01 then
            local charCenterX = curX + charWidths[ci] * 0.5
            nvgSave(vg)
            nvgTranslate(vg, charCenterX, cY)
            nvgScale(vg, cScaleX, cScaleY)
            nvgFontFace(vg, "bold")
            nvgFontSize(vg, banner.size)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            drawLayeredText(vg, 0, 0, ch, banner.r, banner.g, banner.b, cAlpha)
            nvgRestore(vg)
        end

        curX = curX + charWidths[ci]
        ::continue::
    end
end

function easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t - 1)^3 + c1 * (t - 1)^2
end
```

---

## 动效 3：阶段过渡文字（Phase Transition）

### 生命周期：1.2 秒，3 阶段

```
  淡入+弹出(0-25%)   保持(25-72%)   淡出+放大(72-100%)
  ┌──────────────┬──────────────┬──────────────────┐
  │ easeOutBack  │  alpha=1.0   │ easeOutQuad 淡出  │
  │ scale 弹入   │  scale=1.0   │ scale 1.0→1.08   │
  └──────────────┴──────────────┴──────────────────┘
```

### 实现

```lua
-- 单例模式，同时只有一个过渡文字
local phaseTrans = { text="", timer=0, duration=1.2, r=180, g=120, b=255 }

function showTransition(text, r, g, b)
    phaseTrans.text = text
    phaseTrans.timer = phaseTrans.duration   -- 倒计时
    phaseTrans.r = r or 180
    phaseTrans.g = g or 120
    phaseTrans.b = b or 255
end

function updateTransition(dt)
    if phaseTrans.timer > 0 then
        phaseTrans.timer = phaseTrans.timer - dt
    end
end

function drawTransition(vg, screenW, screenH)
    if phaseTrans.timer <= 0 then return end
    local progress = 1.0 - phaseTrans.timer / phaseTrans.duration
    local alpha, scale = 0, 1.0

    if progress < 0.25 then
        ---- 淡入 + 弹出 ----
        local t = progress / 0.25
        alpha = t
        scale = easeOutBack(t)
    elseif progress < 0.72 then
        ---- 保持 ----
        alpha = 1.0
        scale = 1.0
    else
        ---- 淡出 + 轻微放大 ----
        local t = (progress - 0.72) / 0.28
        alpha = 1.0 - easeOutQuad(t)
        scale = 1.0 + t * 0.08
    end

    nvgSave(vg)
    nvgTranslate(vg, screenW/2, screenH/2)
    nvgScale(vg, scale, scale)
    nvgFontFace(vg, "bold")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    drawLayeredText(vg, 0, 0, phaseTrans.text,
        phaseTrans.r, phaseTrans.g, phaseTrans.b, alpha)
    nvgRestore(vg)
end
```

---

## 辅助动效：屏幕震动

双正弦衰减震动，用于得分、爆击等冲击反馈：

```lua
local shake = {
    intensity = 0,   -- 当前强度
    timer = 0,       -- 剩余时间
    duration = 0,    -- 总时长
    frequency = 30,  -- 震动频率
    offsetX = 0,     -- 输出偏移
    offsetY = 0,
}

function triggerShake(intensity, duration, frequency)
    shake.intensity = intensity or 5
    shake.duration = duration or 0.3
    shake.timer = shake.duration
    shake.frequency = frequency or 30
end

function updateShake(dt)
    if shake.timer <= 0 then
        shake.offsetX = 0
        shake.offsetY = 0
        return
    end
    shake.timer = shake.timer - dt
    local decay = (shake.timer / shake.duration) ^ 1.5  -- 幂衰减
    local t = (shake.duration - shake.timer) * shake.frequency
    shake.offsetX = math.sin(t * 2.1) * shake.intensity * decay
    shake.offsetY = math.cos(t * 1.7) * shake.intensity * decay * 0.7
end

-- 使用方式：在渲染开始时 nvgTranslate(vg, shake.offsetX, shake.offsetY)
```

### 常用震动参数

| 场景 | intensity | duration | frequency |
|------|-----------|----------|-----------|
| 轻微反馈 | 2-3 | 0.15 | 35 |
| 得分冲击 | 4-6 | 0.2 | 30 |
| 重击/爆炸 | 8-12 | 0.35-0.5 | 25 |
| 回合结算 | 5-7 | 0.25 | 30 |

---

## 辅助动效：粒子飞行（筹码/金币）

贝塞尔曲线粒子从起点飞到终点：

```lua
function spawnChips(sx, sy, tx, ty, count, r, g, b)
    for i = 1, count do
        local midX = (sx + tx) / 2 + (math.random() - 0.5) * 200
        local midY = math.min(sy, ty) - 80 - math.random() * 100
        particles[#particles + 1] = {
            sx=sx, sy=sy, tx=tx, ty=ty,    -- 起点/终点
            mx=midX, my=midY,               -- 贝塞尔控制点
            delay = (i-1) * 0.04,           -- 交错延迟
            duration = 0.4 + math.random() * 0.3,
            timer = 0,
            r=r, g=g, b=b,
            sparklePhase = math.random() * math.pi * 2,
        }
    end
end

-- 渲染：二次贝塞尔插值
local t = timer / duration
local u = 1 - t
local px = u*u*sx + 2*u*t*mx + t*t*tx
local py = u*u*sy + 2*u*t*my + t*t*ty
```

---

## 集成模板

完整的 VFX 管理器骨架代码见 `references/vfx-manager-template.md`。

---

## 动效速查表

| 动效 | 触发 | 时长 | 阶段 | 缓动 |
|------|------|------|------|------|
| 得分弹字 | spawnPopup | 1.25s | 弹出→回弹→浮动→飞出 | elastic/quad |
| 逐字横幅 | spawnBanner | 1.5s+ | 逐字弹入→果冻→浮动→淡出 | easeOutBack |
| 阶段过渡 | showTransition | 1.2s | 弹出→保持→淡出 | easeOutBack |
| 屏幕震动 | triggerShake | 0.15-0.5s | 双正弦幂衰减 | 自定义 |
| 粒子飞行 | spawnChips | 0.4-0.7s | 贝塞尔路径 | 二次曲线 |

---

## 参考文档

| 文档 | 内容 |
|------|------|
| `references/vfx-manager-template.md` | VFX 管理器完整骨架代码（spawn/update/draw/reset） |
| `references/color-utils.md` | RGB↔HSV 转换、shadowColor 暖偏算法、颜色工具函数 |
