-- ============================================================================
-- InputHandler.lua - 统一输入处理（鼠标 + 触摸）
-- 暴露接口：
--   .isDragging()       -> bool (玩家移动拖拽中)
--   .dragDelta()        -> dx, dy
--   .isBulletTimeHeld() -> bool
--   .isFireHeld()       -> bool
--   .fireDirection()    -> angle (弧度)
-- ============================================================================

local M = {}

local W_, H_ = 0, 0

-- 左侧区域：子弹时间按钮（左下角，半径 50）
local BT_BTN = { x = 80, y = 0, r = 55 }  -- y 在 init 时设置
-- 右侧区域：发射按钮（右下角，半径 50）
local FIRE_BTN = { x = 0, y = 0, r = 55 } -- x/y 在 init 时设置

-- ——— 移动拖拽 ———
local moveTouchId   = nil   -- 正在追踪的触摸 ID（移动）
local moveStartX    = 0
local moveStartY    = 0
local moveDeltaX    = 0
local moveDeltaY    = 0
local mouseHeld     = false
local mousePrevX    = 0
local mousePrevY    = 0
local mouseDeltaX   = 0
local mouseDeltaY   = 0

-- ——— 子弹时间 ———
local btTouchId     = nil
local btKeyHeld     = false  -- Shift 键

-- ——— 发射（简化：只需按住，方向由自动瞄准决定）———
local fireTouchId   = nil
local fireKeyHeld   = false

-- ——— 键盘移动（WASD / 方向键）———
-- 用 held 标志代替每帧读取 input:GetKeyDown，兼容性更好
local keyMoveLeft  = false
local keyMoveRight = false
local keyMoveUp    = false
local keyMoveDown  = false
local KEY_MOVE_SPEED = 300   -- 逻辑像素/秒（键盘移动速度）
-- 键盘 delta 独立存放，不混入鼠标 delta
local keyDeltaX = 0
local keyDeltaY = 0

function M.init(_W, _H)
    W_ = _W
    H_ = _H
    BT_BTN.y   = H_ - 100
    FIRE_BTN.x = W_ - 80
    FIRE_BTN.y = H_ - 100
    print(string.format("[Input] 初始化 BT按钮:(%.0f,%.0f) Fire按钮:(%.0f,%.0f)",
        BT_BTN.x, BT_BTN.y, FIRE_BTN.x, FIRE_BTN.y))
end

function M.update(dt)
    -- 键盘移动 delta（独立计算，不混入鼠标 delta）
    local kx = 0
    local ky = 0
    if keyMoveLeft  then kx = kx - 1 end
    if keyMoveRight then kx = kx + 1 end
    if keyMoveUp    then ky = ky - 1 end
    if keyMoveDown  then ky = ky + 1 end
    if kx ~= 0 or ky ~= 0 then
        -- 归一化斜向移动，避免对角线速度加倍
        local len = math.sqrt(kx * kx + ky * ky)
        keyDeltaX = (kx / len) * KEY_MOVE_SPEED * dt
        keyDeltaY = (ky / len) * KEY_MOVE_SPEED * dt
    else
        keyDeltaX = 0
        keyDeltaY = 0
    end
end

-- 必须在 HandleUpdate 的最末尾（所有子系统读取完 delta 之后）调用
function M.endFrame()
    moveDeltaX  = 0
    moveDeltaY  = 0
    mouseDeltaX = 0
    mouseDeltaY = 0
end

-- ——— 查询接口 ———
function M.isDragging()
    return moveTouchId ~= nil or mouseHeld
end

-- 鼠标/触摸原始 delta（1:1 对应屏幕像素偏移）
function M.dragDelta()
    if moveTouchId ~= nil then
        return moveDeltaX, moveDeltaY
    end
    return mouseDeltaX, mouseDeltaY
end

-- 键盘方向键/WASD 的速度 delta（已按 KEY_MOVE_SPEED * dt 缩放）
function M.keyboardDelta()
    return keyDeltaX, keyDeltaY
end

function M.isBulletTimeHeld()
    return btTouchId ~= nil or btKeyHeld
end

function M.isFireHeld()
    return fireTouchId ~= nil or fireKeyHeld
end

-- 返回按钮位置（供 UI 绘制使用）
function M.getButtonRects()
    return BT_BTN, FIRE_BTN
end

-- ——— 鼠标事件 ———
function M.onMouseDown(btn, x, y)
    if btn == MOUSEB_LEFT then
        mouseHeld  = true
        mousePrevX = x
        mousePrevY = y
    elseif btn == MOUSEB_RIGHT then
        fireKeyHeld = true
    end
end

function M.onMouseUp(btn, x, y)
    if btn == MOUSEB_LEFT then
        mouseHeld   = false
        mouseDeltaX = 0
        mouseDeltaY = 0
    elseif btn == MOUSEB_RIGHT then
        fireKeyHeld = false
    end
end

function M.onMouseMove(x, y)
    if mouseHeld then
        -- 累积而非覆盖，防止同一帧多个 MouseMove 事件互相覆盖
        mouseDeltaX = mouseDeltaX + (x - mousePrevX)
        mouseDeltaY = mouseDeltaY + (y - mousePrevY)
        mousePrevX  = x
        mousePrevY  = y
    end
end

-- ——— 键盘事件 ———
function M.onKeyDown(key)
    if key == KEY_SHIFT then
        btKeyHeld = true
    elseif key == KEY_SPACE then
        fireKeyHeld = true
    -- WASD
    elseif key == KEY_A or key == KEY_LEFT  then keyMoveLeft  = true
    elseif key == KEY_D or key == KEY_RIGHT then keyMoveRight = true
    elseif key == KEY_W or key == KEY_UP    then keyMoveUp    = true
    elseif key == KEY_S or key == KEY_DOWN  then keyMoveDown  = true
    end
end

function M.onKeyUp(key)
    if key == KEY_SHIFT then
        btKeyHeld = false
    elseif key == KEY_SPACE then
        fireKeyHeld = false
    -- WASD
    elseif key == KEY_A or key == KEY_LEFT  then keyMoveLeft  = false
    elseif key == KEY_D or key == KEY_RIGHT then keyMoveRight = false
    elseif key == KEY_W or key == KEY_UP    then keyMoveUp    = false
    elseif key == KEY_S or key == KEY_DOWN  then keyMoveDown  = false
    end
end

-- ——— 触摸事件 ———
local function inCircle(px, py, cx, cy, r)
    local dx = px - cx
    local dy = py - cy
    return dx * dx + dy * dy <= r * r
end

function M.onTouchBegin(id, x, y)
    -- 子弹时间按钮区域
    if btTouchId == nil and inCircle(x, y, BT_BTN.x, BT_BTN.y, BT_BTN.r) then
        btTouchId = id
        return
    end
    -- 发射按钮区域
    if fireTouchId == nil and inCircle(x, y, FIRE_BTN.x, FIRE_BTN.y, FIRE_BTN.r) then
        fireTouchId = id
        return
    end
    -- 其余区域 → 移动拖拽
    if moveTouchId == nil then
        moveTouchId = id
        moveStartX  = x
        moveStartY  = y
    end
end

function M.onTouchMove(id, x, y)
    if id == moveTouchId then
        moveDeltaX = x - moveStartX
        moveDeltaY = y - moveStartY
        moveStartX = x
        moveStartY = y
    end
end

function M.onTouchEnd(id)
    if id == moveTouchId then
        moveTouchId = nil
        moveDeltaX  = 0
        moveDeltaY  = 0
    elseif id == btTouchId then
        btTouchId = nil
    elseif id == fireTouchId then
        fireTouchId = nil
    end
end

return M
