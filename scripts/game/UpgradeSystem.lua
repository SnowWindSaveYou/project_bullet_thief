-- ============================================================================
-- UpgradeSystem.lua - 升级界面（每 50 轨道击杀触发 3选1）
-- 复古卡通桌游风格：米黄底面板 + 深蓝描边卡片 + 棋盘格选中态
-- ============================================================================

local Tween        = require "lib.Tween"
local Theme        = require "ui.Theme"
local Components   = require "ui.Components"
local SkillState   = require "game.SkillState"
local ConfigLoader = require "config.ConfigLoader"

local M = {}

-- 升级里程碑（从 JSON 加载）
local BASE_THRESHOLD = 50
local upgradeCount_  = 0
local showing_       = false
local cards_         = {}
local selectedCard_  = nil
local animT_         = 0  -- 进入动画 0→1

local W_, H_ = 0, 0

-- ═══ Tween 驱动动画状态 ═══
local anim_ = {
    maskAlpha  = 0,   -- 遮罩透明度
    titleScale = 0,   -- 标题缩放
    titleY     = 0,   -- 标题Y偏移
}

-- 每张卡片独立动画
local cardAnims_ = {}  -- { alpha, slideY, scale }

-- ——— 升级选项池（从 JSON 延迟加载） ———
local UPGRADE_POOL = nil
local FIRST_TRIGGER_OVERRIDE = 25

local function loadUpgradePool()
    if UPGRADE_POOL then return UPGRADE_POOL end
    local data = ConfigLoader.load("config/upgrades.json")
    if data then
        BASE_THRESHOLD = data.triggerThreshold or 50
        FIRST_TRIGGER_OVERRIDE = data.firstTriggerOverride or 25
        UPGRADE_POOL = data.pool or {}
        print("[UpgradeSystem] 从 JSON 加载 " .. #UPGRADE_POOL .. " 个升级选项, 阈值=" .. BASE_THRESHOLD)
    end
    if not UPGRADE_POOL or #UPGRADE_POOL == 0 then
        print("[UpgradeSystem] WARN: JSON 加载失败，使用内置默认值")
        UPGRADE_POOL = {
            { id = "orbit_dmg",    tree = "orbit",  name = "穿甲弹芯", desc = "轨道子弹伤害 +1",            icon = "diamond", color = {0.3, 0.8, 1.0}, effect = { stat = "orbitDamage", op = "add", value = 1 } },
            { id = "orbit_layers", tree = "orbit",  name = "扩编轨道", desc = "每圈最多子弹数 +4",           icon = "ring",    color = {0.3, 0.8, 1.0}, effect = { stat = "maxOrbitBullets", op = "add", value = 4 } },
            { id = "bt_cap",       tree = "bullet", name = "深渊容器", desc = "能量上限 +30%（BT持续更久）", icon = "diamond", color = {0.8, 0.4, 1.0}, effect = { stat = "energyMaxMult", op = "mult", value = 1.3 } },
            { id = "bt_regen",     tree = "bullet", name = "量子充能", desc = "能量恢复速度 +40%",           icon = "bolt",    color = {0.8, 0.4, 1.0}, effect = { stat = "energyRegenMult", op = "mult", value = 1.4 } },
            { id = "bt_cost",      tree = "bullet", name = "节能模式", desc = "子弹时间能量消耗 -25%",       icon = "shield",  color = {0.8, 0.4, 1.0}, effect = { stat = "energyCostMult", op = "mult", value = 0.75 } },
            { id = "bt_graze",     tree = "bullet", name = "危险舞者", desc = "擦弹能量获取 +50%",           icon = "star",    color = {0.8, 0.4, 1.0}, effect = { stat = "grazeEnergyMult", op = "mult", value = 1.5 } },
            { id = "hp_up",        tree = "misc",   name = "钢铁意志", desc = "最大血量 +20",                icon = "heart",   color = {1.0, 0.4, 0.4}, effect = { stat = "maxHp", op = "add", value = 20 } },
            { id = "hp_regen",     tree = "misc",   name = "生命脉动", desc = "每次夺取子弹恢复 1 血量",    icon = "heal",    color = {1.0, 0.4, 0.4}, effect = { stat = "stealHeal", op = "add", value = 1 } },
        }
    end
    return UPGRADE_POOL
end

local ownedUpgrades_ = {}

-- ——— 升级树颜色映射（新风格色板）———
local TREE_COLORS = {
    orbit  = Theme.colors.energyCyan,
    bullet = { 0.70, 0.40, 0.90, 1.0 },
    misc   = Theme.colors.accentGreen,
    -- 成长线颜色
    skill_a = { 1.00, 0.70, 0.20, 1.0 },  -- A线: 金色
    skill_b = { 0.30, 1.00, 0.60, 1.0 },  -- B线: 绿色
    skill_c = { 1.00, 0.40, 0.50, 1.0 },  -- C线: 红粉
    skill_d = { 0.40, 0.70, 1.00, 1.0 },  -- D线: 蓝色
}
local TREE_NAMES = {
    orbit = "ORBIT", bullet = "BULLET TIME", misc = "UTILITY",
    skill_a = "A·COMBAT", skill_b = "B·STEAL", skill_c = "C·MINE", skill_d = "D·LINK",
}

-- ——— 成长线升级描述 ———
local SKILL_DESCS = {
    shot  = { "射击伤害+20%", "射击伤害+20%, 射速+15%", "射击伤害+30%, 射速+15%", "射击伤害+40%, 射速+30%" },
    orbit = { "轨道伤害+20%", "轨道伤害+20%, 范围+10%", "轨道伤害+30%, 范围+20%", "轨道最终形态" },
    qte   = { "QTE伤害+25%", "QTE伤害+25%, 时间+1s", "QTE伤害+35%, 时间+1s", "QTE最终形态" },
    steal = { "偷取范围 +20%", "子弹减速 85%", "子弹偏转吸引" },
    mine  = { "更多地雷, 加速放置", "扩大触发范围", "连锁引爆", "减速敌人", "滞留伤害区域" },
    link  = { "更多节点, 延长持续", "扩大连接距离", "减速穿越敌人", "连锁伤害加成", "击杀爆裂传导" },
}

--- 根据当前 SkillState 生成可用的技能升级选项
local function buildSkillPool()
    local pool = {}

    -- A线: shot/orbit/qte 等级提升
    local axes = { "shot", "orbit", "qte" }
    local axisNames = { shot = "射击", orbit = "轨道", qte = "QTE" }
    local axisIcons = { shot = "arrow", orbit = "ring", qte = "bolt" }
    for _, axis in ipairs(axes) do
        local lv = SkillState.getLevel(axis)
        local maxLv = SkillState.MAX_LEVELS[axis]
        if lv < maxLv then
            local nextLv = lv + 1
            local desc = SKILL_DESCS[axis][lv] or (axisNames[axis] .. " Lv" .. nextLv)
            pool[#pool + 1] = {
                id = "skill_" .. axis .. "_lv",
                tree = "skill_a",
                name = axisNames[axis] .. " Lv" .. nextLv,
                desc = desc,
                icon = axisIcons[axis],
                color = TREE_COLORS.skill_a,
                skillAxis = axis,
                skillAction = "levelup",
            }
        end
    end

    -- A线: 形态切换（仅当等级 >= 2 时提供）
    local formAxes = { "shot", "orbit", "qte" }
    local formNames = { shot = "射击形态", orbit = "轨道形态", qte = "QTE形态" }
    for _, axis in ipairs(formAxes) do
        local lv = SkillState.getLevel(axis)
        local curForm = SkillState.getForm(axis)
        local maxForm = SkillState.MAX_FORMS[axis]
        if lv >= 2 and curForm < maxForm then
            local nextForm = curForm + 1
            local formName = SkillState.getFormName(axis, nextForm)
            pool[#pool + 1] = {
                id = "skill_" .. axis .. "_form",
                tree = "skill_a",
                name = formNames[axis] .. "·" .. formName,
                desc = "解锁" .. axisNames[axis] .. "新形态: " .. formName,
                icon = "diamond",
                color = TREE_COLORS.skill_a,
                skillAxis = axis,
                skillAction = "formup",
            }
        end
    end

    -- B线: steal 解锁/升级
    local stealLv = SkillState.getLevel("steal")
    local stealMax = SkillState.MAX_LEVELS.steal
    if stealLv == 0 then
        pool[#pool + 1] = {
            id = "skill_steal_unlock",
            tree = "skill_b",
            name = "解锁·偷取强化",
            desc = "解锁B线: 子弹时间偷取范围+20%",
            icon = "wave",
            color = TREE_COLORS.skill_b,
            skillAxis = "steal",
            skillAction = "levelup",
        }
    elseif stealLv < stealMax then
        local desc = SKILL_DESCS.steal[stealLv] or ("偷取 Lv" .. (stealLv + 1))
        pool[#pool + 1] = {
            id = "skill_steal_lv",
            tree = "skill_b",
            name = "偷取 Lv" .. (stealLv + 1),
            desc = desc,
            icon = "wave",
            color = TREE_COLORS.skill_b,
            skillAxis = "steal",
            skillAction = "levelup",
        }
    end

    -- C线: mine 解锁/升级
    local mineLv = SkillState.getLevel("mine")
    local mineMax = SkillState.MAX_LEVELS.mine
    if mineLv == 0 then
        pool[#pool + 1] = {
            id = "skill_mine_unlock",
            tree = "skill_c",
            name = "解锁·梦境诡雷",
            desc = "解锁C线: 移动时自动布置地雷",
            icon = "diamond",
            color = TREE_COLORS.skill_c,
            skillAxis = "mine",
            skillAction = "levelup",
        }
    elseif mineLv < mineMax then
        local desc = SKILL_DESCS.mine[mineLv] or ("地雷 Lv" .. (mineLv + 1))
        pool[#pool + 1] = {
            id = "skill_mine_lv",
            tree = "skill_c",
            name = "诡雷 Lv" .. (mineLv + 1),
            desc = desc,
            icon = "diamond",
            color = TREE_COLORS.skill_c,
            skillAxis = "mine",
            skillAction = "levelup",
        }
    end

    -- D线: link 解锁/升级
    local linkLv = SkillState.getLevel("link")
    local linkMax = SkillState.MAX_LEVELS.link
    if linkLv == 0 then
        pool[#pool + 1] = {
            id = "skill_link_unlock",
            tree = "skill_d",
            name = "解锁·梦境连线",
            desc = "解锁D线: 击杀留下梦痕连线伤敌",
            icon = "bolt",
            color = TREE_COLORS.skill_d,
            skillAxis = "link",
            skillAction = "levelup",
        }
    elseif linkLv < linkMax then
        local desc = SKILL_DESCS.link[linkLv] or ("连线 Lv" .. (linkLv + 1))
        pool[#pool + 1] = {
            id = "skill_link_lv",
            tree = "skill_d",
            name = "连线 Lv" .. (linkLv + 1),
            desc = desc,
            icon = "bolt",
            color = TREE_COLORS.skill_d,
            skillAxis = "link",
            skillAction = "levelup",
        }
    end

    return pool
end

function M.init()
    loadUpgradePool()
    upgradeCount_   = 0
    showing_        = false
    cards_          = {}
    ownedUpgrades_  = {}
    W_ = 0
    H_ = 0
end

function M.reset()
    upgradeCount_  = 0
    showing_       = false
    cards_         = {}
    ownedUpgrades_ = {}
    animT_         = 0
end

function M.setSize(_W, _H)
    W_ = _W
    H_ = _H
end

function M.getNextThreshold()
    -- 开场首次触发使用 firstTriggerOverride，之后按 BASE_THRESHOLD 递增
    if upgradeCount_ == 0 then
        return FIRST_TRIGGER_OVERRIDE
    end
    return FIRST_TRIGGER_OVERRIDE + BASE_THRESHOLD * upgradeCount_
end

function M.isShowing()
    return showing_
end

-- 触发升级界面
function M.show()
    showing_  = true
    animT_    = 0
    cards_    = {}
    selectedCard_ = nil

    -- 重置并启动 Tween 动画
    Tween.cancelTarget(anim_)
    anim_.maskAlpha  = 0
    anim_.titleScale = 0
    anim_.titleY     = 40

    -- 遮罩淡入
    Tween.to(anim_, { maskAlpha = 1 }, 0.35, {
        easing = Tween.Easing.easeOutCubic,
    })

    -- 标题弹入 (easeOutBack)
    Tween.to(anim_, { titleScale = 1, titleY = 0 }, 0.5, {
        delay = 0.1,
        easing = Tween.Easing.easeOutBack,
    })

    -- 混合池: 静态通用 + 动态成长线
    local skillPool = buildSkillPool()
    local staticPool = {}
    for _, u in ipairs(UPGRADE_POOL) do
        staticPool[#staticPool + 1] = u
    end

    -- Fisher-Yates 洗牌
    local function shuffle(t)
        for i = #t, 2, -1 do
            local j = math.random(1, i)
            t[i], t[j] = t[j], t[i]
        end
    end
    shuffle(skillPool)
    shuffle(staticPool)

    -- 策略: 保证至少 1 个技能升级（如果有），剩余从静态池补充
    local chosen = {}
    local usedIds = {}

    -- 先放入 1-2 个技能升级（如果有的话）
    local skillCount = math.min(2, #skillPool)
    for i = 1, skillCount do
        chosen[#chosen + 1] = skillPool[i]
        usedIds[skillPool[i].id] = true
    end

    -- 从静态池补到 3 个
    local idx = 1
    while #chosen < 3 and idx <= #staticPool do
        if not usedIds[staticPool[idx].id] then
            chosen[#chosen + 1] = staticPool[idx]
            usedIds[staticPool[idx].id] = true
        end
        idx = idx + 1
    end

    -- 如果技能池不够且静态也不够，再从技能池补
    idx = skillCount + 1
    while #chosen < 3 and idx <= #skillPool do
        if not usedIds[skillPool[idx].id] then
            chosen[#chosen + 1] = skillPool[idx]
            usedIds[skillPool[idx].id] = true
        end
        idx = idx + 1
    end

    -- 最终洗牌展示顺序
    shuffle(chosen)

    -- 取前 3，每张卡片带独立动画
    local available = chosen
    cardAnims_ = {}
    local count = math.min(3, #available)
    for i = 1, count do
        local u = available[i]
        table.insert(cards_, {
            upgrade = u,
            hoverT  = 0,
            selectT = 0,
        })

        -- 卡片独立动画状态
        local ca = { alpha = 0, slideY = 80, scale = 0.7 }
        cardAnims_[i] = ca

        -- stagger easeOutBack 从底部弹入
        Tween.to(ca, { alpha = 1, slideY = 0, scale = 1.0 }, 0.55, {
            delay = 0.2 + (i - 1) * 0.12,
            easing = Tween.Easing.easeOutBack,
        })
    end

    print("[Upgrade] 升级界面开启，第 " .. (upgradeCount_ + 1) .. " 次")
end

function M.update(dt)
    if not showing_ then return end

    animT_ = math.min(1, animT_ + dt * 3)

    -- Hover 动画
    for _, card in ipairs(cards_) do
        if card.isHover then
            card.hoverT = math.min(1, card.hoverT + dt * 5)
        else
            card.hoverT = math.max(0, card.hoverT - dt * 5)
        end
        if card.isSelected then
            card.selectT = math.min(1, card.selectT + dt * 4)
            if card.selectT >= 1 then
                M.applyUpgrade(card.upgrade)
                showing_ = false
                upgradeCount_ = upgradeCount_ + 1
                require("game.GameState").set("playing")
                print("[Upgrade] 选择: " .. card.upgrade.id)
            end
        end
    end
end

-- 点击检测
function M.onMouseClick(mx, my)
    if not showing_ then return end
    checkClick(mx, my)
end

function M.onTouchBegin(id, x, y)
    if not showing_ then return end
    checkClick(x, y)
end

function checkClick(x, y)
    for i, card in ipairs(cards_) do
        if card.rect then
            if Components.hitTest(card.rect, x, y) then
                card.isSelected = true
                selectedCard_   = card

                -- 选中 elastic 缩放脉冲
                local ca = cardAnims_[i]
                if ca then
                    Tween.cancelTarget(ca)
                    ca.scale = 1.12
                    Tween.to(ca, { scale = 1.05 }, 0.4, {
                        easing = Tween.Easing.easeOutElastic,
                    })
                end
            end
        end
    end
end

function M.checkHover(x, y)
    for _, card in ipairs(cards_) do
        if card.rect then
            card.isHover = Components.hitTest(card.rect, x, y)
        end
    end
end

-- 应用升级效果到玩家
function M.applyUpgrade(u)
    local Player = require("game.Player")
    local p = Player.getData()
    table.insert(ownedUpgrades_, u.id)

    -- 成长线技能升级
    if u.skillAxis and u.skillAction then
        if u.skillAction == "levelup" then
            SkillState.levelUp(u.skillAxis)
            print("[Upgrade] 技能升级: " .. u.skillAxis .. " -> Lv" .. SkillState.getLevel(u.skillAxis))
        elseif u.skillAction == "formup" then
            SkillState.nextForm(u.skillAxis)
            print("[Upgrade] 形态切换: " .. u.skillAxis .. " -> Form " .. SkillState.getForm(u.skillAxis) .. " (" .. SkillState.getFormName(u.skillAxis) .. ")")
        end
        return
    end

    -- 数据驱动通用升级（基于 effect 字段）
    local eff = u.effect
    if eff and eff.stat and eff.op then
        local stat = eff.stat
        local val  = eff.value or 0
        if eff.op == "add" then
            p[stat] = (p[stat] or 0) + val
        elseif eff.op == "mult" then
            p[stat] = (p[stat] or 1) * val
        end
        -- hp_up 特殊处理：同时治疗
        if u.id == "hp_up" then
            p.hp = math.min(p.maxHp, p.hp + val)
        end
    end
end

-- ═══════════════════════════════════════════
-- 绘制升级界面（由 main HandleRender 调用）
-- ═══════════════════════════════════════════
function M.draw(vg, W, H)
    if not showing_ then return end

    W_ = W
    H_ = H

    -- 半透明遮罩 (Tween 驱动，带色调)
    if anim_.maskAlpha > 0.01 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        local or_, og, ob = Theme.c(Theme.colors.overlay)
        nvgFillColor(vg, nvgRGBAf(or_, og, ob, anim_.maskAlpha * Theme.colors.overlayAlpha))
        nvgFill(vg)
    end

    -- 标题 (Tween 驱动缩放 + Y偏移)
    if anim_.titleScale > 0.01 then
        local titleY = H * 0.14 + anim_.titleY

        nvgSave(vg)
        nvgTranslate(vg, W * 0.5, titleY)
        nvgScale(vg, anim_.titleScale, anim_.titleScale)
        nvgTranslate(vg, -W * 0.5, -titleY)

        Components.drawTitle(vg, W * 0.5, titleY, "LEVEL UP", Theme.font.title, Theme.colors.accentYellow)

        nvgFontFace(vg, Theme.font.family)
        nvgFontSize(vg, Theme.font.body)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(Theme.ca(Theme.colors.lightText, anim_.titleScale * 0.8)))
        nvgText(vg, W * 0.5, titleY + 30, "Choose an upgrade")

        nvgRestore(vg)
    end

    -- 卡片布局 (Tween 驱动每张卡独立动画)
    local cardW  = math.min(140, W * 0.24)
    local cardH  = cardW * 1.7
    local gap    = 16
    local totalW = #cards_ * cardW + (#cards_ - 1) * gap
    local startX = (W - totalW) * 0.5
    local cardY  = H * 0.30

    for i, card in ipairs(cards_) do
        local ca = cardAnims_[i]
        if ca and ca.alpha > 0.01 then
            local cx = startX + (i - 1) * (cardW + gap)
            local slideY = cardY + ca.slideY

            nvgGlobalAlpha(vg, ca.alpha)

            -- 卡片整体缩放
            nvgSave(vg)
            local centerX = cx + cardW * 0.5
            local centerY = slideY + cardH * 0.5
            nvgTranslate(vg, centerX, centerY)
            nvgScale(vg, ca.scale, ca.scale)
            nvgTranslate(vg, -centerX, -centerY)

            card.rect = { x = cx, y = slideY, w = cardW, h = cardH }
            drawUpgradeCard(vg, card, cx, slideY, cardW, cardH)

            nvgRestore(vg)
            nvgGlobalAlpha(vg, 1.0)
        end
    end
end

-- ═══════════════════════════════════════════
-- 单张卡片绘制 - 新风格
-- ═══════════════════════════════════════════
function drawUpgradeCard(vg, card, x, y, w, h)
    local u      = card.upgrade
    local hv     = card.hoverT or 0
    local sel    = card.selectT or 0
    local treeColor = TREE_COLORS[u.tree] or Theme.colors.mutedText

    -- 选中缩放
    local scl = 1.0 + sel * 0.05 + hv * 0.02
    nvgSave(vg)
    nvgTranslate(vg, x + w * 0.5, y + h * 0.5)
    nvgScale(vg, scl, scl)
    nvgTranslate(vg, -w * 0.5, -h * 0.5)

    local cr = Theme.card.cornerRadius
    local bw = Theme.card.borderWidth

    -- 阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 3, 4, w, h, cr)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.25))
    nvgFill(vg)

    -- 底色（米黄，hover 时稍暗）
    local bgAlpha = 1.0
    local bgR, bgG, bgB = Theme.c(Theme.colors.panelBg)
    if hv > 0 then
        bgR = bgR - hv * 0.04
        bgG = bgG - hv * 0.03
        bgB = bgB - hv * 0.06
    end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 0, 0, w, h, cr)
    nvgFillColor(vg, nvgRGBAf(bgR, bgG, bgB, bgAlpha))
    nvgFill(vg)

    -- 选中态：棋盘格覆盖
    if sel > 0 then
        Components.drawCheckered(vg, 0, 0, w, h, cr, Theme.colors.cardSelected)
    end

    -- hover 高亮叠加
    if hv > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 0, 0, w, h, cr)
        nvgFillColor(vg, nvgRGBAf(1, 1, 1, hv * 0.12))
        nvgFill(vg)
        -- 顶部光泽
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 2, 1, w - 4, h * 0.2, cr - 1)
        nvgFillColor(vg, nvgRGBAf(1, 1, 1, hv * 0.08))
        nvgFill(vg)
    end

    -- 描边（深蓝，hover/选中时更粗+亮）
    local strokeW = bw + hv * 1.0 + sel * 1.0
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 0, 0, w, h, cr)
    local br, bg, bb = Theme.c(Theme.colors.panelBorder)
    if hv > 0 then
        -- hover 时描边微微变亮
        nvgStrokeColor(vg, nvgRGBAf(br + hv * 0.15, bg + hv * 0.15, bb + hv * 0.2, 1.0))
    else
        nvgStrokeColor(vg, nvgRGBAf(br, bg, bb, 1.0))
    end
    nvgStrokeWidth(vg, strokeW)
    nvgStroke(vg)

    -- 顶部色带（树颜色）
    local ribbonH = 6
    nvgSave(vg)
    nvgIntersectScissor(vg, 0, 0, w, cr + ribbonH)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 0, 0, w, ribbonH + cr, cr)
    nvgFillColor(vg, nvgRGBAf(Theme.c(treeColor)))
    nvgFill(vg)
    nvgRestore(vg)

    -- 图标区域
    local iconY = h * 0.28
    drawUpgradeIcon(vg, u.icon, w * 0.5, iconY, 22, treeColor)

    -- 名称
    nvgFontFace(vg, Theme.font.family)
    nvgFontSize(vg, Theme.font.button)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local nameColor = sel > 0 and Theme.colors.white or Theme.colors.titleText
    nvgFillColor(vg, nvgRGBAf(Theme.c(nameColor)))
    nvgText(vg, w * 0.5, h * 0.50, u.name)

    -- 描述
    nvgFontSize(vg, Theme.font.small)
    local descColor = sel > 0 and Theme.colors.lightText or Theme.colors.bodyText
    nvgFillColor(vg, nvgRGBAf(Theme.c(descColor)))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgTextBox(vg, 8, h * 0.60, w - 16, u.desc)

    -- 升级树标签（底部）
    nvgFontSize(vg, Theme.font.badge)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(Theme.ca(treeColor, 0.9)))
    nvgText(vg, w * 0.5, h * 0.90, TREE_NAMES[u.tree] or "")

    nvgRestore(vg)
end

-- ═══════════════════════════════════════════
-- 图标绘制
-- ═══════════════════════════════════════════
function drawUpgradeIcon(vg, icon, cx, cy, r, color)
    local cr, cg, cb = Theme.c(color)

    -- 外圆底色
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r + 6)
    nvgFillColor(vg, nvgRGBAf(cr, cg, cb, 0.15))
    nvgFill(vg)

    -- 内圆
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r + 2)
    nvgStrokeColor(vg, nvgRGBAf(cr, cg, cb, 0.5))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    if icon == "diamond" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - r)
        nvgLineTo(vg, cx + r, cy)
        nvgLineTo(vg, cx, cy + r)
        nvgLineTo(vg, cx - r, cy)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBAf(cr, cg, cb, 0.9))
        nvgFill(vg)
    elseif icon == "bolt" or icon == "star" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + r*0.3, cy - r)
        nvgLineTo(vg, cx - r*0.1, cy)
        nvgLineTo(vg, cx + r*0.2, cy)
        nvgLineTo(vg, cx - r*0.3, cy + r)
        nvgStrokeColor(vg, nvgRGBAf(cr, cg, cb, 0.9))
        nvgStrokeWidth(vg, 2.5)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    elseif icon == "heart" or icon == "heal" then
        nvgBeginPath(vg)
        nvgRect(vg, cx - r*0.25, cy - r, r*0.5, r*2)
        nvgFillColor(vg, nvgRGBAf(cr, cg, cb, 0.9))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, cx - r, cy - r*0.25, r*2, r*0.5)
        nvgFillColor(vg, nvgRGBAf(cr, cg, cb, 0.9))
        nvgFill(vg)
    elseif icon == "arrow" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - r, cy)
        nvgLineTo(vg, cx + r * 0.4, cy)
        nvgMoveTo(vg, cx + r * 0.4, cy)
        nvgLineTo(vg, cx, cy - r * 0.6)
        nvgMoveTo(vg, cx + r * 0.4, cy)
        nvgLineTo(vg, cx, cy + r * 0.6)
        nvgStrokeColor(vg, nvgRGBAf(cr, cg, cb, 0.9))
        nvgStrokeWidth(vg, 2.5)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    elseif icon == "orbit" or icon == "ring" then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r * 0.7)
        nvgStrokeColor(vg, nvgRGBAf(cr, cg, cb, 0.9))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)
        -- 小点
        nvgBeginPath(vg)
        nvgCircle(vg, cx + r * 0.7, cy, 3)
        nvgFillColor(vg, nvgRGBAf(cr, cg, cb, 1.0))
        nvgFill(vg)
    elseif icon == "shield" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - r)
        nvgLineTo(vg, cx + r * 0.8, cy - r * 0.4)
        nvgLineTo(vg, cx + r * 0.6, cy + r * 0.7)
        nvgLineTo(vg, cx, cy + r)
        nvgLineTo(vg, cx - r * 0.6, cy + r * 0.7)
        nvgLineTo(vg, cx - r * 0.8, cy - r * 0.4)
        nvgClosePath(vg)
        nvgStrokeColor(vg, nvgRGBAf(cr, cg, cb, 0.9))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)
    elseif icon == "wave" then
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, r * 0.5, -math.pi * 0.6, math.pi * 0.6, NVG_CW)
        nvgStrokeColor(vg, nvgRGBAf(cr, cg, cb, 0.7))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, r * 0.85, -math.pi * 0.5, math.pi * 0.5, NVG_CW)
        nvgStrokeColor(vg, nvgRGBAf(cr, cg, cb, 0.9))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)
    else
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r * 0.6)
        nvgFillColor(vg, nvgRGBAf(cr, cg, cb, 0.7))
        nvgFill(vg)
    end
end

function easeOutBack(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * ((t-1)^3) + c1 * ((t-1)^2)
end

return M
