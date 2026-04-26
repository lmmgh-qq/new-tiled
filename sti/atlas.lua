---- Simple Tiled Implementation 的纹理图集辅助模块
-- 用于将多张图片打包到一张纹理图集（Texture Atlas）中，
-- 以减少绘制调用次数并提高渲染性能。
-- @copyright 2022
-- @author Eduardo Hernández coz.eduardo.hernandez@gmail.com
-- @license MIT/X11

local module = {}

--- 创建纹理图集
-- 将多张独立图片打包为一张大纹理，并返回每张图片在图集中的坐标。
-- @param files 文件名数组，包含所有需要打包的图片路径
-- @param sort 排序方式："size" 按面积降序排列，"id" 按 ID 排列，其他值不排序
-- @param ids 与 files 对应的 ID 数组（可选）
-- @param pow2 若为 true，则强制图集尺寸为 2 的幂次方
-- @return table 包含 image（Canvas）和 coords（坐标表）的结果表，
--              或在纹理超过系统限制时返回错误字符串
function module.Atlas( files, sort, ids, pow2 )

    --- 创建一个矩形节点（用于二叉树空间分割）
    -- @param x 节点左上角 X 坐标
    -- @param y 节点左上角 Y 坐标
    -- @param w 节点宽度
    -- @param h 节点高度
    -- @return table 矩形节点表
    local function Node(x, y, w, h)
        return {x = x, y = y, w = w, h = h}
    end

    --- 计算大于等于 n 的最小 2 的幂次方
    -- @param n 输入正整数
    -- @return number 最小的满足条件的 2 的幂次方
    local function nextpow2( n )
        local res = 1
        while res <= n do
            res = res * 2
        end
        return res
    end

    --- 加载所有图片并（可选地）按面积排序
    -- @return table 图片信息数组，每项含 img、w、h、area 及可选的 id 字段
    local function loadImgs()
        local images = {}
        for i = 1, #files do
            images[i] = {}
            if ids then images[i].id = ids[i] end
            images[i].img = love.graphics.newImage( files[i] )
            images[i].w = images[i].img:getWidth()
            images[i].h = images[i].img:getHeight()
            images[i].area = images[i].w * images[i].h
        end
        if sort == "size" or sort == "id" then
            table.sort( images, function( a, b ) return ( a.area > b.area ) end )
        end
        return images
    end

    --- 向二叉树中递归插入一个矩形区域（bin packing 算法）
    -- @param root 当前树节点
    -- @param id 待插入图片的编号
    -- @param w 待插入区域宽度
    -- @param h 待插入区域高度
    -- @return table|nil 成功时返回放置节点，失败时返回 nil
    local function add(root, id, w, h)
        if root.left or root.right then
            if root.left then
                local node = add(root.left, id, w, h)
                if node then return node end
            end
            if root.right then
                local node = add(root.right, id, w, h)
                if node then return node end
            end
            return nil
        end

        if w > root.w or h > root.h then return nil end

        local _w, _h = root.w - w, root.h - h

        if _w <= _h then
            root.left = Node(root.x + w, root.y, _w, h)
            root.right = Node(root.x, root.y + h, root.w, _h)
        else
            root.left = Node(root.x, root.y + h, w, _h)
            root.right = Node(root.x + w, root.y, _w, root.h)
        end

        root.w = w
        root.h = h
        root.id = id

        return root
    end

    --- 将二叉树展开为以 ID 为键的坐标映射表
    -- @param root 二叉树根节点（可为 nil）
    -- @return table 以图片编号为键、{x, y} 为值的坐标表
    local function unmap(root)
        if not root then return {} end

        local tree = {}
        if root.id then
            tree[root.id] = {}
            tree[root.id].x, tree[root.id].y = root.x, root.y
        end

        local left = unmap(root.left)
        local right = unmap(root.right)

        for k, v in pairs(left) do
            tree[k] = {}
            tree[k].x, tree[k].y = v.x, v.y
        end
        for k, v in pairs(right) do
            tree[k] = {}
            tree[k].x, tree[k].y = v.x, v.y
        end

        return tree
    end

    --- 执行图集烘焙：将所有图片绘制到一张 Canvas 上
    -- 自动调整 Canvas 尺寸直到所有图片均能放入
    -- @return table|string 成功时返回 {image, coords}，
    --                      纹理过大时返回错误信息字符串
    local function bake()
        local images = loadImgs()

        local root = {}
        local w, h = images[1].w, images[1].h

        if pow2 then
            if w % 1 == 0 then w = nextpow2(w) end
            if h % 1 == 0 then h = nextpow2(h) end
        end

        repeat
            local node

            root = Node(0, 0, w, h)

            for i = 1, #images do
                node = add(root, i, images[i].w, images[i].h)
                if not node then break end
            end

            if not node then
                -- 图集不够大，按需扩展
                if h <= w then
                    if pow2 then h = h * 2 else h = h + 1 end
                else
                    if pow2 then w = w * 2 else w = w + 1 end
                end
            else
                break
            end
        until false

        local limits = love.graphics.getSystemLimits()
        if w > limits.texturesize or h > limits.texturesize then
            return "Resulting texture is too large for this system"
        end

        local coords = unmap(root)
        local map = love.graphics.newCanvas(w, h)
        love.graphics.setCanvas( map )

        -- 将每张图片绘制到图集的对应位置
        for i = 1, #images do
            love.graphics.draw(images[i].img, coords[i].x, coords[i].y)
            if ids then coords[i].id = images[i].id end
        end
        love.graphics.setCanvas()

        if sort == "ids" then
            table.sort( coords, function( a, b ) return ( a.id < b.id ) end )
        end

        return { image = map, coords = coords }
    end

    return bake()
end

return module
