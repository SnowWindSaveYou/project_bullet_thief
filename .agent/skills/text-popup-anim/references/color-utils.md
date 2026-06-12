# 颜色工具函数

> RGB ↔ HSV 转换、暖偏阴影算法、色相旋转工具。
> 所有函数均为纯函数，无外部依赖。

## RGB ↔ HSV 双向转换

### rgbToHsv — RGB(0-255) → HSV

```lua
--- RGB 转 HSV
---@param r number  R (0-255)
---@param g number  G (0-255)
---@param b number  B (0-255)
---@return number h  色相 (0-360°)
---@return number s  饱和度 (0.0-1.0)
---@return number v  明度 (0.0-1.0)
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
```

### hsvToRgb — HSV → RGB(0-255)

```lua
--- HSV 转 RGB
---@param h number  色相 (0-360°)
---@param s number  饱和度 (0.0-1.0)
---@param v number  明度 (0.0-1.0)
---@return number r  R (0-255)
---@return number g  G (0-255)
---@return number b  B (0-255)
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
    return math.floor((r + m) * 255),
           math.floor((g + m) * 255),
           math.floor((b + m) * 255)
end
```

## shadowColor — 同色系暖偏阴影

### 算法原理

普通阴影直接降低亮度会导致"灰暗死板"的效果。`shadowColor` 通过 HSV 色相偏转产生**同色系但偏暖**的阴影，视觉上更像插画/手绘风格：

| 步骤 | 操作 | 效果 |
|------|------|------|
| 1. 色相偏转 | h = (h - 30°) mod 360 | 向暖色方向偏转，保持同色系 |
| 2. 饱和度增强 | s = max(0.85, s × 1.05) | 拉高饱和度，阴影更鲜艳 |
| 3. 固定明度 | v = 0.50 | 中暗亮度：够深但颜色仍可辨认 |

### 色彩效果示例

| 主色 | 阴影色 | 说明 |
|------|--------|------|
| 金色 (45°, 0.8, 1.0) | 深橙 (15°, 0.85, 0.5) | 金 → 暖橙阴影 |
| 紫色 (280°, 0.7, 0.9) | 深蓝紫 (250°, 0.85, 0.5) | 紫 → 蓝紫阴影 |
| 红色 (0°, 0.9, 1.0) | 深玫红 (330°, 0.95, 0.5) | 红 → 暖玫红阴影 |
| 绿色 (120°, 0.8, 0.9) | 深青绿 (90°, 0.85, 0.5) | 绿 → 暖黄绿阴影 |
| 蓝色 (210°, 0.8, 0.9) | 深紫蓝 (180°, 0.85, 0.5) | 蓝 → 青蓝阴影 |

### 完整实现

```lua
--- 同色系暖偏阴影色
--- 用途：4 层浮雕文字的第 1 层（深色阴影），以及卡牌/UI 的投影
---@param r number     主色 R (0-255)
---@param g number     主色 G (0-255)
---@param b number     主色 B (0-255)
---@param alpha number 阴影不透明度 (0-255)
---@return NVGColor    NanoVG 颜色值
local function shadowColor(r, g, b, alpha)
    local h, s, _ = rgbToHsv(r, g, b)
    h = (h - 30 + 360) % 360       -- 向暖侧偏转 30°
    s = math.max(0.85, s * 1.05)    -- 拉高饱和度
    local v = 0.50                   -- 固定中暗亮度
    local sr, sg, sb = hsvToRgb(h, s, v)
    return nvgRGBA(sr, sg, sb, alpha)
end
```

### 调参指南

| 参数 | 默认值 | 调大效果 | 调小效果 |
|------|--------|---------|---------|
| 色相偏转 | -30° | 阴影更暖（偏橙/红） | 阴影偏冷（偏蓝/紫） |
| 饱和度下限 | 0.85 | 阴影更鲜艳 | 阴影更灰暗 |
| 固定明度 | 0.50 | 阴影更浅 | 阴影更深 |

```lua
-- 变体：冷色系阴影（适合科幻/冰雪主题）
local function coldShadowColor(r, g, b, alpha)
    local h, s, _ = rgbToHsv(r, g, b)
    h = (h + 30) % 360              -- 向冷侧偏转 30°
    s = math.max(0.80, s * 1.0)
    local v = 0.45
    local sr, sg, sb = hsvToRgb(h, s, v)
    return nvgRGBA(sr, sg, sb, alpha)
end

-- 变体：高对比阴影（适合竞技/格斗游戏）
local function hardShadowColor(r, g, b, alpha)
    local h, s, _ = rgbToHsv(r, g, b)
    h = (h - 30 + 360) % 360
    s = math.max(0.90, s * 1.1)
    local v = 0.35                   -- 更深
    local sr, sg, sb = hsvToRgb(h, s, v)
    return nvgRGBA(sr, sg, sb, alpha)
end
```

## hueToRgb — 纯色相转 RGB

用于粒子等只需色相变化的场景（固定 S=1, V=1）：

```lua
--- 纯色相（最大饱和度+最大明度）→ RGB
---@param h number  色相 (0-360°)
---@return number r, number g, number b  (0-255)
local function hueToRgb(h)
    h = h % 360
    local c = 1.0
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local r, g, b = 0, 0, 0
    if     h < 60  then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else                r, g, b = c, 0, x
    end
    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end
```

## 4 层浮雕文字渲染

将 `shadowColor` 应用于多层文字绘制，产生游戏风格的立体文字效果：

```
渲染顺序（从后到前）：
┌─────────────────────────────────┐
│  层 4: 白色高光  (-1, -1.5)      │  ← 最上层，alpha × 85
│  层 3: 主色      (0, 0)          │  ← alpha × 255
│  层 2: 内描边    (+1, +1.5)      │  ← 主色 × 0.65, alpha × 160
│  层 1: 暖偏阴影  (+2.5, +3.5)    │  ← shadowColor(), alpha × 200
└─────────────────────────────────┘
```

### 各层详细参数

| 层 | 颜色来源 | 偏移 (x, y) | alpha 系数 | 视觉作用 |
|----|---------|-------------|-----------|---------|
| 1 (阴影) | `shadowColor(r,g,b, α×200)` | +2.5, +3.5 | 200/255 ≈ 78% | 深度感、立体感 |
| 2 (内描) | `rgb × 0.65` | +1.0, +1.5 | 160/255 ≈ 63% | 描边轮廓、锐利边缘 |
| 3 (主色) | 原始 `r,g,b` | 0, 0 | 255/255 = 100% | 文字主体 |
| 4 (高光) | 纯白 `255,255,255` | -1.0, -1.5 | 85/255 ≈ 33% | 光泽感、高光反射 |

### 完整实现

```lua
--- 4 层浮雕文字渲染
--- 调用前需已设置 nvgFontFace / nvgFontSize / nvgTextAlign
function drawLayeredText(x, y, text, r, g, b, alpha)
    -- 层 1: 暖偏阴影
    nvgFillColor(vg, shadowColor(r, g, b, math.floor(alpha * 200)))
    nvgText(vg, x + 2.5, y + 3.5, text, nil)
    -- 层 2: 内描边 (65% 亮度)
    nvgFillColor(vg, nvgRGBA(
        math.floor(r * 0.65), math.floor(g * 0.65), math.floor(b * 0.65),
        math.floor(alpha * 160)))
    nvgText(vg, x + 1.0, y + 1.5, text, nil)
    -- 层 3: 主色
    nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(alpha * 255)))
    nvgText(vg, x, y, text, nil)
    -- 层 4: 白色高光
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 85)))
    nvgText(vg, x - 1.0, y - 1.5, text, nil)
end
```

## 常见陷阱

### 1. HSV 色相环绕

```lua
-- ❌ 可能产生负数
h = h - 30

-- ✅ 正确：加 360 后取模
h = (h - 30 + 360) % 360
```

### 2. 饱和度 0 的颜色（纯灰/黑/白）

纯灰色 (s=0) 经过 `shadowColor` 处理后饱和度被拉到 0.85，会变成有色彩的阴影。
如果需要保持灰色阴影：

```lua
local function neutralShadowColor(r, g, b, alpha)
    local _, s, _ = rgbToHsv(r, g, b)
    if s < 0.05 then
        -- 纯灰色：直接降低亮度
        local v = math.floor(math.max(r, g, b) * 0.4)
        return nvgRGBA(v, v, v, alpha)
    end
    return shadowColor(r, g, b, alpha)
end
```

### 3. alpha 参数范围

- `shadowColor` 的 `alpha` 参数范围是 **0-255**（NanoVG 原生范围）
- `drawLayeredText` 的 `alpha` 参数范围是 **0.0-1.0**（归一化），内部乘以 255 转换

```lua
-- ✅ shadowColor 直接传 0-255
shadowColor(255, 200, 0, 200)

-- ✅ drawLayeredText 传 0.0-1.0
drawLayeredText(x, y, "Score\!", 255, 200, 0, 0.8)
```
