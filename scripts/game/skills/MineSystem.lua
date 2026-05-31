-- ============================================================================
-- MineSystem.lua - C线 梦境诡雷
-- BT 期间夺取子弹时，概率在被夺子弹原位布雷
-- 地雷被敌人踩中后引爆；玩家经过已有地雷可叠加层数(+伤害/+范围)
-- 等级 0=未解锁, 1~5 逐步增强
-- ============================================================================

local SkillState = require "game.SkillState"
local ConfigLoader = require "config.ConfigLoader"

local M = {}

-- ═══ 等级配置（从 JSON 加载） ═══

local LEVEL_CFG = nil  -- 延迟初始化

--- 从 protagonist.json 加载地雷等级配置
local function loadLevelCfg()
    if LEVEL_CFG then return LEVEL_CFG end

    local data = ConfigLoader.load("config/characters/protagonist.json")
    if data and data.skills and data.skills.mine and data.skills.mine.levels then
        LEVEL_CFG = {}
        for k, v in pairs(data.skills.mine.levels) do
            LEVEL_CFG[tonumber(k)] = v
        end
        print("[MineSystem] 从 JSON 加载 " .. #LEVEL_CFG .. " 个等级配置")
    end

    -- 兜底默认值
    if not LEVEL_CFG or #LEVEL_CFG == 0 then
        print("[MineSystem] WARN: JSON 加载失败，使用内置默认值")
        LEVEL_CFG = {
            [1] = { placeChance = 0.60, maxMines = 5, armTime = 0.6, lifetime = 15.0, triggerRadius = 28, explodeRadius = 50, baseDmg = 8, mineRadius = 6, stackChance = 0, stackBonusDmg = 0, stackBonusRadius = 0 },
            [2] = { placeChance = 0.65, maxMines = 7, armTime = 0.5, lifetime = 16.0, triggerRadius = 32, explodeRadius = 60, baseDmg = 12, mineRadius = 7, stackChance = 0.3, stackBonusDmg = 4, stackBonusRadius = 8, maxStack = 2 },
            [3] = { placeChance = 0.70, maxMines = 8, armTime = 0.4, lifetime = 18.0, triggerRadius = 36, explodeRadius = 70, baseDmg = 16, mineRadius = 7, stackChance = 0.4, stackBonusDmg = 5, stackBonusRadius = 10, maxStack = 3, chainRadius = 80 },
            [4] = { placeChance = 0.75, maxMines = 10, armTime = 0.3, lifetime = 20.0, triggerRadius = 40, explodeRadius = 85, baseDmg = 22, mineRadius = 8, stackChance = 0.5, stackBonusDmg = 6, stackBonusRadius = 12, maxStack = 4, chainRadius = 90, slowFactor = 0.5, slowDuration = 1.5 },
            [5] = { placeChance = 0.80, maxMines = 12, armTime = 0.2, lifetime = 22.0, triggerRadius = 44, explodeRadius = 100, baseDmg = 30, mineRadius = 9, stackChance = 0.6, stackBonusDmg = 8, stackBonusRadius = 15, maxStack = 5, chainRadius = 100, slowFactor = 0.4, slowDuration = 2.0, lingerDmg = 4, lingerDuration = 3.0, lingerRadius = 55 },
        }
    end
    return LEVEL_CFG
end

-- ═══ 状态 ═══

local mines_ = {}           -- 已布置的地雷 { x, y, age, armed, stacks, alpha, ... }
local explosions_ = {}      -- 爆炸视觉效果
local lingerZones_ = {}     -- Lv5 残留伤害区域
local petals_ = {}          -- 花瓣飞散粒子 { x, y, vx, vy, rot, rotSpeed, size, age, lifetime, colorIdx }

-- ═══ 常量 ═══
local STACK_TRIGGER_RADIUS = 24   -- 玩家经过这个距离内的地雷可叠加

-- ═══ 核心接口 ═══

function M.init()
    M.reset()
end

function M.reset()
    mines_ = {}
    explosions_ = {}
    lingerZones_ = {}
    petals_ = {}
end

--- 获取当前等级配置，未解锁返回 nil
---@return table|nil
function M.getCfg()
    local level = SkillState.getLevel("mine")
    if level < 1 then return nil end
    local cfg = loadLevelCfg()
    return cfg[math.min(level, 5)]
end

function M.isActive()
    return SkillState.getLevel("mine") >= 1
end

--- BT期间夺取子弹时调用 —— 概率在子弹原位布雷
---@param bulletX number 被夺子弹的原始位置
---@param bulletY number
function M.onBulletStolen(bulletX, bulletY)
    local cfg = M.getCfg()
    if not cfg then return end

    -- 概率判定
    if math.random() > cfg.placeChance then return end

    -- 上限检查
    if #mines_ >= cfg.maxMines then
        -- 移除最旧的
        table.remove(mines_, 1)
    end

    mines_[#mines_ + 1] = {
        x = bulletX,
        y = bulletY,
        age = 0,
        armed = false,
        armTime = cfg.armTime,
        lifetime = cfg.lifetime,
        stacks = 1,
        alpha = 0,
    }
end

--- 每帧更新：老化地雷、检测敌人踩中、玩家叠加
---@param dt number
---@param playerX number
---@param playerY number
---@param enemies table[]
---@param bossData table|nil
---@return table hits { {x, y, dmg, radius, slow, enemyIndices, hitBoss, isLinger} ... }
function M.update(dt, playerX, playerY, enemies, bossData)
    local cfg = M.getCfg()
    if not cfg then return {} end

    local hits = {}

    -- 1. 玩家叠加检测（经过已有地雷时概率+1层）
    if cfg.stackChance and cfg.stackChance > 0 then
        for _, m in ipairs(mines_) do
            if m.armed then
                local dx = playerX - m.x
                local dy = playerY - m.y
                if dx * dx + dy * dy < STACK_TRIGGER_RADIUS * STACK_TRIGGER_RADIUS then
                    -- 每次经过只判定一次（用 stackCooldown 防连续触发）
                    if not m.stackCooldown or m.stackCooldown <= 0 then
                        if math.random() < cfg.stackChance then
                            local maxS = cfg.maxStack or 99
                            if m.stacks < maxS then
                                m.stacks = m.stacks + 1
                                m.stackCooldown = 1.0  -- 1秒内不再叠加
                            end
                        else
                            m.stackCooldown = 0.5
                        end
                    end
                end
            end
        end
    end

    -- 2. 更新地雷状态
    local toExplode = {}

    for i = #mines_, 1, -1 do
        local m = mines_[i]
        m.age = m.age + dt

        -- 叠加冷却
        if m.stackCooldown and m.stackCooldown > 0 then
            m.stackCooldown = m.stackCooldown - dt
        end

        -- 渐显
        if m.alpha < 1 then
            m.alpha = math.min(1, m.alpha + dt * 3)
        end

        -- 激活
        if not m.armed and m.age >= m.armTime then
            m.armed = true
        end

        -- 超时消散（不爆炸）
        if m.age >= m.lifetime then
            table.remove(mines_, i)
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

    -- 3. 处理爆炸（含连锁）
    local explodedSet = {}
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

            -- 爆炸视觉
            explosions_[#explosions_ + 1] = {
                x = m.x, y = m.y,
                radius = hit.radius,
                maxRadius = hit.radius,
                stacks = m.stacks,
                t = 0,
                duration = 0.5,
            }

            -- 花瓣飞散粒子
            M._spawnPetals(m.x, m.y, m.stacks or 1, hit.radius)

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

    -- 4. 更新爆炸动画
    for i = #explosions_, 1, -1 do
        local exp = explosions_[i]
        exp.t = exp.t + dt
        if exp.t >= exp.duration then
            table.remove(explosions_, i)
        end
    end

    -- 4.5 更新花瓣飞散粒子
    M.updatePetals(dt)

    -- 5. 残留区域 tick
    for i = #lingerZones_, 1, -1 do
        local zone = lingerZones_[i]
        zone.remaining = zone.remaining - dt
        if zone.remaining <= 0 then
            table.remove(lingerZones_, i)
        else
            zone.tickTimer = zone.tickTimer + dt
            if zone.tickTimer >= 0.5 then
                zone.tickTimer = zone.tickTimer - 0.5
                local dmg = math.floor(zone.dmgPerSec * 0.5)
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

--- 单颗地雷爆炸：计算叠加后的伤害和范围
---@return table hit
function M._explodeMine(mine, cfg, enemies, bossData)
    local stacks = mine.stacks or 1
    local dmg = cfg.baseDmg + (stacks - 1) * (cfg.stackBonusDmg or 0)
    local radius = cfg.explodeRadius + (stacks - 1) * (cfg.stackBonusRadius or 0)

    local hit = {
        x = mine.x,
        y = mine.y,
        dmg = dmg,
        radius = radius,
        slow = cfg.slowFactor and { factor = cfg.slowFactor, duration = cfg.slowDuration } or nil,
        enemyIndices = {},
        hitBoss = false,
        isLinger = false,
        stacks = stacks,
    }

    for ei, e in ipairs(enemies) do
        if not e.dead then
            local ex = e.x - mine.x
            local ey = e.y - mine.y
            if ex * ex + ey * ey < (radius + (e.radius or 16)) ^ 2 then
                hit.enemyIndices[#hit.enemyIndices + 1] = ei
            end
        end
    end

    if bossData and not bossData.dead then
        local bx = bossData.x - mine.x
        local by = bossData.y - mine.y
        if bx * bx + by * by < (radius + (bossData.radius or 30)) ^ 2 then
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

-- ═══ 绘制辅助 ═══

--- 绘制圆角花瓣（椭圆形，更干净的卡通造型）
local function drawPetal(vg, cx, cy, size, rotation, r, g, b, a)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, rotation)
    nvgBeginPath(vg)
    -- 椭圆形花瓣：宽扁、顶端略尖
    nvgEllipse(vg, 0, -size * 0.45, size * 0.38, size * 0.55)
    nvgFillColor(vg, nvgRGBA(r, g, b, a))
    nvgFill(vg)
    nvgRestore(vg)
end

--- 绘制花蕾（闭合状态）—— 简洁水滴形，青色系
local function drawBudClosed(vg, cx, cy, size, sway, alpha)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, sway * 0.04)

    -- 花茎
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, size * 0.3)
    nvgLineTo(vg, 0, size * 1.2)
    nvgStrokeColor(vg, nvgRGBA(40, 140, 140, math.floor(200 * alpha)))
    nvgStrokeWidth(vg, 1.8)
    nvgStroke(vg)

    -- 两片小叶子（青绿色）
    nvgBeginPath(vg)
    nvgEllipse(vg, -size * 0.35, size * 0.7, size * 0.25, size * 0.12)
    nvgFillColor(vg, nvgRGBA(50, 160, 150, math.floor(160 * alpha)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgEllipse(vg, size * 0.3, size * 0.9, size * 0.22, size * 0.1)
    nvgFillColor(vg, nvgRGBA(45, 145, 140, math.floor(140 * alpha)))
    nvgFill(vg)

    -- 花蕾主体（深青色）
    nvgBeginPath(vg)
    nvgEllipse(vg, 0, 0, size * 0.4, size * 0.6)
    nvgFillColor(vg, nvgRGBA(30, 120, 145, math.floor(200 * alpha)))
    nvgFill(vg)

    -- 花蕾顶端亮色（暗示内部花瓣）
    nvgBeginPath(vg)
    nvgEllipse(vg, 0, -size * 0.25, size * 0.22, size * 0.2)
    nvgFillColor(vg, nvgRGBA(60, 190, 210, math.floor(160 * alpha)))
    nvgFill(vg)

    -- 顶部小尖（花蕾尖端）
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -size * 0.6)
    nvgLineTo(vg, -size * 0.08, -size * 0.35)
    nvgLineTo(vg, size * 0.08, -size * 0.35)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(50, 170, 190, math.floor(180 * alpha)))
    nvgFill(vg)

    nvgRestore(vg)
end

--- 绘制花朵（激活状态）—— 干净的卡通花，青色系
local function drawBudOpen(vg, cx, cy, size, stacks, age, alpha)
    local breathe = 1 + 0.06 * math.sin(age * 2.5)
    local petalCount = math.min(4 + stacks, 8) -- 4~8 瓣
    local drawSize = size * breathe

    -- 底层光晕（青色）
    local glowR = drawSize * (1.6 + stacks * 0.2)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, glowR)
    nvgFillColor(vg, nvgRGBA(50, 200, 230, math.floor(20 * alpha)))
    nvgFill(vg)

    -- 花茎
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy + drawSize * 0.5)
    nvgLineTo(vg, cx, cy + drawSize * 1.3)
    nvgStrokeColor(vg, nvgRGBA(40, 150, 145, math.floor(190 * alpha)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 花瓣（均匀排列的椭圆，青色交替深浅）
    local petalLen = drawSize * (0.7 + stacks * 0.04)
    local petalW   = drawSize * (0.35 + stacks * 0.02)
    local baseRot  = age * 0.4 -- 缓慢整体旋转

    for i = 1, petalCount do
        local angle = baseRot + (i / petalCount) * math.pi * 2
        -- 交替深浅青色
        local shade = (i % 2 == 0)
        local cr = shade and 60 or 40
        local cg = shade and 220 or 195
        local cb = shade and 240 or 220

        nvgSave(vg)
        nvgTranslate(vg, cx, cy)
        nvgRotate(vg, angle)
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, -petalLen * 0.55, petalW, petalLen * 0.5)
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, math.floor(200 * alpha)))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 花心（亮青白色）
    local coreR = drawSize * 0.32
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, coreR)
    nvgFillColor(vg, nvgRGBA(140, 240, 255, math.floor(240 * alpha)))
    nvgFill(vg)
    -- 花心内高光
    nvgBeginPath(vg)
    nvgCircle(vg, cx - coreR * 0.2, cy - coreR * 0.25, coreR * 0.35)
    nvgFillColor(vg, nvgRGBA(220, 255, 255, math.floor(180 * alpha)))
    nvgFill(vg)

    -- 叠加指示：花心周围旋转的小光点（暖黄保留，作为点缀对比色）
    if stacks > 1 then
        for s = 1, math.min(stacks - 1, 5) do
            local dotAngle = (s / 5) * math.pi * 2 + age * 2.5
            local dotDist = coreR + drawSize * 0.15
            local dx = cx + math.cos(dotAngle) * dotDist
            local dy = cy + math.sin(dotAngle) * dotDist
            local dotPulse = 0.6 + 0.4 * math.sin(age * 4 + s * 1.5)
            nvgBeginPath(vg)
            nvgCircle(vg, dx, dy, 1.8 * dotPulse)
            nvgFillColor(vg, nvgRGBA(255, 230, 120, math.floor(210 * alpha * dotPulse)))
            nvgFill(vg)
        end
    end
end

-- ═══ 绘制 ═══

function M.draw(vg)
    if not M.isActive() then return end
    local cfg = M.getCfg()
    if not cfg then return end

    -- 残留区域（底层）—— 寂灭霜原：地面冰晶花纹
    for _, zone in ipairs(lingerZones_) do
        local fadeAlpha = math.min(1, zone.remaining / 0.8)
        local elapsed = (zone.remaining < 3.0) and (3.0 - zone.remaining) or 0
        local R = zone.radius

        -- ① 底层：径向渐变霜冻地面（中心青→边缘透明）
        local gradR = R * (1.0 - math.max(0, 1 - zone.remaining / 0.5) * 0.3) -- 消散时缩小
        nvgBeginPath(vg)
        nvgCircle(vg, zone.x, zone.y, gradR)
        local innerA = math.floor(35 * fadeAlpha)
        local paint = nvgRadialGradient(vg, zone.x, zone.y, R * 0.1, gradR,
            nvgRGBA(40, 190, 220, innerA), nvgRGBA(30, 160, 200, 0))
        nvgFillPaint(vg, paint)
        nvgFill(vg)

        -- ② 中层：6条霜花臂（中心粗→末端细，带分叉）
        local armCount = 6
        local baseAngle = zone.remaining * 0.15  -- 极慢旋转
        nvgSave(vg)
        nvgTranslate(vg, zone.x, zone.y)
        for i = 1, armCount do
            local angle = baseAngle + (i / armCount) * math.pi * 2
            local armLen = R * (0.75 + 0.15 * math.sin(i * 2.3)) * fadeAlpha
            local cosA = math.cos(angle)
            local sinA = math.sin(angle)

            -- 主干（用多段线模拟渐细：从中心粗→末端细）
            local segments = 4
            for s = 0, segments - 1 do
                local t0 = s / segments
                local t1 = (s + 1) / segments
                local x0 = cosA * armLen * t0
                local y0 = sinA * armLen * t0
                local x1 = cosA * armLen * t1
                local y1 = sinA * armLen * t1
                local width = 2.5 * (1 - t0 * 0.8)  -- 2.5 → 0.5 渐细
                nvgBeginPath(vg)
                nvgMoveTo(vg, x0, y0)
                nvgLineTo(vg, x1, y1)
                nvgStrokeColor(vg, nvgRGBA(80, 220, 240, math.floor(90 * fadeAlpha)))
                nvgStrokeWidth(vg, width)
                nvgStroke(vg)
            end

            -- 分叉（每条臂2~3个分支，同样渐细）
            local branchCount = 2 + (i % 2)
            for b = 1, branchCount do
                local bPos = (b / (branchCount + 1))  -- 在主干上的位置 (0~1)
                local bx = cosA * armLen * bPos
                local by = sinA * armLen * bPos
                local bLen = armLen * (0.3 - b * 0.05)  -- 分支长度递减
                -- 交替分叉方向（左右）
                local bAngle = angle + (b % 2 == 0 and 0.6 or -0.6)
                local bex = bx + math.cos(bAngle) * bLen
                local bey = by + math.sin(bAngle) * bLen
                -- 分支线宽：起点较粗，终点细
                local bWidth = 1.8 * (1 - bPos * 0.6)

                nvgBeginPath(vg)
                nvgMoveTo(vg, bx, by)
                nvgLineTo(vg, bex, bey)
                nvgStrokeColor(vg, nvgRGBA(70, 210, 235, math.floor(65 * fadeAlpha)))
                nvgStrokeWidth(vg, bWidth)
                nvgStroke(vg)
            end
        end
        nvgRestore(vg)

        -- ③ 顶层：散布的冰晶闪点（沿霜花臂闪烁）
        local sparkleTime = 3.0 - zone.remaining  -- 已经存在的时间
        for i = 1, 10 do
            local seed = i * 97.3
            local sparkAngle = seed + sparkleTime * 0.3
            local sparkDist = R * (0.2 + 0.5 * math.abs(math.sin(seed * 0.47)))
            local sx = zone.x + math.cos(sparkAngle) * sparkDist
            local sy = zone.y + math.sin(sparkAngle) * sparkDist
            -- 闪烁：用 sin 波让每颗星交替明灭
            local twinkle = math.sin(sparkleTime * 5 + seed) * 0.5 + 0.5
            local sparkA = math.floor(100 * fadeAlpha * twinkle)
            if sparkA > 10 then
                local sz = 1.0 + 0.8 * math.sin(seed * 1.7)
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, sz)
                nvgFillColor(vg, nvgRGBA(180, 250, 255, sparkA))
                nvgFill(vg)
            end
        end

        -- ④ 外环：呼吸脉冲环
        local pulsePhase = math.sin(sparkleTime * 3) * 0.5 + 0.5
        local ringR = R * (0.92 + 0.08 * pulsePhase) * fadeAlpha
        nvgBeginPath(vg)
        nvgCircle(vg, zone.x, zone.y, ringR)
        nvgStrokeColor(vg, nvgRGBA(60, 200, 230, math.floor(50 * fadeAlpha * (0.5 + 0.5 * pulsePhase))))
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)
    end

    -- 地雷（花蕾）
    for _, m in ipairs(mines_) do
        local alpha = m.alpha
        local r = cfg.mineRadius
        local stacks = m.stacks or 1

        if m.armed then
            -- 已激活：半开的花蕾，随叠加层数绽放更多
            drawBudOpen(vg, m.x, m.y, r, stacks, m.age, alpha)
        else
            -- 未激活：闭合花蕾，轻微摇摆
            local sway = math.sin(m.age * 2.5) * 3
            drawBudClosed(vg, m.x, m.y, r, sway, alpha)
        end
    end

    -- 花瓣飞散粒子（青色系）
    for _, p in ipairs(petals_) do
        local lifeRatio = p.age / p.lifetime
        local fadeA = 1 - lifeRatio
        local petalColors = {
            {40, 200, 220},  -- 深青
            {80, 230, 255},  -- 亮青
            {50, 210, 235},  -- 中青
            {30, 180, 200},  -- 暗青
            {120, 245, 255}, -- 青白
        }
        local c = petalColors[((p.colorIdx - 1) % #petalColors) + 1]
        local sz = p.size * (1 - lifeRatio * 0.5) -- 逐渐缩小
        drawPetal(vg, p.x, p.y, sz, p.rot, c[1], c[2], c[3], math.floor(220 * fadeA))
    end

    -- 爆炸效果（花朵绽放，青色）
    for _, exp in ipairs(explosions_) do
        local t = exp.t / exp.duration
        local fadeAlpha = 1 - t
        local stacks = exp.stacks or 1

        -- 绽放光环（青色扩散）
        local bloomR = exp.maxRadius * (0.2 + 0.8 * t)
        nvgBeginPath(vg)
        nvgCircle(vg, exp.x, exp.y, bloomR)
        nvgStrokeColor(vg, nvgRGBA(80, 230, 255, math.floor(150 * fadeAlpha)))
        nvgStrokeWidth(vg, (2 + stacks * 0.5) * (1 - t * 0.7))
        nvgStroke(vg)

        -- 内部绽放光晕
        nvgBeginPath(vg)
        nvgCircle(vg, exp.x, exp.y, bloomR * 0.5)
        nvgFillColor(vg, nvgRGBA(130, 240, 255, math.floor(80 * fadeAlpha)))
        nvgFill(vg)

        -- 中心白光闪烁（绽放瞬间）
        if t < 0.25 then
            local flashA = (1 - t / 0.25)
            nvgBeginPath(vg)
            nvgCircle(vg, exp.x, exp.y, (8 + stacks * 2) * (1 - t * 2))
            nvgFillColor(vg, nvgRGBA(220, 255, 255, math.floor(255 * flashA)))
            nvgFill(vg)
        end

        -- 放射状花瓣线条（像绽放的花朵轮廓）
        local petalLines = 5 + stacks
        for i = 1, petalLines do
            local angle = (i / petalLines) * math.pi * 2 + exp.t * 2
            local len = bloomR * (0.4 + 0.3 * math.sin(i * 2.1))
            local lx = exp.x + math.cos(angle) * len * t
            local ly = exp.y + math.sin(angle) * len * t
            nvgBeginPath(vg)
            nvgMoveTo(vg, exp.x, exp.y)
            nvgLineTo(vg, lx, ly)
            nvgStrokeColor(vg, nvgRGBA(60, 210, 240, math.floor(100 * fadeAlpha)))
            nvgStrokeWidth(vg, 1.2 * (1 - t))
            nvgStroke(vg)
        end
    end
end

-- ═══ 花瓣粒子更新（在 M.update 中调用）═══

function M.updatePetals(dt)
    for i = #petals_, 1, -1 do
        local p = petals_[i]
        p.age = p.age + dt
        if p.age >= p.lifetime then
            table.remove(petals_, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy + 30 * dt  -- 轻微下坠（花瓣飘落感）
            p.vx = p.vx * 0.98     -- 空气阻力
            p.rot = p.rot + p.rotSpeed * dt
        end
    end
end

--- 在爆炸时生成花瓣飞散粒子
function M._spawnPetals(x, y, stacks, radius)
    local count = 6 + stacks * 2
    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.5
        local speed = 60 + math.random() * 80 + stacks * 10
        petals_[#petals_ + 1] = {
            x = x,
            y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - 40 - math.random() * 30,
            rot = math.random() * math.pi * 2,
            rotSpeed = (math.random() - 0.5) * 8,
            size = 4 + math.random() * 3,
            age = 0,
            lifetime = 0.6 + math.random() * 0.5,
            colorIdx = math.random(1, 5),
        }
    end
end

return M
