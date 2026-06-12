# 地图数据准备与发布实施指南

## 文档概述

本文档说明基于 OpenStreetMap（OSM）、OpenMapTiles、Martin 和 MapLibre 的地图数据准备、处理与离线发布流程。

适用场景：

- 构建国家、省、市等区域地图数据
- 离线地图服务部署
- 地图数据增量扩展与区域合并
- MBTiles 矢量瓦片发布

---

# 1. 地图数据准备（联网环境）

> 说明：首次执行时需要联网下载依赖环境、OSM 数据及 Wikidata 数据。完成数据准备后，可在相同地区范围内进行离线处理（地区范围外仍需重新下载 OSM 与  Wikidata 数据）。生成 MBTiles 文件后可导入终端设备进行离线发布。

## 1.1 项目目录结构

```text
/
├── client
├── host
└── makefile
```

## 1.2 环境初始化

在项目根目录执行：

```bash
# 下载并初始化运行环境
make
```

## 1.3 下载并构建指定区域地图

用于从网络下载指定区域的 OSM 与 Wikidata 数据，并生成对应的 MBTiles 文件。

执行命令：

```bash
make download-data area=<AREA>
```

参数说明：

| 参数 | 说明 |
|--------|--------|
| AREA | 地图区域路径，例如 `asia/china/sichuan` |

执行流程：

1. 初始化数据库。
2. 下载指定区域 OSM 数据。
3. 下载相关 Wikidata 数据。
4. 生成矢量瓦片数据。
5. 输出 MBTiles 文件。

输出结果：

```text
data/tiles.mbtiles
```

该文件包含完整的矢量瓦片数据，可直接用于后续地图服务发布。

## 1.4 使用本地 PBF 数据生成 MBTiles

当已有 `.osm.pbf` 文件时，可跳过 OSM 数据下载步骤。

将 PBF 文件放置到 OpenMapTiles 指定目录后执行：

```bash
make pbf-to-mbtiles area=<AREA> download=<true|false>
```

参数说明：

| 参数 | 说明 |
|--------|--------|
| AREA | PBF 文件名称（不含扩展名） |
| download | 是否下载 Wikidata 数据。若数据已存在，可设置为 `false` 实现离线运行（默认值为 `false` ） |

---

# 2. 区域数据扩展与合并（可离线）

当需要在现有地图数据基础上增加新的行政区、城市或自定义区域时，可通过 Osmium 对数据进行裁剪和合并（相关可执行文件未包括在项目内）。

## 2.1 目录结构

```text
.
├── full_area.osm.pbf
├── orig_area.osm.pbf
└── config.json
```

文件说明：

| 文件 | 说明 |
|--------|--------|
| full_area.osm.pbf | 包含目标区域的完整数据 |
| orig_area.osm.pbf | 当前正在使用的数据 |
| config.json | 区域提取配置文件 |

## 2.2 提取新增区域

根据配置文件从完整数据源中提取目标区域。

```bash
osmium extract \
    -c config.json \
    full_area.osm.pbf
```

执行完成后将生成配置文件中定义的区域数据文件。

## 2.3 合并区域数据

将新增区域与现有地图数据进行合并。

```bash
osmium merge \
    orig_area.osm.pbf \
    new_area_1.osm.pbf \
    new_area_2.osm.pbf \
    -o output.osm.pbf
```

输出文件：

```text
output.osm.pbf
```

该文件即为合并后的完整地图数据。

## 2.4 区域提取配置说明

支持以下提取方式：

- Bounding Box（矩形范围）
- Polygon（单个多边形）
- Multipolygon（多个多边形）

示例配置：

```json
{
  "extracts": [
    {
      "output": "new_area_1.osm.pbf",
      "description": "Area 1",
      "bbox": [120.0, 30.0, 121.0, 31.0]
    },
    {
      "output": "new_area_2.osm.pbf",
      "description": "Area 2",
      "polygon": [[
        [9.613465, 53.58071],
        [9.647599, 53.59655],
        [9.649288, 53.61059],
        [9.613465, 53.58071]
      ]]
    }
  ]
}
```

## 2.5 重新生成 MBTiles

完成数据扩展或合并后，需重新生成 MBTiles。同，若已有新区域全部 Wikidata 数据，可将 download 设置为 `false` 以离线运行。

```bash
make pbf-to-mbtiles area=<AREA> download=<true|false>
```

建议流程：

```text
数据提取 / 数据合并
    ↓
生成 output.osm.pbf
    ↓
重新生成 MBTiles
```

---

# 3. MBTiles 服务发布（离线）

> 说明：将 MBTiles 文件导入目标终端后，本章节所有操作均可在离线环境执行。

## 3.1 系统架构

发布方案采用以下组件：

| 组件 | 功能 |
|--------|--------|
| Martin | 提供矢量瓦片服务接口 |
| Nginx | 提供静态资源服务 |
| MapLibre GL JS | 地图渲染引擎 |
| MBTiles | 矢量瓦片数据存储 |

系统架构：

```text
Browser
   │
   ▼
Nginx (Frontend)
   │
   ▼
Martin
   │
   ▼
area.mbtiles
```

## 3.2 项目目录结构

```text
client
├── docker-compose.yaml
├── nginx
│   └── nginx.conf
├── frontend
│   ├── index.html
│   ├── maplibre-gl.js
│   ├── maplibre-gl.css
│   ├── styles
│   │   └── style.json
│   ├── glyphs
│   └── sprites
└── martin
    ├── config.yaml
    └── area.mbtiles
```

## 3.3 Martin 服务验证

服务启动后访问：

```text
http://localhost:3000/catalog
```

验证项：

- 服务正常响应
- 已加载 MBTiles 数据
- 数据集名称显示正确

## 3.4 MapLibre 样式配置

配置文件：

```text
frontend/styles/style.json
```

建议基于 OpenMapTiles 官方样式（例如 `dark-matter`）进行本地化修改。

关键配置示例：

```json
{
  "sources": {
    "martin": {
      "type": "vector",
      "url": "http://localhost:3000/area"
    }
  },
  "sprite": "http://localhost:8088/sprites/sprite",
  "glyphs": "http://localhost:8088/glyphs/{fontstack}/{range}.pbf"
}
```

配置要求：

- `sources` 指向 Martin 服务。
- `sprite` 使用本地 Sprite 资源。
- `glyphs` 使用本地字体资源。
- 离线部署时避免引用外部资源。

## 3.5 启动服务

将 MBTiles 文件重命名并放置到（若使用 `make` 命令完成生成可跳过）：

```text
client/martin/area.mbtiles
```

在项目根目录执行：

```bash
# 启动地图服务
make publish-mbtiles

# 停止服务：
make stop
```

## 3.6 发布结果验证

访问：

```text
http://localhost:8088
```

检查以下内容：

| 检查项 | 验证要求 |
|----------|----------|
| 地图加载 | 地图正常显示 |
| 瓦片请求 | HTTP 状态码返回 200 |
| 字体资源 | 字体文件正常加载 |
| Sprite 资源 | 图标资源正常加载 |
| 浏览器控制台 | 无跨域或资源加载错误 |

当以上检查项全部通过后，即可确认地图服务发布成功。
