---
name: card-anim
description: >
  NanoVG 卡牌动效系统完整集成指南：手牌扇形布局、悬停弹起、选中举牌、
  抽牌/出牌/弃牌 tween 动画、翻牌、拖拽换位、查阅放大、3D 倾斜视差、
  全息闪光等 Balatro 风格卡牌交互动效。
  Use when users need to (1) 实现卡牌手牌系统,
  (2) 卡牌扇形/弧形排列布局,
  (3) 卡牌悬停/选中/拖拽交互动效,
  (4) 抽牌/出牌/弃牌动画,
  (5) 卡牌翻转/翻面效果,
  (6) 卡牌3D倾斜/视差/全息闪光,
  (7) 用户提到 card animation、手牌、card hand、balatro 风格,
  (8) 需要卡牌游戏的交互和动效系统。
---

# 卡牌动效系统 — Card Animation System

基于 NanoVG 的 Balatro 风格卡牌动效方案，覆盖手牌管理全流程。
**零引擎依赖的动效层**——只关注位置/缩放/旋转/透明度的插值与渲染，卡牌内容（花色、数值、技能）由使用方定义。

> **前置依赖**：需要一个 Tween 引擎（`Tween.to()` + `Tween.damp()` + 缓动函数库）。
> 推荐使用 `@soyoyo_tween` skill 或自建简易 Tween 模块。

---

## 架构概览

```
CardHand (手牌管理器)
  ├── 布局引擎: 扇形排列 + 曲线 + 旋转
  ├── 交互系统: 悬停 / 选中 / 拖拽 / 长按
  └── 动画系统: Tween 驱动生命周期动画
         │
         ▼
Card (单张卡牌)
  ├── 显示状态 + 目标状态（双态平滑插值）
  └── 视觉特效: 翻牌 / 倾斜 / 全息 / 暗淡 / 微动
```

---

## 核心概念：双态平滑插值模型

每张卡牌维护**显示状态**和**目标状态**，每帧通过 `Tween.damp()` 指数衰减平滑过渡：

```lua
card = {
    -- 显示状态（当前帧渲染值）
    x = 0, y = 0,
    rotation = 0,        -- 度数
    scale = 1.0,
    opacity = 255,

    -- 目标状态（布局引擎计算）
    targetX = 0, targetY = 0,
    targetRotation = 0,
    targetScale = 1.0,

    -- 交互状态
    hovered = false, selected = false, dragging = false, faceUp = true,

    -- Z 排序
    zIndex = 0, baseZIndex = 0,

    -- 视差倾斜
    tiltX = 0, tiltY = 0,
    targetTiltX = 0, targetTiltY = 0,

    -- 翻牌
    flipProgress = 0,  -- 0=背面, 1=正面

    -- 微动
    wobblePhase = math.random() * math.pi * 2,

    -- 拖拽惯性
    dragTilt = 0, dragVelX = 0,
}
```

**每帧更新**（非 tween 动画时）：

```lua
local speed = 14
if not Tween.isAnimating(card) then
    card.x = Tween.damp(card.x, card.targetX, speed, dt)
    card.y = Tween.damp(card.y, card.targetY, speed, dt)
    card.rotation = Tween.dampAngle(card.rotation, card.targetRotation, speed, dt)
    card.scale = Tween.damp(card.scale, card.targetScale, speed, dt)
end
```

> **关键**：`Tween.damp` 用于连续状态过渡（布局、悬停），`Tween.to` 用于一次性动画（抽牌、出牌）。两者互斥。

---

## 动效清单

### 1. 扇形手牌布局（每帧连续）

卡牌在手中呈**抛物线弧形**排列，两端微旋转：

```lua
local CONFIG = {
    maxSpread   = 500,   -- 最大水平展开宽度(px)
    cardSpacing = 70,    -- 基础间距
    curveAmount = 15,    -- 弧线高度(px)
    maxRotation = 6,     -- 两端最大旋转角(度)
}

function updateTargets(cards, screenW, handY)
    local n = #cards
    local centerX = screenW / 2
    local spacing = math.min(CONFIG.cardSpacing, CONFIG.maxSpread / math.max(1, n))

    for i = 1, n do
        local t = (n > 1) and ((i - 1) / (n - 1) * 2 - 1) or 0
        cards[i].targetX = centerX + t * (spacing * (n - 1)) / 2
        cards[i].targetY = handY + t * t * CONFIG.curveAmount   -- 抛物线
        cards[i].targetRotation = t * CONFIG.maxRotation
        cards[i].baseZIndex = i
    end
end
```

### 2. 悬停弹起 + 邻牌推开

```lua
-- 悬停卡牌
if card.hovered then
    card.targetY = card.targetY - 40    -- 上移40px
    card.targetScale = 1.18
    card.targetRotation = 0
    card.zIndex = 100
end

-- 邻牌推开（距离<=2 的卡牌）
for i, other in ipairs(cards) do
    local dist = i - hoveredIndex
    if other ~= hoveredCard and math.abs(dist) <= 2 then
        local push = 25 * (1 - math.abs(dist) / 3)
        if dist < 0 then push = -push end
        other.targetX = other.targetX + push
    end
end
```

### 3. 3D 倾斜视差

```lua
if card.hovered then
    local normX = clamp((mouseX - card.x) / (CARD_W/2 * card.scale), -1, 1)
    local normY = clamp((mouseY - card.y) / (CARD_H/2 * card.scale), -1, 1)
    card.targetTiltX = -normY * 6
    card.targetTiltY = normX * 6
end
card.tiltX = Tween.damp(card.tiltX, card.targetTiltX, 10, dt)
card.tiltY = Tween.damp(card.tiltY, card.targetTiltY, 10, dt)

-- 渲染时用 nvgSkewX/Y 模拟 3D
nvgSkewX(vg, math.rad(card.tiltY * 0.6))
nvgSkewY(vg, math.rad(card.tiltX * 0.6))
```

### 4. 选中举牌

```lua
if card.selected and not card.hovered then
    card.targetY = card.targetY - 30
    card.zIndex = card.baseZIndex + 50
end
```

### 5. 抽牌动画（Tween 驱动）

```lua
-- 从牌堆飞到手牌位置，带翻转和过冲弹性
Tween.to(card, {
    x = targetX, y = targetY,
    rotation = targetRot, scale = 1.0,
    flipProgress = 1.0,        -- 驱动翻牌
}, 0.35, {
    easing = Tween.Easing.easeOutBack,
    delay = (i - 1) * 0.08,   -- 多张抽牌交错
    onComplete = function()
        card.faceUp = true
        card.flipProgress = 0
    end
})
```

**翻牌渲染**（cosine X 轴缩放）：
```lua
local flipScale = math.cos(card.flipProgress * math.pi)
-- flipProgress 0→0.5: flipScale 1→0 (背面缩小)
-- flipProgress 0.5→1: flipScale 0→-1 (正面展开)
nvgScale(vg, math.abs(flipScale) * card.scale, card.scale)
-- flipScale > 0 显示背面，< 0 显示正面
```

### 6. 出牌动画

```lua
Tween.to(card, {
    x = playAreaX + offsetX, y = playAreaY,
    rotation = 0, scale = 1.05,
}, 0.3, { easing = Tween.Easing.easeOutCubic })
```

### 7. 弃牌动画

```lua
Tween.to(card, {
    x = discardX, y = discardY,
    rotation = 15 + math.random() * 20,  -- 随机旋转
    scale = 0.5, opacity = 80,
}, 0.25, {
    easing = Tween.Easing.easeInCubic,
    delay = (i - 1) * 0.05,
})
```

### 8. 查阅放大

```lua
-- 打开：飞到屏幕中央放大
Tween.to(card, {
    x = screenW/2, y = screenH/2,
    rotation = 0, scale = 2.2,
}, 0.25, { easing = Tween.Easing.easeOutCubic })

-- 关闭：飞回原位
Tween.to(card, {
    x = savedX, y = savedY, scale = savedScale,
}, 0.25, { easing = Tween.Easing.easeOutCubic })
```

### 9. 拖拽换位

```lua
if card.dragging then
    card.x = mouseX - dragOffsetX
    card.y = mouseY - dragOffsetY
    card.targetScale = 1.1
    card.zIndex = 200
    -- 惯性旋转
    card.dragTilt = Tween.damp(card.dragTilt, -velX * 0.8, 8, dt)
end
-- 松手时根据插入位置重排数组
```

### 10. 微动呼吸

```lua
card.wobbleAmount = math.sin(time * 1.5 + card.wobblePhase) * 0.5
-- 渲染时 y += wobbleAmount
```

---

## 动画锁机制

抽牌/出牌等动画期间锁定交互，使用引用计数：

```lua
local animLockCount = 0
function lockAnim(n) animLockCount = animLockCount + (n or 1) end
function unlockAnim()
    animLockCount = math.max(0, animLockCount - 1)
end
-- animLockCount > 0 时跳过悬停检测和点击响应
```

---

## 移动端适配要点

| 交互 | 桌面端 | 移动端 |
|------|--------|--------|
| 悬停 | 鼠标 hover | 触摸按下即视为悬停 |
| 查阅 | 右键 | 长按 0.5s |
| hover 抑制 | 不需要 | 手指抬起后抑制直到移动 |

---

## 完整配置参数表

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `maxSpread` | 500 | 手牌最大展开宽度(px) |
| `cardSpacing` | 70 | 基础卡牌间距(px) |
| `curveAmount` | 15 | 弧线深度(px) |
| `maxRotation` | 6 | 两端最大旋转角(度) |
| `hoverLift` | 40 | 悬停上移(px) |
| `hoverScale` | 1.18 | 悬停缩放 |
| `hoverPushApart` | 25 | 邻牌推开距离(px) |
| `hoverSpeed` | 14 | damp 平滑速度 |
| `selectLift` | 30 | 选中上移(px) |
| `drawDuration` | 0.35 | 抽牌动画时长(s) |
| `drawStagger` | 0.08 | 多张抽牌间隔(s) |
| `playDuration` | 0.3 | 出牌动画时长(s) |
| `discardDuration` | 0.25 | 弃牌动画时长(s) |
| `dragScale` | 1.1 | 拖拽时缩放 |
| `inspectScale` | 2.2 | 查阅放大倍率 |
| `inspectDuration` | 0.25 | 查阅动画时长(s) |
| `maxHandSize` | 8 | 最大手牌数 |

---

## 动效速查表

| 动效 | 驱动 | 时长 | 缓动 | 关键属性 |
|------|------|------|------|---------|
| 扇形布局 | damp | 连续 | 指数衰减 | x, y, rotation, scale |
| 悬停弹起 | damp | 连续 | 指数衰减 | y-40, scale 1.18 |
| 倾斜视差 | damp | 连续 | 指数衰减 | tiltX/Y +/-6 |
| 邻牌推开 | damp | 连续 | 指数衰减 | x +/-25 |
| 选中举牌 | damp | 连续 | 指数衰减 | y-30 |
| 抽牌 | Tween.to | 0.35s | easeOutBack | x,y,rot,scale,flip |
| 翻牌 | cosine | 随抽牌 | easeOutBack | cos(progress*pi) |
| 出牌 | Tween.to | 0.3s | easeOutCubic | x,y,rot=0,scale=1.05 |
| 弃牌 | Tween.to | 0.25s | easeInCubic | x,y,rot随机,scale=0.5 |
| 查阅 | Tween.to | 0.25s | easeOutCubic | x=中心,scale=2.2 |
| 拖拽 | 直接赋值 | 连续 | — | 跟随鼠标+惯性旋转 |
| 微动 | sin(t) | 连续 | 正弦 | y +/-0.5px |

---

## 参考文档

| 文档 | 内容 |
|------|------|
| `references/visual-effects.md` | 卡牌渲染管线（阴影、倾斜高光、全息闪光、暗淡过渡、卡背装饰）完整代码 |
