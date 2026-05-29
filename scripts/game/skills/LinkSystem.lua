-- ============================================================================
-- LinkSystem.lua - D线 梦境连线
-- 击杀敌人时，在死亡位置留下"梦痕节点"，节点间形成连线
-- 敌人穿越连线时受到伤害
-- 等级 0=未解锁, 1~5 逐步增强
-- ============================================================================

local SkillState = require "game.SkillState"

local M = {}

-- ═══ 等级配置 ═══

local LEVEL_CFG = {
    [1] = {
        maxNodes       = 4,        -- 同时存在的节点上限
        nodeDuration   = 6.0,      -- 节点存活时间
        linkRange      = 120,      -- 连线最大距离（超出则不连）
        linkDmg        = 5,        -- 穿越连线的伤害
        nodeRadius     = 5,        -- 节点视觉半径
        hitCooldown    = 0.8,      -- 同一敌人两次触线间隔
    },
    [2] = {
        maxNodes       = 6,
        nodeDuration   = 8.0,
        linkRange      = 140,
        linkDmg        = 8,
        nodeRadius     = 6,
        hitCooldown    = 0.7,
    },
    [3] = {
        maxNodes       = 8,
        nodeDuration   = 10.0,
        linkRange      = 160,
        linkDmg        = 12,
        nodeRadius     = 6,
        hitCooldown    = 0.6,
        slowFactor     = 0.6,      -- 穿越连线减速
        slowDuration   = 1.0,
    },
    [4] = {
        maxNodes       = 10,
        nodeDuration   = 12.0,
        linkRange      = 180,
        linkDmg        = 18,
        nodeRadius     = 7,
        hitCooldown    = 0.5,
        slowFactor     = 0.5,
        slowDuration   = 1.5,
        chainDmgMult   = 1.3,      -- 连续穿越多条线伤害递增
    },
    [5] = {
        maxNodes       = 12,
        nodeDuration   = 15.0,
        linkRange      = 200,
        linkDmg        = 25,
        nodeRadius     = 7,
        hitCooldown    = 0.4,
        slowFactor     = 0.4,
        slowDuration   = 2.0,
        chainDmgMult   = 1.5,
        snapOnKill     = true,     -- 击杀时爆发连线能量，对连线上所有敌人造成额外伤害
        snapDmg        = 15,
    },
}

-- ═══ 状态 ═══

local nodes_ = {}           -- 梦痕节点列表 { x, y, age, id }
local links_ = {}           -- 已建立的连线缓存（每帧重新计算）
local nodeIdCounter_ = 0    -- 节点 ID 计数器
local hitCooldowns_ = {}    -- [enemyIdx][linkKey] = remaining cooldown
local flashEffects_ = {}    -- 触线闪光效果

-- ═══ 核心接口 ═══

function M.init()
    M.reset()
end

function M.reset()
    nodes_ = {}
    links_ = {}
    nodeIdCounter_ = 0
    hitCooldowns_ = {}
    flashEffects_ = {}
end

--- 获取当前等级配置，未解锁返回 nil
---@return table|nil
function M.getCfg()
    local level = SkillState.getLevel("link")
    if level < 1 then return nil end
    return LEVEL_CFG[math.min(level, 5)]
end

function M.isActive()
    return SkillState.getLevel("link") >= 1
end

--- 当击杀敌人时调用，在死亡位置创建梦痕节点
---@param x number
---@param y number
function M.onEnemyKilled(x, y)
    local cfg = M.getCfg()
    if not cfg then return end

    nodeIdCounter_ = nodeIdCounter_ + 1
    nodes_[#nodes_ + 1] = {
        x = x,
        y = y,
        age = 0,
        id = nodeIdCounter_,
        alpha = 0,  -- 渐显
    }

    -- 超出上限，移除最旧的
    while #nodes_ > cfg.maxNodes do
        table.remove(nodes_, 1)
    end
end

--- 每帧更新：老化节点、计算连线、检测敌人穿越
---@param dt number
---@param enemies table[] EnemyMgr.getEnemies()
---@param bossData table|nil
---@return table hits { {enemyIdx, x, y, dmg, slow} ... }
function M.update(dt, enemies, bossData)
    local cfg = M.getCfg()
    if not cfg then return {} end

    local hits = {}

    -- 1. 更新节点（老化 + 渐显）
    for i = #nodes_, 1, -1 do
        local n = nodes_[i]
        n.age = n.age + dt
        if n.alpha < 1 then
            n.alpha = math.min(1, n.alpha + dt * 4)
        end
        if n.age >= cfg.nodeDuration then
            table.remove(nodes_, i)
        end
    end

    -- 2. 重建连线（相邻节点在范围内则连）
    links_ = {}
    local rangeSq = cfg.linkRange * cfg.linkRange
    for i = 1, #nodes_ do
        for j = i + 1, #nodes_ do
            local a = nodes_[i]
            local b = nodes_[j]
            local dx = b.x - a.x
            local dy = b.y - a.y
            if dx * dx + dy * dy <= rangeSq then
                links_[#links_ + 1] = {
                    x1 = a.x, y1 = a.y,
                    x2 = b.x, y2 = b.y,
                    idA = a.id, idB = b.id,
                    -- 视觉用
                    alphaA = a.alpha, alphaB = b.alpha,
                }
            end
        end
    end

    -- 3. 清理过期的 hit cooldown
    for ei, cds in pairs(hitCooldowns_) do
        for key, rem in pairs(cds) do
            cds[key] = rem - dt
            if cds[key] <= 0 then
                cds[key] = nil
            end
        end
        -- 清理空表
        if not next(cds) then
            hitCooldowns_[ei] = nil
        end
    end

    -- 4. 检测敌人与连线碰撞
    for _, link in ipairs(links_) do
        local linkKey = link.idA .. "_" .. link.idB

        -- vs enemies
        for ei, e in ipairs(enemies) do
            if not e.dead then
                if M._segCircleIntersect(link.x1, link.y1, link.x2, link.y2, e.x, e.y, e.radius or 16) then
                    -- 检查冷却
                    if not hitCooldowns_[ei] or not hitCooldowns_[ei][linkKey] then
                        -- 命中！
                        if not hitCooldowns_[ei] then hitCooldowns_[ei] = {} end
                        hitCooldowns_[ei][linkKey] = cfg.hitCooldown

                        -- 计算伤害（连续触线加成）
                        local dmg = cfg.linkDmg
                        if cfg.chainDmgMult then
                            -- 统计该敌人当前有多少条线在冷却中
                            local chainCount = 0
                            for _ in pairs(hitCooldowns_[ei]) do chainCount = chainCount + 1 end
                            if chainCount > 1 then
                                dmg = math.floor(dmg * cfg.chainDmgMult)
                            end
                        end

                        hits[#hits + 1] = {
                            enemyIdx = ei,
                            x = e.x,
                            y = e.y,
                            dmg = dmg,
                            slow = cfg.slowFactor and { factor = cfg.slowFactor, duration = cfg.slowDuration } or nil,
                            targetType = "enemy",
                        }

                        -- 闪光效果
                        flashEffects_[#flashEffects_ + 1] = {
                            x1 = link.x1, y1 = link.y1,
                            x2 = link.x2, y2 = link.y2,
                            t = 0, duration = 0.25,
                        }
                    end
                end
            end
        end

        -- vs Boss
        if bossData and not bossData.dead then
            local bossKey = "boss_" .. linkKey
            if M._segCircleIntersect(link.x1, link.y1, link.x2, link.y2, bossData.x, bossData.y, bossData.radius or 30) then
                if not hitCooldowns_[-1] or not hitCooldowns_[-1][bossKey] then
                    if not hitCooldowns_[-1] then hitCooldowns_[-1] = {} end
                    hitCooldowns_[-1][bossKey] = cfg.hitCooldown

                    hits[#hits + 1] = {
                        x = bossData.x,
                        y = bossData.y,
                        dmg = cfg.linkDmg,
                        targetType = "boss",
                    }

                    flashEffects_[#flashEffects_ + 1] = {
                        x1 = link.x1, y1 = link.y1,
                        x2 = link.x2, y2 = link.y2,
                        t = 0, duration = 0.25,
                    }
                end
            end
        end
    end

    -- 5. 更新闪光动画
    for i = #flashEffects_, 1, -1 do
        flashEffects_[i].t = flashEffects_[i].t + dt
        if flashEffects_[i].t >= flashEffects_[i].duration then
            table.remove(flashEffects_, i)
        end
    end

    return hits
end

--- Lv5 snapOnKill：击杀时连线能量爆发
--- 对连线上所有敌人造成额外伤害
---@param killX number 击杀位置
---@param killY number
---@param enemies table[]
---@param bossData table|nil
---@return table snapHits
function M.onSnapKill(killX, killY, enemies, bossData)
    local cfg = M.getCfg()
    if not cfg or not cfg.snapOnKill then return {} end

    local snapHits = {}

    -- 找到与击杀位置最近的节点
    local closestNode = nil
    local closestDist = math.huge
    for _, n in ipairs(nodes_) do
        local dx = n.x - killX
        local dy = n.y - killY
        local d = dx * dx + dy * dy
        if d < closestDist then
            closestDist = d
            closestNode = n
        end
    end

    if not closestNode then return {} end

    -- 找到该节点的所有连线，对连线上的敌人造成 snapDmg
    local rangeSq = cfg.linkRange * cfg.linkRange
    for _, n in ipairs(nodes_) do
        if n.id ~= closestNode.id then
            local dx = n.x - closestNode.x
            local dy = n.y - closestNode.y
            if dx * dx + dy * dy <= rangeSq then
                -- 这条线上的所有敌人
                for ei, e in ipairs(enemies) do
                    if not e.dead then
                        if M._segCircleIntersect(closestNode.x, closestNode.y, n.x, n.y, e.x, e.y, e.radius or 16) then
                            snapHits[#snapHits + 1] = {
                                enemyIdx = ei,
                                x = e.x, y = e.y,
                                dmg = cfg.snapDmg,
                                targetType = "enemy",
                            }
                        end
                    end
                end
                -- Boss
                if bossData and not bossData.dead then
                    if M._segCircleIntersect(closestNode.x, closestNode.y, n.x, n.y, bossData.x, bossData.y, bossData.radius or 30) then
                        snapHits[#snapHits + 1] = {
                            x = bossData.x, y = bossData.y,
                            dmg = cfg.snapDmg,
                            targetType = "boss",
                        }
                    end
                end

                -- 视觉闪光
                flashEffects_[#flashEffects_ + 1] = {
                    x1 = closestNode.x, y1 = closestNode.y,
                    x2 = n.x, y2 = n.y,
                    t = 0, duration = 0.35,
                }
            end
        end
    end

    return snapHits
end

-- ═══ 辅助：线段 vs 圆碰撞 ═══

--- 判断线段(x1,y1)-(x2,y2)是否与圆(cx,cy,r)相交
function M._segCircleIntersect(x1, y1, x2, y2, cx, cy, r)
    local dx = x2 - x1
    local dy = y2 - y1
    local fx = x1 - cx
    local fy = y1 - cy

    local lenSq = dx * dx + dy * dy
    if lenSq < 0.001 then
        -- 退化为点
        return fx * fx + fy * fy <= r * r
    end

    -- 投影参数
    local t = -(fx * dx + fy * dy) / lenSq
    t = math.max(0, math.min(1, t))

    local closestX = x1 + t * dx
    local closestY = y1 + t * dy
    local distX = closestX - cx
    local distY = closestY - cy

    return distX * distX + distY * distY <= r * r
end

-- ═══ 查询接口 ═══

function M.getNodes()
    return nodes_
end

function M.getLinks()
    return links_
end

-- ═══ 绘制 ═══

function M.draw(vg)
    if not M.isActive() then return end
    local cfg = M.getCfg()
    if not cfg then return end

    -- 绘制连线（底层）
    for _, link in ipairs(links_) do
        local alpha = math.min(link.alphaA, link.alphaB)
        nvgBeginPath(vg)
        nvgMoveTo(vg, link.x1, link.y1)
        nvgLineTo(vg, link.x2, link.y2)
        nvgStrokeColor(vg, nvgRGBA(80, 200, 255, math.floor(120 * alpha)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 内发光线
        nvgBeginPath(vg)
        nvgMoveTo(vg, link.x1, link.y1)
        nvgLineTo(vg, link.x2, link.y2)
        nvgStrokeColor(vg, nvgRGBA(150, 230, 255, math.floor(60 * alpha)))
        nvgStrokeWidth(vg, 4)
        nvgStroke(vg)
    end

    -- 绘制闪光效果
    for _, f in ipairs(flashEffects_) do
        local t = f.t / f.duration
        local flashA = 1 - t
        nvgBeginPath(vg)
        nvgMoveTo(vg, f.x1, f.y1)
        nvgLineTo(vg, f.x2, f.y2)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * flashA)))
        nvgStrokeWidth(vg, 4 * (1 - t * 0.5))
        nvgStroke(vg)
    end

    -- 绘制节点
    for _, n in ipairs(nodes_) do
        local alpha = n.alpha
        local r = cfg.nodeRadius

        -- 渐隐：最后 2 秒
        local fadeStart = cfg.nodeDuration - 2
        if n.age > fadeStart then
            alpha = alpha * (1 - (n.age - fadeStart) / 2)
        end

        -- 外圈发光
        nvgBeginPath(vg)
        nvgCircle(vg, n.x, n.y, r * 2.5)
        nvgFillColor(vg, nvgRGBA(80, 200, 255, math.floor(25 * alpha)))
        nvgFill(vg)

        -- 节点核心
        nvgBeginPath(vg)
        nvgCircle(vg, n.x, n.y, r)
        nvgFillColor(vg, nvgRGBA(100, 220, 255, math.floor(200 * alpha)))
        nvgFill(vg)

        -- 内核
        nvgBeginPath(vg)
        nvgCircle(vg, n.x, n.y, r * 0.4)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(220 * alpha)))
        nvgFill(vg)

        -- 脉冲环
        local pulseR = r * (1.5 + 0.5 * math.sin(n.age * 4))
        nvgBeginPath(vg)
        nvgCircle(vg, n.x, n.y, pulseR)
        nvgStrokeColor(vg, nvgRGBA(100, 220, 255, math.floor(80 * alpha)))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end
end

return M
