-- local patchy = require "patchy"
local slicy = require "slicy"

local SCALE = 4
local CANVASW = 160
local CANVASH = 120
local WINDOWW = CANVASW * SCALE
local WINDOWH = CANVASH * SCALE
local SPEED = 30

local pane
local width, height
local canvas
local lipsum = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

local keys = {
    right = function(dt) width = width + SPEED * dt end,
    left = function(dt) width = width - SPEED * dt end,
    up = function(dt) height = height - SPEED * dt end,
    down = function(dt) height = height + SPEED * dt end
}

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setMode(WINDOWW, WINDOWH, {})

    -- pane = patchy.load("Pane.9.png")
    pane = slicy.load("Pane.9.png")
    canvas = love.graphics.newCanvas(CANVASW, CANVASH)
    width = 100
    height = 100
end

function love.update(dt)
    for key, f in pairs(keys) do
        if love.keyboard.isDown(key) then
            f(dt)
        end
    end
    pane:resize(math.floor(width), math.floor(height))
end

function love.keypressed(k)
    if k == "space" then
        slicy.setDebug{draw = not slicy.isDebugDrawing()}
    end
end

function love.draw()
    love.graphics.setCanvas(canvas)
        love.graphics.clear()
        pane:draw(10, 10)
        local cx, cy, cw, ch = pane:getContentWindow()
        love.graphics.setScissor(cx, cy, cw, ch)
            love.graphics.printf(lipsum, cx, cy, cw, "justify")
        love.graphics.setScissor()
    love.graphics.setCanvas()
    love.graphics.draw(canvas, 0, 0, 0, SCALE, SCALE)
end