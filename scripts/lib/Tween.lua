-- ============================================================================
-- Tween.lua - Balatro 风格动画引擎
-- 支持多属性动画、缓动函数、延迟、回调、链式调用
-- 可独立复用于任何 UrhoX 项目
-- ============================================================================

local M = {}

-- ============================================================================
-- 缓动函数库 (Easing Functions)
-- ============================================================================
M.Easing = {}

function M.Easing.linear(t) return t end

function M.Easing.easeInQuad(t) return t * t end
function M.Easing.easeOutQuad(t) return t * (2 - t) end
function M.Easing.easeInOutQuad(t)
    if t < 0.5 then return 2 * t * t end
    return -1 + (4 - 2 * t) * t
end

function M.Easing.easeInCubic(t) return t * t * t end
function M.Easing.easeOutCubic(t) return 1 - (1 - t) ^ 3 end
function M.Easing.easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    return 1 - (-2 * t + 2) ^ 3 / 2
end

function M.Easing.easeOutQuart(t) return 1 - (1 - t) ^ 4 end

--- 回弹过冲 (Balatro 抽卡最爱)
function M.Easing.easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

--- 弹性 (得分弹跳)
function M.Easing.easeOutElastic(t)
    if t == 0 or t == 1 then return t end
    local c4 = (2 * math.pi) / 3
    return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * c4) + 1
end

--- 弹跳 (落地效果)
function M.Easing.easeOutBounce(t)
    local n1 = 7.5625
    local d1 = 2.75
    if t < 1 / d1 then
        return n1 * t * t
    elseif t < 2 / d1 then
        t = t - 1.5 / d1
        return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then
        t = t - 2.25 / d1
        return n1 * t * t + 0.9375
    else
        t = t - 2.625 / d1
        return n1 * t * t + 0.984375
    end
end

--- 平滑呼吸 (idle 微动)
function M.Easing.easeInOutSine(t)
    return -(math.cos(math.pi * t) - 1) / 2
end

-- ============================================================================
-- Tween 实例
-- ============================================================================

---@class TweenInstance
---@field target table 动画目标对象
---@field props table<string, {from: number, to: number}> 属性映射
---@field duration number 持续时间（秒）
---@field elapsed number 已过时间
---@field delay number 延迟启动（秒）
---@field easing function 缓动函数
---@field onComplete function|nil 完成回调
---@field onUpdate function|nil 每帧回调
---@field dead boolean 是否已结束
---@field tag string|nil 标签，用于批量取消

local activeTweens = {}

--- 创建动画
---@param target table 目标对象（其属性会被直接修改）
---@param toProps table<string, number> 目标属性值
---@param duration number 持续时间（秒）
---@param opts table|nil 可选 {easing, delay, onComplete, onUpdate, tag}
---@return TweenInstance
function M.to(target, toProps, duration, opts)
    opts = opts or {}
    local tween = {
        target = target,
        props = {},
        duration = math.max(0.001, duration),
        elapsed = 0,
        delay = opts.delay or 0,
        easing = opts.easing or M.Easing.easeOutCubic,
        onComplete = opts.onComplete,
        onUpdate = opts.onUpdate,
        dead = false,
        tag = opts.tag,
    }
    -- 记录起始值
    for k, v in pairs(toProps) do
        tween.props[k] = { from = target[k] or 0, to = v }
    end
    activeTweens[#activeTweens + 1] = tween
    return tween
end

--- 取消目标上的所有动画
function M.cancelTarget(target)
    for i = #activeTweens, 1, -1 do
        if activeTweens[i].target == target then
            activeTweens[i].dead = true
        end
    end
end

--- 取消指定标签的所有动画
function M.cancelTag(tag)
    for i = #activeTweens, 1, -1 do
        if activeTweens[i].tag == tag then
            activeTweens[i].dead = true
        end
    end
end

--- 取消所有动画
function M.cancelAll()
    for i = #activeTweens, 1, -1 do
        activeTweens[i].dead = true
    end
end

--- 每帧更新（在 HandleUpdate 中调用）
function M.update(dt)
    local i = 1
    while i <= #activeTweens do
        local tw = activeTweens[i]
        if tw.dead then
            table.remove(activeTweens, i)
        else
            -- 延迟阶段
            if tw.delay > 0 then
                tw.delay = tw.delay - dt
                i = i + 1
            else
                tw.elapsed = tw.elapsed + dt
                local t = math.min(tw.elapsed / tw.duration, 1.0)
                local easedT = tw.easing(t)

                -- 插值属性
                for k, v in pairs(tw.props) do
                    tw.target[k] = v.from + (v.to - v.from) * easedT
                end

                if tw.onUpdate then tw.onUpdate(tw.target, t) end

                if t >= 1.0 then
                    -- 确保精确到达目标
                    for k, v in pairs(tw.props) do
                        tw.target[k] = v.to
                    end
                    tw.dead = true
                    if tw.onComplete then tw.onComplete(tw.target) end
                    table.remove(activeTweens, i)
                else
                    i = i + 1
                end
            end
        end
    end
end

--- 当前活跃动画数量
function M.count()
    return #activeTweens
end

--- 目标是否有活跃动画
function M.isAnimating(target)
    for _, tw in ipairs(activeTweens) do
        if tw.target == target and not tw.dead then return true end
    end
    return false
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 平滑逼近（指数衰减，用于持续跟随动画）
function M.damp(current, target, speed, dt)
    return current + (target - current) * math.min(1, dt * speed)
end

--- 角度平滑逼近（处理 -180/180 跳变）
function M.dampAngle(current, target, speed, dt)
    local diff = target - current
    while diff > 180 do diff = diff - 360 end
    while diff < -180 do diff = diff + 360 end
    return current + diff * math.min(1, dt * speed)
end

return M
