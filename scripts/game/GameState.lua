-- ============================================================================
-- GameState.lua - 游戏状态机
-- 状态: menu / prelevel / bestiary / playing / upgrade / gameover
-- ============================================================================

local M = {}

local currentState = "menu"

function M.init()
    currentState = "menu"
    print("[GameState] 初始化 -> menu")
end

function M.get()
    return currentState
end

function M.set(newState)
    print("[GameState] " .. currentState .. " -> " .. newState)
    currentState = newState
end

function M.updateMenu(dt)
    -- 菜单动画更新（留给 GameUI 处理）
end

return M
