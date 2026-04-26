-- 一些不应暴露给外部的工具函数
local utils = {}

--- 格式化文件路径，规范化路径中的 . 和 .. 部分
-- 参考自 https://github.com/stevedonovan/Penlight/blob/master/lua/pl/path.lua#L286
-- @param path 需要格式化的路径字符串
-- @return string 格式化后的路径字符串
function utils.format_path(path)
	local np_gen1,np_gen2  = '[^SEP]+SEP%.%.SEP?','SEP+%.?SEP'
	local np_pat1, np_pat2 = np_gen1:gsub('SEP','/'), np_gen2:gsub('SEP','/')
	local k

	repeat -- /./ -> /
		path,k = path:gsub(np_pat2,'/',1)
	until k == 0

	repeat -- A/../ -> (empty)
		path,k = path:gsub(np_pat1,'',1)
	until k == 0

	if path == '' then path = '.' end

	return path
end

--- 计算因缩放/旋转引起的位移补偿
-- @param tile 瓦片对象（含 sx、sy、r 字段）
-- @param tileX 瓦片在 X 轴上的绘制位置（像素）
-- @param tileY 瓦片在 Y 轴上的绘制位置（像素）
-- @param tileW 瓦片宽度（像素）
-- @param tileH 瓦片高度（像素）
-- @return number 补偿后的 X 轴位置
-- @return number 补偿后的 Y 轴位置
function utils.compensate(tile, tileX, tileY, tileW, tileH)
	local compx = 0
	local compy = 0

	if tile.sx < 0 then compx = tileW end
	if tile.sy < 0 then compy = tileH end

	if tile.r > 0 then
		tileX = tileX + tileH - compy
		tileY = tileY + tileH + compx - tileW
	elseif tile.r < 0 then
		tileX = tileX + compy
		tileY = tileY - compx + tileH
	else
		tileX = tileX + compx
		tileY = tileY + compy
	end

	return tileX, tileY
end

--- 将图片缓存到主 STI 模块的缓存表中
-- @param sti STI 主模块对象（含 cache 字段）
-- @param path 图片文件路径
-- @param image （可选）已加载的 LÖVE 图片对象；若未提供则从路径加载
function utils.cache_image(sti, path, image)
	image = image or love.graphics.newImage(path)
	image:setFilter("nearest", "nearest")
	sti.cache[path] = image
end

--- 计算一行/列中可以容纳的瓦片数量
-- @param imageW 图片宽度（或高度，以像素为单位）
-- @param tileW 单个瓦片宽度（或高度，以像素为单位）
-- @param margin 图集边距（像素）
-- @param spacing 瓦片间距（像素）
-- @return number 该方向上可容纳的瓦片数量
function utils.get_tiles(imageW, tileW, margin, spacing)
	imageW  = imageW - margin
	local n = 0

	while imageW >= tileW do
		imageW = imageW - tileW
		if n ~= 0 then imageW = imageW - spacing end
		if imageW >= 0 then n  = n + 1 end
	end

	return n
end

--- 解压 Base64 编码的瓦片图层数据
-- 使用 LuaJIT FFI 将二进制字节流转换为 uint32 数组
-- @param data 已解码的二进制字符串
-- @return table 包含 GID 值的整数数组
function utils.get_decompressed_data(data)
	local ffi     = require "ffi"
	local d       = {}
	local decoded = ffi.cast("uint32_t*", data)

	for i = 0, data:len() / ffi.sizeof("uint32_t") do
		table.insert(d, tonumber(decoded[i]))
	end

	return d
end

--- 将 Tiled 椭圆对象转换为 LÖVE 多边形顶点数组
-- @param x 椭圆左上角 X 坐标（像素）
-- @param y 椭圆左上角 Y 坐标（像素）
-- @param w 椭圆宽度（像素）
-- @param h 椭圆高度（像素）
-- @param max_segments 最大分段数（可选，默认 64）
-- @return table 包含顶点 {x, y} 的数组
function utils.convert_ellipse_to_polygon(x, y, w, h, max_segments)
	local ceil = math.ceil
	local cos  = math.cos
	local sin  = math.sin

	--- 根据 Box2D 精度阈值计算合适的分段数
	-- @param segments 候选分段数
	-- @return number 最终分段数
	local function calc_segments(segments)
		local function vdist(a, b)
			local c = {
				x = a.x - b.x,
				y = a.y - b.y,
			}

			return c.x * c.x + c.y * c.y
		end

		segments = segments or 64
		local vertices = {}

		local v = { 1, 2, ceil(segments/4-1), ceil(segments/4) }

		local m
		if love and love.physics then
			m = love.physics.getMeter()
		else
			m = 32
		end

		for _, i in ipairs(v) do
			local angle = (i / segments) * math.pi * 2
			local px    = x + w / 2 + cos(angle) * w / 2
			local py    = y + h / 2 + sin(angle) * h / 2

			table.insert(vertices, { x = px / m, y = py / m })
		end

		local dist1 = vdist(vertices[1], vertices[2])
		local dist2 = vdist(vertices[3], vertices[4])

		-- Box2D 最小距离阈值
		if dist1 < 0.0025 or dist2 < 0.0025 then
			return calc_segments(segments-2)
		end

		return segments
	end

	local segments = calc_segments(max_segments)
	local vertices = {}

	table.insert(vertices, { x = x + w / 2, y = y + h / 2 })

	for i = 0, segments do
		local angle = (i / segments) * math.pi * 2
		local px    = x + w / 2 + cos(angle) * w / 2
		local py    = y + h / 2 + sin(angle) * h / 2

		table.insert(vertices, { x = px, y = py })
	end

	return vertices
end

--- 对单个顶点应用旋转变换（支持等距地图坐标系转换）
-- @param map 地图对象（含 orientation 字段）
-- @param vertex 顶点对象（含 x、y 字段，将被原地修改）
-- @param x 旋转中心 X 坐标
-- @param y 旋转中心 Y 坐标
-- @param cos 旋转角度的余弦值
-- @param sin 旋转角度的正弦值
-- @param oy Y 轴旋转偏移量（可选）
-- @return number 旋转后顶点的 X 坐标
-- @return number 旋转后顶点的 Y 坐标
function utils.rotate_vertex(map, vertex, x, y, cos, sin, oy)
	if map.orientation == "isometric" then
		x, y               = utils.convert_isometric_to_screen(map, x, y)
		vertex.x, vertex.y = utils.convert_isometric_to_screen(map, vertex.x, vertex.y)
	end

	vertex.x = vertex.x - x
	vertex.y = vertex.y - y

	return
		x + cos * vertex.x - sin * vertex.y,
		y + sin * vertex.x + cos * vertex.y - (oy or 0)
end

--- 将等距坐标（世界空间）投影到屏幕笛卡尔坐标
-- @param map 地图对象（含 width、tilewidth、tileheight 字段）
-- @param x 等距空间中的 X 坐标
-- @param y 等距空间中的 Y 坐标
-- @return number 屏幕空间中的 X 坐标（像素）
-- @return number 屏幕空间中的 Y 坐标（像素）
function utils.convert_isometric_to_screen(map, x, y)
	local mapW    = map.width
	local tileW   = map.tilewidth
	local tileH   = map.tileheight
	local tileX   = x / tileH
	local tileY   = y / tileH
	local offsetX = mapW * tileW / 2

	return
		(tileX - tileY) * tileW / 2 + offsetX,
		(tileX + tileY) * tileH / 2
end

--- 将十六进制颜色字符串转换为 LÖVE 颜色表（0~1 范围）
-- @param hex 十六进制颜色字符串，格式为 "#rrggbb" 或 "rrggbb"
-- @return table 包含 r、g、b 字段的颜色表（值域 0~1）
function utils.hex_to_color(hex)
	if hex:sub(1, 1) == "#" then
		hex = hex:sub(2)
	end

	return {
		r = tonumber(hex:sub(1, 2), 16) / 255,
		g = tonumber(hex:sub(3, 4), 16) / 255,
		b = tonumber(hex:sub(5, 6), 16) / 255
	}
end

--- 像素映射函数：将与透明色匹配的像素 alpha 设为 0
-- 由 love.image.ImageData:mapPixel() 调用
-- @param _ 像素 X 坐标（未使用）
-- @param _ 像素 Y 坐标（未使用）
-- @param r 当前像素红色通道值（0~1）
-- @param g 当前像素绿色通道值（0~1）
-- @param b 当前像素蓝色通道值（0~1）
-- @param a 当前像素 alpha 通道值（0~1）
-- @return number, number, number, number 处理后的 r, g, b, a 值
function utils.pixel_function(_, _, r, g, b, a)
	local mask = utils._TC

	if r == mask.r and
		g == mask.g and
		b == mask.b then
		return r, g, b, 0
	end

	return r, g, b, a
end

--- 处理瓦片集透明色：将透明色对应像素的 alpha 设为 0
-- @param tileset 瓦片集数据表（含 transparentcolor 字段）
-- @param path 图片文件路径
function utils.fix_transparent_color(tileset, path)
	local image_data = love.image.newImageData(path)
	tileset.image = love.graphics.newImage(image_data)

	if tileset.transparentcolor then
		utils._TC = utils.hex_to_color(tileset.transparentcolor)

		image_data:mapPixel(utils.pixel_function)
		tileset.image = love.graphics.newImage(image_data)
	end
end

--- 深拷贝一个表（递归复制所有嵌套子表）
-- @param t 待复制的表
-- @return table 深拷贝后的新表
function utils.deepCopy(t)
	local copy = {}
	for k,v in pairs(t) do
		if type(v) == "table" then
			v = utils.deepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

--- 解析 tintcolor 字符串（Tiled 1.2.1 新增格式）为数值数组
-- 支持 "#aarrggbb" 格式（Tiled 导出的 argb 十六进制字符串）
-- @param str tintcolor 字符串，格式为 "#aarrggbb"
-- @return table 包含 {r, g, b, a} 的数值数组（值域 0~255）
function utils.parse_tintcolor(str)
	if str:sub(1, 1) == "#" then
		str = str:sub(2)
	end
	-- Tiled 使用 argb 顺序
	local a = tonumber(str:sub(1, 2), 16) or 255
	local r = tonumber(str:sub(3, 4), 16) or 255
	local g = tonumber(str:sub(5, 6), 16) or 255
	local b = tonumber(str:sub(7, 8), 16) or 255
	return { r, g, b, a }
end

return utils
