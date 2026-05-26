-- ============================================================================
-- EnemyManager.lua - 敌人生成、移动、攻击
-- 敌人类型: "scout"(侦察) / "heavy"(重炮) / "sniper"(狙击)
-- ============================================================================

local Renderer  = require "game.Renderer"
local BulletMgr = require "game.BulletManager"
local Player    = require "game.Player"
local Pool      = require "lib.Pool"

local M = {}

local W_, H_ = 0, 0

local enemyPool_ = Pool.new(32)

---@type table[]
local enemies_ = {}

local spawnTimer_  = 0
local waveTimer_   = 0
local difficulty_  = 1.0

-- ——— 敌人配置 ———
-- 设计约定：hp == bulletCount * bulletDamage
-- 即玩家把一次攻击的子弹全部夺取并打回，恰好能击杀该敌人
local ENEMY_TYPES = {
    scout = {
        radius        = 14,
        hp            = 1,   -- bulletCount(1) * bulletDamage(1)
        speed         = 90,
        color         = { 0.85, 0.6, 0.1 },  -- 橙色
        shootInterval = 2.0,
        bulletCount   = 1,
        bulletSpread  = 0,
        bulletSpeed   = 200,
        bulletDamage  = 1,
    },
    heavy = {
        radius        = 22,
        hp            = 3,   -- bulletCount(3) * bulletDamage(1)
        speed         = 50,
        color         = { 0.6, 0.2, 0.8 },  -- 紫色
        shootInterval = 3.0,
        bulletCount   = 3,   -- 扇形三连射
        bulletSpread  = 18,  -- 各子弹偏转 ±18°
        bulletSpeed   = 160,
        bulletDamage  = 1,
    },
    sniper = {
        radius        = 12,
        hp            = 2,   -- bulletCount(1) * bulletDamage(2)
        speed         = 70,
        color         = { 0.9, 0.15, 0.3 },  -- 深红
        shootInterval = 4.0,
        bulletCount   = 1,
        bulletSpread  = 0,
        bulletSpeed   = 380,
        bulletDamage  = 2,   -- 高伤单发，夺取后一击毙命
    },
}

-- 生成间隔（随难度缩短）
local BASE_SPAWN_INTERVAL = 1.8

function M.init(_W, _H)
    W_ = _W
    H_ = _H
    M.reset()
end

function M.reset()
    enemyPool_:drain(enemies_)
    spawnTimer_ = 1.0
    waveTimer_  = 0
    difficulty_ = 1.0
end

function M.getEnemies()
    return enemies_
end

-- ——— 更新 ———
function M.update(dt)
    waveTimer_ = waveTimer_ + dt
    -- 难度随时间提升
    difficulty_ = 1.0 + waveTimer_ * 0.015

    -- 生成
    local spawnInterval = BASE_SPAWN_INTERVAL / math.min(difficulty_, 3.0)
    spawnTimer_ = spawnTimer_ - dt
    if spawnTimer_ <= 0 then
        spawnTimer_ = spawnInterval
        local count = math.floor(difficulty_ * 0.7)
        count = math.max(1, math.min(count, 4))
        for _ = 1, count do
            spawnEnemy()
        end
    end

    local player = Player.getData()

    -- 更新每个敌人
    for i = #enemies_, 1, -1 do
        local e = enemies_[i]
        if e.dead then
            enemyPool_:release(e)
            table.remove(enemies_, i)
        else
            -- 朝玩家移动
            local dx = player.x - e.x
            local dy = player.y - e.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > e.radius + player.radius + 5 then
                local spd = e.speed * dt
                e.x = e.x + (dx / dist) * spd
                e.y = e.y + (dy / dist) * spd
            end

            -- age 累加（用于动画效果，如幽灵眼血丝旋转）
            e.age = (e.age or 0) + dt

            -- 射击计时
            e.shootTimer = e.shootTimer - dt
            if e.shootTimer <= 0 then
                e.shootTimer = e.cfg.shootInterval * (0.8 + math.random() * 0.4)
                shootAtPlayer(e, player)
            end
        end
    end
end

-- 对敌人造成伤害
-- isOrbitKill: 是否由轨道子弹造成（计入击杀计数）
function M.damageEnemy(idx, dmg, isOrbitKill)
    local e = enemies_[idx]
    if not e or e.dead then return end
    e.hp = e.hp - dmg
    e.hitFlash = 0.4
    if e.hp <= 0 then
        e.dead = true
        if isOrbitKill then
            Player.addOrbitKill()
        end
        -- 掉落道具
        local ItemMgr = require "game.ItemManager"
        ItemMgr.tryDrop(e.x, e.y, e.cfg)
        print("[Enemy] 击杀 type=" .. e.etype
            .. " orbitKill=" .. tostring(isOrbitKill)
            .. " killCount=" .. Player.getKillCount())
    end
end

-- ——— 绘制 ———
function M.draw(vg)
    for _, e in ipairs(enemies_) do
        if not e.dead then
            drawEnemy(vg, e)
        end
    end
end

-- ——— 内部函数 ———

function spawnEnemy()
    local margin = 40
    local side = math.random(1, 4)
    local x, y
    if side == 1 then
        x = math.random(margin, W_ - margin)
        y = -margin
    elseif side == 2 then
        x = math.random(margin, W_ - margin)
        y = H_ + margin
    elseif side == 3 then
        x = -margin
        y = math.random(margin, H_ - margin)
    else
        x = W_ + margin
        y = math.random(margin, H_ - margin)
    end

    -- 随难度决定类型
    local etype
    local r = math.random()
    if difficulty_ < 2.0 then
        etype = r < 0.7 and "scout" or "heavy"
    else
        if r < 0.5 then etype = "scout"
        elseif r < 0.8 then etype = "heavy"
        else etype = "sniper" end
    end

    local cfg = ENEMY_TYPES[etype]
    local e = enemyPool_:get()
    e.x          = x
    e.y          = y
    e.etype      = etype
    e.cfg        = cfg
    e.radius     = cfg.radius
    e.hp         = cfg.hp
    e.maxHp      = cfg.hp
    e.speed      = cfg.speed
    e.shootTimer = cfg.shootInterval * (0.5 + math.random() * 0.5)
    e.dead       = false
    e.hitFlash   = 0
    e.age        = 0
    table.insert(enemies_, e)
end

function shootAtPlayer(e, player)
    local dx = player.x - e.x
    local dy = player.y - e.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return end

    -- 简单预判（提前量）
    local lead = e.cfg.bulletSpeed and (dist / e.cfg.bulletSpeed * 0.3) or 0
    local px = player.x + (player.vx or 0) * lead
    local py = player.y + (player.vy or 0) * lead
    dx = px - e.x
    dy = py - e.y
    local len = math.sqrt(dx * dx + dy * dy)
    local baseAngle = math.atan(dy, dx)

    local count  = e.cfg.bulletCount or 1
    local spread = e.cfg.bulletSpread or 0  -- 度数，单侧偏转量
    local spd    = e.cfg.bulletSpeed

    for i = 1, count do
        -- 均匀分布在 [-spread, +spread] 范围内
        local offset = 0
        if count > 1 then
            offset = (i - 1) / (count - 1) * 2 * spread - spread
        end
        local angle = baseAngle + math.rad(offset)
        BulletMgr.spawnEnemyBullet(e.x, e.y,
            math.cos(angle) * spd,
            math.sin(angle) * spd,
            {
                damage    = e.cfg.bulletDamage,
                radius    = 7,
                stealable = true,
            }
        )
    end
end

function drawEnemy(vg, e)
    -- 斜投影阴影
    local ox, oy = Renderer.shadowOffset(0)
    nvgBeginPath(vg)
    nvgCircle(vg, e.x + ox, e.y + oy, e.radius * 0.9)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.35))
    nvgFill(vg)

    -- hitFlash 衰减（在此统一处理）
    if (e.hitFlash or 0) > 0 then
        e.hitFlash = math.max(0, (e.hitFlash or 0) - 0.05)
    end
    local flash = e.hitFlash or 0

    -- 按类型分发绘制
    if e.etype == "scout" then
        drawFogWraith(vg, e, flash)
    elseif e.etype == "heavy" then
        drawNightmareCat(vg, e, flash)
    elseif e.etype == "sniper" then
        drawGhostEye(vg, e, flash)
    end
end

-- ——— 迷雾鬼 Fog Wraith ———
-- 深灰蓝毛刺球 + 双橙色眼（伪3D跟随），飘浮动画
function drawFogWraith(vg, e, flash)
    local cx, cy, r = e.x, e.y, e.radius
    local player = Player.getData()

    -- 飘浮动画（上下起伏）
    local floatY = math.sin(e.age * 2.5) * r * 0.08

    nvgSave(vg)
    nvgTranslate(vg, cx, cy + floatY)
    -- 此后以 (0,0) 为中心绘制

    -- 颜色（纯色）
    local bodyR, bodyG, bodyB = 0.10, 0.10, 0.18  -- 深灰蓝
    if flash > 0 then
        bodyR, bodyG, bodyB = 0.55, 0.50, 0.55
    end

    -- === 身体（毛刺球）===
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r * 0.8)
    nvgFillColor(vg, nvgRGBAf(bodyR, bodyG, bodyB, 1.0))
    nvgFill(vg)

    -- 毛球突起（10个，蓬松散乱）
    local mdx = player.x - e.x
    local mdy = player.y - e.y
    local mdist = math.sqrt(mdx * mdx + mdy * mdy)
    local moveAngle = 0
    if mdist > 1 then moveAngle = math.atan(mdy, mdx) end

    local furCount = 10
    local seed = 5431
    for i = 1, furCount do
        local angle = (i / furCount) * math.pi * 2
        seed = (seed * 1103 + 2731) & 0x7fff
        local rndSize = 0.85 + (seed % 100) / 280.0
        seed = (seed * 1103 + 2731) & 0x7fff
        local rndDist = 0.9 + (seed % 100) / 500.0

        local dot = math.cos(angle - moveAngle)
        local dirFactor = -dot * 0.2
        local bumpR = r * 0.3 * rndSize * (1.0 + dirFactor * 0.5)
        local bumpDist = r * 0.65 * rndDist * (1.0 + dirFactor)
        local bx = math.cos(angle) * bumpDist
        local by = math.sin(angle) * bumpDist

        nvgBeginPath(vg)
        nvgCircle(vg, bx, by, bumpR)
        nvgFillColor(vg, nvgRGBAf(bodyR, bodyG, bodyB, 1.0))
        nvgFill(vg)
    end

    -- === 双眼（伪3D：近大远小 + 偏移）===
    local dx = player.x - e.x
    local dy = player.y - e.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- 朝向角
    local facingAngle = 0
    if dist > 1 then
        facingAngle = (dx / dist) * 0.5  -- maxFacing=0.5
    end

    -- 面部整体偏移
    local faceShift = facingAngle * r * 0.3

    -- 近大远小
    local scaleNear = 1.0 + math.abs(facingAngle) * 0.3
    local scaleFar  = 1.0 - math.abs(facingAngle) * 0.25

    local function sideScale(side)
        if (side > 0 and facingAngle > 0) or (side < 0 and facingAngle < 0) then
            return scaleFar
        else
            return scaleNear
        end
    end

    -- 深度排序（远侧先画）
    local drawOrder = { -1, 1 }
    if facingAngle < 0 then drawOrder = { 1, -1 } end

    local eyeSpacing = r * 0.25
    local baseEyeR = r * 0.13
    local eyeY = -r * 0.05

    for _, side in ipairs(drawOrder) do
        local sc = sideScale(side)
        local ex = faceShift + side * eyeSpacing * sc
        local er = baseEyeR * sc

        -- 橙色豆豆眼（纯实心小圆点，无瞳孔）
        nvgBeginPath(vg)
        nvgCircle(vg, ex, eyeY, er)
        nvgFillColor(vg, nvgRGBAf(1.0, 0.55, 0.0, 1.0))
        nvgFill(vg)
    end

    -- hitFlash
    if flash > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, r)
        nvgFillColor(vg, nvgRGBAf(1.0, 1.0, 1.0, flash * 0.5))
        nvgFill(vg)
    end

    nvgRestore(vg)
end

-- ——— 噩梦猫 Nightmare Cat ———
-- 深色圆形身体 + 大号粉红圆环眼睛占主体 + 两个尖耳朵 + 弯曲尾巴
-- 纯色设计，无渐变；眼睛跟随玩家方向偏移；移动时Q弹缩放
function drawNightmareCat(vg, e, flash)
    local cx, cy, r = e.x, e.y, e.radius
    local player = Player.getData()

    -- Q弹缩放动画（基于 age 做呼吸/蹦跳效果）
    local bounceFreq = 3.5  -- 弹跳频率
    local bounceAmp  = 0.06 -- 幅度 6%
    local breathT = math.sin(e.age * bounceFreq) * bounceAmp
    local scaleX = 1.0 + breathT
    local scaleY = 1.0 - breathT  -- X扩Y缩，产生Q弹感

    -- 应用缩放变换
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, scaleX, scaleY)
    -- 此后以 (0,0) 为中心绘制

    -- 颜色定义（纯色，无渐变）
    local bodyR, bodyG, bodyB = 0.14, 0.12, 0.22  -- 深灰紫身体
    local eyeR_col, eyeG, eyeB = 0.85, 0.25, 0.35 -- 粉红圆环眼
    local pupilR_col, pupilG, pupilB = 0.12, 0.08, 0.15 -- 深色瞳孔
    if flash > 0 then
        bodyR, bodyG, bodyB = 0.6, 0.5, 0.6
    end

    -- === 尾巴（绘制在身体后面）===
    local tailStartX = r * 0.6
    local tailStartY = r * 0.3
    nvgBeginPath(vg)
    nvgMoveTo(vg, tailStartX, tailStartY)
    nvgBezierTo(vg, r*1.4, tailStartY + r*0.3,
                    r*1.6, -r*0.2,
                    r*1.2, -r*1.0)
    nvgStrokeColor(vg, nvgRGBAf(bodyR + 0.05, bodyG + 0.03, bodyB + 0.05, 1.0))
    nvgStrokeWidth(vg, r * 0.28)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- === 耳朵（大三角，底部宽）===
    local earH = r * 1.0
    -- 左耳
    nvgBeginPath(vg)
    nvgMoveTo(vg, -r*0.85, -r*0.25)   -- 底部左点
    nvgLineTo(vg, -r*0.6, -r*0.25 - earH)   -- 尖端
    nvgLineTo(vg, -r*0.1, -r*0.45)    -- 底部右点
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(bodyR, bodyG, bodyB, 1.0))
    nvgFill(vg)
    -- 右耳
    nvgBeginPath(vg)
    nvgMoveTo(vg, r*0.1, -r*0.45)     -- 底部左点
    nvgLineTo(vg, r*0.6, -r*0.25 - earH)    -- 尖端
    nvgLineTo(vg, r*0.85, -r*0.25)    -- 底部右点
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(bodyR, bodyG, bodyB, 1.0))
    nvgFill(vg)

    -- === 身体（毛茸茸的毛刺球）===
    -- 先画主体圆
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r * 0.85)
    nvgFillColor(vg, nvgRGBAf(bodyR, bodyG, bodyB, 1.0))
    nvgFill(vg)

    -- 用一圈大小不一的圆形突起模拟毛茸茸感（柔和圆弧，不是尖刺）
    -- 根据移动方向产生形态变化：前方压缩，后方舒展（像毛被风吹向后）
    local mdx = player.x - e.x
    local mdy = player.y - e.y
    local mdist = math.sqrt(mdx * mdx + mdy * mdy)
    local moveAngle = 0
    if mdist > 1 then
        moveAngle = math.atan(mdy, mdx)
    end

    local furCount = 14
    local seed = 7919  -- 固定种子，让毛刺位置稳定不跳动
    for i = 1, furCount do
        local angle = (i / furCount) * math.pi * 2
        -- 用固定伪随机偏移让每个毛球大小/位置略有差异
        seed = (seed * 1103 + 2731) & 0x7fff
        local rndSize = 0.8 + (seed % 100) / 250.0  -- 0.8~1.2 范围
        seed = (seed * 1103 + 2731) & 0x7fff
        local rndDist = 0.9 + (seed % 100) / 500.0  -- 0.9~1.1 范围

        -- 方向感：计算该毛球与移动方向的夹角
        -- dot = cos(angle - moveAngle)，1=正前方，-1=正后方
        local dot = math.cos(angle - moveAngle)
        -- 前方(dot>0)压缩：距离缩短、毛球缩小
        -- 后方(dot<0)舒展：距离拉长、毛球放大
        local dirFactor = -dot * 0.25  -- [-0.25, +0.25]
        local bumpR = r * 0.28 * rndSize * (1.0 + dirFactor * 0.5)
        local bumpDist = r * 0.72 * rndDist * (1.0 + dirFactor)
        local bx = math.cos(angle) * bumpDist
        local by = math.sin(angle) * bumpDist

        nvgBeginPath(vg)
        nvgCircle(vg, bx, by, bumpR)
        nvgFillColor(vg, nvgRGBAf(bodyR, bodyG, bodyB, 1.0))
        nvgFill(vg)
    end

    -- === 圆环眼睛 ===
    -- 眼睛跟随玩家方向偏移
    local dx = player.x - e.x
    local dy = player.y - e.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local eyeOffX, eyeOffY = 0, 0
    if dist > 1 then
        local maxOff = r * 0.3  -- 偏移量加大，更明显
        eyeOffX = (dx / dist) * maxOff
        eyeOffY = (dy / dist) * maxOff
    end

    local ringOuterR = r * 0.5   -- 缩小圆环外半径
    local ringInnerR = r * 0.25  -- 缩小圆环内半径

    -- 圆环（外圆减去内圆）
    nvgBeginPath(vg)
    nvgCircle(vg, eyeOffX, eyeOffY, ringOuterR)
    -- 用 pathWinding 做减法孔洞
    nvgPathWinding(vg, NVG_HOLE)
    nvgCircle(vg, eyeOffX, eyeOffY, ringInnerR)
    nvgFillColor(vg, nvgRGBAf(eyeR_col, eyeG, eyeB, 1.0))
    nvgFill(vg)

    -- 瞳孔（圆环中心的小实心圆）
    local pupilRadius = r * 0.12
    nvgBeginPath(vg)
    nvgCircle(vg, eyeOffX, eyeOffY, pupilRadius)
    nvgFillColor(vg, nvgRGBAf(pupilR_col, pupilG, pupilB, 1.0))
    nvgFill(vg)

    -- hitFlash 白闪叠加
    if flash > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, r)
        nvgFillColor(vg, nvgRGBAf(1.0, 1.0, 1.0, flash * 0.5))
        nvgFill(vg)
    end

    nvgRestore(vg)
end

-- ═══════════════════════════════════════════
-- 暴露绘制方法（供 Bestiary 页面调用）
-- 参数: vg, cx, cy, radius, age (用于动画)
-- ═══════════════════════════════════════════
function M.drawFogWraithStatic(vg, cx, cy, radius, age)
    local e = {
        x = cx, y = cy, radius = radius,
        age = age or 0, hitFlash = 0, etype = "scout",
    }
    -- 模拟玩家在右方（让眼睛看向右侧）
    local savedPlayer = Player.getData
    Player.getData = function() return { x = cx + 100, y = cy } end
    drawFogWraith(vg, e, 0)
    Player.getData = savedPlayer
end

function M.drawNightmareCatStatic(vg, cx, cy, radius, age)
    local e = {
        x = cx, y = cy, radius = radius,
        age = age or 0, hitFlash = 0, etype = "heavy",
        shootTimer = 99,
    }
    local savedPlayer = Player.getData
    Player.getData = function() return { x = cx + 100, y = cy } end
    drawNightmareCat(vg, e, 0)
    Player.getData = savedPlayer
end

function M.drawGhostEyeStatic(vg, cx, cy, radius, age)
    local e = {
        x = cx, y = cy, radius = radius,
        age = age or 0, hitFlash = 0, etype = "sniper",
        shootTimer = 99,
    }
    local savedPlayer = Player.getData
    Player.getData = function() return { x = cx + 100, y = cy } end
    drawGhostEye(vg, e, 0)
    Player.getData = savedPlayer
end

--- 获取敌人类型配置（供 Bestiary 使用）
function M.getEnemyTypes()
    return ENEMY_TYPES
end

-- ——— 幽灵眼 Ghost Eye ———
-- 光滑白圆身体 + 纯色红虹膜 + 黑瞳孔（蓄力时变竖线）+ 底部触须 + 伪3D注视
function drawGhostEye(vg, e, flash)
    local cx, cy, r = e.x, e.y, e.radius
    local player = Player.getData()

    -- 蓄力状态
    local charging = (e.shootTimer or 99) < 0.8
    local chargeT  = charging and (1.0 - e.shootTimer / 0.8) or 0.0

    -- 蓄力时微微前倾缩放（X稍大Y稍小，瞄准紧张感）
    local scX = 1.0 + chargeT * 0.08
    local scY = 1.0 - chargeT * 0.06

    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, scX, scY)

    -- === 底部触须（3条，先画在身体后面）===
    local tentacleColor = flash > 0 and 0.7 or 0.75
    nvgStrokeColor(vg, nvgRGBAf(tentacleColor, tentacleColor, tentacleColor, 1.0))
    nvgStrokeWidth(vg, r * 0.12)
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 3 do
        local baseAngle = math.pi * 0.5 + (i - 2) * 0.4  -- 底部扇开
        local sway = math.sin(e.age * 2.0 + i * 1.5) * 0.15  -- 轻微摆动
        local angle = baseAngle + sway
        local startX = math.cos(angle) * r * 0.6
        local startY = math.sin(angle) * r * 0.6
        local endX = math.cos(angle) * r * 1.4
        local endY = math.sin(angle) * r * 1.4
        -- 贝塞尔弯曲
        local ctrlX = (startX + endX) * 0.5 + math.sin(e.age * 1.8 + i) * r * 0.2
        local ctrlY = (startY + endY) * 0.5
        nvgBeginPath(vg)
        nvgMoveTo(vg, startX, startY)
        nvgQuadTo(vg, ctrlX, ctrlY, endX, endY)
        nvgStroke(vg)
    end

    -- === 身体（光滑纯白圆 — 和毛刺球区分）===
    local bodyW = flash > 0 and 0.7 or 0.92
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r)
    nvgFillColor(vg, nvgRGBAf(bodyW, bodyW - 0.02, bodyW - 0.02, 1.0))
    nvgFill(vg)

    -- === 虹膜 + 瞳孔（伪3D注视偏移）===
    local dx = player.x - e.x
    local dy = player.y - e.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- 注视偏移（虹膜整体跟随玩家移动）
    local eyeOffX, eyeOffY = 0, 0
    if dist > 1 then
        local maxOff = r * 0.25
        eyeOffX = (dx / dist) * maxOff
        eyeOffY = (dy / dist) * maxOff
    end

    -- 虹膜（纯色深红）
    local irisR = r * 0.5
    nvgBeginPath(vg)
    nvgCircle(vg, eyeOffX, eyeOffY, irisR)
    nvgFillColor(vg, nvgRGBAf(0.8, 0.05, 0.1, 1.0))
    nvgFill(vg)

    -- 瞳孔（蓄力时从圆形变成竖线椭圆）
    local pupilW = irisR * (0.4 - chargeT * 0.3)   -- 宽度缩小
    local pupilH = irisR * 0.45                      -- 高度保持
    nvgBeginPath(vg)
    nvgEllipse(vg, eyeOffX, eyeOffY, pupilW, pupilH)
    nvgFillColor(vg, nvgRGBAf(0.02, 0.0, 0.02, 1.0))
    nvgFill(vg)

    -- 高光小点（右上，增加立体感）
    nvgBeginPath(vg)
    nvgCircle(vg, eyeOffX + irisR * 0.3, eyeOffY - irisR * 0.35, r * 0.1)
    nvgFillColor(vg, nvgRGBAf(1.0, 1.0, 1.0, 0.85))
    nvgFill(vg)

    -- hitFlash
    if flash > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, r)
        nvgFillColor(vg, nvgRGBAf(1.0, 1.0, 1.0, flash * 0.5))
        nvgFill(vg)
    end

    nvgRestore(vg)
end

return M
