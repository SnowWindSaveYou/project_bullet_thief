-- ============================================================================
-- SkillState.lua - 技能/成长线状态数据中心
-- 管理 A/B/C/D 四条成长线的当前等级和形态选择
-- ============================================================================

local M = {}

-- ═══ 形态名称定义 ═══

M.SHOT_FORMS = {
    [1] = { id = "default",  name = "默认" },
    [2] = { id = "pierce",   name = "穿透" },
    [3] = { id = "laser",    name = "激光" },
    [4] = { id = "splash",   name = "扩散" },
    [5] = { id = "shotgun",  name = "霰弹" },
}

M.ORBIT_FORMS = {
    [1] = { id = "default",   name = "默认" },
    [2] = { id = "blade",     name = "刀锋" },
    [3] = { id = "pulse",     name = "脉冲" },
    [4] = { id = "resonance", name = "共鸣" },
    [5] = { id = "shield",    name = "护盾" },
}

M.QTE_FORMS = {
    [1] = { id = "default", name = "默认" },
    [2] = { id = "beam",    name = "光束" },
    [3] = { id = "radial",  name = "星坠" },
    [4] = { id = "homing",  name = "群星" },
}

-- ═══ 等级上限 ═══

M.MAX_LEVELS = {
    shot  = 5,
    orbit = 5,
    qte   = 5,
    steal = 3,
    mine  = 5,
    link  = 5,
}

M.MAX_FORMS = {
    shot  = 5,
    orbit = 5,
    qte   = 4,
}

-- ═══ 状态数据 ═══

---@class SkillAxisState
---@field form integer 当前形态 (1=默认)
---@field level integer 当前等级 (1=基础)

---@class SkillLineState
---@field level integer 当前等级 (0=未解锁, 1+=已解锁)

local state = {}

function M.init()
    M.reset()
end

function M.reset()
    state = {
        -- A线三轴
        shot  = { form = 1, level = 1 },
        orbit = { form = 1, level = 1 },
        qte   = { form = 1, level = 1 },
        -- B线
        steal = { level = 0 },
        -- C线
        mine  = { level = 0 },
        -- D线
        link  = { level = 0 },
    }
end

-- ═══ 读取接口 ═══

--- 获取完整状态快照（只读）
function M.getState()
    return state
end

--- 获取 A线某轴的形态ID
---@param axis "shot"|"orbit"|"qte"
---@return integer form
function M.getForm(axis)
    return state[axis] and state[axis].form or 1
end

--- 获取某轴/线的等级
---@param axis string
---@return integer level
function M.getLevel(axis)
    local s = state[axis]
    if not s then return 0 end
    return s.level or 0
end

-- ═══ 修改接口 ═══

--- 设置 A线某轴的形态
---@param axis "shot"|"orbit"|"qte"
---@param form integer
function M.setForm(axis, form)
    if not state[axis] then return end
    local maxF = M.MAX_FORMS[axis] or 1
    state[axis].form = math.max(1, math.min(maxF, form))
end

--- 设置某轴/线的等级
---@param axis string
---@param level integer
function M.setLevel(axis, level)
    if not state[axis] then return end
    local maxL = M.MAX_LEVELS[axis] or 1
    state[axis].level = math.max(0, math.min(maxL, level))
end

--- 增加等级 (+1)
---@param axis string
function M.levelUp(axis)
    local cur = M.getLevel(axis)
    M.setLevel(axis, cur + 1)
end

--- 减少等级 (-1)
---@param axis string
function M.levelDown(axis)
    local cur = M.getLevel(axis)
    M.setLevel(axis, cur - 1)
end

--- 切换到下一个形态（循环）
---@param axis "shot"|"orbit"|"qte"
function M.nextForm(axis)
    local cur = M.getForm(axis)
    local maxF = M.MAX_FORMS[axis] or 1
    local next = cur + 1
    if next > maxF then next = 1 end
    M.setForm(axis, next)
end

--- 切换到上一个形态（循环）
---@param axis "shot"|"orbit"|"qte"
function M.prevForm(axis)
    local cur = M.getForm(axis)
    local maxF = M.MAX_FORMS[axis] or 1
    local prev = cur - 1
    if prev < 1 then prev = maxF end
    M.setForm(axis, prev)
end

-- ═══ 查询接口 ═══

--- 获取形态显示名称
---@param axis "shot"|"orbit"|"qte"
---@param form integer|nil 不传则取当前
---@return string
function M.getFormName(axis, form)
    form = form or M.getForm(axis)
    local tbl
    if axis == "shot" then tbl = M.SHOT_FORMS
    elseif axis == "orbit" then tbl = M.ORBIT_FORMS
    elseif axis == "qte" then tbl = M.QTE_FORMS
    end
    if tbl and tbl[form] then
        return tbl[form].name
    end
    return "?"
end

--- 获取形态ID字符串
---@param axis "shot"|"orbit"|"qte"
---@return string
function M.getFormId(axis)
    local form = M.getForm(axis)
    local tbl
    if axis == "shot" then tbl = M.SHOT_FORMS
    elseif axis == "orbit" then tbl = M.ORBIT_FORMS
    elseif axis == "qte" then tbl = M.QTE_FORMS
    end
    if tbl and tbl[form] then
        return tbl[form].id
    end
    return "default"
end

--- 判断某线是否已解锁
---@param axis "steal"|"mine"|"link"
---@return boolean
function M.isUnlocked(axis)
    return M.getLevel(axis) >= 1
end

return M
