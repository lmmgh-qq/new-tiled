--- Simple and fast Tiled map loader and renderer.
-- 简单、快速的 Tiled 地图加载与渲染库，适配 LÖVE 框架。
-- 已适配 Tiled 1.2.1：支持 class/type 兼容、视差默认值、tintcolor 字符串解析、
-- 对象模板保护及 wangsets 安全忽略。
-- @module sti
-- @author Landon Manning
-- @copyright 2019
-- @license MIT/X11

local STI = {
	_LICENSE     = "MIT/X11",
	_URL         = "https://github.com/karai17/Simple-Tiled-Implementation",
	_VERSION     = "1.2.3.0",
	_DESCRIPTION = "Simple Tiled Implementation is a Tiled Map Editor library designed for the *awesome* LÖVE framework.",
	cache        = {}
}
STI.__index = STI

local love  = _G.love
local cwd   = (...):gsub('%.init$', '') .. "."
local utils = require(cwd .. "utils")
local ceil  = math.ceil
local floor = math.floor
local lg    = require(cwd .. "graphics")
local atlas = require(cwd .. "atlas")
local Map   = {}
Map.__index = Map

--- 内部构造函数：加载地图文件或地图表，并初始化地图对象
-- @param map 地图文件路径（.lua 格式）或地图数据表
-- @param plugins 插件列表（可选）
-- @param ox X 轴偏移量（像素，可选）
-- @param oy Y 轴偏移量（像素，可选）
-- @return table 已加载并初始化的地图对象
local function new(map, plugins, ox, oy)
	local dir = ""

	if type(map) == "table" then
		map = setmetatable(map, Map)
	else
		-- 检查文件类型是否合法
		local ext = map:sub(-4, -1)
		assert(ext == ".lua", string.format(
			"Invalid file type: %s. File must be of type: lua.",
			ext
		))

		-- 获取地图文件所在目录
		dir = map:reverse():find("[/\\]") or ""
		if dir ~= "" then
			dir = map:sub(1, 1 + (#map - dir))
		end

		-- 使用 LÖVE 文件系统加载地图文件
		map = setmetatable(assert(love.filesystem.load(map))(), Map)
	end

	map:init(dir, plugins, ox, oy)

	return map
end

--- 创建地图实例（通过 STI() 调用）
-- @param map 地图文件路径（.lua 格式）或地图数据表
-- @param plugins 插件列表（可选）
-- @param ox X 轴偏移量（像素，可选）
-- @param oy Y 轴偏移量（像素，可选）
-- @return table 已加载的地图对象
function STI.__call(_, map, plugins, ox, oy)
	return new(map, plugins, ox, oy)
end

--- 清空图片缓存
-- 释放所有已缓存的图片资源，下次使用时将重新加载。
function STI:flush()
	self.cache = {}
end

--- 地图对象

--- 初始化地图：处理瓦片集、图层等所有地图数据
-- @param path 地图文件所在目录路径
-- @param plugins 插件名称列表（可选）
-- @param ox X 轴偏移量（像素，可选，默认 0）
-- @param oy Y 轴偏移量（像素，可选，默认 0）
function Map:init(path, plugins, ox, oy)
	if type(plugins) == "table" then
		self:loadPlugins(plugins)
	end

	self:resize()
	self.objects       = {}
	self.tiles         = {}
	self.tileInstances = {}
	self.offsetx = ox or 0
	self.offsety = oy or 0

	self.freeBatchSprites = {}
	setmetatable(self.freeBatchSprites, { __mode = 'k' })

	-- 遍历所有瓦片集，加载图片并生成瓦片数据
	local gid = 1
	for i, tileset in ipairs(self.tilesets) do
		assert(not tileset.filename, "STI does not support external Tilesets.\nYou need to embed all Tilesets.")

		-- 注意：wangsets 字段（Tiled 1.2+）在此处安全忽略，无需处理
        if tileset.image then
            -- 缓存瓦片集图片
            if lg.isCreated then
                local formatted_path = utils.format_path(path .. tileset.image)

                if not STI.cache[formatted_path] then
                    utils.fix_transparent_color(tileset, formatted_path)
                    utils.cache_image(STI, formatted_path, tileset.image)
                else
                    tileset.image = STI.cache[formatted_path]
                end
            end

            gid = self:setTiles(i, tileset, gid)
        elseif tileset.tilecount > 0 then
            -- 图片集合类型（无单一图片），构建纹理图集
            local files, ids = {}, {}
            for j = 1, #tileset.tiles do
                files[ j ] = utils.format_path(path .. tileset.tiles[j].image)
                ids[ j ] = tileset.tiles[j].id
            end

            local map = atlas.Atlas( files, "ids", ids )

            if lg.isCreated then
                local formatted_path = utils.format_path(path .. tileset.name)

                if not STI.cache[formatted_path] then
                    -- 集合类型无需处理透明色
                    utils.cache_image(STI, formatted_path, map.image)
                    tileset.image = map.image
                else
                    tileset.image = STI.cache[formatted_path]
                end
            end

            gid = self:setAtlasTiles(i, tileset, map.coords, gid)
        end
	end

	local layers = {}
	for _, layer in ipairs(self.layers) do
		self:groupAppendToList(layers, layer)
	end
	self.layers = layers

	-- 初始化所有图层
	for _, layer in ipairs(self.layers) do
		self:setLayer(layer, path)
	end
end

--- 将分组图层（group）中的子图层递归展开并追加到图层列表中
-- @param layers 目标图层列表
-- @param layer 当前图层数据（可能是 group 类型）
function Map:groupAppendToList(layers, layer)
	if layer.type == "group" then
		for _, groupLayer in pairs(layer.layers) do
			groupLayer.name = layer.name .. "." .. groupLayer.name
			groupLayer.visible = layer.visible
			groupLayer.opacity = layer.opacity * groupLayer.opacity
			groupLayer.offsetx = layer.offsetx + groupLayer.offsetx
			groupLayer.offsety = layer.offsety + groupLayer.offsety

			-- 继承父分组的自定义属性（子图层已有的属性优先）
			for key, property in pairs(layer.properties) do
				if groupLayer.properties[key] == nil then
					groupLayer.properties[key] = property
				end
			end

			self:groupAppendToList(layers, groupLayer)
		end
	else
		table.insert(layers, layer)
	end
end

--- 加载并注入插件
-- 插件文件位于 sti/plugins/ 目录下，以 .lua 为扩展名。
-- @param plugins 插件名称列表（字符串数组）
function Map:loadPlugins(plugins)
	for _, plugin in ipairs(plugins) do
		local pluginModulePath = cwd .. 'plugins.' .. plugin
		local ok, pluginModule = pcall(require, pluginModulePath)
		if ok then
			for k, func in pairs(pluginModule) do
				if not self[k] then
					self[k] = func
				end
			end
		end
	end
end

--- 根据单张瓦片集图片创建所有瓦片对象
-- 适配 Tiled 1.2.1：兼容 tile.class 与 tile.type 两种字段名。
-- @param index 瓦片集在 self.tilesets 中的索引
-- @param tileset 瓦片集数据表
-- @param gid 当前瓦片集第一个瓦片的全局 ID（Global ID）
-- @return number 下一个瓦片集的起始 GID
function Map:setTiles(index, tileset, gid)
	local quad    = lg.newQuad
	local imageW  = tileset.imagewidth
	local imageH  = tileset.imageheight
	local tileW   = tileset.tilewidth
	local tileH   = tileset.tileheight
	local margin  = tileset.margin
	local spacing = tileset.spacing
	local w       = utils.get_tiles(imageW, tileW, margin, spacing)
	local h       = utils.get_tiles(imageH, tileH, margin, spacing)

	for y = 1, h do
		for x = 1, w do
			local id    = gid - tileset.firstgid
			local quadX = (x - 1) * tileW + margin + (x - 1) * spacing
			local quadY = (y - 1) * tileH + margin + (y - 1) * spacing
			-- 适配 Tiled 1.2.1：class 字段取代旧的 type 字段
			local type = ""
			local properties, terrain, animation, objectGroup

			for _, tile in pairs(tileset.tiles) do
				if tile.id == id then
					properties  = tile.properties
					animation   = tile.animation
					objectGroup = tile.objectGroup
					-- 兼容 Tiled 1.2.1 的 class 字段与旧版的 type 字段
					type        = tile.class or tile.type or ""

					if tile.terrain then
						terrain = {}

						for i = 1, #tile.terrain do
							terrain[i] = tileset.terrains[tile.terrain[i] + 1]
						end
					end
				end
			end

			local tile = {
				id          = id,
				gid         = gid,
				tileset     = index,
				type        = type,
				quad        = quad(
					quadX,  quadY,
					tileW,  tileH,
					imageW, imageH
				),
				properties  = properties or {},
				terrain     = terrain,
				animation   = animation,
				objectGroup = objectGroup,
				frame       = 1,
				time        = 0,
				width       = tileW,
				height      = tileH,
				sx          = 1,
				sy          = 1,
				r           = 0,
				offset      = tileset.tileoffset,
			}

			self.tiles[gid] = tile
			gid             = gid + 1
		end
	end

	return gid
end

--- 根据纹理图集创建所有瓦片对象（用于图片集合类型瓦片集）
-- 适配 Tiled 1.2.1：兼容 tile.class 与 tile.type 两种字段名。
-- @param index 瓦片集在 self.tilesets 中的索引
-- @param tileset 瓦片集数据表
-- @param coords 每个图片在图集中的坐标映射表
-- @param gid 当前瓦片集第一个瓦片的全局 ID
-- @return number 下一个瓦片集的起始 GID
function Map:setAtlasTiles(index, tileset, coords, gid)
    local quad      = lg.newQuad
    local imageW    = tileset.image:getWidth()
    local imageH    = tileset.image:getHeight()

    local firstgid = tileset.firstgid
    for i = 1, #tileset.tiles do
        local tile = tileset.tiles[i]
        local terrain
        if tile.terrain then
            terrain = {}

            for j = 1, #tile.terrain do
                terrain[j] = tileset.terrains[tile.terrain[j] + 1]
            end
        end

        local tile = {
            id          = tile.id,
            gid         = firstgid + tile.id,
            tileset     = index,
            -- 适配 Tiled 1.2.1：兼容 class 与旧版 type 字段
            type        = tile.class or tile.type or "",
            quad        = quad(
                coords[i].x,  coords[i].y,
                tile.width,  tile.height,
                imageW, imageH
            ),
            properties  = tile.properties or {},
            terrain     = terrain,
            animation   = tile.animation,
            objectGroup = tile.objectGroup,
            frame       = 1,
            time        = 0,
            width       = tile.width,
            height      = tile.height,
            sx          = 1,
            sy          = 1,
            r           = 0,
            offset      = tileset.tileoffset,
        }

        -- 注意：图片集合的 self.tiles 可能是稀疏数组
        self.tiles[tile.gid] = tile
    end

    return gid + #tileset.tiles
end

--- 初始化图层：解压数据、设置坐标并注册绘制函数
-- 适配 Tiled 1.2.1：初始化视差滚动默认值（parallaxx/parallaxy = 1）。
-- @param layer 图层数据表
-- @param path 地图文件所在目录路径（用于加载图片图层的图片）
function Map:setLayer(layer, path)
	if layer.encoding then
		if layer.encoding == "base64" then
			assert(require "ffi", "Compressed maps require LuaJIT FFI.\nPlease Switch your interperator to LuaJIT or your Tile Layer Format to \"CSV\".")
			local fd = love.data.decode("string", "base64", layer.data)

			if not layer.compression then
				layer.data = utils.get_decompressed_data(fd)
			else
				assert(love.data.decompress, "zlib and gzip compression require LOVE 11.0+.\nPlease set your Tile Layer Format to \"Base64 (uncompressed)\" or \"CSV\".")

				if layer.compression == "zlib" then
					local data = love.data.decompress("string", "zlib", fd)
					layer.data = utils.get_decompressed_data(data)
				end

				if layer.compression == "gzip" then
					local data = love.data.decompress("string", "gzip", fd)
					layer.data = utils.get_decompressed_data(data)
				end
			end
		end
	end

	layer.x      = (layer.x or 0) + layer.offsetx + self.offsetx
	layer.y      = (layer.y or 0) + layer.offsety + self.offsety
	layer.update = function() end

	-- 适配 Tiled 1.2.1：为视差滚动字段设置默认值（旧版地图可能缺少这两个字段）
	layer.parallaxx = layer.parallaxx or 1
	layer.parallaxy = layer.parallaxy or 1

	if layer.type == "tilelayer" then
		self:setTileData(layer)
		self:setSpriteBatches(layer)
		layer.draw = function() self:drawTileLayer(layer) end
	elseif layer.type == "objectgroup" then
		self:setObjectData(layer)
		self:setObjectCoordinates(layer)
		self:setObjectSpriteBatches(layer)
		layer.draw = function() self:drawObjectLayer(layer) end
	elseif layer.type == "imagelayer" then
		layer.draw = function() self:drawImageLayer(layer) end

		if layer.image ~= "" then
			local formatted_path = utils.format_path(path .. layer.image)
			if not STI.cache[formatted_path] then
				utils.cache_image(STI, formatted_path)
			end

			layer.image  = STI.cache[formatted_path]
			layer.width  = layer.image:getWidth()
			layer.height = layer.image:getHeight()
		end
	end

	self.layers[layer.name] = layer
end

--- 将瓦片数据填充到瓦片图层的二维数组中
-- 支持无限地图（Infinite Map）的 chunk 分块数据。
-- @param layer 瓦片图层数据表（或 chunk 数据表）
function Map:setTileData(layer)
	if layer.chunks then
		-- 无限地图：递归处理每个 chunk
		for _, chunk in ipairs(layer.chunks) do
			self:setTileData(chunk)
		end
		return
	end

	local i   = 1
	local map = {}

	for y = 1, layer.height do
		map[y] = {}
		for x = 1, layer.width do
			local gid = layer.data[i]

			-- 注意：空瓦片的 GID 为 0
			if gid > 0 then
				map[y][x] = self.tiles[gid] or self:setFlippedGID(gid)
			end

			i = i + 1
		end
	end

	layer.data = map
end

--- 将对象图层中的所有对象注册到地图的全局对象表中
-- 适配 Tiled 1.2.1：对对象模板（template）引入的可选字段添加默认值保护，
-- 防止 object.properties、object.width、object.height 为 nil 时报错。
-- @param layer 对象图层数据表
function Map:setObjectData(layer)
	for _, object in ipairs(layer.objects) do
		object.layer            = layer
		-- 适配 Tiled 1.2.1 模板对象：可能缺少 properties/width/height 字段
		object.properties = object.properties or {}
		object.width      = object.width  or 0
		object.height     = object.height or 0
		self.objects[object.id] = object
	end
end

--- 计算并修正对象图层中所有对象的世界坐标及顶点
-- 适配 Tiled 1.2.1：已在 setObjectData 中保证 width/height 有默认值。
-- @param layer 对象图层数据表
function Map:setObjectCoordinates(layer)
	for _, object in ipairs(layer.objects) do
		local x   = layer.x + object.x
		local y   = layer.y + object.y
		local w   = object.width
		local h   = object.height
		local cos = math.cos(math.rad(object.rotation))
		local sin = math.sin(math.rad(object.rotation))

		if object.shape == "rectangle" and not object.gid then
			object.rectangle = {}

			local vertices = {
				{ x=x,     y=y     },
				{ x=x + w, y=y     },
				{ x=x + w, y=y + h },
				{ x=x,     y=y + h },
			}

			for _, vertex in ipairs(vertices) do
				vertex.x, vertex.y = utils.rotate_vertex(self, vertex, x, y, cos, sin)
				table.insert(object.rectangle, { x = vertex.x, y = vertex.y })
			end
		elseif object.shape == "ellipse" then
			object.ellipse = {}
			local vertices = utils.convert_ellipse_to_polygon(x, y, w, h)

			for _, vertex in ipairs(vertices) do
				vertex.x, vertex.y = utils.rotate_vertex(self, vertex, x, y, cos, sin)
				table.insert(object.ellipse, { x = vertex.x, y = vertex.y })
			end
		elseif object.shape == "polygon" then
			for _, vertex in ipairs(object.polygon) do
				vertex.x           = vertex.x + x
				vertex.y           = vertex.y + y
				vertex.x, vertex.y = utils.rotate_vertex(self, vertex, x, y, cos, sin)
			end
		elseif object.shape == "polyline" then
			for _, vertex in ipairs(object.polyline) do
				vertex.x           = vertex.x + x
				vertex.y           = vertex.y + y
				vertex.x, vertex.y = utils.rotate_vertex(self, vertex, x, y, cos, sin)
			end
		end
	end
end

--- 将瓦片坐标（行列）转换为该瓦片在图层中的像素坐标
-- 根据地图方向（正交、等距、六边形、交错）进行不同的坐标计算。
-- @param layer 瓦片图层
-- @param tile 瓦片对象
-- @param x 瓦片列坐标（从 1 开始）
-- @param y 瓦片行坐标（从 1 开始）
-- @return number 瓦片实例在 X 轴上的像素位置
-- @return number 瓦片实例在 Y 轴上的像素位置
function Map:getLayerTilePosition(layer, tile, x, y)
	local tileW = self.tilewidth
	local tileH = self.tileheight
	local tileX, tileY

	if self.orientation == "orthogonal" then
		tileX = (x - 1) * tileW + tile.offset.x
		tileY = (y - 0) * tileH + tile.offset.y - tile.height
		tileX, tileY = utils.compensate(tile, tileX, tileY, tileW, tileH)
	elseif self.orientation == "isometric" then
		tileX = (x - y) * (tileW / 2) + tile.offset.x + layer.width * tileW / 2 - self.tilewidth / 2
		tileY = (x + y - 2) * (tileH / 2) + tile.offset.y
	else
		local sideLen = self.hexsidelength or 0
		if self.staggeraxis == "y" then
			if self.staggerindex == "odd" then
				if y % 2 == 0 then
					tileX = (x - 1) * tileW + tileW / 2 + tile.offset.x
				else
					tileX = (x - 1) * tileW + tile.offset.x
				end
			else
				if y % 2 == 0 then
					tileX = (x - 1) * tileW + tile.offset.x
				else
					tileX = (x - 1) * tileW + tileW / 2 + tile.offset.x
				end
			end

			local rowH = tileH - (tileH - sideLen) / 2
			tileY = (y - 1) * rowH + tile.offset.y
		else
			if self.staggerindex == "odd" then
				if x % 2 == 0 then
					tileY = (y - 1) * tileH + tileH / 2 + tile.offset.y
				else
					tileY = (y - 1) * tileH + tile.offset.y
				end
			else
				if x % 2 == 0 then
					tileY = (y - 1) * tileH + tile.offset.y
				else
					tileY = (y - 1) * tileH + tileH / 2 + tile.offset.y
				end
			end

			local colW = tileW - (tileW - sideLen) / 2
			tileX = (x - 1) * colW + tile.offset.x
		end
	end

	return tileX, tileY
end

--- 向精灵批处理中添加新的瓦片实例
-- @param layer 瓦片图层
-- @param chunk 图层分块数据（无限地图时使用，否则为 nil）
-- @param tile 瓦片对象
-- @param x 瓦片列坐标（含 chunk 偏移）
-- @param y 瓦片行坐标（含 chunk 偏移）
function Map:addNewLayerTile(layer, chunk, tile, x, y)
	local tileset = tile.tileset
	local image   = self.tilesets[tile.tileset].image
	local batches
	local size

	if chunk then
		batches = chunk.batches
		size    = chunk.width * chunk.height
	else
		batches = layer.batches
		size    = layer.width * layer.height
	end

	batches[tileset] = batches[tileset] or lg.newSpriteBatch(image, size)

	local batch = batches[tileset]
	local tileX, tileY = self:getLayerTilePosition(layer, tile, x, y)

	local instance = {
		layer = layer,
		chunk = chunk,
		gid   = tile.gid,
		x     = tileX,
		y     = tileY,
		r     = tile.r,
		oy    = 0
	}

	-- 注意：STI 可以在无图形环境下运行，此时 batch 可能为 nil
	if batch then
		instance.batch = batch
		instance.id = batch:add(tile.quad, tileX, tileY, tile.r, tile.sx, tile.sy)
	end

	self.tileInstances[tile.gid] = self.tileInstances[tile.gid] or {}
	table.insert(self.tileInstances[tile.gid], instance)
end

--- 遍历图层（或 chunk）中的所有格子并创建精灵批处理
-- 根据地图方向和渲染顺序决定遍历顺序。
-- @param layer 瓦片图层
-- @param chunk 图层分块（无限地图时使用，否则为 nil）
function Map:set_batches(layer, chunk)
	if chunk then
		chunk.batches = {}
	else
		layer.batches = {}
	end

	if self.orientation == "orthogonal" or self.orientation == "isometric" then
		local offsetX = chunk and chunk.x or 0
		local offsetY = chunk and chunk.y or 0

		local startX     = 1
		local startY     = 1
		local endX       = chunk and chunk.width  or layer.width
		local endY       = chunk and chunk.height or layer.height
		local incrementX = 1
		local incrementY = 1

		-- 根据 renderorder 决定瓦片加入批处理的顺序（默认 right-down）
		if self.renderorder == "right-up" then
			startY, endY, incrementY = endY, startY, -1
		elseif self.renderorder == "left-down" then
			startX, endX, incrementX = endX, startX, -1
		elseif self.renderorder == "left-up" then
			startX, endX, incrementX = endX, startX, -1
			startY, endY, incrementY = endY, startY, -1
		end

		for y = startY, endY, incrementY do
			for x = startX, endX, incrementX do
				-- 注意：不能短路，因为 tile 为 nil 是合法的（空格子）
				local tile
				if chunk then
					tile = chunk.data[y][x]
				else
					tile = layer.data[y][x]
				end

				if tile then
					self:addNewLayerTile(layer, chunk, tile, x + offsetX, y + offsetY)
				end
			end
		end
	else
		if self.staggeraxis == "y" then
			for y = 1, (chunk and chunk.height or layer.height) do
				for x = 1, (chunk and chunk.width or layer.width) do
					local tile
					if chunk then
						tile = chunk.data[y][x]
					else
						tile = layer.data[y][x]
					end

					if tile then
						self:addNewLayerTile(layer, chunk, tile, x, y)
					end
				end
			end
		else
			local i = 0
			local _x

			if self.staggerindex == "odd" then
				_x = 1
			else
				_x = 2
			end

			while i < (chunk and chunk.width * chunk.height or layer.width * layer.height) do
				for _y = 1, (chunk and chunk.height or layer.height) + 0.5, 0.5 do
					local y = floor(_y)

					for x = _x, (chunk and chunk.width or layer.width), 2 do
						i = i + 1

						local tile
						if chunk then
							tile = chunk.data[y][x]
						else
							tile = layer.data[y][x]
						end

						if tile then
							self:addNewLayerTile(layer, chunk, tile, x, y)
						end
					end

					if _x == 1 then
						_x = 2
					else
						_x = 1
					end
				end
			end
		end
	end
end

--- 为瓦片图层创建精灵批处理以提升绘制性能
-- 支持无限地图（Infinite Map）的 chunk 分块处理。
-- @param layer 瓦片图层数据表
function Map:setSpriteBatches(layer)
	if layer.chunks then
		-- 无限地图：逐个处理每个 chunk
		for _, chunk in ipairs(layer.chunks) do
			self:set_batches(layer, chunk)
		end
		return
	end

	self:set_batches(layer)
end

--- 为对象图层中的瓦片对象创建精灵批处理
-- 按绘制顺序（topdown 时按 y 坐标排序）处理对象。
-- @param layer 对象图层数据表
function Map:setObjectSpriteBatches(layer)
	local newBatch = lg.newSpriteBatch
	local batches  = {}

	if layer.draworder == "topdown" then
		table.sort(layer.objects, function(a, b)
			return a.y + a.height < b.y + b.height
		end)
	end

	for _, object in ipairs(layer.objects) do
		if object.gid then
			local tile    = self.tiles[object.gid] or self:setFlippedGID(object.gid)
			local tileset = tile.tileset
			local image   = self.tilesets[tileset].image

			batches[tileset] = batches[tileset] or newBatch(image)

			local sx = object.width  / tile.width
			local sy = object.height / tile.height

			-- Tiled 以左下角为旋转中心，而 LÖVE 以左上角为旋转中心
			local ox = 0
			local oy = tile.height

			local batch = batches[tileset]
			local tileX = object.x + tile.offset.x
			local tileY = object.y + tile.offset.y
			local tileR = math.rad(object.rotation)

			-- 处理水平翻转的旋转补偿
			if tile.sx == -1 then
				tileX = tileX + object.width

				if tileR ~= 0 then
					tileX = tileX - object.width
					ox = ox + tile.width
				end
			end

			-- 处理垂直翻转的旋转补偿
			if tile.sy == -1 then
				tileY = tileY - object.height

				if tileR ~= 0 then
					tileY = tileY + object.width
					oy = oy - tile.width
				end
			end

			local instance = {
				id    = batch:add(tile.quad, tileX, tileY, tileR, tile.sx * sx, tile.sy * sy, ox, oy),
				batch = batch,
				layer = layer,
				gid   = tile.gid,
				x     = tileX,
				y     = tileY - oy,
				r     = tileR,
				oy    = oy
			}

			self.tileInstances[tile.gid] = self.tileInstances[tile.gid] or {}
			table.insert(self.tileInstances[tile.gid], instance)
		end
	end

	layer.batches = batches
end

--- 添加自定义图层（用于放置游戏精灵等用户数据）
-- @param name 自定义图层名称
-- @param index 图层在绘制栈中的位置（可选，默认追加到末尾）
-- @return table 新创建的自定义图层对象
function Map:addCustomLayer(name, index)
	index = index or #self.layers + 1
	local layer = {
      type       = "customlayer",
      name       = name,
      visible    = true,
      opacity    = 1,
      properties = {},
    }

	function layer.draw() end
	function layer.update() end

	table.insert(self.layers, index, layer)
	self.layers[name] = self.layers[index]

	return layer
end

--- 将指定图层转换为自定义图层（清除瓦片/对象数据，保留名称和属性）
-- @param index 图层索引或图层名称
-- @return table 转换后的自定义图层对象
function Map:convertToCustomLayer(index)
	local layer = assert(self.layers[index], "Layer not found: " .. index)

	layer.type     = "customlayer"
	layer.x        = nil
	layer.y        = nil
	layer.width    = nil
	layer.height   = nil
	layer.encoding = nil
	layer.data     = nil
	layer.chunks   = nil
	layer.objects  = nil
	layer.image    = nil

	function layer.draw() end
	function layer.update() end

	return layer
end

--- 从图层栈中移除指定图层，并清理关联的批处理和对象数据
-- @param index 图层索引或图层名称
function Map:removeLayer(index)
	local layer = assert(self.layers[index], "Layer not found: " .. index)

	if type(index) == "string" then
		for i, l in ipairs(self.layers) do
			if l.name == index then
				table.remove(self.layers, i)
				self.layers[index] = nil
				break
			end
		end
	else
		local name = self.layers[index].name
		table.remove(self.layers, index)
		self.layers[name] = nil
	end

	-- 清理图层级批处理
	if layer.batches then
		for _, batch in pairs(layer.batches) do
			self.freeBatchSprites[batch] = nil
		end
	end

	-- 清理 chunk 级批处理（无限地图）
	if layer.chunks then
		for _, chunk in ipairs(layer.chunks) do
			for _, batch in pairs(chunk.batches) do
				self.freeBatchSprites[batch] = nil
			end
		end
	end

	-- 清理属于该图层的瓦片实例
	if layer.type == "tilelayer" then
		for _, tiles in pairs(self.tileInstances) do
			for i = #tiles, 1, -1 do
				local tile = tiles[i]
				if tile.layer == layer then
					table.remove(tiles, i)
				end
			end
		end
	end

	-- 清理属于该图层的对象
	if layer.objects then
		for i, object in pairs(self.objects) do
			if object.layer == layer then
				self.objects[i] = nil
			end
		end
	end
end

--- 更新动画瓦片帧并调用每个图层的 update 回调
-- @param dt 自上一帧以来经过的时间（秒）
function Map:update(dt)
	for _, tile in pairs(self.tiles) do
		local update = false

		if tile.animation then
			tile.time = tile.time + dt * 1000

			while tile.time > tonumber(tile.animation[tile.frame].duration) do
				update     = true
				tile.time  = tile.time  - tonumber(tile.animation[tile.frame].duration)
				tile.frame = tile.frame + 1

				if tile.frame > #tile.animation then tile.frame = 1 end
			end

			if update and self.tileInstances[tile.gid] then
				for _, j in pairs(self.tileInstances[tile.gid]) do
					local t = self.tiles[tonumber(tile.animation[tile.frame].tileid) + self.tilesets[tile.tileset].firstgid]
					j.batch:set(j.id, t.quad, j.x, j.y, j.r, tile.sx, tile.sy, 0, j.oy)
				end
			end
		end
	end

	for _, layer in ipairs(self.layers) do
		layer:update(dt)
	end
end

--- 将所有可见图层绘制到 Canvas，再将 Canvas 绘制到屏幕
-- 使用 Canvas 中间层可避免截断（scissoring）和撕裂（tearing）问题。
-- 支持视差滚动（parallax scrolling）。
-- @param tx X 轴平移量（像素，可选）
-- @param ty Y 轴平移量（像素，可选）
-- @param sx X 轴缩放比例（可选）
-- @param sy Y 轴缩放比例（可选）
function Map:draw(tx, ty, sx, sy)
	local current_canvas = lg.getCanvas()
	lg.setCanvas(self.canvas)
	lg.clear()

	-- 以 1.0 比例绘制到 Canvas，避免撕裂；平移到正确位置以绘制正确区域
	lg.push()
	lg.origin()

	--[[
		视差滚动实现参考：
		https://love2d.org/forums/viewtopic.php?p=238378#p238378
	]]

	tx, ty = tx or 0, ty or 0

	for _, layer in ipairs(self.layers) do
		if layer.visible and layer.opacity > 0 then
			-- parallaxx/parallaxy 已在 setLayer 中初始化为默认值 1
			local px, py = layer.parallaxx, layer.parallaxy
			px, py = math.floor(tx * px), math.floor(ty * py)
			lg.translate(px, py)
			self:drawLayer(layer)
			lg.translate(-px, -py)
		end
	end

	lg.pop()

	-- 以正确的缩放比例将 Canvas 绘制到屏幕（0,0 位置），修复裁剪问题
	lg.push()
	lg.origin()
	lg.scale(sx or 1, sy or sx or 1)

	lg.setCanvas(current_canvas)
	lg.draw(self.canvas)

	lg.pop()
end

--- 绘制单个图层（处理颜色、透明度和 tintcolor）
-- 适配 Tiled 1.2.1：同时支持字符串格式（"#aarrggbb"）和数组格式的 tintcolor。
-- @param _ 地图对象（未使用，保持 API 一致性）
-- @param layer 待绘制的图层
function Map.drawLayer(_, layer)
	local r,g,b,a = lg.getColor()
	-- 适配 Tiled 1.2.1：tintcolor 可能是 "#aarrggbb" 字符串
	if layer.tintcolor and type(layer.tintcolor) == "string" then
		layer.tintcolor = utils.parse_tintcolor(layer.tintcolor)
	end
	-- 如果图层设置了 tintcolor，则使用该颜色（Tiled 使用 0~255 范围）
	if layer.tintcolor then
		r, g, b, a = unpack(layer.tintcolor)
		a = a or 255
		lg.setColor(r/255, g/255, b/255, a/255)
	else
		-- 无 tintcolor 时使用当前颜色乘以图层透明度
		lg.setColor(r, g, b, a * layer.opacity)
	end
	layer:draw()
	lg.setColor(r,g,b,a)
end

--- 默认的瓦片图层绘制函数
-- 支持无限地图（chunk 模式）和普通地图。
-- @param layer 待绘制的瓦片图层（可传入索引或名称）
function Map:drawTileLayer(layer)
	if type(layer) == "string" or type(layer) == "number" then
		layer = self.layers[layer]
	end

	assert(layer.type == "tilelayer", "Invalid layer type: " .. layer.type .. ". Layer must be of type: tilelayer")

	-- 注意：chunk 模式不支持绘制范围裁剪，始终绘制所有 chunk
	if layer.chunks then
		for _, chunk in ipairs(layer.chunks) do
			for _, batch in pairs(chunk.batches) do
				lg.draw(batch, 0, 0)
			end
		end

		return
	end

	for _, batch in pairs(layer.batches) do
		lg.draw(batch, floor(layer.x), floor(layer.y))
	end
end

--- 默认的对象图层绘制函数
-- 绘制所有对象（矩形、椭圆、多边形、折线、点及瓦片对象）。
-- @param layer 待绘制的对象图层（可传入索引或名称）
function Map:drawObjectLayer(layer)
	if type(layer) == "string" or type(layer) == "number" then
		layer = self.layers[layer]
	end

	assert(layer.type == "objectgroup", "Invalid layer type: " .. layer.type .. ". Layer must be of type: objectgroup")

	local line  = { 160, 160, 160, 255 * layer.opacity       }
	local fill  = { 160, 160, 160, 255 * layer.opacity * 0.5 }
	local r,g,b,a = lg.getColor()
	local reset = {   r,   g,   b,   a * layer.opacity       }

	--- 将对象顶点列表转换为 LÖVE polygon 所需的扁平数值数组
	-- @param obj 顶点表（每项含 x、y 字段）
	-- @return table 扁平化的 {x1, y1, x2, y2, ...} 数组
	local function sortVertices(obj)
		local vertex = {}

		for _, v in ipairs(obj) do
			table.insert(vertex, v.x)
			table.insert(vertex, v.y)
		end

		return vertex
	end

	--- 根据形状类型绘制单个对象
	-- @param obj 顶点表（含 x、y 字段的数组）
	-- @param shape 形状类型字符串（"polyline"、"polygon" 或其他矩形/椭圆）
	local function drawShape(obj, shape)
		local vertex = sortVertices(obj)

		if shape == "polyline" then
			lg.setColor(line)
			lg.line(vertex)
			return
		elseif shape == "polygon" then
			lg.setColor(fill)
			if not love.math.isConvex(vertex) then
				local triangles = love.math.triangulate(vertex)
				for _, triangle in ipairs(triangles) do
					lg.polygon("fill", triangle)
				end
			else
				lg.polygon("fill", vertex)
			end
		else
			lg.setColor(fill)
			lg.polygon("fill", vertex)
		end

		lg.setColor(line)
		lg.polygon("line", vertex)
	end

	for _, object in ipairs(layer.objects) do
		if object.visible then
			if object.shape == "rectangle" and not object.gid then
				drawShape(object.rectangle, "rectangle")
			elseif object.shape == "ellipse" then
				drawShape(object.ellipse, "ellipse")
			elseif object.shape == "polygon" then
				drawShape(object.polygon, "polygon")
			elseif object.shape == "polyline" then
				drawShape(object.polyline, "polyline")
			elseif object.shape == "point" then
				lg.points(object.x, object.y)
			end
		end
	end

	lg.setColor(reset)
	for _, batch in pairs(layer.batches) do
		lg.draw(batch, 0, 0)
	end
	lg.setColor(r,g,b,a)
end

--- 默认的图片图层绘制函数
-- 支持 repeatx 和 repeaty 属性（图片平铺）。
-- @param layer 待绘制的图片图层（可传入索引或名称）
function Map:drawImageLayer(layer)
	if type(layer) == "string" or type(layer) == "number" then
		layer = self.layers[layer]
	end

	assert(layer.type == "imagelayer", "Invalid layer type: " .. layer.type .. ". Layer must be of type: imagelayer")

	if layer.image ~= "" then
		lg.draw(layer.image, layer.x, layer.y)
		-- 获取像素尺寸用于平铺计算
		local imagewidth, imageheight = layer.image:getDimensions()
		-- Y 轴平铺
		if layer.repeaty then
			local x = imagewidth
			local y = imageheight
			while y < self.height * self.tileheight do
				lg.draw(layer.image, x, y)
				-- 同时在 X 轴平铺
				if layer.repeatx then
					x = x + imagewidth
					while x < self.width * self.tilewidth do
						lg.draw(layer.image, x, y)
						x = x + imagewidth
					end
				end
				y = y + imageheight
			end
		-- 仅 X 轴平铺
		elseif layer.repeatx then
			local x = imagewidth
			while x < self.width * self.tilewidth do
				lg.draw(layer.image, x, layer.y)
				x = x + imagewidth
			end
		end
	end
end

--- 调整地图绘制区域的大小（重建 Canvas）
-- @param w 新的绘制区域宽度（像素，可选，默认为窗口宽度）
-- @param h 新的绘制区域高度（像素，可选，默认为窗口高度）
function Map:resize(w, h)
	if lg.isCreated then
		w = w or lg.getWidth()
		h = h or lg.getHeight()

		self.canvas = lg.newCanvas(w, h)
		self.canvas:setFilter("nearest", "nearest")
	end
end

--- 根据 GID 的翻转/旋转位标志创建对应的翻转瓦片
-- Tiled 使用高位 bit31、bit30、bit29 分别表示水平翻转、垂直翻转和对角线翻转。
-- @param gid 含翻转标志的全局瓦片 ID
-- @return table 处理后的翻转瓦片对象
function Map:setFlippedGID(gid)
	local bit31   = 2147483648
	local bit30   = 1073741824
	local bit29   = 536870912
	local flipX   = false
	local flipY   = false
	local flipD   = false
	local realgid = gid

	if realgid >= bit31 then
		realgid = realgid - bit31
		flipX   = not flipX
	end

	if realgid >= bit30 then
		realgid = realgid - bit30
		flipY   = not flipY
	end

	if realgid >= bit29 then
		realgid = realgid - bit29
		flipD   = not flipD
	end

	local tile = self.tiles[realgid]
	local data = {
		id         = tile.id,
		gid        = gid,
		tileset    = tile.tileset,
		frame      = tile.frame,
		time       = tile.time,
		width      = tile.width,
		height     = tile.height,
		offset     = tile.offset,
		quad       = tile.quad,
		properties = tile.properties,
		terrain    = tile.terrain,
		animation  = tile.animation,
		sx         = tile.sx,
		sy         = tile.sy,
		r          = tile.r,
	}

	-- 根据翻转标志组合计算最终变换
	if flipX then
		if flipY and flipD then
			data.r  = math.rad(-90)
			data.sy = -1
		elseif flipY then
			data.sx = -1
			data.sy = -1
		elseif flipD then
			data.r = math.rad(90)
		else
			data.sx = -1
		end
	elseif flipY then
		if flipD then
			data.r = math.rad(-90)
		else
			data.sy = -1
		end
	elseif flipD then
		data.r  = math.rad(90)
		data.sy = -1
	end

	self.tiles[gid] = data

	return self.tiles[gid]
end

--- 获取指定图层的自定义属性表
-- @param layer 图层名称或索引
-- @return table 属性表；若图层不存在则返回空表
function Map:getLayerProperties(layer)
	local l = self.layers[layer]

	if not l then
		return {}
	end

	return l.properties
end

--- 获取指定瓦片的自定义属性表
-- @param layer 图层名称或索引
-- @param x 瓦片列坐标（从 1 开始）
-- @param y 瓦片行坐标（从 1 开始）
-- @return table 属性表；若瓦片不存在则返回空表
function Map:getTileProperties(layer, x, y)
	local tile = self.layers[layer].data[y][x]

	if not tile then
		return {}
	end

	return tile.properties
end

--- 获取指定对象的自定义属性表
-- @param layer 图层名称或索引
-- @param object 对象索引（数字）或对象名称（字符串）
-- @return table 属性表；若对象不存在则返回空表
function Map:getObjectProperties(layer, object)
	local o = self.layers[layer].objects

	if type(object) == "number" then
		o = o[object]
	else
		for _, v in ipairs(o) do
			if v.name == object then
				o = v
				break
			end
		end
	end

	if not o then
		return {}
	end

	return o.properties
end

--- 将图层中指定位置的瓦片替换为另一个瓦片
-- @param layer 图层名称或索引
-- @param x 瓦片列坐标
-- @param y 瓦片行坐标
-- @param gid 新瓦片的全局 ID
function Map:setLayerTile(layer, x, y, gid)
	layer = self.layers[layer]

	layer.data[y] = layer.data[y] or {}
	local tile = layer.data[y][x]
	local instance
	if tile then
		local tileX, tileY = self:getLayerTilePosition(layer, tile, x, y)
		for _, inst in pairs(self.tileInstances[tile.gid]) do
			if inst.x == tileX and inst.y == tileY then
				instance = inst
				break
			end
		end
	end

	if tile == self.tiles[gid] then
		return
	end

	tile = self.tiles[gid]

	if instance then
		self:swapTile(instance, tile)
	else
		self:addNewLayerTile(layer, tile, x, y)
	end
	layer.data[y][x] = tile
end

--- 在精灵批处理中将一个瓦片实例替换为另一个
-- @param instance 当前需要替换的瓦片实例对象
-- @param tile 替换用的新瓦片对象（nil 表示清除该实例）
function Map:swapTile(instance, tile)
	-- 更新精灵批处理
	if instance.batch then
		if tile then
			instance.batch:set(
				instance.id,
				tile.quad,
				instance.x,
				instance.y,
				tile.r,
				tile.sx,
				tile.sy
			)
		else
			instance.batch:set(
				instance.id,
				instance.x,
				instance.y,
				0,
				0)

			self.freeBatchSprites[instance.batch] = self.freeBatchSprites[instance.batch] or {}
			table.insert(self.freeBatchSprites[instance.batch], instance)
		end
	end

	-- 移除旧瓦片实例记录
	for i, ins in ipairs(self.tileInstances[instance.gid]) do
		if ins.batch == instance.batch and ins.id == instance.id then
			table.remove(self.tileInstances[instance.gid], i)
			break
		end
	end

	-- 添加新瓦片实例记录
	if tile then
		self.tileInstances[tile.gid] = self.tileInstances[tile.gid] or {}

		local freeBatchSprites = self.freeBatchSprites[instance.batch]
		local newInstance
		if freeBatchSprites and #freeBatchSprites > 0 then
			newInstance = freeBatchSprites[#freeBatchSprites]
			freeBatchSprites[#freeBatchSprites] = nil
		else
			newInstance = {}
		end

		newInstance.layer = instance.layer
		newInstance.batch = instance.batch
		newInstance.id    = instance.id
		newInstance.gid   = tile.gid or 0
		newInstance.x     = instance.x
		newInstance.y     = instance.y
		newInstance.r     = tile.r or 0
		newInstance.oy    = tile.r ~= 0 and tile.height or 0
		table.insert(self.tileInstances[tile.gid], newInstance)
	end
end

--- 将瓦片坐标转换为像素坐标
-- 根据地图方向（正交、等距、交错/六边形）进行计算。
-- @param x 瓦片 X 轴坐标（列）
-- @param y 瓦片 Y 轴坐标（行）
-- @return number 像素 X 坐标
-- @return number 像素 Y 坐标
function Map:convertTileToPixel(x,y)
	if self.orientation == "orthogonal" then
		local tileW = self.tilewidth
		local tileH = self.tileheight
		return
			x * tileW,
			y * tileH
	elseif self.orientation == "isometric" then
		local mapH    = self.height
		local tileW   = self.tilewidth
		local tileH   = self.tileheight
		local offsetX = mapH * tileW / 2
		return
			(x - y) * tileW / 2 + offsetX,
			(x + y) * tileH / 2
	elseif self.orientation == "staggered" or
		self.orientation     == "hexagonal" then
		local tileW   = self.tilewidth
		local tileH   = self.tileheight
		local sideLen = self.hexsidelength or 0

		if self.staggeraxis == "x" then
			return
				x * tileW,
				ceil(y) * (tileH + sideLen) + (ceil(y) % 2 == 0 and tileH or 0)
		else
			return
				ceil(x) * (tileW + sideLen) + (ceil(x) % 2 == 0 and tileW or 0),
				y * tileH
		end
	end
end

--- 将像素坐标转换为瓦片坐标
-- 根据地图方向（正交、等距、交错、六边形）进行计算。
-- @param x 像素 X 坐标
-- @param y 像素 Y 坐标
-- @return number 瓦片 X 轴坐标（列）
-- @return number 瓦片 Y 轴坐标（行）
function Map:convertPixelToTile(x, y)
	if self.orientation == "orthogonal" then
		local tileW = self.tilewidth
		local tileH = self.tileheight
		return
			x / tileW,
			y / tileH
	elseif self.orientation == "isometric" then
		local mapH    = self.height
		local tileW   = self.tilewidth
		local tileH   = self.tileheight
		local offsetX = mapH * tileW / 2
		return
			y / tileH + (x - offsetX) / tileW,
			y / tileH - (x - offsetX) / tileW
	elseif self.orientation == "staggered" then
		local staggerX = self.staggeraxis  == "x"
		local even     = self.staggerindex == "even"

		--- 计算交错地图中左上方相邻格子坐标
		local function topLeft(x, y)
			if staggerX then
				if ceil(x) % 2 == 1 and even then
					return x - 1, y
				else
					return x - 1, y - 1
				end
			else
				if ceil(y) % 2 == 1 and even then
					return x, y - 1
				else
					return x - 1, y - 1
				end
			end
		end

		--- 计算交错地图中右上方相邻格子坐标
		local function topRight(x, y)
			if staggerX then
				if ceil(x) % 2 == 1 and even then
					return x + 1, y
				else
					return x + 1, y - 1
				end
			else
				if ceil(y) % 2 == 1 and even then
					return x + 1, y - 1
				else
					return x, y - 1
				end
			end
		end

		--- 计算交错地图中左下方相邻格子坐标
		local function bottomLeft(x, y)
			if staggerX then
				if ceil(x) % 2 == 1 and even then
					return x - 1, y + 1
				else
					return x - 1, y
				end
			else
				if ceil(y) % 2 == 1 and even then
					return x, y + 1
				else
					return x - 1, y + 1
				end
			end
		end

		--- 计算交错地图中右下方相邻格子坐标
		local function bottomRight(x, y)
			if staggerX then
				if ceil(x) % 2 == 1 and even then
					return x + 1, y + 1
				else
					return x + 1, y
				end
			else
				if ceil(y) % 2 == 1 and even then
					return x + 1, y + 1
				else
					return x, y + 1
				end
			end
		end

		local tileW = self.tilewidth
		local tileH = self.tileheight

		if staggerX then
			x = x - (even and tileW / 2 or 0)
		else
			y = y - (even and tileH / 2 or 0)
		end

		local halfH      = tileH / 2
		local ratio      = tileH / tileW
		local referenceX = ceil(x / tileW)
		local referenceY = ceil(y / tileH)
		local relativeX  = x - referenceX * tileW
		local relativeY  = y - referenceY * tileH

		if (halfH - relativeX * ratio > relativeY) then
			return topLeft(referenceX, referenceY)
		elseif (-halfH + relativeX * ratio > relativeY) then
			return topRight(referenceX, referenceY)
		elseif (halfH + relativeX * ratio < relativeY) then
			return bottomLeft(referenceX, referenceY)
		elseif (halfH * 3 - relativeX * ratio < relativeY) then
			return bottomRight(referenceX, referenceY)
		end

		return referenceX, referenceY
	elseif self.orientation == "hexagonal" then
		local staggerX  = self.staggeraxis  == "x"
		local even      = self.staggerindex == "even"
		local tileW     = self.tilewidth
		local tileH     = self.tileheight
		local sideLenX  = 0
		local sideLenY  = 0

		local colW       = tileW / 2
		local rowH       = tileH / 2
		if staggerX then
			sideLenX = self.hexsidelength
			x = x - (even and tileW or (tileW - sideLenX) / 2)
			colW = colW - (colW  - sideLenX / 2) / 2
		else
			sideLenY = self.hexsidelength
			y = y - (even and tileH or (tileH - sideLenY) / 2)
			rowH = rowH - (rowH  - sideLenY / 2) / 2
		end

		local referenceX = ceil(x) / (colW * 2)
		local referenceY = ceil(y) / (rowH * 2)

		-- 若在交错行/列，则参考坐标偏移 0.5
		if staggerX then
			if (floor(referenceX) % 2 == 0) == even then
				referenceY = referenceY - 0.5
			end
		else
			if (floor(referenceY) % 2 == 0) == even then
				referenceX = referenceX - 0.5
			end
		end

		local relativeX  = x - referenceX * colW * 2
		local relativeY  = y - referenceY * rowH * 2
		local centers

		if staggerX then
			local left    = sideLenX / 2
			local centerX = left + colW
			local centerY = tileH / 2

			centers = {
				{ x = left,           y = centerY        },
				{ x = centerX,        y = centerY - rowH },
				{ x = centerX,        y = centerY + rowH },
				{ x = centerX + colW, y = centerY        },
			}
		else
			local top     = sideLenY / 2
			local centerX = tileW / 2
			local centerY = top + rowH

			centers = {
				{ x = centerX,        y = top },
				{ x = centerX - colW, y = centerY },
				{ x = centerX + colW, y = centerY },
				{ x = centerX,        y = centerY + rowH }
			}
		end

		local nearest = 0
		local minDist = math.huge

		--- 计算两点距离的平方
		-- @param ax 第一点 X 坐标
		-- @param ay 第一点 Y 坐标
		-- @return number 距离平方值
		local function len2(ax, ay)
			return ax * ax + ay * ay
		end

		for i = 1, 4 do
			local dc = len2(centers[i].x - relativeX, centers[i].y - relativeY)

			if dc < minDist then
				minDist = dc
				nearest = i
			end
		end

		local offsetsStaggerX = {
			{ x = 1, y =  1 },
			{ x = 2, y =  0 },
			{ x = 2, y =  1 },
			{ x = 3, y =  1 },
		}

		local offsetsStaggerY = {
			{ x =  1, y = 1 },
			{ x =  0, y = 2 },
			{ x =  1, y = 2 },
			{ x =  1, y = 3 },
		}

		local offsets = staggerX and offsetsStaggerX or offsetsStaggerY

		return
			referenceX + offsets[nearest].x,
			referenceY + offsets[nearest].y
	end
end

--- 图层索引表（按绘制顺序和名称双重索引）
-- @table Map.layers
-- @see TileLayer
-- @see ObjectLayer
-- @see ImageLayer
-- @see CustomLayer

--- 瓦片索引表（按全局 ID 索引）
-- @table Map.tiles
-- @see Tile
-- @see Map.tileInstances

--- 瓦片实例索引表（按全局 ID 索引）
-- @table Map.tileInstances
-- @see TileInstance
-- @see Tile
-- @see Map.tiles

--- 空闲批处理精灵池（按批处理对象弱引用索引）
-- @table Map.freeBatchSprites

--- 对象索引表（按全局 ID 索引）
-- @table Map.objects
-- @see Object

--- @table TileLayer
-- @field name 图层名称
-- @field x 在 X 轴上的位置（像素）
-- @field y 在 Y 轴上的位置（像素）
-- @field width 图层宽度（瓦片数）
-- @field height 图层高度（瓦片数）
-- @field visible 是否可见
-- @field opacity 透明度
-- @field properties 自定义属性表
-- @field data 二维瓦片数据数组，以 [y][x] 索引（瓦片坐标）
-- @field update 更新回调函数
-- @field draw 绘制回调函数
-- @see Map.layers
-- @see Tile

--- @table ObjectLayer
-- @field name 图层名称
-- @field x 在 X 轴上的位置（像素）
-- @field y 在 Y 轴上的位置（像素）
-- @field visible 是否可见
-- @field opacity 透明度
-- @field properties 自定义属性表
-- @field objects 对象列表（按绘制顺序索引）
-- @field update 更新回调函数
-- @field draw 绘制回调函数
-- @see Map.layers
-- @see Object

--- @table ImageLayer
-- @field name 图层名称
-- @field x 在 X 轴上的位置（像素）
-- @field y 在 Y 轴上的位置（像素）
-- @field visible 是否可见
-- @field opacity 透明度
-- @field properties 自定义属性表
-- @field image 要绘制的图片对象
-- @field update 更新回调函数
-- @field draw 绘制回调函数
-- @see Map.layers

--- 自定义图层，用于在地图绘制顺序中放置用户数据（如玩家精灵）。
-- @table CustomLayer
-- @field name 图层名称
-- @field x 在 X 轴上的位置（像素）
-- @field y 在 Y 轴上的位置（像素）
-- @field visible 是否可见
-- @field opacity 透明度
-- @field properties 自定义属性表
-- @field update 更新回调函数
-- @field draw 绘制回调函数
-- @see Map.layers
-- @usage
--	-- 创建自定义图层
--	local spriteLayer = map:addCustomLayer("Sprite Layer", 3)
--
--	-- 向自定义图层添加数据
--	spriteLayer.sprites = {
--		player = {
--			image = lg.newImage("assets/sprites/player.png"),
--			x = 64,
--			y = 64,
--			r = 0,
--		}
--	}
--
--	-- 自定义图层更新回调
--	function spriteLayer:update(dt)
--		for _, sprite in pairs(self.sprites) do
--			sprite.r = sprite.r + math.rad(90 * dt)
--		end
--	end
--
--	-- 自定义图层绘制回调
--	function spriteLayer:draw()
--		for _, sprite in pairs(self.sprites) do
--			local x = math.floor(sprite.x)
--			local y = math.floor(sprite.y)
--			local r = sprite.r
--			lg.draw(sprite.image, x, y, r)
--		end
--	end

--- @table Tile
-- @field id 瓦片在瓦片集中的本地 ID
-- @field gid 全局 ID
-- @field tileset 所属瓦片集的索引
-- @field quad LÖVE Quad 裁剪对象
-- @field properties 自定义属性表
-- @field terrain 地形数据
-- @field animation 动画帧数据
-- @field frame 当前动画帧编号
-- @field time 在当前帧上已累计的时间（毫秒）
-- @field width 瓦片宽度（像素）
-- @field height 瓦片高度（像素）
-- @field sx X 轴缩放值
-- @field sy Y 轴缩放值
-- @field r 旋转角度（弧度）
-- @field offset 绘制位置偏移量
-- @field offset.x X 轴偏移值
-- @field offset.y Y 轴偏移值
-- @see Map.tiles

--- @table TileInstance
-- @field batch 所属精灵批处理对象
-- @field id 在精灵批处理中的 ID
-- @field gid 全局 ID
-- @field x 在 X 轴上的位置（像素）
-- @field y 在 Y 轴上的位置（像素）
-- @see Map.tileInstances
-- @see Tile

--- @table Object
-- @field id 全局 ID
-- @field name 对象名称（非唯一）
-- @field shape 对象形状类型
-- @field x 在 X 轴上的位置（像素）
-- @field y 在 Y 轴上的位置（像素）
-- @field width 宽度（像素）
-- @field height 高度（像素）
-- @field rotation 旋转角度（弧度）
-- @field visible 是否可见
-- @field properties 自定义属性表
-- @field ellipse 椭圆顶点列表
-- @field rectangle 矩形顶点列表
-- @field polygon 多边形顶点列表
-- @field polyline 折线顶点列表
-- @see Map.objects

return setmetatable({}, STI)
