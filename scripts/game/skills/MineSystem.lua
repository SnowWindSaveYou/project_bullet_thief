-- ============================================================================
-- MineSystem.lua - C线 梦境诡雷
-- 玩家移动时自动布置地雷，敌人踩中或超时后爆炸
-- 等级 0=未解锁, 1~5 逐步增强
-- ============================================================================

local SkillState = require "game.SkillState"

local M = {}

-- ═══ 等级配置 ═══

local LEVEL_CFG = {
    [1] = {
        maxMines       = 3,        -- 同时存在上限
        placeInterval  = 4.0,      -- 布置间隔（秒）
        armTime        = 0.8,      -- 布置后激活延迟
        lifetime       = 12.0,     -- 存活时间（超时自动引爆）
        triggerRadius  = 28,       -- 敌人踩中半径
        explodeRadius  = 50,       -- 爆炸伤害半径
        baseDmg        = 8,        -- 基础伤害
        mineRadius     = 6,        -- 视觉显示半径
    },
    [2] = {
        maxMines       = 5,
        placeInterval  = 3.0,
        armTime        = 0.6,
        lifetime       = 14.0,
        triggerRadius  = 32,
        explodeRadius  = 65,
        baseDmg        = 12,
        mineRadius     = 7,
    },
    [3] = {
        maxMines       = 6,
        placeInterval  = 2.5,
        armTime        = 0.5,
        lifetime       = 16.0,
        triggerRadius  = 36,
        explodeRadius  = 75,
        baseDmg        = 16,
        mineRadius     = 7,
        chainRadius    = 80,       -- 连锁引爆范围
    },
    [4] = {
        maxMines       = 8,
        placeInterval  = 2.0,
        armTime        = 0.4,
        lifetime       = 18.0,
        triggerRadius  = 40,
        explodeRadius  = 90,
        baseDmg        = 22,
        mineRadius     = 8,
        chainRadius    = 90,
        slowFactor     = 0.5,      -- 爆炸后减速倍率
        slowDuration   = 1.5,      -- 减速持续时间
    },
    [5] = {
        maxMines       = 10,
        placeInterval  = 1.5,
        armTime        = 0.3,
        lifetime       = 20.0,
        triggerRadius  = 44,
        explodeRadius  = 110,
        baseDmg        = 30,
        mineRadius     = 9,
        chainRadius    = 100,
        slowFactor     = 0.4,
        slowDuration   = 2.0,
        lingerDmg      = 4,        -- 爆炸后残留区域每秒伤害
        lingerDuration = 3.0,      -- 残留区域持续时间
        lingerRadius   = 60,       -- 残留区域半径
    },
}

-- ═══ 状态 ═══

local mines_ = {}           -- 已布置的地雷列表
local explosions_ = {}      -- 爆炸视觉效果列表
local lingerZones_ = {}     -- Lv5 残留伤害区域
local placeTimer_ = 0       -- 布置冷却计时
local lastPlayerX_ = 0
local lastPlayerY_ = 0
local moveAccum_ = 0        -- 移动距离累积（需移动才布雷）

-- ═══ 常量 ═══
local MIN_MOVE_DIST = 20    -- 至少移动这个距离才布置下一颗

-- ═══ 核心接口 ═══

function M.init()
    M.reset()
end

function M.reset()
    mines_ = {}
    explosions_ = {}
    lingerZones_ = {}
    placeTimer_ = 0
    lastPlayerX_ = 0
    lastPlayerY_ = 0
    moveAccum_ = 0
end

--- 获取当前等级配置，未解锁返回 nil
---@return table|nil
function M.getCfg()
    local level = SkillState.getLevel("mine")
    if level < 1 then return nil end
    return LEVEL_CFG[math.min(level, 5)]
end

--- 每帧更新
---@param dt number
---@param playerX number
---@param playerY number
---@param enemies table[] EnemyMgr.getEnemies()
---@param bossData table|nil BossMgr.getBoss() (nil if inactive)
---@return table hits { {x, y, dmg, radius, slow, enemyIndices, hitBoss} ... }
function M.update(dt, playerX, playerY, enemies, bossData)
    local cfg = M.getCfg()
    if not cfg then return {} end

    local hits = {}

    -- 1. 累积移动距离
    local dx = playerX - lastPlayerX_
    local dy = playerY - lastPlayerY_
    local moveDist = math.sqrt(dx * dx + dy * dy)
    if moveDist < 200 then  -- 防止 teleport 误算
        moveAccum_ = moveAccum_ + moveDist
    end
    lastPlayerX_ = playerX
    lastPlayerY_ = playerY

    -- 2. 布置地雷
    placeTimer_ = placeTimer_ + dt
    if placeTimer_ >= cfg.placeInterval and moveAccum_ >= MIN_MOVE_DIST then
        placeTimer_ = 0
        moveAccum_ = 0
        if #mines_ < cfg.maxMines then
            mines_[#mines_ + 1] = {
                x = playerX,
                y = playerY,
                age = 0,
                armed = false,
                armTime = cfg.armTime,
                lifetime = cfg.lifetime,
                alpha = 0,  -- 渐显动画
            }
        end
    end

    -- 3. 更新地雷状态
    local toExplode = {}  -- 索引列表

    for i = #mines_, 1, -1 do
        local m = mines_[i]
        m.age = m.age + dt

        -- 渐显
        if m.alpha < 1 then
            m.alpha = math.min(1, m.alpha + dt * 3)
        end

        -- 激活
        if not m.armed and m.age >= m.armTime then
            m.armed = true
        end

        -- 超时引爆
        if m.age >= m.lifetime then
            toExplode[#toExplode + 1] = i
            goto continue_mine
        end

        -- 触发检测（仅已激活）
        if m.armed then
            local triggered = false
            -- vs enemies
            for _, e in ipairs(enemies) do
                if not e.dead then
                    local ex = e.x - m.x
                    local ey = e.y - m.y
                    local distSq = ex * ex + ey * ey
                    local r = cfg.triggerRadius + (e.radius or 16)
                    if distSq < r * r then
                        triggered = true
                        break
                    end
                end
            end
            -- vs Boss
            if not triggered and bossData and not bossData.dead then
                local bx = bossData.x - m.x
                local by = bossData.y - m.y
                local distSq = bx * bx + by * by
                local r = cfg.triggerRadius + (bossData.radius or 30)
                if distSq < r * r then
                    triggered = true
                end
            end

            if triggered then
                toExplode[#toExplode + 1] = i
            end
        end

        ::continue_mine::
    end

    -- 4. 处理爆炸（含连锁）
    local explodedSet = {}  -- 用 set 防重复
    local explodeQueue = {}
    for _, idx in ipairs(toExplode) do
        if not explodedSet[idx] then
            explodedSet[idx] = true
            explodeQueue[#explodeQueue + 1] = idx
        end
    end

    -- 连锁扩展
    if cfg.chainRadius then
        local queuePos = 1
        while queuePos <= #explodeQueue do
            local idx = explodeQueue[queuePos]
            queuePos = queuePos + 1
            local m = mines_[idx]
            if m then
                for j = 1, #mines_ do
                    if not explodedSet[j] and mines_[j].armed then
                        local cx = mines_[j].x - m.x
                        local cy = mines_[j].y - m.y
                        if cx * cx + cy * cy < cfg.chainRadius * cfg.chainRadius then
                            explodedSet[j] = true
                            explodeQueue[#explodeQueue + 1] = j
                        end
                    end
                end
            end
        end
    end

    -- 按索引降序排列以安全移除
    table.sort(explodeQueue, function(a, b) return a > b end)

    for _, idx in ipairs(explodeQueue) do
        local m = mines_[idx]
        if m then
            local hit = M._explodeMine(m, cfg, enemies, bossData)
            hits[#hits + 1] = hit

            -- 创建爆炸视觉
            explosions_[#explosions_ + 1] = {
                x = m.x, y = m.y,
                radius = cfg.explodeRadius,
                maxRadius = cfg.explodeRadius,
                t = 0,
                duration = 0.4,
            }

            -- Lv5 残留区域
            if cfg.lingerDmg then
                lingerZones_[#lingerZones_ + 1] = {
                    x = m.x, y = m.y,
                    radius = cfg.lingerRadius,
                    dmgPerSec = cfg.lingerDmg,
                    remaining = cfg.lingerDuration,
                    tickTimer = 0,
                }
            end

            table.remove(mines_, idx)
        end
    end

    -- 5. 更新爆炸动画
    for i = #explosions_, 1, -1 do
        local exp = explosions_[i]
        exp.t = exp.t + dt
        if exp.t >= exp.duration then
            table.remove(explosions_, i)
        end
    end

    -- 6. 更新残留区域 & 造成持续伤害
    for i = #lingerZones_, 1, -1 do
        local zone = lingerZones_[i]
        zone.remaining = zone.remaining - dt
        if zone.remaining <= 0 then
            table.remove(lingerZones_, i)
        else
            zone.tickTimer = zone.tickTimer + dt
            if zone.tickTimer >= 0.5 then  -- 每 0.5 秒一次 tick
                zone.tickTimer = zone.tickTimer - 0.5
                local dmg = math.floor(zone.dmgPerSec * 0.5)
                -- 收集在范围内的目标
                local lingerHit = {
                    x = zone.x, y = zone.y,
                    dmg = dmg,
                    radius = zone.radius,
                    enemyIndices = {},
                    hitBoss = false,
                    isLinger = true,
                }
                for ei, e in ipairs(enemies) do
                    if not e.dead then
                        local ex = e.x - zone.x
                        local ey = e.y - zone.y
                        if ex * ex + ey * ey < (zone.radius + (e.radius or 16)) ^ 2 then
                            lingerHit.enemyIndices[#lingerHit.enemyIndices + 1] = ei
                        end
                    end
                end
                if bossData and not bossData.dead then
                    local bx = bossData.x - zone.x
                    local by = bossData.y - zone.y
                    if bx * bx + by * by < (zone.radius + (bossData.radius or 30)) ^ 2 then
                        lingerHit.hitBoss = true
                    end
                end
                if #lingerHit.enemyIndices > 0 or lingerHit.hitBoss then
                    hits[#hits + 1] = lingerHit
                end
            end
        end
    end

    return hits
end

--- 单颗地雷爆炸：计算范围内命中
---@return table hit
function M._explodeMine(mine, cfg, enemies, bossData)
    local hit = {
        x = mine.x,
        y = mine.y,
        dmg = cfg.baseDmg,
        radius = cfg.explodeRadius,
        slow = cfg.slowFactor and { factor = cfg.slowFactor, duration = cfg.slowDuration } or nil,
        enemyIndices = {},
        hitBoss = false,
        isLinger = false,
    }

    local rSq = cfg.explodeRadius * cfg.explodeRadius
    for ei, e in ipairs(enemies) do
        if not e.dead then
            local ex = e.x - mine.x
            local ey = e.y - mine.y
            if ex * ex + ey * ey < (cfg.explodeRadius + (e.radius or 16)) ^ 2 then
                hit.enemyIndices[#hit.enemyIndices + 1] = ei
            end
        end
    end

    if bossData and not bossData.dead then
        local bx = bossData.x - mine.x
        local by = bossData.y - mine.y
        if bx * bx + by * by < (cfg.explodeRadius + (bossData.radius or 30)) ^ 2 then
            hit.hitBoss = true
        end
    end

    return hit
end

-- ═══ 查询接口 ═══

function M.getMines()
    return mines_
end

function M.getExplosions()
    return explosions_
end

function M.getLingerZones()
    return lingerZones_
end

function M.isActive()
    return SkillState.getLevel("mine") >= 1
end

-- ═══ 绘制 ═══

function M.draw(vg)
    if not M.isActive() then return end
    local cfg = M.getCfg()
    if not cfg then return end

    -- 绘制残留区域（底层）
    for _, zone in ipairs(lingerZones_) do
        local fadeAlpha = math.min(1, zone.remaining / 0.5)  -- 最后 0.5 秒渐隐
        local pulse = 0.3 + 0.15 * math.sin(zone.remaining * 6)
        nvgBeginPath(vg)
        nvgCircle(vg, zone.x, zone.y, zone.radius)
        nvgFillColor(vg, nvgRGBA(180, 50, 220, math.floor(pulse * fadeAlpha * 255)))
        nvgFill(vg)
        -- 边缘线
        nvgBeginPath(vg)
        nvgCircle(vg, zone.x, zone.y, zone.radius)
        nvgStrokeColor(vg, nvgRGBA(220, 80, 255, math.floor(0.5 * fadeAlpha * 255)))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end

    -- 绘制地雷
    for _, m in ipairs(mines_) do
        local alpha = m.alpha
        local r = cfg.mineRadius

        -- 脉冲呼吸动画
        local breathe = 1 + 0.15 * math.sin(m.age * 3)
        local drawR = r * breathe

        if m.armed then
            -- 已激活：紫色发光
            nvgBeginPath(vg)
            nvgCircle(vg, m.x, m.y, drawR * 2)
            nvgFillColor(vg, nvgRGBA(160, 40, 220, math.floor(30 * alpha)))
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgCircle(vg, m.x, m.y, drawR)
            nvgFillColor(vg, nvgRGBA(200, 60, 255, math.floor(200 * alpha)))
            nvgFill(vg)

            -- 内核
            nvgBeginPath(vg)
            nvgCircle(vg, m.x, m.y, drawR * 0.5)
            nvgFillColor(vg, nvgRGBA(255, 180, 255, math.floor(255 * alpha)))
            nvgFill(vg)
        else
            -- 未激活：灰色半透明
            nvgBeginPath(vg)
            nvgCircle(vg, m.x, m.y, drawR)
            nvgFillColor(vg, nvgRGBA(120, 120, 140, math.floor(150 * alpha)))
            nvgFill(vg)
        end
    end

    -- 绘制爆炸效果
    for _, exp in ipairs(explosions_) do
        local t = exp.t / exp.duration  -- 0~1
        local expandR = exp.maxRadius * (0.3 + 0.7 * t)
        local fadeAlpha = 1 - t

        -- 外圈冲击波
        nvgBeginPath(vg)
        nvgCircle(vg, exp.x, exp.y, expandR)
        nvgStrokeColor(vg, nvgRGBA(255, 120, 255, math.floor(200 * fadeAlpha)))
        nvgStrokeWidth(vg, 3 * (1 - t))
        nvgStroke(vg)

        -- 内圈填充
        nvgBeginPath(vg)
        nvgCircle(vg, exp.x, exp.y, expandR * 0.6)
        nvgFillColor(vg, nvgRGBA(255, 200, 255, math.floor(120 * fadeAlpha)))
        nvgFill(vg)

        -- 中心闪光
        if t < 0.3 then
            local flashA = (1 - t / 0.3)
            nvgBeginPath(vg)
            nvgCircle(vg, exp.x, exp.y, 12 * (1 - t))
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * flashA)))
            nvgFill(vg)
        end
    end
end

return M
