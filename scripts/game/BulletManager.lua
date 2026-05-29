-- ============================================================================
-- BulletManager.lua - 子弹系统（敌方飞行子弹 + 轨道子弹）
-- ============================================================================

local Renderer      = require "game.Renderer"
local Pool          = require "lib.Pool"
local ShotHandler   = require "game.skills.ShotHandler"
local OrbitModifier = require "game.skills.OrbitModifier"
local QTEHandler    = require "game.skills.QTEHandler"

local M = {}

local W_, H_ = 0, 0
local drawTime_ = 0  -- 累计时间，用于动画脉冲

-- ——— 对象池 ———
local bulletPool_ = Pool.new(128)      -- 飞行子弹池
local orbitPool_  = Pool.new(64)       -- 轨道子弹池

-- ——— 飞行子弹（活跃列表） ———
---@type table[]
local bullets_ = {}

-- ——— 轨道子弹 ———
---@type table[]
local orbitBullets_ = {}

-- 轨道配置
local ORBIT_CFG = {
    baseRadius   = 48,
    radiusStep   = 22,
    perLayer     = 12,
    collectSpeed = 320,  -- 夺取时飞向玩家的速度
}

function M.init(_W, _H)
    W_ = _W
    H_ = _H
    ShotHandler.init()
    OrbitModifier.init()
    QTEHandler.init()
    M.reset()
end

function M.reset()
    bulletPool_:drain(bullets_)
    orbitPool_:drain(orbitBullets_)
    ShotHandler.resetLaser()
    OrbitModifier.resetPulse()
    QTEHandler.resetBeam()
    QTEHandler.clearHomingBullets()
end

function M.getBullets()
    return bullets_
end

function M.getOrbitBullets()
    return orbitBullets_
end

-- ——— 生成敌方子弹 ———
function M.spawnEnemyBullet(x, y, vx, vy, opts)
    opts = opts or {}
    local b = bulletPool_:get()
    b.x        = x
    b.y        = y
    b.vx       = vx
    b.vy       = vy
    b.owner    = "enemy"
    b.radius   = opts.radius   or 7
    b.damage   = opts.damage   or 1
    b.stealable = opts.stealable ~= false -- 默认可夺取
    -- 不可夺取类型: "laser_dot" / "mortar" / "boss"
    b.btype    = opts.btype    or "normal"
    b.grazed   = false
    b.dead     = false
    b.life     = opts.life     or 8.0  -- 最长存活时间
    b.age      = 0
    -- 抛物线子弹额外字段
    b.height   = opts.height   or 0
    b.vHeight  = opts.vHeight  or 0
    -- 颜色过渡（夺取中）
    b.stealing = false
    b.stealT   = 0
    table.insert(bullets_, b)
end

-- ——— 生成玩家发射的子弹 ———
function M.spawnPlayerBullet(x, y, angle, speed, opts)
    opts = opts or {}
    local b = bulletPool_:get()
    b.x      = x
    b.y      = y
    b.vx     = math.cos(angle) * speed
    b.vy     = math.sin(angle) * speed
    b.owner  = "player"
    b.radius = opts.radius or 8
    b.damage = opts.damage or 1
    b.dead   = false
    b.life   = 3.0
    b.age    = 0
    b.btype  = "orbit_shot"
    -- 清理可能残留的敌方子弹字段
    b.stealable = nil
    b.grazed    = nil
    b.stealing  = nil
    b.stealT    = nil
    b.height    = nil
    b.vHeight   = nil
    -- 清理射击形态字段（防止池复用残留）
    b.pierce      = nil
    b.pierceDecay = nil
    b.endAoe      = nil
    b.splash      = nil
    b.splashCount = nil
    b.splashDmgMult = nil
    b.splashRadius  = nil
    b.splashRange   = nil
    b.splashChain   = nil
    b.splashSlow    = nil
    b.dmgMult       = nil
    b.closeDmg      = nil
    b.originX       = nil
    b.originY       = nil
    -- 应用射击形态修饰（穿透/溅射/散弹属性）
    if not opts.skipShotMod then
        ShotHandler.modifyBullet(b)
    end
    -- 散弹近距离加伤需要记录发射原点
    if b.closeDmg then
        b.originX = x
        b.originY = y
    end
    table.insert(bullets_, b)
end

-- ——— 夺取子弹（变为轨道子弹） ———
function M.stealBullet(idx)
    local b = bullets_[idx]
    if not b or b.dead then return end
    b.dead = true

    -- 创建轨道子弹（先标记为"飞向轨道"状态）
    local PlayerMod = require("game.Player")
    local inBT = PlayerMod.getData().bulletTimeActive
    local ob = orbitPool_:get()
    ob.collecting  = true     -- 正在飞向轨道
    ob.x           = b.x
    ob.y           = b.y
    ob.layer       = 0
    ob.indexInLayer = 0
    ob.targetAngle = 0
    ob.damage      = b.damage or 1
    -- 颜色渐变
    ob.colorT      = 0        -- 0=暖色(敌方) 1=冷色(轨道)
    ob.flashT      = 0.3      -- 夺取闪烁
    -- 子弹时间内夺取的子弹，需等子弹时间结束后才可造成伤害
    ob.btShielded  = inBT or false
    ob.slotAngle   = 0
    -- 清理轨道形态残留字段（池复用安全）
    ob.bladeDurability = nil
    ob.bladeDmgMult = nil
    ob.shieldHP = nil
    ob.shieldMax = nil
    -- 应用轨道形态修饰（刀刃耐久/护盾值等）
    OrbitModifier.modifyOrbitBullet(ob)
    table.insert(orbitBullets_, ob)
    -- 重新分配所有轨道子弹的位置
    M.reassignOrbitSlots()
end

-- 重新分配轨道子弹的层/角度槽位
function M.reassignOrbitSlots()
    local perLayer = ORBIT_CFG.perLayer
    for i, ob in ipairs(orbitBullets_) do
        local layer = math.floor((i - 1) / perLayer)
        local idx   = (i - 1) % perLayer
        local total = math.min(perLayer, #orbitBullets_ - layer * perLayer)
        ob.layer    = layer
        ob.indexInLayer = idx
        ob.slotAngle = (idx / total) * math.pi * 2  -- 均匀分布
    end
end

-- 获取轨道子弹实时位置（基于玩家 + orbitAngle）
function M.getOrbitBulletPos(ob, playerX, playerY, orbitAngle)
    local r = ORBIT_CFG.baseRadius + ob.layer * ORBIT_CFG.radiusStep
    local a = ob.slotAngle + orbitAngle
    return playerX + math.cos(a) * r, playerY + math.sin(a) * r
end

-- ——— 获取撞击命中数量（玩家冲入敌人时） ———
function M.getRamHits(player, enemy)
    if #orbitBullets_ == 0 then return 0 end

    -- 玩家->敌人方向
    local dx = enemy.x - player.x
    local dy = enemy.y - player.y
    local angle = math.atan(dy, dx)

    -- 扇形角：±60度
    local halfArc = math.pi / 3

    local hits = 0
    local toRemove = {}
    for i, ob in ipairs(orbitBullets_) do
        if not ob.collecting then
            local bx, by = M.getOrbitBulletPos(ob, player.x, player.y, player.orbitAngle or 0)
            local bAngle = math.atan(by - player.y, bx - player.x)
            local diff = math.abs(normalizeAngle(bAngle - angle))
            if diff <= halfArc then
                hits = hits + ob.damage
                table.insert(toRemove, i)
            end
        end
    end

    -- 移除命中的轨道子弹（从后往前）
    table.sort(toRemove, function(a, b) return a > b end)
    for _, i in ipairs(toRemove) do
        orbitPool_:release(orbitBullets_[i])
        table.remove(orbitBullets_, i)
    end
    if #toRemove > 0 then
        M.reassignOrbitSlots()
    end

    return hits
end

-- 直接按索引移除轨道子弹（用于轨道子弹碰到敌人时消耗）
function M.removeOrbitBullet(idx)
    if idx >= 1 and idx <= #orbitBullets_ then
        orbitPool_:release(orbitBullets_[idx])
        table.remove(orbitBullets_, idx)
        M.reassignOrbitSlots()
    end
end

-- ——— 新发射系统：按持有数量决定射速和多发 ———
local FIRE_CFG = {
    -- 射速档位（按轨道子弹数）
    tiers = {
        { maxBullets = 3,  interval = 0.28, perShot = 1, spread = 0    },
        { maxBullets = 8,  interval = 0.18, perShot = 1, spread = 0    },
        { maxBullets = 15, interval = 0.14, perShot = 2, spread = 0.18 },  -- ~10°
        { maxBullets = 999,interval = 0.10, perShot = 3, spread = 0.25 },  -- ~14°
    },
    speed = 420,
}
local fireCooldown_ = 0  -- 发射冷却计时器
local wasFireHeld_ = false  -- 上一帧是否按住发射

-- ——— QTE 全弹爆发系统 ———
local QTE_CFG = {
    window      = 1.5,    -- QTE 窗口持续时间（秒）
    burstDelay  = 0.03,   -- 爆发时每颗子弹间隔
    speedMult   = 1.8,    -- 爆发子弹速度倍率
    baseDmgMult = 1.5,    -- 基础伤害倍率
    countBonus  = 0.12,   -- 每颗额外伤害加成（count * bonus）
}
local qteState_ = {
    active    = false,   -- QTE 窗口是否激活
    timer     = 0,       -- 剩余时间
    needRelease = false, -- 需要先松手才能触发（防止提前按住）
    -- 爆发执行中
    bursting  = false,
    burstQueue = {},     -- 待发射的角度列表
    burstTimer = 0,
    burstDmgMult = 1,    -- 本次爆发的伤害倍率
    -- 闪白效果
    flashAlpha = 0,
}
local wasBTActive_ = false  -- 上一帧子弹时间是否激活

-- QTE 状态查询（供外部 UI 绘制用）
function M.getQTEState()
    return qteState_
end

-- 获取当前射速档位
local function getFireTier()
    local count = #orbitBullets_
    for _, tier in ipairs(FIRE_CFG.tiers) do
        if count <= tier.maxBullets then
            return tier
        end
    end
    return FIRE_CFG.tiers[#FIRE_CFG.tiers]
end

-- 从轨道中取出距离目标方向最近的一颗子弹并发射
-- skipShielded: 如果为 true，跳过 btShielded 子弹（子弹时间中保留给 QTE）
local function fireOneBullet(playerX, playerY, playerOrbitAngle, angle, speed, skipShielded)
    if #orbitBullets_ == 0 then return false end

    -- 找最接近目标方向的轨道子弹（无角度限制，任意方向都能射）
    local bestIdx  = nil
    local bestDiff = math.huge

    for i, ob in ipairs(orbitBullets_) do
        if not ob.collecting and not (skipShielded and ob.btShielded) then
            local a = ob.slotAngle + playerOrbitAngle
            local diff = math.abs(normalizeAngle(a - angle))
            if diff < bestDiff then
                bestDiff = diff
                bestIdx  = i
            end
        end
    end

    if not bestIdx then
        -- 所有子弹都在 collecting 中或被保护，找不到可发射的
        return false
    end

    local ob = orbitBullets_[bestIdx]
    local bx, by = M.getOrbitBulletPos(ob, playerX, playerY, playerOrbitAngle)
    M.spawnPlayerBullet(bx, by, angle, speed, { damage = ob.damage })
    orbitPool_:release(ob)
    table.remove(orbitBullets_, bestIdx)
    M.reassignOrbitSlots()
    return true
end

-- 执行一次发射（按当前档位射出 perShot 颗子弹）
-- skipShielded: BT 期间跳过受保护子弹
function M.doFire(playerX, playerY, playerOrbitAngle, targetAngle, skipShielded)
    local tier = getFireTier()
    local perShot = tier.perShot
    local spread  = tier.spread
    local speed   = FIRE_CFG.speed

    -- A线射击形态覆盖（穿透/散弹可能改变参数）
    local overrides = ShotHandler.getFireOverrides()
    if overrides then
        if overrides.perShot then perShot = overrides.perShot end
        if overrides.spread then spread = overrides.spread end
        if overrides.speed then speed = overrides.speed end
    end

    for i = 1, perShot do
        if #orbitBullets_ == 0 then break end
        -- 多发时扇形分布
        local offset = 0
        if perShot > 1 then
            offset = (i - 1) / (perShot - 1) * 2 * spread - spread
        end
        local angle = targetAngle + offset
        fireOneBullet(playerX, playerY, playerOrbitAngle, angle, speed, skipShielded)
    end
end

-- 旧接口保留兼容（现在内部直接转发）
function M.tryFireOrbit(playerX, playerY, playerOrbitAngle, targetAngle, speed)
    if #orbitBullets_ == 0 then return false end
    fireOneBullet(playerX, playerY, playerOrbitAngle, targetAngle, speed or FIRE_CFG.speed)
    return true
end

-- ——— QTE 爆发触发（按形态路由） ———
function M._triggerQTEBurst(player)
    local VFX = require("lib.VFX")
    local EnemyMgr = require("game.EnemyManager")
    local PlayerMod = require("game.Player")
    local count = #orbitBullets_
    local dmgMult = QTEHandler.calcDmgMult(count)
    qteState_.burstDmgMult = dmgMult
    qteState_.active = false
    qteState_.flashAlpha = 1.0
    VFX.triggerShake(8, 0.3)

    local formId = QTEHandler.getFormId()
    print("[BulletMgr] QTE 成功! 形态=" .. formId .. " count=" .. count .. " dmgMult=" .. string.format("%.2f", dmgMult))

    if formId == "beam" then
        -- ═══ 光束形态：所有轨道弹融合为一道光束 ═══
        local fa, _ = PlayerMod.getFireDirection()
        local avgDmg = 0
        for _, ob in ipairs(orbitBullets_) do avgDmg = avgDmg + (ob.damage or 1) end
        avgDmg = avgDmg / math.max(1, count)

        local beamResult = QTEHandler.fireBeam(player.x, player.y, fa, count, avgDmg)
        -- 存储光束结果供 main.lua 碰撞检测
        M._lastBeamResult = beamResult

        -- 清空所有轨道弹
        for i = #orbitBullets_, 1, -1 do
            orbitPool_:release(orbitBullets_[i])
            table.remove(orbitBullets_, i)
        end
        M.reassignOrbitSlots()
        VFX.triggerShake(12, 0.4)

    elseif formId == "radial" then
        -- ═══ 星坠形态：360° 全方向同时爆发 ═══
        local angles, radialOpts = QTEHandler.calcRadialAngles(count)
        qteState_.burstQueue = angles
        qteState_.bursting = true
        qteState_.burstTimer = 0
        qteState_.radialOpts = radialOpts

    elseif formId == "homing" then
        -- ═══ 群星追踪形态：生成追踪弹 ═══
        local enemies = EnemyMgr.getEnemies()
        local liveEnemies = {}
        for _, e in ipairs(enemies) do
            if not e.dead then table.insert(liveEnemies, e) end
        end
        -- 按距离排序
        table.sort(liveEnemies, function(a, b)
            local da = (a.x - player.x)^2 + (a.y - player.y)^2
            local db = (b.x - player.x)^2 + (b.y - player.y)^2
            return da < db
        end)

        for i = #orbitBullets_, 1, -1 do
            local ob = orbitBullets_[i]
            local bx, by = ob.x, ob.y
            if not ob.collecting then
                bx, by = M.getOrbitBulletPos(ob, player.x, player.y, player.orbitAngle)
            end
            -- 分配目标（循环）
            local target = nil
            if #liveEnemies > 0 then
                local tIdx = ((#orbitBullets_ - i) % #liveEnemies) + 1
                target = liveEnemies[tIdx]
            end
            local angle = target and math.atan(target.y - by, target.x - bx) or (math.random() * math.pi * 2)
            local dmg = math.floor((ob.damage or 1) * dmgMult)
            QTEHandler.spawnHomingBullet(bx, by, angle, dmg, target)
            orbitPool_:release(ob)
            table.remove(orbitBullets_, i)
        end
        M.reassignOrbitSlots()

    else
        -- ═══ 默认形态：自动瞄准连射 ═══
        local enemies = EnemyMgr.getEnemies()
        local targets = {}
        for _, e in ipairs(enemies) do
            if not e.dead then
                local dx = e.x - player.x
                local dy = e.y - player.y
                table.insert(targets, { angle = math.atan(dy, dx), dist = dx*dx + dy*dy })
            end
        end
        table.sort(targets, function(a, b) return a.dist < b.dist end)

        qteState_.burstQueue = {}
        local fa, _ = PlayerMod.getFireDirection()
        for i = 1, count do
            if #targets > 0 then
                local tIdx = ((i - 1) % #targets) + 1
                table.insert(qteState_.burstQueue, targets[tIdx].angle)
            else
                local spread = (i - 1) / math.max(1, count - 1) * 0.8 - 0.4
                table.insert(qteState_.burstQueue, fa + spread)
            end
        end
        qteState_.bursting = true
        qteState_.burstTimer = 0
    end
end

-- ——— 更新 ———
-- dt      : 当前帧时间步长（子弹时间激活时为 slowDt，用于敌方子弹/玩家发射弹）
-- realDt  : 真实帧时间步长（始终为 Update 的原始 dt，用于轨道归位，保证即夺即用）
function M.update(dt, realDt)
    realDt = realDt or dt
    drawTime_ = drawTime_ + (realDt or dt)
    local player = require("game.Player").getData()

    -- 更新飞行子弹
    for i = #bullets_, 1, -1 do
        local b = bullets_[i]
        if b.dead then
            bulletPool_:release(b)
            table.remove(bullets_, i)
        else
            -- 己方子弹（orbit_shot）不受子弹时间影响，始终用 realDt
            local bdt = (b.owner == "player") and realDt or dt

            b.age = b.age + bdt
            b.life = b.life - bdt
            if b.life <= 0 then
                b.dead = true
            else
                -- 普通移动
                if b.btype == "mortar" then
                    -- 抛物线：实体跟着水平轨迹走，高度单独计算
                    b.x = b.x + b.vx * bdt
                    b.y = b.y + b.vy * bdt
                    b.height  = b.height + b.vHeight * bdt
                    b.vHeight = b.vHeight + 600 * bdt  -- 重力
                    if b.height >= 0 and b.vHeight > 0 then
                        -- 落地 → 触发 AOE 爆炸
                        b.height = 0
                        b.dead   = true
                        b.aoeTriggered = true  -- 标记，供碰撞检测处理伤害
                        b.aoeX = b.x
                        b.aoeY = b.y
                        b.aoeRadius = (b.aoeRadius or 60)
                        -- 触发视觉爆炸特效 + 震屏
                        local VFX = require("lib.VFX")
                        VFX.spawnAOE(b.x, b.y, b.aoeRadius, b.damage or 2)
                        VFX.triggerShake(5, 0.2)
                    end
                else
                    b.x = b.x + b.vx * bdt
                    b.y = b.y + b.vy * bdt
                end

                -- 飞出屏幕
                local pad = 60
                if b.x < -pad or b.x > W_ + pad
                   or b.y < -pad or b.y > H_ + pad then
                    b.dead = true
                end

                -- 夺取颜色过渡动画
                if b.stealing then
                    b.stealT = math.min(1, b.stealT + bdt * 4)
                    if b.stealT >= 1 then b.stealing = false end
                end
            end
        end
    end

    -- 更新轨道子弹（collecting 阶段飞向轨道目标点）
    -- 注意：归位使用 realDt（真实帧时间），不受子弹时间缩放影响
    -- 保证被夺取的子弹能立即归入轨道，玩家可以随时使用
    local btActive = player.bulletTimeActive
    for _, ob in ipairs(orbitBullets_) do
        -- 子弹时间结束后解除保护
        if ob.btShielded and not btActive then
            ob.btShielded = false
        end
        ob.flashT = math.max(0, ob.flashT - realDt * 2)
        if ob.colorT < 1 then
            ob.colorT = math.min(1, ob.colorT + realDt * 3)
        end
        if ob.collecting then
            local tx, ty = M.getOrbitBulletPos(ob, player.x, player.y, player.orbitAngle)
            local dx = tx - ob.x
            local dy = ty - ob.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 8 then
                ob.collecting = false
                ob.x = tx
                ob.y = ty
            else
                local spd = ORBIT_CFG.collectSpeed * realDt
                ob.x = ob.x + (dx / dist) * math.min(spd, dist)
                ob.y = ob.y + (dy / dist) * math.min(spd, dist)
            end
        else
            local tx, ty = M.getOrbitBulletPos(ob, player.x, player.y, player.orbitAngle)
            ob.x = tx
            ob.y = ty
        end
    end

    -- ——— 轨道形态更新（脉冲/护盾再生） ———
    OrbitModifier.updateShieldRegen(realDt, orbitBullets_)
    local pulseHit = OrbitModifier.updatePulse(realDt, #orbitBullets_, player.x, player.y)
    if pulseHit and pulseHit.cost > 0 and #orbitBullets_ > 0 then
        -- 脉冲消耗轨道弹
        for _ = 1, math.min(pulseHit.cost, #orbitBullets_) do
            orbitPool_:release(orbitBullets_[#orbitBullets_])
            table.remove(orbitBullets_, #orbitBullets_)
        end
        M.reassignOrbitSlots()
    end
    -- pulseHit 存储在模块级变量供 main.lua 碰撞检测读取
    M._lastPulseHit = pulseHit

    -- ——— QTE 全弹爆发系统 ———
    local InputH = require("game.InputHandler")
    local PlayerMod = require("game.Player")
    local fireHeld = InputH.isFireHeld()
    local justPressed = fireHeld and not wasFireHeld_
    wasFireHeld_ = fireHeld

    -- 检测子弹时间结束瞬间 → 触发 QTE 窗口
    if wasBTActive_ and not btActive then
        -- BT 刚结束，且轨道有子弹时才触发 QTE
        if #orbitBullets_ > 0 then
            -- 自动触发（默认形态 Lv5）：跳过窗口直接爆发
            if QTEHandler.isAutoTrigger() then
                M._triggerQTEBurst(player)
            else
                qteState_.active = true
                qteState_.timer  = QTEHandler.getWindow()
                qteState_.flashAlpha = 0
                qteState_.needRelease = fireHeld
                print("[BulletMgr] QTE 窗口开启, 形态=" .. QTEHandler.getFormId() .. " 轨道弹数=" .. #orbitBullets_)
            end
        end
    end
    wasBTActive_ = btActive

    -- QTE 窗口倒计时
    if qteState_.active then
        qteState_.timer = qteState_.timer - realDt

        -- 等待松手后才接受按下
        if qteState_.needRelease then
            if not fireHeld then
                qteState_.needRelease = false
            end
        end

        -- 玩家在窗口内按下发射 → 触发全弹爆发
        local qteAccept = justPressed and not qteState_.needRelease
        if qteAccept then
            M._triggerQTEBurst(player)
        elseif qteState_.timer <= 0 then
            qteState_.active = false
            print("[BulletMgr] QTE 超时，窗口关闭")
        end
    end

    -- 执行爆发连射（default / radial 模式使用 burstQueue）
    if qteState_.bursting then
        qteState_.burstTimer = qteState_.burstTimer - realDt
        local burstDelay = QTEHandler.getBurstDelay()
        while qteState_.burstTimer <= 0 and #qteState_.burstQueue > 0 and #orbitBullets_ > 0 do
            local angle = table.remove(qteState_.burstQueue, 1)
            local dmgMult = qteState_.burstDmgMult
            -- 取最近的轨道子弹发射
            local bestIdx = nil
            local bestDiff = math.huge
            for i, ob in ipairs(orbitBullets_) do
                if not ob.collecting then
                    local a = ob.slotAngle + player.orbitAngle
                    local diff = math.abs(normalizeAngle(a - angle))
                    if diff < bestDiff then
                        bestDiff = diff
                        bestIdx = i
                    end
                end
            end
            if not bestIdx then
                for i, ob in ipairs(orbitBullets_) do
                    local bAngle = math.atan(ob.y - player.y, ob.x - player.x)
                    local diff = math.abs(normalizeAngle(bAngle - angle))
                    if diff < bestDiff then
                        bestDiff = diff
                        bestIdx = i
                    end
                end
            end
            if bestIdx then
                local ob = orbitBullets_[bestIdx]
                local bx, by = ob.x, ob.y
                if not ob.collecting then
                    bx, by = M.getOrbitBulletPos(ob, player.x, player.y, player.orbitAngle)
                end
                local burstSpeed = FIRE_CFG.speed * QTEHandler.getSpeedMult()
                local opts = { damage = math.floor((ob.damage or 1) * dmgMult), radius = 9 }
                -- 星坠爆炸弹标记
                if qteState_.radialOpts and qteState_.radialOpts.explodeOnHit then
                    opts.endAoe = true
                    opts.splash = false  -- 不走 splash 逻辑
                    opts.radialExplode = true
                    opts.radialRadius = qteState_.radialOpts.explodeRadius or 30
                end
                M.spawnPlayerBullet(bx, by, angle, burstSpeed, opts)
                orbitPool_:release(ob)
                table.remove(orbitBullets_, bestIdx)
                M.reassignOrbitSlots()
            end
            qteState_.burstTimer = qteState_.burstTimer + burstDelay
        end
        -- 爆发结束
        if #qteState_.burstQueue == 0 or #orbitBullets_ == 0 then
            qteState_.bursting = false
            qteState_.burstQueue = {}
            qteState_.radialOpts = nil
        end
    end

    -- 更新 QTEHandler 光束视觉和追踪弹
    QTEHandler.updateBeamVisual(realDt)

    -- 闪白衰减
    if qteState_.flashAlpha > 0 then
        qteState_.flashAlpha = math.max(0, qteState_.flashAlpha - realDt * 4)
    end

    -- 处理常规发射（QTE 窗口/爆发期间禁止常规发射）
    fireCooldown_ = fireCooldown_ - dt
    if not qteState_.active and not qteState_.bursting then
        -- ——— 激光模式特殊处理 ———
        if ShotHandler.isLaserMode() then
            local fireAngle, _ = PlayerMod.getFireDirection()
            if fireHeld and #orbitBullets_ > 0 then
                -- 按住 → 蓄力
                if not ShotHandler.getLaserState().charging then
                    ShotHandler.laserChargeStart()
                end
                ShotHandler.laserChargeUpdate(realDt, #orbitBullets_)
            elseif ShotHandler.getLaserState().charging then
                -- 松开 → 释放激光
                local consumed = ShotHandler.laserRelease(fireAngle)
                if consumed > 0 then
                    -- 从轨道中移除对应数量子弹
                    for _ = 1, consumed do
                        if #orbitBullets_ > 0 then
                            orbitPool_:release(orbitBullets_[#orbitBullets_])
                            table.remove(orbitBullets_, #orbitBullets_)
                        end
                    end
                    M.reassignOrbitSlots()
                    local VFX = require("lib.VFX")
                    VFX.triggerShake(4, 0.2)
                end
            end
            -- 激光发射中持续更新
            ShotHandler.laserFireUpdate(realDt)
        else
            -- ——— 常规发射 ———
            if fireHeld and #orbitBullets_ > 0 then
                if justPressed or fireCooldown_ <= 0 then
                    local fireAngle, _ = PlayerMod.getFireDirection()
                    -- BT 期间跳过 btShielded 子弹（保留给 QTE 爆发）
                    M.doFire(player.x, player.y, player.orbitAngle, fireAngle, btActive)
                    -- 射击冷却：使用形态覆盖或默认档位
                    local overrides = ShotHandler.getFireOverrides()
                    if overrides and overrides.interval then
                        fireCooldown_ = overrides.interval
                    else
                        local tier = getFireTier()
                        fireCooldown_ = tier.interval
                    end
                end
            else
                fireCooldown_ = 0
            end
        end
    end
end

-- ——— 激光碰撞查询（供 main.lua 碰撞检测调用） ———
-- 返回激光信息 { active, x1,y1, x2,y2, width, dps, dir } 或 nil
function M.getPlayerLaser()
    local ls = ShotHandler.getLaserState()
    if not ls.firing then return nil end
    local player = require("game.Player").getData()
    local len = 800  -- 激光长度（足够贯穿屏幕）
    local x1 = player.x
    local y1 = player.y
    local x2 = x1 + math.cos(ls.fireDir) * len
    local y2 = y1 + math.sin(ls.fireDir) * len
    return {
        active = true,
        x1 = x1, y1 = y1,
        x2 = x2, y2 = y2,
        width = ls.width,
        dps   = ls.dps,
        dir   = ls.fireDir,
    }
end

-- ——— 激光蓄力/发射绘制 ———
function M.drawPlayerLaser(vg)
    local ls = ShotHandler.getLaserState()
    local player = require("game.Player").getData()

    -- 蓄力指示（充能中显示渐粗光线预览）
    if ls.charging and ls.charged > 0 then
        local PlayerMod = require("game.Player")
        local dir, _ = PlayerMod.getFireDirection()
        local previewW = 2 + (ls.charged / 10) * 12
        local len = 600
        local x1 = player.x
        local y1 = player.y
        local x2 = x1 + math.cos(dir) * len
        local y2 = y1 + math.sin(dir) * len
        nvgLineCap(vg, NVG_ROUND)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, x2, y2)
        nvgStrokeColor(vg, nvgRGBAf(0.4, 0.8, 1.0, 0.3 + ls.charged * 0.04))
        nvgStrokeWidth(vg, previewW)
        nvgStroke(vg)
    end

    -- 激光发射中
    if ls.firing then
        local len = 800
        local x1 = player.x
        local y1 = player.y
        local x2 = x1 + math.cos(ls.fireDir) * len
        local y2 = y1 + math.sin(ls.fireDir) * len
        local w = ls.width
        local progress = 1.0 - (ls.fireTimer / ls.duration)
        -- 闪烁效果
        local flicker = 0.9 + 0.1 * math.sin(drawTime_ * 40)

        -- 外层光晕
        nvgLineCap(vg, NVG_ROUND)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, x2, y2)
        nvgStrokeColor(vg, nvgRGBAf(0.3, 0.7, 1.0, 0.3 * flicker))
        nvgStrokeWidth(vg, w * 2.0)
        nvgStroke(vg)

        -- 主体
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, x2, y2)
        nvgStrokeColor(vg, nvgRGBAf(0.6, 0.95, 1.0, 0.85 * flicker))
        nvgStrokeWidth(vg, w)
        nvgStroke(vg)

        -- 核心白线
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, x2, y2)
        nvgStrokeColor(vg, nvgRGBAf(1.0, 1.0, 1.0, 0.9 * flicker))
        nvgStrokeWidth(vg, w * 0.3)
        nvgStroke(vg)
    end
end

-- ——— 轨道形态查询接口（供外部碰撞检测） ———
function M.getOrbitModifier()
    return OrbitModifier
end

function M.getQTEHandler()
    return QTEHandler
end

--- 获取上一帧脉冲触发信息（用于 main.lua 应用脉冲伤害）
function M.getLastPulseHit()
    return M._lastPulseHit
end

--- 获取光束结果（一次性消费：读取后清空）
function M.consumeBeamResult()
    local r = M._lastBeamResult
    M._lastBeamResult = nil
    return r
end

-- ——— 脉冲波绘制 ———
function M.drawPulseWave(vg)
    local ps = OrbitModifier.getPulseState()
    if not ps.pulsing or ps.radius <= 0 then return end

    local player = require("game.Player").getData()
    local r = ps.radius
    local alpha = 0.6 * (1.0 - ps.pulseT / 0.5)  -- 随扩张衰减
    alpha = math.max(0, alpha)

    -- 外圈
    nvgBeginPath(vg)
    nvgCircle(vg, player.x, player.y, r)
    nvgStrokeColor(vg, nvgRGBAf(0.3, 0.9, 1.0, alpha))
    nvgStrokeWidth(vg, 3.0)
    nvgStroke(vg)

    -- 内填充
    nvgBeginPath(vg)
    nvgCircle(vg, player.x, player.y, r)
    nvgFillColor(vg, nvgRGBAf(0.3, 0.9, 1.0, alpha * 0.15))
    nvgFill(vg)
end

-- ——— 绘制 ———
function M.draw(vg)
    local player = require("game.Player").getData()

    -- 绘制飞行子弹
    for _, b in ipairs(bullets_) do
        if not b.dead then
            drawBullet(vg, b)
        end
    end

    -- 绘制轨道子弹
    for _, ob in ipairs(orbitBullets_) do
        drawOrbitBullet(vg, ob)
    end

    -- 方向指示：始终显示小白箭头，开火时加虚线+锁定
    local InputH = require("game.InputHandler")
    local PlayerMod = require("game.Player")
    local fa, lockedEnemy = PlayerMod.getFireDirection()
    local firing = InputH.isFireHeld() and #orbitBullets_ > 0

    -- 常驻小箭头（圆角 chevron）
    local arrowDist = player.radius + 20
    local ax = player.x + math.cos(fa) * arrowDist
    local ay = player.y + math.sin(fa) * arrowDist
    local armLen = 8
    local halfAngle = math.pi * 0.75  -- 张开角度
    local la = fa + halfAngle
    local ra = fa - halfAngle
    nvgLineCap(vg, NVG_ROUND)
    nvgLineJoin(vg, NVG_ROUND)
    nvgBeginPath(vg)
    nvgMoveTo(vg, ax + math.cos(la) * armLen, ay + math.sin(la) * armLen)
    nvgLineTo(vg, ax, ay)
    nvgLineTo(vg, ax + math.cos(ra) * armLen, ay + math.sin(ra) * armLen)
    nvgStrokeColor(vg, nvgRGBAf(1.0, 1.0, 1.0, firing and 0.9 or 0.45))
    nvgStrokeWidth(vg, 3.0)
    nvgStroke(vg)

    -- 开火时：加虚线 + 锁定菱形
    if firing then
        local aimColor = nvgRGBAf(1.0, 0.9, 0.2, 0.7)
        local lineLen = 55
        local startOffset = player.radius + 28

        local sx = player.x + math.cos(fa) * startOffset
        local sy = player.y + math.sin(fa) * startOffset
        local ex = player.x + math.cos(fa) * (startOffset + lineLen)
        local ey = player.y + math.sin(fa) * (startOffset + lineLen)

        drawCapsuleDashLine(vg, sx, sy, ex, ey, aimColor, 5, 14, 9)
        drawCapsuleArrow(vg, ex, ey, fa, aimColor, 10)

        if lockedEnemy then
            local eex, eey = lockedEnemy.x, lockedEnemy.y
            local markR = lockedEnemy.radius + 8
            nvgLineCap(vg, NVG_ROUND)
            nvgStrokeColor(vg, aimColor)
            nvgStrokeWidth(vg, 3.5)
            nvgBeginPath(vg)
            nvgMoveTo(vg, eex, eey - markR)
            nvgLineTo(vg, eex + markR, eey)
            nvgLineTo(vg, eex, eey + markR)
            nvgLineTo(vg, eex - markR, eey)
            nvgClosePath(vg)
            nvgStroke(vg)
        end
    end

    -- QTE 窗口提示：音游风格缩圈（圆环从大向小收缩）
    if qteState_.active then
        local progress = 1.0 - (qteState_.timer / QTEHandler.getWindow())  -- 0→1
        -- 缩圈：从大半径收缩到玩家半径
        local maxR = player.radius + 80
        local minR = player.radius + 4
        local ringR = maxR - (maxR - minR) * progress

        -- 圆环透明度：淡入后保持，最后 0.3 秒加速闪烁
        local ringAlpha
        if progress < 0.1 then
            ringAlpha = progress / 0.1  -- 淡入
        elseif qteState_.timer < 0.4 then
            -- 快到时间了，闪烁催促
            ringAlpha = 0.5 + 0.5 * math.abs(math.sin(qteState_.timer * 16))
        else
            ringAlpha = 0.9
        end

        -- 外圈缩小（主要视觉）
        nvgBeginPath(vg)
        nvgCircle(vg, player.x, player.y, ringR)
        nvgStrokeColor(vg, nvgRGBAf(1.0, 0.95, 0.3, ringAlpha))
        nvgStrokeWidth(vg, 3.5)
        nvgStroke(vg)

        -- 内圈目标位置（固定小圈，作为缩圈目标参照）
        nvgBeginPath(vg)
        nvgCircle(vg, player.x, player.y, minR)
        nvgStrokeColor(vg, nvgRGBAf(1.0, 1.0, 1.0, 0.35))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- "FIRE!" 文字（随缩圈节奏呼吸）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16 + progress * 4)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(1.0, 0.95, 0.3, ringAlpha))
        nvgText(vg, player.x, player.y - player.radius - 28, "FIRE!")
    end
end

-- QTE 闪白全屏覆盖（在 main.lua 渲染最后调用）
function M.drawQTEFlash(vg, w, h)
    if qteState_.flashAlpha > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(1.0, 1.0, 1.0, qteState_.flashAlpha * 0.5))
        nvgFill(vg)
    end
end

-- QTE 光束/追踪弹特效绘制
function M.drawQTEEffects(vg)
    QTEHandler.drawBeam(vg)
    QTEHandler.drawHomingBullets(vg)
end

function drawBullet(vg, b)
    -- 斜投影阴影
    local ox, oy = Renderer.shadowOffset(b.height or 0)
    nvgBeginPath(vg)
    nvgCircle(vg, b.x + ox, b.y + oy, b.radius * 0.8)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.4))
    nvgFill(vg)

    -- 子弹颜色
    local fr, fg, fb
    if b.btype == "orbit_shot" then
        -- 发射出去的轨道弹：青白色，与轨道弹外观一致
        nvgBeginPath(vg)
        nvgCircle(vg, b.x, b.y, b.radius)
        nvgFillColor(vg, nvgRGBAf(0.5, 0.95, 1.0, 1.0))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, b.x, b.y, b.radius + 2)
        nvgStrokeColor(vg, nvgRGBAf(0.7, 1.0, 1.0, 0.4))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        return
    elseif b.btype == "mortar" then
        -- 抛物线：深橙菱形，实体根据高度向上偏移
        fr, fg, fb = 0.8, 0.5, 0.1
        local heightOffset = -(b.height or 0) * 0.5  -- 高度越高，实体越往上
        drawDiamond(vg, b.x, b.y + heightOffset, b.radius, fr, fg, fb)
        -- 地面预警圆（虚线段圆环 + 填充，越接近落地越大越不透明）
        -- 预警圈固定在预计算落点位置，不跟随炮弹移动
        local landProgress = 1.0 - math.max(0, math.min(1, -(b.height or 0) / 80))
        local warnAlpha = 0.2 + landProgress * 0.5
        local warnRadius = (b.aoeRadius or 60) * (0.3 + landProgress * 0.7)
        -- 脉冲呼吸（接近落地时加速）
        local pulseFreq = 6 + landProgress * 10
        local pulse = 0.8 + 0.2 * math.sin(drawTime_ * pulseFreq)
        local wcx, wcy = (b.landX or b.x) + ox, (b.landY or b.y) + oy
        -- 1) 填充预警（半透明）
        nvgBeginPath(vg)
        nvgCircle(vg, wcx, wcy, warnRadius)
        nvgFillColor(vg, nvgRGBAf(0.9, 0.4, 0.1, warnAlpha * 0.15 * pulse))
        nvgFill(vg)
        -- 2) 虚线段圆环（胶囊段，与激光/锁定风格统一）
        local segments = 12
        local arcPer = (math.pi * 2) / segments
        local gapRatio = 0.35  -- 留 35% 做间隙
        nvgLineCap(vg, NVG_ROUND)
        nvgStrokeColor(vg, nvgRGBAf(0.9, 0.4, 0.1, warnAlpha * pulse))
        nvgStrokeWidth(vg, 2.5)
        for si = 0, segments - 1 do
            local a0 = si * arcPer
            local a1 = a0 + arcPer * (1.0 - gapRatio)
            nvgBeginPath(vg)
            nvgArc(vg, wcx, wcy, warnRadius, a0, a1, NVG_CW)
            nvgStroke(vg)
        end
        return
    elseif b.stealable then
        -- 可夺取：橙红
        if b.stealing then
            -- 夺取颜色过渡：橙→青
            local t = b.stealT
            fr = lerpC(0.95, 0.3, t)
            fg = lerpC(0.4,  0.9, t)
            fb = lerpC(0.1,  1.0, t)
        else
            fr, fg, fb = 0.95, 0.4, 0.1
        end
    else
        -- 不可夺取：深红/boss 黑红
        if b.btype == "boss" then
            fr, fg, fb = 0.1, 0.0, 0.0
        else
            fr, fg, fb = 0.6, 0.0, 0.0
        end
    end

    nvgBeginPath(vg)
    nvgCircle(vg, b.x, b.y, b.radius)
    nvgFillColor(vg, nvgRGBAf(fr, fg, fb, 1.0))
    nvgFill(vg)

    -- 可夺取子弹：橙色外发光描边
    if b.stealable then
        local player = require("game.Player").getData()
        if player.bulletTimeActive then
            -- 子弹时间中：呼吸脉冲高亮
            local pulse = 0.5 + 0.5 * math.sin(drawTime_ * 10)
            local glowR = b.radius + 3 + pulse * 3
            nvgBeginPath(vg)
            nvgCircle(vg, b.x, b.y, glowR)
            nvgStrokeColor(vg, nvgRGBAf(1.0, 0.9, 0.3, 0.4 + pulse * 0.4))
            nvgStrokeWidth(vg, 2.5)
            nvgStroke(vg)
        else
            nvgBeginPath(vg)
            nvgCircle(vg, b.x, b.y, b.radius + 1.5)
            nvgStrokeColor(vg, nvgRGBAf(1.0, 0.6, 0.2, 0.5))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end
end

function drawOrbitBullet(vg, ob)
    local flash = ob.flashT or 0
    local t = ob.colorT or 1

    -- 颜色插值：橙→青白
    local fr = lerpC(0.95, 0.5, t)
    local fg = lerpC(0.4,  0.95, t)
    local fb = lerpC(0.1,  1.0, t)
    local fa = 1.0

    -- 夺取闪烁
    if flash > 0 then
        fr = math.min(1, fr + flash)
        fg = math.min(1, fg + flash)
        fb = math.min(1, fb + flash)
    end

    -- 外发光
    nvgBeginPath(vg)
    nvgCircle(vg, ob.x, ob.y, 11)
    nvgFillColor(vg, nvgRGBAf(fr, fg, fb, 0.2))
    nvgFill(vg)

    -- 主体
    nvgBeginPath(vg)
    nvgCircle(vg, ob.x, ob.y, 7)
    nvgFillColor(vg, nvgRGBAf(fr, fg, fb, fa))
    nvgFill(vg)

    -- 描边
    nvgBeginPath(vg)
    nvgCircle(vg, ob.x, ob.y, 7)
    nvgStrokeColor(vg, nvgRGBAf(0.7, 1.0, 1.0, 0.8))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

function drawDiamond(vg, cx, cy, r, fr, fg, fb)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx,     cy - r)
    nvgLineTo(vg, cx + r, cy)
    nvgLineTo(vg, cx,     cy + r)
    nvgLineTo(vg, cx - r, cy)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(fr, fg, fb, 1.0))
    nvgFill(vg)
    nvgLineJoin(vg, NVG_ROUND)
    nvgStrokeColor(vg, nvgRGBAf(1.0, 0.7, 0.2, 0.6))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

function lerpC(a, b, t)
    return a + (b - a) * math.max(0, math.min(1, t))
end

function normalizeAngle(a)
    while a > math.pi  do a = a - math.pi * 2 end
    while a < -math.pi do a = a + math.pi * 2 end
    return a
end

return M
