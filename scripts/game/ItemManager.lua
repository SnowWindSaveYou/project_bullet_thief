-- ============================================================================
-- ItemManager.lua - 道具掉落、漂浮、拾取
-- 道具类型: coin / heal / energy / magnet
-- ============================================================================

local Renderer = require "game.Renderer"

local M = {}

local W_, H_ = 0, 0

---@type table[]
local items_ = {}

local magnetActive_  = false
local magnetTimer_   = 0

-- 掉落概率配置（按敌人类型）
local DROP_CHANCE = {
    scout  = { coin = 0.35, energy = 0.15, heal = 0.05, magnet = 0.02 },
    heavy  = { coin = 0.25, energy = 0.20, heal = 0.12, magnet = 0.06 },
    sniper = { coin = 0.40, energy = 0.10, heal = 0.06, magnet = 0.03 },
    laser  = { coin = 0.45, energy = 0.25, heal = 0.10, magnet = 0.05 },
    boss   = { coin = 1.00, energy = 0.50, heal = 0.50, magnet = 0.30 },
}

function M.init(_W, _H)
    W_ = _W
    H_ = _H
    M.reset()
end

function M.reset()
    items_       = {}
    magnetActive_ = false
    magnetTimer_  = 0
end

function M.getItems()
    return items_
end

-- 尝试掉落道具（敌人死亡时调用）
function M.tryDrop(x, y, enemyCfg)
    local etype = enemyCfg and enemyCfg.etype or "scout"
    -- 修正：etype 可能在 cfg 上
    local chances = DROP_CHANCE[etype] or DROP_CHANCE.scout

    -- 随机掉落（可能掉多个）
    local types = { "coin", "energy", "heal", "magnet" }
    for _, t in ipairs(types) do
        if math.random() < (chances[t] or 0) then
            spawnItem(x + math.random(-15, 15), y + math.random(-15, 15), t)
        end
    end
end

function spawnItem(x, y, itype)
    local item = {
        x       = x,
        y       = y,
        type    = itype,
        radius  = 12,
        value   = 1,
        dead    = false,
        life    = 12.0,    -- 12 秒后消失
        age     = 0,
        floatOffset = 0,
        floatSpeed  = 1.5 + math.random() * 1.0,
        bobPhase    = math.random() * math.pi * 2,
        -- 弹出动画
        scaleAnim   = 0,
        scale       = 0,
    }
    -- 金币随机价值
    if itype == "coin" then
        item.value = math.random(1, 3)
    end
    table.insert(items_, item)
end

-- 激活磁铁效果（x 秒内自动吸引道具）
function M.activateMagnet(player, duration)
    magnetActive_ = true
    magnetTimer_  = duration
    print("[ItemMgr] 磁铁激活 " .. duration .. "s")
end

-- 拾取道具（由 main.lua 碰撞检测调用）
function M.pickupItem(idx)
    local item = items_[idx]
    if item then
        item.dead = true
    end
end

-- 更新
function M.update(dt)
    -- 磁铁计时
    if magnetActive_ then
        magnetTimer_ = magnetTimer_ - dt
        if magnetTimer_ <= 0 then
            magnetActive_ = false
        end
    end

    local player = nil
    if magnetActive_ then
        player = require("game.Player").getData()
    end

    for i = #items_, 1, -1 do
        local item = items_[i]
        if item.dead then
            table.remove(items_, i)
        else
            item.age  = item.age + dt
            item.life = item.life - dt
            if item.life <= 0 then
                item.dead = true
            else
                -- 弹出缩放动画
                if item.scaleAnim < 1 then
                    item.scaleAnim = math.min(1, item.scaleAnim + dt * 6)
                    -- easeOutBack
                    local t = item.scaleAnim
                    local c1, c3 = 1.70158, 2.70158
                    item.scale = 1 + c3 * ((t - 1)^3) + c1 * ((t - 1)^2)
                    item.scale = math.max(0, item.scale)
                else
                    item.scale = 1.0
                end

                -- 漂浮
                item.floatOffset = math.sin(item.age * item.floatSpeed + item.bobPhase) * 3.5

                -- 磁铁吸引
                if magnetActive_ and player then
                    local dx = player.x - item.x
                    local dy = player.y - item.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist > 1 then
                        local spd = math.min(300, 120 + (1 - dist / 300) * 200) * dt
                        item.x = item.x + (dx / dist) * spd
                        item.y = item.y + (dy / dist) * spd
                    end
                end
            end
        end
    end
end

-- 绘制
function M.draw(vg)
    for _, item in ipairs(items_) do
        if not item.dead then
            drawItem(vg, item)
        end
    end
end

function drawItem(vg, item)
    local drawY = item.y + item.floatOffset
    local s     = item.scale or 1.0

    nvgSave(vg)
    nvgTranslate(vg, item.x, drawY)
    nvgScale(vg, s, s)

    -- 斜投影阴影
    local ox, oy = Renderer.shadowOffset(math.abs(item.floatOffset))
    nvgBeginPath(vg)
    nvgCircle(vg, ox, oy + item.radius * 0.1, item.radius * 0.6)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.3))
    nvgFill(vg)

    -- 即将消失时闪烁（最后 3 秒）
    local alpha = 1.0
    if item.life < 3.0 then
        alpha = 0.4 + 0.6 * math.abs(math.sin(item.age * 6))
    end

    if item.type == "coin" then
        drawCoin(vg, item.radius, alpha)
    elseif item.type == "heal" then
        drawHeal(vg, item.radius, alpha)
    elseif item.type == "energy" then
        drawEnergy(vg, item.radius, alpha)
    elseif item.type == "magnet" then
        drawMagnet(vg, item.radius, alpha)
    end

    nvgRestore(vg)
end

-- 金币：黄色圆形，内有环形
function drawCoin(vg, r, alpha)
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r)
    nvgFillColor(vg, nvgRGBAf(1.0, 0.85, 0.1, alpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBAf(1.0, 0.65, 0.0, alpha * 0.8))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    -- 内圆
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r * 0.55)
    nvgStrokeColor(vg, nvgRGBAf(1.0, 0.5, 0.0, alpha * 0.5))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
end

-- 治疗：绿色十字形
function drawHeal(vg, r, alpha)
    local w = r * 0.35
    local h = r * 0.85
    -- 背景圆
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r)
    nvgFillColor(vg, nvgRGBAf(0.1, 0.6, 0.2, alpha * 0.8))
    nvgFill(vg)
    -- 横
    nvgBeginPath(vg)
    nvgRect(vg, -h, -w, h*2, w*2)
    nvgFillColor(vg, nvgRGBAf(0.3, 1.0, 0.4, alpha))
    nvgFill(vg)
    -- 竖
    nvgBeginPath(vg)
    nvgRect(vg, -w, -h, w*2, h*2)
    nvgFillColor(vg, nvgRGBAf(0.3, 1.0, 0.4, alpha))
    nvgFill(vg)
end

-- 充能：青色闪电形
function drawEnergy(vg, r, alpha)
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r)
    nvgFillColor(vg, nvgRGBAf(0.0, 0.5, 0.7, alpha * 0.8))
    nvgFill(vg)
    -- 闪电：Z形路径
    local s = r * 0.7
    nvgBeginPath(vg)
    nvgMoveTo(vg,  s * 0.3, -s)
    nvgLineTo(vg, -s * 0.1,  0)
    nvgLineTo(vg,  s * 0.2,  0)
    nvgLineTo(vg, -s * 0.3,  s)
    nvgStrokeColor(vg, nvgRGBAf(0.4, 1.0, 1.0, alpha))
    nvgStrokeWidth(vg, 2.0)
    nvgLineCap(vg, NVG_ROUND)
    nvgLineJoin(vg, NVG_ROUND)
    nvgStroke(vg)
end

-- 磁铁：蓝色 U 形 + 两极
function drawMagnet(vg, r, alpha)
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r)
    nvgFillColor(vg, nvgRGBAf(0.1, 0.3, 0.8, alpha * 0.8))
    nvgFill(vg)
    local rr = r * 0.6
    -- U 形弧
    nvgBeginPath(vg)
    nvgArc(vg, 0, -r * 0.1, rr, math.pi, 0, NVG_CCW)
    nvgStrokeColor(vg, nvgRGBAf(0.5, 0.7, 1.0, alpha))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)
    -- 左极（红）
    nvgBeginPath(vg)
    nvgRect(vg, -rr - 2, -r * 0.1, 5, r * 0.45)
    nvgFillColor(vg, nvgRGBAf(1.0, 0.2, 0.2, alpha))
    nvgFill(vg)
    -- 右极（蓝）
    nvgBeginPath(vg)
    nvgRect(vg, rr - 3, -r * 0.1, 5, r * 0.45)
    nvgFillColor(vg, nvgRGBAf(0.2, 0.4, 1.0, alpha))
    nvgFill(vg)
end

return M
