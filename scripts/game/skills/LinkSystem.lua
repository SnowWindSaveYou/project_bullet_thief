-- ============================================================================
-- LinkSystem.lua - D线 梦境连线
-- BT期间夺取子弹时，在被夺子弹原位留下锚点
-- 锚点按夺取顺序自动连线
-- BT结束后，连线变为持续伤害光束(2.5s)，之后消散
-- 等级 0=未解锁, 1~5 逐步增强
-- ============================================================================

local SkillState = require "game.SkillState"
local Player = require "game.Player"
local ConfigLoader = require "config.ConfigLoader"

local M = {}

-- ═══ 等级配置（从 JSON 加载） ═══

local LEVEL_CFG = nil  -- 延迟初始化

--- 从 protagonist.json 加载连线等级配置
local function loadLevelCfg()
    if LEVEL_CFG then return LEVEL_CFG end

    local data = ConfigLoader.load("config/characters/protagonist.json")
    if data and data.skills and data.skills.link and data.skills.link.levels then
        LEVEL_CFG = {}
        for k, v in pairs(data.skills.link.levels) do
            LEVEL_CFG[tonumber(k)] = v
        end
        print("[LinkSystem] 从 JSON 加载 " .. #LEVEL_CFG .. " 个等级配置")
    end

    -- 兜底默认值
    if not LEVEL_CFG or #LEVEL_CFG == 0 then
        print("[LinkSystem] WARN: JSON 加载失败，使用内置默认值")
        LEVEL_CFG = {
            [1] = { maxAnchors = 8, beamDuration = 2.0, beamWidth = 10, beamDPS = 2, tickInterval = 0.3, anchorRadius = 4 },
            [2] = { maxAnchors = 12, beamDuration = 2.5, beamWidth = 12, beamDPS = 2.5, tickInterval = 0.3, anchorRadius = 5 },
            [3] = { maxAnchors = 18, beamDuration = 2.5, beamWidth = 12, beamDPS = 3, tickInterval = 0.25, anchorRadius = 5, denseThreshold = 80, denseWidth = 20, denseDPSMult = 1.3 },
            [4] = { maxAnchors = 24, beamDuration = 3.0, beamWidth = 12, beamDPS = 3.5, tickInterval = 0.25, anchorRadius = 6, denseThreshold = 80, denseWidth = 22, denseDPSMult = 1.4, slowFactor = 0.6, slowDuration = 1.0 },
            [5] = { maxAnchors = 30, beamDuration = 3.5, beamWidth = 14, beamDPS = 4, tickInterval = 0.2, anchorRadius = 6, denseThreshold = 80, denseWidth = 24, denseDPSMult = 1.5, slowFactor = 0.5, slowDuration = 1.5, explosionOnEnd = true, explosionRadius = 35, explosionDmg = 8 },
        }
    end
    return LEVEL_CFG
end

-- ═══ 状态 ═══

-- BT期间收集的锚点（BT结束后转为光束）
local anchors_ = {}          -- { {x, y}, ... } 按夺取顺序
local collectingBT_ = false  -- 当前是否在 BT 收集阶段

-- 光束阶段
local beams_ = {}            -- { segments, remaining, tickTimer, cfg }
-- segments: { {x1, y1, x2, y2, isDense, width, dps}, ... }

-- 结束爆炸效果
local endExplosions_ = {}    -- { {x, y, t, radius} }

-- BT结束回调已注册标记
local callbackRegistered_ = false

-- ═══ 核心接口 ═══

function M.init()
    M.reset()
    -- 注册 BT 结束回调
    if not callbackRegistered_ then
        Player.onBTEnd(function()
            M._onBTEnd()
        end)
        callbackRegistered_ = true
    end
end

function M.reset()
    anchors_ = {}
    beams_ = {}
    endExplosions_ = {}
    collectingBT_ = false
end

--- 获取当前等级配置
---@return table|nil
function M.getCfg()
    local level = SkillState.getLevel("link")
    if level < 1 then return nil end
    local cfg = loadLevelCfg()
    return cfg[math.min(level, 5)]
end

function M.isActive()
    return SkillState.getLevel("link") >= 1
end

--- BT期间夺取子弹时调用 —— 在子弹原位留锚点
---@param bulletX number 被夺子弹的原始位置
---@param bulletY number
function M.onBulletStolen(bulletX, bulletY)
    local cfg = M.getCfg()
    if not cfg then return end

    collectingBT_ = true

    -- 上限检查
    if #anchors_ >= cfg.maxAnchors then return end

    anchors_[#anchors_ + 1] = { x = bulletX, y = bulletY }
end

--- BT结束时内部调用 —— 将锚点转为光束
function M._onBTEnd()
    local cfg = M.getCfg()
    if not cfg then
        anchors_ = {}
        collectingBT_ = false
        return
    end

    -- 不在收集中或没有足够锚点
    if #anchors_ < 2 then
        anchors_ = {}
        collectingBT_ = false
        return
    end

    -- 构建光束段（按顺序连线）
    local segments = {}
    for i = 1, #anchors_ - 1 do
        local a = anchors_[i]
        local b = anchors_[i + 1]
        local dx = b.x - a.x
        local dy = b.y - a.y
        local dist = math.sqrt(dx * dx + dy * dy)

        -- 密集判定
        local isDense = cfg.denseThreshold and dist < cfg.denseThreshold
        local width = isDense and (cfg.denseWidth or cfg.beamWidth) or cfg.beamWidth
        local dps = isDense and cfg.beamDPS * (cfg.denseDPSMult or 1) or cfg.beamDPS

        segments[#segments + 1] = {
            x1 = a.x, y1 = a.y,
            x2 = b.x, y2 = b.y,
            isDense = isDense,
            width = width,
            dps = dps,
        }
    end

    -- 创建光束实例
    beams_[#beams_ + 1] = {
        segments = segments,
        anchors = anchors_,       -- 保留锚点用于绘制和结束爆炸
        remaining = cfg.beamDuration,
        duration = cfg.beamDuration,
        tickTimer = 0,
        cfg = cfg,
    }

    -- 重置收集
    anchors_ = {}
    collectingBT_ = false
end

--- 每帧更新：光束 DPS tick + 动画
---@param dt number
---@param enemies table[]
---@param bossData table|nil
---@return table hits { {enemyIdx, x, y, dmg, slow, targetType} ... }
function M.update(dt, enemies, bossData)
    local cfg = M.getCfg()
    if not cfg then return {} end

    local hits = {}

    -- 更新光束
    for i = #beams_, 1, -1 do
        local beam = beams_[i]
        beam.remaining = beam.remaining - dt

        if beam.remaining <= 0 then
            -- 光束结束
            -- Lv5 结束爆炸
            if beam.cfg.explosionOnEnd and beam.anchors then
                for _, anchor in ipairs(beam.anchors) do
                    endExplosions_[#endExplosions_ + 1] = {
                        x = anchor.x, y = anchor.y,
                        t = 0, duration = 0.35,
                        radius = beam.cfg.explosionRadius,
                    }
                    -- 爆炸伤害
                    local expHits = M._explosionHit(
                        anchor.x, anchor.y,
                        beam.cfg.explosionRadius,
                        beam.cfg.explosionDmg,
                        enemies, bossData
                    )
                    for _, h in ipairs(expHits) do
                        hits[#hits + 1] = h
                    end
                end
            end
            table.remove(beams_, i)
        else
            -- DPS tick
            beam.tickTimer = beam.tickTimer + dt
            local interval = beam.cfg.tickInterval
            if beam.tickTimer >= interval then
                beam.tickTimer = beam.tickTimer - interval
                local dmgMult = interval  -- DPS × tick时间 = 单次tick伤害

                for _, seg in ipairs(beam.segments) do
                    local tickDmg = math.max(1, math.floor(seg.dps * dmgMult))
                    local halfW = seg.width * 0.5

                    -- 检测线段范围内的敌人
                    for ei, e in ipairs(enemies) do
                        if not e.dead then
                            if M._segCircleIntersect(
                                seg.x1, seg.y1, seg.x2, seg.y2,
                                e.x, e.y, (e.radius or 16) + halfW
                            ) then
                                hits[#hits + 1] = {
                                    enemyIdx = ei,
                                    x = e.x, y = e.y,
                                    dmg = tickDmg,
                                    slow = beam.cfg.slowFactor and {
                                        factor = beam.cfg.slowFactor,
                                        duration = beam.cfg.slowDuration,
                                    } or nil,
                                    targetType = "enemy",
                                }
                            end
                        end
                    end

                    -- vs Boss
                    if bossData and not bossData.dead then
                        if M._segCircleIntersect(
                            seg.x1, seg.y1, seg.x2, seg.y2,
                            bossData.x, bossData.y, (bossData.radius or 30) + halfW
                        ) then
                            hits[#hits + 1] = {
                                x = bossData.x, y = bossData.y,
                                dmg = math.max(1, math.floor(seg.dps * dmgMult)),
                                targetType = "boss",
                            }
                        end
                    end
                end
            end
        end
    end

    -- 更新结束爆炸动画
    for i = #endExplosions_, 1, -1 do
        endExplosions_[i].t = endExplosions_[i].t + dt
        if endExplosions_[i].t >= endExplosions_[i].duration then
            table.remove(endExplosions_, i)
        end
    end

    return hits
end

--- Lv5 锚点爆炸伤害计算
function M._explosionHit(cx, cy, radius, dmg, enemies, bossData)
    local results = {}
    local rSq = radius * radius
    for ei, e in ipairs(enemies) do
        if not e.dead then
            local dx = e.x - cx
            local dy = e.y - cy
            if dx * dx + dy * dy < (radius + (e.radius or 16)) ^ 2 then
                results[#results + 1] = {
                    enemyIdx = ei,
                    x = e.x, y = e.y,
                    dmg = dmg,
                    targetType = "enemy",
                }
            end
        end
    end
    if bossData and not bossData.dead then
        local dx = bossData.x - cx
        local dy = bossData.y - cy
        if dx * dx + dy * dy < (radius + (bossData.radius or 30)) ^ 2 then
            results[#results + 1] = {
                x = bossData.x, y = bossData.y,
                dmg = dmg,
                targetType = "boss",
            }
        end
    end
    return results
end

-- ═══ 辅助：线段 vs 圆碰撞 ═══

function M._segCircleIntersect(x1, y1, x2, y2, cx, cy, r)
    local dx = x2 - x1
    local dy = y2 - y1
    local fx = x1 - cx
    local fy = y1 - cy

    local lenSq = dx * dx + dy * dy
    if lenSq < 0.001 then
        return fx * fx + fy * fy <= r * r
    end

    local t = -(fx * dx + fy * dy) / lenSq
    t = math.max(0, math.min(1, t))

    local closestX = x1 + t * dx
    local closestY = y1 + t * dy
    local distX = closestX - cx
    local distY = closestY - cy

    return distX * distX + distY * distY <= r * r
end

-- ═══ 查询接口 ═══

function M.getAnchors()
    return anchors_
end

function M.getBeams()
    return beams_
end

function M.isCollecting()
    return collectingBT_ and #anchors_ > 0
end

-- ═══ 绘制 ═══

function M.draw(vg)
    if not M.isActive() then return end
    local cfg = M.getCfg()
    if not cfg then return end

    -- 1. BT收集阶段：绘制锚点和预览连线
    if #anchors_ > 0 then
        -- 预览连线（虚线效果）
        for i = 1, #anchors_ - 1 do
            local a = anchors_[i]
            local b = anchors_[i + 1]
            nvgBeginPath(vg)
            nvgMoveTo(vg, a.x, a.y)
            nvgLineTo(vg, b.x, b.y)
            nvgStrokeColor(vg, nvgRGBA(80, 200, 255, 80))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
        -- 锚点
        for _, a in ipairs(anchors_) do
            nvgBeginPath(vg)
            nvgCircle(vg, a.x, a.y, cfg.anchorRadius)
            nvgFillColor(vg, nvgRGBA(100, 220, 255, 160))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, a.x, a.y, cfg.anchorRadius * 0.5)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgFill(vg)
        end
    end

    -- 2. 光束阶段
    for _, beam in ipairs(beams_) do
        local lifeRatio = beam.remaining / beam.duration
        -- 最后0.5秒渐隐
        local fadeAlpha = math.min(1, beam.remaining / 0.5)
        -- 脉冲闪烁
        local pulse = 0.7 + 0.3 * math.sin(beam.remaining * 12)

        for _, seg in ipairs(beam.segments) do
            local w = seg.width * pulse
            local baseAlpha = fadeAlpha * 0.8

            -- 外发光
            nvgBeginPath(vg)
            nvgMoveTo(vg, seg.x1, seg.y1)
            nvgLineTo(vg, seg.x2, seg.y2)
            nvgStrokeColor(vg, nvgRGBA(80, 180, 255, math.floor(60 * baseAlpha)))
            nvgStrokeWidth(vg, w * 2.5)
            nvgStroke(vg)

            -- 主光束
            nvgBeginPath(vg)
            nvgMoveTo(vg, seg.x1, seg.y1)
            nvgLineTo(vg, seg.x2, seg.y2)
            local r, g, b_color = 100, 220, 255
            if seg.isDense then
                r, g, b_color = 180, 240, 255  -- 密集段更亮
            end
            nvgStrokeColor(vg, nvgRGBA(r, g, b_color, math.floor(200 * baseAlpha)))
            nvgStrokeWidth(vg, w)
            nvgStroke(vg)

            -- 内核高亮
            nvgBeginPath(vg)
            nvgMoveTo(vg, seg.x1, seg.y1)
            nvgLineTo(vg, seg.x2, seg.y2)
            nvgStrokeColor(vg, nvgRGBA(220, 245, 255, math.floor(150 * baseAlpha * pulse)))
            nvgStrokeWidth(vg, w * 0.4)
            nvgStroke(vg)
        end

        -- 光束上的锚点
        if beam.anchors then
            for _, a in ipairs(beam.anchors) do
                nvgBeginPath(vg)
                nvgCircle(vg, a.x, a.y, cfg.anchorRadius * 1.2)
                nvgFillColor(vg, nvgRGBA(150, 230, 255, math.floor(180 * fadeAlpha)))
                nvgFill(vg)
            end
        end
    end

    -- 3. 结束爆炸
    for _, exp in ipairs(endExplosions_) do
        local t = exp.t / exp.duration
        local expandR = exp.radius * (0.3 + 0.7 * t)
        local fadeA = 1 - t

        nvgBeginPath(vg)
        nvgCircle(vg, exp.x, exp.y, expandR)
        nvgStrokeColor(vg, nvgRGBA(100, 220, 255, math.floor(200 * fadeA)))
        nvgStrokeWidth(vg, 2 * (1 - t))
        nvgStroke(vg)

        if t < 0.4 then
            nvgBeginPath(vg)
            nvgCircle(vg, exp.x, exp.y, expandR * 0.5)
            nvgFillColor(vg, nvgRGBA(200, 240, 255, math.floor(150 * (1 - t / 0.4))))
            nvgFill(vg)
        end
    end
end

return M
