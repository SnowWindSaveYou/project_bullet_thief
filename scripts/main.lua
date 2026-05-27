-- ============================================================================
-- BulletThief - 主入口
-- 类幸存者游戏：夺取敌人子弹，以其人之道还治其人之身
-- 所有渲染均通过 raw NanoVG，不使用 urhox-libs/UI 组件系统
-- ============================================================================

local Tween = require "lib.Tween"
local VFX   = require "lib.VFX"

local GameState    = require "game.GameState"
local Renderer     = require "game.Renderer"
local Input        = require "game.InputHandler"
local Player       = require "game.Player"
local EnemyMgr     = require "game.EnemyManager"
local BossMgr      = require "game.BossManager"
local BulletMgr    = require "game.BulletManager"
local ItemMgr      = require "game.ItemManager"
local UI           = require "game.GameUI"
local Upgrade      = require "game.UpgradeSystem"

-- 新增页面
local PagePreLevel = require "ui.PagePreLevel"
local PageBestiary = require "ui.PageBestiary"
local PagePractice = require "ui.PagePractice"
local DebugPanel   = require "ui.DebugPanel"

-- ============================================================================
-- 全局上下文
-- ============================================================================
---@type userdata  NanoVG 渲染上下文
local vg = nil

-- 逻辑分辨率（基于物理分辨率 / DPR）
local W, H = 0, 0
local dpr  = 1.0

local gameTime = 0.0
local isRunning = false
local wasBulletTime = false  -- 子弹时间闪光追踪

-- 高分记录
local highScore_ = 0
-- 难度倍率
local difficultyMult_ = 1.0
-- 练习模式标记
local practiceMode_ = false

-- ============================================================================
-- 引擎入口
-- ============================================================================
function Start()
    local phW = graphics:GetWidth()
    local phH = graphics:GetHeight()
    dpr       = graphics:GetDPR()
    W         = phW / dpr
    H         = phH / dpr

    print(string.format("[BulletThief] 分辨率: %dx%d  DPR: %.1f  逻辑: %.0fx%.0f",
        phW, phH, dpr, W, H))

    -- 创建 NanoVG 上下文（AA 模式）
    vg = nvgCreate(1)
    assert(vg ~= nil, "NanoVG 创建失败")

    -- 加载字体
    local fontOk = nvgCreateFont(vg, "sans",  "Fonts/MiSans-Regular.ttf")
    nvgCreateFont(vg, "bold",  "Fonts/MiSans-Regular.ttf")
    nvgCreateFont(vg, "pixel", "Fonts/MiSans-Regular.ttf")
    assert(fontOk ~= -1, "字体加载失败: Fonts/MiSans-Regular.ttf")

    -- 初始化各子系统
    GameState.init()
    Renderer.init(vg, W, H, dpr)
    Player.init(W, H)
    EnemyMgr.init(W, H)
    BossMgr.init(W, H)
    BulletMgr.init(W, H)
    ItemMgr.init(W, H)
    UI.init(vg, W, H)
    Upgrade.init()
    Input.init(W, H)

    -- 新页面初始化
    PagePreLevel.init(W, H)
    PageBestiary.init(W, H)
    PagePractice.init(W, H)
    DebugPanel.init(W, H)

    VFX.setContext(vg, W, H, 0)

    -- 订阅事件
    SubscribeToEvent(vg, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update",           "HandleUpdate")
    SubscribeToEvent("KeyDown",          "HandleKeyDown")
    SubscribeToEvent("KeyUp",            "HandleKeyUp")
    SubscribeToEvent("MouseButtonDown",  "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp",    "HandleMouseUp")
    SubscribeToEvent("MouseMove",        "HandleMouseMove")
    SubscribeToEvent("TouchBegin",       "HandleTouchBegin")
    SubscribeToEvent("TouchMove",        "HandleTouchMove")
    SubscribeToEvent("TouchEnd",         "HandleTouchEnd")

    isRunning = true
    print("[BulletThief] 初始化完成，进入菜单")
end

function Stop()
    if vg ~= nil then
        nvgDelete(vg)
        vg = nil
    end
end

-- ============================================================================
-- 主更新
-- ============================================================================
---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if not isRunning then return end
    local dt = eventData["TimeStep"]:GetFloat()
    dt = math.min(dt, 0.05) -- 限制最大步长，防止卡帧导致穿透

    gameTime = gameTime + dt
    Tween.update(dt)

    local state = GameState.get()

    if state == "menu" then
        GameState.updateMenu(dt)

    elseif state == "prelevel" then
        PagePreLevel.update(dt)

    elseif state == "bestiary" then
        PageBestiary.update(dt)

    elseif state == "practice" then
        -- 练习模式：与 playing 相同的游戏逻辑，但不自动生成敌人
        PagePractice.update(dt)
        Input.update(dt)
        Player.update(dt)

        local isBT = Player.getData().bulletTimeActive
        if isBT and not wasBulletTime then
            VFX.triggerBTFlash()
        end
        wasBulletTime = isBT
        local btScale = isBT and 0.2 or 1.0
        local slowDt  = dt * btScale

        EnemyMgr.update(slowDt)
        BulletMgr.update(slowDt, dt)
        ItemMgr.update(dt)
        VFX.setContext(vg, W, H, gameTime)
        VFX.updateAll(dt)

        -- 碰撞检测
        checkCollisions(dt)

        -- 练习模式：玩家不会死，HP 低时自动回满
        local pData = Player.getData()
        if pData.hp <= 0 then
            pData.hp = pData.maxHp
        end

        UI.update(dt)
        Input.endFrame()

    elseif state == "playing" then
        -- 暂停时只更新 UI 动画（Tween 已在上方全局 update）
        if UI.isPaused() then
            UI.update(dt)
            Input.endFrame()
        else
            Input.update(dt)
            Player.update(dt)

            -- 子弹时间：主观慢动作，敌人/子弹速度降至 20%
            local isBT = Player.getData().bulletTimeActive
            if isBT and not wasBulletTime then
                VFX.triggerBTFlash()
            end
            wasBulletTime = isBT
            local btScale = isBT and 0.2 or 1.0
            local slowDt  = dt * btScale

            EnemyMgr.update(slowDt)
            BossMgr.update(slowDt)
            BulletMgr.update(slowDt, dt)
            ItemMgr.update(dt)
            VFX.setContext(vg, W, H, gameTime)
            VFX.updateAll(dt)

            -- Boss 触发检测
            BossMgr.checkSpawn(Player.getKillCount())

            -- Boss 召唤小怪（转调 EnemyMgr）
            local summonCount = BossMgr.getPendingSummon()
            for _ = 1, summonCount do
                EnemyMgr.forceSpawn()
            end

            -- 碰撞检测
            checkCollisions(dt)

            -- UI 动画更新
            UI.update(dt)

            -- 帧末重置输入 delta
            Input.endFrame()
        end

    elseif state == "upgrade" then
        UI.update(dt)
        Upgrade.update(dt)

    elseif state == "gameover" then
        UI.update(dt)
    end
end

-- ============================================================================
-- 碰撞检测总入口
-- ============================================================================
function checkCollisions(dt)
    local player = Player.getData()
    local bullets = BulletMgr.getBullets()
    local enemies = EnemyMgr.getEnemies()
    local items   = ItemMgr.getItems()

    -- 1. 敌方子弹 vs 玩家
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        if b.owner == "enemy" and not b.dead then
            local dx = b.x - player.x
            local dy = b.y - player.y
            local dist = math.sqrt(dx * dx + dy * dy)

            -- 迫击炮不做直接碰撞（它的伤害在 AOE 阶段处理）
            if b.btype == "mortar" then
                goto continue_bullet
            end

            -- 擦弹
            if dist < player.grazeRadius and not b.grazed then
                b.grazed = true
                local grazeFactor = 1.0 - (dist / player.grazeRadius)
                Player.addEnergy(0.08 * grazeFactor)
                VFX.spawnGraze(b.x, b.y, player.x, player.y)
                VFX.spawnPopup("+EN", b.x, b.y, 100, 220, 255)
            end

            -- 命中判定
            if dist < (player.radius + b.radius) then
                if player.bulletTimeActive then
                    BulletMgr.stealBullet(i)
                    Player.onSteal()
                    VFX.spawnPopup("STEAL!", b.x, b.y, 80, 255, 200)
                else
                    b.dead = true
                    Player.takeDamage(b.damage or 1)
                    VFX.triggerShake(6, 0.25)
                    VFX.spawnHit(b.x, b.y, 255, 80, 80)
                    VFX.spawnPopup("-" .. (b.damage or 1), player.x, player.y - 40, 255, 80, 80)
                end
            end
        end
        ::continue_bullet::
    end

    -- 1b. 迫击炮 AOE 范围伤害检测（落地爆炸后对玩家造成伤害）
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        if b.aoeTriggered then
            local dx = b.aoeX - player.x
            local dy = b.aoeY - player.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < b.aoeRadius then
                -- 距离衰减：中心全伤害，边缘半伤害
                local dmgFactor = 1.0 - (dist / b.aoeRadius) * 0.5
                local aoeDmg = math.ceil((b.damage or 2) * dmgFactor)
                Player.takeDamage(aoeDmg)
                VFX.spawnPopup("-" .. aoeDmg, player.x, player.y - 40, 255, 100, 30)
            end
            b.aoeTriggered = false  -- 只触发一次
        end
    end

    -- 1c. 激光 vs 玩家（线段碰撞检测，持续伤害每 0.25s 一次）
    local lasers = EnemyMgr.getActiveLasers()
    for li, laser in ipairs(lasers) do
        -- 点到线段距离计算
        local lx1, ly1 = laser.x1, laser.y1
        local lx2, ly2 = laser.x2, laser.y2
        local segDx, segDy = lx2 - lx1, ly2 - ly1
        local segLenSq = segDx * segDx + segDy * segDy
        if segLenSq > 0 then
            local t = ((player.x - lx1) * segDx + (player.y - ly1) * segDy) / segLenSq
            t = math.max(0, math.min(1, t))
            local closestX = lx1 + t * segDx
            local closestY = ly1 + t * segDy
            local pdx = player.x - closestX
            local pdy = player.y - closestY
            local pDist = math.sqrt(pdx * pdx + pdy * pdy)
            local hitWidth = (laser.width or 8) * 0.5 + player.radius
            if pDist < hitWidth then
                -- 检查 tick 计时
                if laser.dmgTick >= 0.25 then
                    Player.takeDamage(laser.damage or 1)
                    EnemyMgr.resetLaserDmgTick(laser.enemyIdx)
                    VFX.spawnHit(closestX, closestY, 255, 50, 50)
                    VFX.spawnPopup("-" .. (laser.damage or 1), player.x, player.y - 40, 255, 50, 50)
                    VFX.triggerShake(4, 0.15)
                end
            end
        end
    end

    -- 2a. 轨道子弹 vs 敌人（含 collecting 阶段，但子弹时间内夺取的需等结束后才生效）
    local orbitBullets = BulletMgr.getOrbitBullets()
    for oi = #orbitBullets, 1, -1 do
        local ob = orbitBullets[oi]
        if ob.btShielded then goto continue_orbit end
        for ei = #enemies, 1, -1 do
            local e = enemies[ei]
            if not e.dead then
                local dx   = ob.x - e.x
                local dy   = ob.y - e.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < (7 + e.radius) then
                    local dmg = (ob.damage or 1) * (player.orbitDamage or 1)
                    EnemyMgr.damageEnemy(ei, dmg, true)
                    BulletMgr.removeOrbitBullet(oi)
                    VFX.spawnHit(ob.x, ob.y, 100, 220, 255)
                    VFX.spawnPopup(tostring(dmg), e.x, e.y - 24, 100, 220, 255)
                    VFX.triggerShake(3, 0.1)
                    break
                end
            end
        end
        ::continue_orbit::
    end

    -- 2b. 玩家子弹 vs 敌人
    for ei = #enemies, 1, -1 do
        local e = enemies[ei]
        if not e.dead then
            for bi = #bullets, 1, -1 do
                local b = bullets[bi]
                if b.owner == "player" and not b.dead then
                    local bdx   = b.x - e.x
                    local bdy   = b.y - e.y
                    local bdist = math.sqrt(bdx * bdx + bdy * bdy)
                    if bdist < (b.radius + e.radius) then
                        b.dead = true
                        EnemyMgr.damageEnemy(ei, b.damage or 1, true)
                        VFX.spawnHit(b.x, b.y, 100, 220, 255)
                        VFX.spawnPopup(tostring(b.damage or 1), e.x, e.y - 30, 100, 220, 255)
                    end
                end
            end
        end
    end

    -- 2c. 轨道子弹 vs Boss
    if BossMgr.isActive() then
        local bossData = BossMgr.getBoss()
        if bossData and not bossData.dead then
            for oi = #orbitBullets, 1, -1 do
                local ob = orbitBullets[oi]
                if ob.btShielded then goto continue_orbit_boss end
                local bdx = ob.x - bossData.x
                local bdy = ob.y - bossData.y
                local bdist = math.sqrt(bdx * bdx + bdy * bdy)
                if bdist < (7 + bossData.radius) then
                    local dmg = (ob.damage or 1) * (player.orbitDamage or 1)
                    BossMgr.damageBoss(dmg)
                    BulletMgr.removeOrbitBullet(oi)
                    VFX.spawnHit(ob.x, ob.y, 180, 100, 255)
                    VFX.spawnPopup(tostring(dmg), bossData.x, bossData.y - 30, 180, 100, 255)
                    VFX.triggerShake(3, 0.1)
                    break
                end
                ::continue_orbit_boss::
            end

            -- 2d. 玩家子弹 vs Boss
            for bi = #bullets, 1, -1 do
                local b = bullets[bi]
                if b.owner == "player" and not b.dead then
                    local bdx = b.x - bossData.x
                    local bdy = b.y - bossData.y
                    local bdist = math.sqrt(bdx * bdx + bdy * bdy)
                    if bdist < (b.radius + bossData.radius) then
                        b.dead = true
                        BossMgr.damageBoss(b.damage or 1)
                        VFX.spawnHit(b.x, b.y, 180, 100, 255)
                        VFX.spawnPopup(tostring(b.damage or 1), bossData.x, bossData.y - 30, 180, 100, 255)
                    end
                end
            end

            -- 2e. Boss 激光 vs 玩家
            local bossLasers = BossMgr.getActiveLasers()
            for _, laser in ipairs(bossLasers) do
                local lx1, ly1 = laser.x1, laser.y1
                local lx2, ly2 = laser.x2, laser.y2
                local segDx, segDy = lx2 - lx1, ly2 - ly1
                local segLenSq = segDx * segDx + segDy * segDy
                if segLenSq > 0 then
                    local t = ((player.x - lx1) * segDx + (player.y - ly1) * segDy) / segLenSq
                    t = math.max(0, math.min(1, t))
                    local closestX = lx1 + t * segDx
                    local closestY = ly1 + t * segDy
                    local pdx = player.x - closestX
                    local pdy = player.y - closestY
                    local pDist = math.sqrt(pdx * pdx + pdy * pdy)
                    local hitWidth = (laser.width or 12) * 0.5 + player.radius
                    if pDist < hitWidth and laser.dmgTick >= 0.25 then
                        Player.takeDamage(laser.damage or 2)
                        BossMgr.resetBossLaserDmgTick()
                        VFX.spawnHit(closestX, closestY, 180, 0, 255)
                        VFX.spawnPopup("-" .. (laser.damage or 2), player.x, player.y - 40, 180, 0, 255)
                        VFX.triggerShake(5, 0.2)
                    end
                end
            end
        end
    end

    -- 3. 道具拾取
    for i = #items, 1, -1 do
        local item = items[i]
        if not item.dead then
            local dx = item.x - player.x
            local dy = item.y - player.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < (player.radius + item.radius) then
                ItemMgr.pickupItem(i)
                applyItemEffect(item)
            end
        end
    end

    -- 4. 玩家死亡
    if player.hp <= 0 and GameState.get() == "playing" then
        -- 更新高分
        local killCount = Player.getKillCount()
        if killCount > highScore_ then
            highScore_ = killCount
        end
        GameState.set("gameover")
        UI.showGameOver(killCount)
        VFX.triggerShake(15, 0.6)
    end

    -- 5. 升级触发
    local kc = Player.getKillCount()
    local upgradeThreshold = Upgrade.getNextThreshold()
    if kc >= upgradeThreshold and not Upgrade.isShowing() then
        GameState.set("upgrade")
        Upgrade.show()
    end
end

-- 应用道具效果
function applyItemEffect(item)
    if item.type == "heal" then
        Player.heal(15)
        VFX.spawnHeal(Player.getData(), Player.getData().radius)
        VFX.spawnBanner("HEAL", 80, 200, 80)
    elseif item.type == "energy" then
        Player.addEnergy(0.4)
        VFX.spawnBanner("CHARGE", 80, 220, 255)
    elseif item.type == "coin" then
        Player.addCoins(item.value or 1)
        VFX.spawnPopup("+" .. (item.value or 1), item.x, item.y, 255, 210, 50)
    elseif item.type == "magnet" then
        ItemMgr.activateMagnet(Player.getData(), 5.0)
        VFX.spawnBanner("MAGNET", 100, 150, 255)
    end
end

-- ============================================================================
-- 开始游戏（从 prelevel 进入 playing）
-- ============================================================================
local function startGame()
    difficultyMult_ = PagePreLevel.getSelectedDifficulty()
    practiceMode_ = false
    GameState.set("playing")
    Player.reset(W, H)
    EnemyMgr.reset()
    BossMgr.reset()
    BulletMgr.reset()
    ItemMgr.reset()
    Upgrade.reset()
    VFX.resetAll()
    UI.hideMenu()
    print("[BulletThief] 开始游戏 difficulty=" .. difficultyMult_)
end

-- ============================================================================
-- 练习模式（空场地，手动召唤敌人）
-- ============================================================================
local function startPractice()
    practiceMode_ = true
    GameState.set("practice")
    Player.reset(W, H)
    EnemyMgr.reset()
    EnemyMgr.setAutoSpawn(false)  -- 禁用自动生成
    BossMgr.reset()
    BulletMgr.reset()
    ItemMgr.reset()
    VFX.resetAll()
    UI.hideMenu()
    PagePractice.show()
    print("[BulletThief] 进入练习模式")
end

--- 处理练习模式召唤
local function handlePracticeSummon()
    local spawnList = PagePractice.getSpawnList()
    for _, entry in ipairs(spawnList) do
        for _ = 1, entry.count do
            if entry.type == "boss" then
                -- Boss 只能存在一个，重复召唤忽略
                if not BossMgr.isActive() then
                    BossMgr.spawnBoss()
                end
            else
                EnemyMgr.spawnType(entry.type)
            end
        end
    end
end

-- ============================================================================
-- 渲染
-- ============================================================================
function HandleRender(eventType, eventData)
    if not isRunning then return end

    local phW = graphics:GetWidth()
    local phH = graphics:GetHeight()

    nvgBeginFrame(vg, phW, phH, dpr)

    local state = GameState.get()

    if state == "menu" then
        Renderer.drawBackground(state)
        UI.draw(vg, state)

    elseif state == "prelevel" then
        PagePreLevel.draw(vg, W, H)

    elseif state == "bestiary" then
        PageBestiary.draw(vg, W, H)

    elseif state == "practice" then
        -- 练习模式：渲染游戏世界 + 浮动面板
        Renderer.drawBackground("playing")
        local shakeX, shakeY = VFX.getShakeOffset()
        nvgSave(vg)
        nvgTranslate(vg, shakeX, shakeY)
        Renderer.drawWorld()
        ItemMgr.draw(vg)
        EnemyMgr.draw(vg)
        EnemyMgr.drawLasers(vg)
        BossMgr.draw(vg)
        BossMgr.drawLasers(vg)
        BulletMgr.draw(vg)
        Player.draw(vg)
        VFX.drawAOEExplosions()
        VFX.drawHitEffects()
        VFX.drawGrazeSparks()
        VFX.drawHealEffects()
        VFX.drawBanners()
        VFX.drawPopups()
        nvgRestore(vg)

        if Player.getData().bulletTimeActive then
            Renderer.drawVignette(0.55)
        end
        VFX.drawBTFlash()
        BulletMgr.drawQTEFlash(vg, W, H)
        BossMgr.drawHPBar(vg)
        UI.draw(vg, "playing")

        -- 练习面板覆盖在最上方
        PagePractice.draw(vg, W, H)

    elseif state == "playing" or state == "upgrade" then
        Renderer.drawBackground(state)
        local shakeX, shakeY = VFX.getShakeOffset()
        nvgSave(vg)
        nvgTranslate(vg, shakeX, shakeY)
        Renderer.drawWorld()
        ItemMgr.draw(vg)
        EnemyMgr.draw(vg)
        EnemyMgr.drawLasers(vg)
        BossMgr.draw(vg)
        BossMgr.drawLasers(vg)
        BulletMgr.draw(vg)
        Player.draw(vg)
        VFX.drawAOEExplosions()
        VFX.drawHitEffects()
        VFX.drawGrazeSparks()
        VFX.drawHealEffects()
        VFX.drawBanners()
        VFX.drawPopups()
        nvgRestore(vg)

        -- 子弹时间四角压暗 + 全屏闪光
        if Player.getData().bulletTimeActive then
            Renderer.drawVignette(0.55)
        end
        VFX.drawBTFlash()

        -- QTE 爆发全屏闪光
        BulletMgr.drawQTEFlash(vg, W, H)

        -- Boss 血条（在 shake 之外，固定位置）
        BossMgr.drawHPBar(vg)

        -- UI 层
        UI.draw(vg, state)

        -- 升级界面覆盖
        if state == "upgrade" then
            Upgrade.draw(vg, W, H)
        end

    elseif state == "gameover" then
        Renderer.drawBackground(state)
        UI.draw(vg, state)
    end

    -- Debug 面板始终在最上层
    DebugPanel.draw(vg, W, H)

    -- CRT 扫线叠加（Balatro 风格，最顶层覆盖）
    Renderer.drawScanlines(3, 0.12)

    nvgEndFrame(vg)
end

-- ============================================================================
-- 输入事件
-- ============================================================================
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    Input.onKeyDown(key)

    local state = GameState.get()

    -- Debug 面板切换（KEY_0 = 数字0）
    if key == KEY_0 then
        DebugPanel.toggle()
        return
    end

    -- Debug 面板打开时拦截其他按键
    if DebugPanel.isVisible() then
        if key == KEY_ESCAPE then
            DebugPanel.hide()
        end
        return
    end

    if state == "menu" then
        if key == KEY_RETURN or key == KEY_SPACE then
            GameState.set("prelevel")
            PagePreLevel.show(highScore_)
        end
    elseif state == "playing" then
        if key == KEY_ESCAPE then
            if UI.isPaused() then
                UI.hidePause()
            else
                UI.showPause()
            end
        end
    elseif state == "prelevel" then
        if key == KEY_ESCAPE then
            GameState.set("menu")
            UI.showMenu()
        elseif key == KEY_RETURN or key == KEY_SPACE then
            startGame()
        end
    elseif state == "bestiary" then
        if key == KEY_ESCAPE then
            GameState.set("prelevel")
            PagePreLevel.show(highScore_)
        end
    elseif state == "practice" then
        if key == KEY_ESCAPE then
            practiceMode_ = false
            GameState.set("prelevel")
            PagePreLevel.show(highScore_)
        end
    elseif state == "gameover" then
        if key == KEY_RETURN or key == KEY_SPACE then
            GameState.set("menu")
            UI.showMenu()
        end
    end
end

function HandleKeyUp(eventType, eventData)
    Input.onKeyUp(eventData["Key"]:GetInt())
end

function HandleMouseDown(eventType, eventData)
    local btn = eventData["Button"]:GetInt()
    local x   = eventData["X"]:GetInt() / dpr
    local y   = eventData["Y"]:GetInt() / dpr
    Input.onMouseDown(btn, x, y)

    -- Debug 面板优先处理
    if DebugPanel.isVisible() then
        local action = DebugPanel.onClick(x, y)
        if action then
            handleDebugAction(action)
        end
        return
    end

    local state = GameState.get()

    if state == "menu" then
        GameState.set("prelevel")
        PagePreLevel.show(highScore_)

    elseif state == "prelevel" then
        local action = PagePreLevel.onClick(x, y)
        if action == "start" then
            startGame()
        elseif action == "bestiary" then
            GameState.set("bestiary")
            PageBestiary.show()
        elseif action == "practice" then
            startPractice()
        end

    elseif state == "playing" then
        -- 暂停弹窗优先
        if UI.isPaused() then
            local action = UI.onPauseClick(x, y)
            if action == "resume" then
                UI.hidePause()
            elseif action == "menu" then
                UI.hidePause()
                GameState.set("menu")
                UI.showMenu()
            end
            return
        end
        -- 暂停按钮
        if UI.hitPauseButton(x, y) then
            UI.showPause()
            return
        end

    elseif state == "bestiary" then
        local action = PageBestiary.onClick(x, y)
        if action == "back" then
            GameState.set("prelevel")
            PagePreLevel.show(highScore_)
        end

    elseif state == "practice" then
        local action = PagePractice.onClick(x, y)
        if action == "summon" then
            handlePracticeSummon()
        elseif action == "back" then
            practiceMode_ = false
            GameState.set("prelevel")
            PagePreLevel.show(highScore_)
        end

    elseif state == "gameover" then
        GameState.set("menu")
        UI.showMenu()

    elseif state == "upgrade" then
        Upgrade.onMouseClick(x, y)
    end
end

function HandleMouseUp(eventType, eventData)
    local btn = eventData["Button"]:GetInt()
    local x   = eventData["X"]:GetInt() / dpr
    local y   = eventData["Y"]:GetInt() / dpr
    Input.onMouseUp(btn, x, y)
end

function HandleMouseMove(eventType, eventData)
    local x = eventData["X"]:GetInt() / dpr
    local y = eventData["Y"]:GetInt() / dpr
    Input.onMouseMove(x, y)
    local Comp = require "ui.Components"
    Comp.setPointer(x, y)
end

function HandleTouchBegin(eventType, eventData)
    local touchId = eventData["TouchID"]:GetInt()
    local x = eventData["X"]:GetInt() / dpr
    local y = eventData["Y"]:GetInt() / dpr
    Input.onTouchBegin(touchId, x, y)

    -- Debug 面板优先
    if DebugPanel.isVisible() then
        local action = DebugPanel.onClick(x, y)
        if action then
            handleDebugAction(action)
        end
        return
    end

    local state = GameState.get()

    if state == "menu" then
        GameState.set("prelevel")
        PagePreLevel.show(highScore_)

    elseif state == "prelevel" then
        local action = PagePreLevel.onClick(x, y)
        if action == "start" then
            startGame()
        elseif action == "bestiary" then
            GameState.set("bestiary")
            PageBestiary.show()
        elseif action == "practice" then
            startPractice()
        end

    elseif state == "playing" then
        -- 暂停弹窗优先
        if UI.isPaused() then
            local action = UI.onPauseClick(x, y)
            if action == "resume" then
                UI.hidePause()
            elseif action == "menu" then
                UI.hidePause()
                GameState.set("menu")
                UI.showMenu()
            end
            return
        end
        -- 暂停按钮
        if UI.hitPauseButton(x, y) then
            UI.showPause()
            return
        end

    elseif state == "bestiary" then
        local action = PageBestiary.onClick(x, y)
        if action == "back" then
            GameState.set("prelevel")
            PagePreLevel.show(highScore_)
        end

    elseif state == "practice" then
        local action = PagePractice.onClick(x, y)
        if action == "summon" then
            handlePracticeSummon()
        elseif action == "back" then
            practiceMode_ = false
            GameState.set("prelevel")
            PagePreLevel.show(highScore_)
        end

    elseif state == "gameover" then
        GameState.set("menu")
        UI.showMenu()

    elseif state == "upgrade" then
        Upgrade.onTouchBegin(touchId, x, y)
    end
end

function HandleTouchMove(eventType, eventData)
    local touchId = eventData["TouchID"]:GetInt()
    local x = eventData["X"]:GetInt() / dpr
    local y = eventData["Y"]:GetInt() / dpr
    Input.onTouchMove(touchId, x, y)
end

function HandleTouchEnd(eventType, eventData)
    local touchId = eventData["TouchID"]:GetInt()
    Input.onTouchEnd(touchId)
end

-- ============================================================================
-- Debug 动作处理
-- ============================================================================
function handleDebugAction(action)
    local state = GameState.get()

    if action == "shop" then
        -- 一键调出商店（升级界面）
        if state == "playing" then
            GameState.set("upgrade")
            Upgrade.show()
            DebugPanel.hide()
        else
            print("[Debug] shop: 仅在 playing 状态可用")
        end

    elseif action == "heal" then
        if state == "playing" then
            local p = Player.getData()
            p.hp = p.maxHp
            VFX.spawnBanner("DEBUG: FULL HP", 80, 200, 80)
        end

    elseif action == "energy" then
        if state == "playing" then
            Player.addEnergy(1.0)
            VFX.spawnBanner("DEBUG: MAX EN", 80, 220, 255)
        end

    elseif action == "kill100" then
        if state == "playing" then
            for _ = 1, 100 do
                Player.addOrbitKill()
            end
            VFX.spawnBanner("DEBUG: +100 KILLS", 255, 210, 50)
        end

    elseif action == "godmode" then
        if state == "playing" then
            local p = Player.getData()
            p.maxHp = 9999
            p.hp = 9999
            VFX.spawnBanner("DEBUG: GOD MODE", 255, 80, 80)
        end
    end

    print("[Debug] 执行: " .. action)
end
