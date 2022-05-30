local M = {}

--[[
    file format is as follows:
    * extension: *.9.png, same as patchy and (afaik) behaves the same
    * original author never documented it anywhere
    * actual image has a 1 pixel border on all sides
    * pixels in the border can either be black with opacity > 0 ("set") or not
    * set pixels serve as metadata for how to slice the image into 9 patches
    * first and last set pixels on the top and left define the interval for the "edge" portions of the image
        * image "edge" will be scaled in 1 dimension to accomodate variable size
    * first and last set pixels on the bottom and right define the "content window"
        * content window defines inner padding so that content doesn't touch the borders
        * can be different from the "edge" definitions
        * getContentRegion() returns the content region bounds for a given size
]]

---@class PatchedImage
---@field patches table
---@field contentPadding table
---@field x number
---@field y number
---@field width number
---@field height number
local PatchedImage = {}

local PatchedImageMt = {__index = PatchedImage}

local debugDraw = false
local debugLog = false
local DEBUG_DRAW_SEP_WIDTH = 1

local function dbg(...)
    if debugLog then
        print(...)
    end
end

local function firstBlackPixel(imgData, axis, axisoffset, reversed)
    local lim, getpixel
    if axis == "row" then
        lim = imgData:getWidth() - 1
        getpixel = function(idx)
            return imgData:getPixel(idx, axisoffset)
        end
    elseif axis == "col" then
        lim = imgData:getHeight() - 1
        getpixel = function(idx)
            return imgData:getPixel(axisoffset, idx)
        end
    else
        return nil, "argument 2: expected either 'row' or 'col', got " .. tostring(axis)
    end
    dbg("looking for black pixel in axis", axis, axisoffset)

    local startidx, endidx, step
    if reversed then
        -- start at last valid position, down to 0
        startidx, endidx, step = lim, 0, -1
    else
        -- go upwards instead
        startidx, endidx, step = 0, lim, 1
    end

    for idx = startidx, endidx, step do
        local r, g, b, a = getpixel(idx)
        -- black non-transparent pixel
        if r + g + b == 0 and a > 0 then
            dbg("black pixel found at idx", idx)
            return idx
        end
    end
    return nil, "no black pixel found"
end

local function setCorners(p, rawdata, horizontalEdgeSegment, verticalEdgeSegment)
    dbg("slicing corners")

    -- -1 from file format border, -1 from excluding the pixel itself
    local brCornerWidth = rawdata:getWidth() - horizontalEdgeSegment[2] - 2
    local brCornerHeight = rawdata:getHeight() - verticalEdgeSegment[2] - 2

    local tlCorner = love.image.newImageData(horizontalEdgeSegment[1] - 1, verticalEdgeSegment[1] - 1)
    tlCorner:paste(
        rawdata,
        0, 0,
        -- skip metadata column and row
        1, 1,
        tlCorner:getDimensions()
    )
    p.patches[1][1] = love.graphics.newImage(tlCorner, {})
    tlCorner:release()
    dbg("top left corner:", p.patches[1][1]:getDimensions())

    local trCorner = love.image.newImageData(brCornerWidth, verticalEdgeSegment[1] - 1)
    trCorner:paste(
        rawdata,
        0, 0,
        horizontalEdgeSegment[2] + 1, 1,
        trCorner:getDimensions()
    )
    p.patches[1][3] = love.graphics.newImage(trCorner, {})
    trCorner:release()
    dbg("top right corner:", p.patches[1][3]:getDimensions())

    local blCorner = love.image.newImageData(horizontalEdgeSegment[1] - 1, brCornerHeight)
    blCorner:paste(
        rawdata,
        0, 0,
        1, verticalEdgeSegment[2] + 1,
        blCorner:getDimensions()
    )
    p.patches[3][1] = love.graphics.newImage(blCorner, {})
    blCorner:release()
    dbg("bottom left corner:", p.patches[3][1]:getDimensions())

    local brCorner = love.image.newImageData(brCornerWidth, brCornerHeight)
    brCorner:paste(
        rawdata,
        0, 0,
        horizontalEdgeSegment[2] + 1, verticalEdgeSegment[2] + 1,
        brCorner:getDimensions()
    )
    p.patches[3][3] = love.graphics.newImage(brCorner, {})
    brCorner:release()
    dbg("bottom right corner:", p.patches[3][3]:getDimensions())
end

local function setMiddle(p, rawdata, horizontalEdgeSegment, verticalEdgeSegment)
    dbg("slicing middle")
    local w = horizontalEdgeSegment[2] - horizontalEdgeSegment[1] + 1
    local h = verticalEdgeSegment[2] - verticalEdgeSegment[1] + 1
    local middle = love.image.newImageData(w, h)
    middle:paste(
        rawdata,
        0, 0,
        horizontalEdgeSegment[1], verticalEdgeSegment[1],
        w, h
    )
    p.patches[2][2] = love.graphics.newImage(middle, {})
    middle:release()
    dbg("middle:", p.patches[2][2]:getDimensions())
end

local function setEdges(p, rawdata, horizontalEdgeSegment, verticalEdgeSegment)
    dbg("slicing edges")
    local hlen = horizontalEdgeSegment[2] - horizontalEdgeSegment[1] + 1
    local vlen = verticalEdgeSegment[2] - verticalEdgeSegment[1] + 1

    local top = love.image.newImageData(hlen, verticalEdgeSegment[1] - 1)
    top:paste(
        rawdata,
        0, 0,
        -- 1 to skip over metadata row
        horizontalEdgeSegment[1], 1,
        top:getDimensions()
    )
    p.patches[1][2] = love.graphics.newImage(top, {})
    top:release()
    dbg("top:", p.patches[1][2]:getDimensions())

    -- -2 because of 2 distinct -1s, see comments in setCorners
    local bottom = love.image.newImageData(hlen, rawdata:getHeight() - verticalEdgeSegment[2] - 2)
    bottom:paste(
        rawdata,
        0, 0,
        horizontalEdgeSegment[1], verticalEdgeSegment[2] + 1,
        bottom:getDimensions()
    )
    p.patches[3][2] = love.graphics.newImage(bottom, {})
    bottom:release()
    dbg("bottom:", p.patches[3][2]:getDimensions())

    local left = love.image.newImageData(horizontalEdgeSegment[1] - 1, vlen)
    left:paste(
        rawdata,
        0, 0,
        1, verticalEdgeSegment[1],
        left:getDimensions()
    )
    p.patches[2][1] = love.graphics.newImage(left, {})
    left:release()
    dbg("left:", p.patches[2][1]:getDimensions())

    local right = love.image.newImageData(rawdata:getWidth() - horizontalEdgeSegment[2] - 2, vlen)
    right:paste(
        rawdata,
        0, 0,
        horizontalEdgeSegment[2] + 1, verticalEdgeSegment[1],
        right:getDimensions()
    )
    p.patches[2][3] = love.graphics.newImage(right, {})
    dbg("right:", p.patches[2][3]:getDimensions())
end

---Load a 9-slice image
---@param arg string|love.ImageData filename or raw image data to use for 9-slicing
---@return nil
---@return string
function M.load(arg)
    local rawdata
    local release = false
    local p = {}

    if type(arg) == "string" then
        dbg("loading sliced image from:", arg)

        rawdata = love.image.newImageData(arg, {})
        release = true
    elseif arg.type and arg:type() == "ImageData" then
        rawdata = arg
    else
        return nil, "expected string or ImageData, got "..tostring(arg)
    end

    local horizontalEdgeSegment = {
        assert(firstBlackPixel(rawdata, "row", 0, false)),
        assert(firstBlackPixel(rawdata, "row", 0, true))
    }

    local verticalEdgeSegment = {
        assert(firstBlackPixel(rawdata, "col", 0, false)),
        assert(firstBlackPixel(rawdata, "col", 0, true))
    }

    local horizontalContentPadding = {
        assert(firstBlackPixel(rawdata, "row", rawdata:getHeight() - 1, false)) - 1,
        rawdata:getWidth() - assert(firstBlackPixel(rawdata, "row", rawdata:getHeight() - 1, true)) - 1
    }

    local verticalContentPadding = {
        assert(firstBlackPixel(rawdata, "col", rawdata:getWidth() - 1, false)) - 1,
        rawdata:getHeight() - assert(firstBlackPixel(rawdata, "col", rawdata:getWidth() - 1, true)) - 1
    }

    -- TODO check for valid value ranges in content padding

    p.contentPadding = {
        left = horizontalContentPadding[1],
        right = horizontalContentPadding[2],
        up = verticalContentPadding[1],
        down = verticalContentPadding[2]
    }
    dbg("padding (u,d,l,r):", p.contentPadding.up, p.contentPadding.down, p.contentPadding.left, p.contentPadding.right)

    p.patches = {{}, {}, {}}

    setCorners(p, rawdata, horizontalEdgeSegment, verticalEdgeSegment)
    setMiddle(p, rawdata, horizontalEdgeSegment, verticalEdgeSegment)
    setEdges(p, rawdata, horizontalEdgeSegment, verticalEdgeSegment)

    p.x, p.y = 0, 0
    p.width = p.patches[1][1]:getWidth() + p.patches[1][3]:getWidth()
    p.height = p.patches[1][1]:getHeight() + p.patches[3][1]:getHeight()

    if release then
        rawdata:release()
    end

    setmetatable(p, PatchedImageMt)
    return p
end

-- THIS REUSES THE IMAGE OBJECTS FROM THE ORIGINAL
function PatchedImage:clone()
    local c = {}

    for i = 1, 3 do
        c.patches[i] = {}
        for j = 1, 3 do
            c.patches[i][j] = self.patches[i][j]
        end
    end

    c.contentPadding = {
        left = self.contentPadding.left,
        right = self.contentPadding.right,
        up = self.contentPadding.up,
        down = self.contentPadding.down
    }
    c.x, c.y = self.x, self.y
    c.width, c.height = self.width, self.height

    setmetatable(c, PatchedImageMt)
    return c
end

---Resize image to given dimensions
---@param w number new width
---@param h number new height
function PatchedImage:resize(w, h)
    self.width = self:clampWidth(assert(w))
    self.height = self:clampHeight(assert(h))
end

---Move image to given position
---@param x number
---@param y number
function PatchedImage:move(x, y)
    self.x = assert(x)
    self.y = assert(y)
end

function PatchedImage:getX()
    return self.x
end

function PatchedImage:getY()
    return self.y
end

function PatchedImage:getPosition()
    return self.x, self.y
end

function PatchedImage:getWidth()
    return self.width
end

function PatchedImage:getHeight()
    return self.height
end

function PatchedImage:getDimensions()
    return self.width, self.height
end

---Draws a patch with an optional background debug rect
---@param p love.Image
---@param x number
---@param y number
---@param sx number?
---@param sy number?
local function drawPatch(p, x, y, sx, sy)
    sx = sx or 1
    sy = sy or 1
    if debugDraw then
        love.graphics.rectangle("fill", x, y, p:getWidth() * sx, p:getHeight() * sy)
    end
    love.graphics.draw(p, x, y, 0, sx, sy)
end

function PatchedImage:draw(x, y, w, h)
    if x then
        self.x = x
    else
        x = self.x
    end
    if y then
        self.y = y
    else
        y = self.y
    end
    if w then
        self.width = w
    else
        w = self.width
    end
    if h then
        self.height = h
    else
        h = self.height
    end
    local debugSpacing = debugDraw and DEBUG_DRAW_SEP_WIDTH or 0
    local horizontalEdgeLen = w - self.patches[1][1]:getWidth() - self.patches[1][3]:getWidth()
    local verticalEdgeLen = h - self.patches[1][1]:getHeight() - self.patches[3][1]:getHeight()

    horizontalEdgeLen = math.max(horizontalEdgeLen, 0)
    verticalEdgeLen = math.max(verticalEdgeLen, 0)

    local horizontalEdgeScale = horizontalEdgeLen / self.patches[1][2]:getWidth()
    local verticalEdgeScale = verticalEdgeLen / self.patches[2][1]:getHeight()

    -- middle
    drawPatch(
        self.patches[2][2],
        x + debugSpacing + self.patches[1][1]:getWidth(),
        y + debugSpacing + self.patches[1][1]:getHeight(),
        horizontalEdgeScale, verticalEdgeScale
    )

    -- edges
    --  top
    drawPatch(
        self.patches[1][2],
        x + debugSpacing + self.patches[1][1]:getWidth(),
        y,
        horizontalEdgeScale, 1
    )
    --  left
    drawPatch(
        self.patches[2][1],
        x,
        y + debugSpacing + self.patches[1][1]:getHeight(),
        1, verticalEdgeScale
    )
    --  right
    drawPatch(
        self.patches[2][3],
        x + 2*debugSpacing + self.patches[1][1]:getWidth() + horizontalEdgeLen,
        y + debugSpacing + self.patches[1][1]:getHeight(),
        1, verticalEdgeScale
    )
    --  bottom
    drawPatch(
        self.patches[3][2],
        x + debugSpacing + self.patches[1][1]:getWidth(),
        y + 2*debugSpacing + self.patches[1][1]:getHeight() + verticalEdgeLen,
        horizontalEdgeScale, 1
    )

    -- corners
    --  top left
    drawPatch(self.patches[1][1], x, y)
    --  top right
    drawPatch(
        self.patches[1][3],
        x + 2*debugSpacing + self.patches[1][1]:getWidth() + horizontalEdgeLen,
        y
    )
    --  bottom left
    drawPatch(
        self.patches[3][1],
        x,
        y + 2*debugSpacing + self.patches[1][1]:getHeight() + verticalEdgeLen
    )
    --  bottom right
    drawPatch(
        self.patches[3][3],
        x + 2*debugSpacing + self.patches[1][1]:getWidth() + horizontalEdgeLen,
        y + 2*debugSpacing + self.patches[1][1]:getHeight() + verticalEdgeLen
    )

    if debugDraw then
        local rw = 2*debugSpacing
            - self.contentPadding.left - self.contentPadding.right
            + self.patches[1][1]:getWidth() + horizontalEdgeLen + self.patches[1][3]:getWidth()
        local rh = 2*debugSpacing
            - self.contentPadding.up - self.contentPadding.down
            + self.patches[1][1]:getHeight() + verticalEdgeLen + self.patches[3][1]:getHeight()

        local r, g, b, a = love.graphics.getColor()
        local lw = love.graphics.getLineWidth()
        love.graphics.setColor(1, 0, 0)
        love.graphics.setLineWidth(1)
            love.graphics.rectangle(
                "line",
                x + self.contentPadding.left + 0.5, y + self.contentPadding.up + 0.5,
                rw, rh
            )
        love.graphics.setColor(r, g, b, a)
        love.graphics.setLineWidth(lw)
    end
end

function PatchedImage:getContentWindow(x, y, w, h)
    x = x or self.x
    y = y or self.y
    w = w or self.width
    h = h or self.height

    x = x + self.contentPadding.left
    y = y + self.contentPadding.up

    w = self:clampWidth(w) - self.contentPadding.left - self.contentPadding.right
    h = self:clampHeight(h) - self.contentPadding.up - self.contentPadding.down

    if debugDraw then
        w = w + 2*DEBUG_DRAW_SEP_WIDTH
        h = h + 2*DEBUG_DRAW_SEP_WIDTH
    end

    return x, y, w, h
end

function PatchedImage:clampWidth(w)
    return math.max(w, self.patches[1][1]:getWidth() + self.patches[1][3]:getWidth())
end

function PatchedImage:clampHeight(h)
    return math.max(h, self.patches[1][1]:getHeight() + self.patches[3][1]:getHeight())
end

function M.setDebug(t)
    debugDraw = t.draw
    debugLog = t.log
end

function M.isDebugLogging()
    return debugLog
end

function M.isDebugDrawing()
    return debugDraw
end

return M