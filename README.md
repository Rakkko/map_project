# OpenMapTiles + Martin 离线地图数据构建与发布指南

## 文档说明

本文档描述基于 OpenStreetMap（OSM）、OpenMapTiles、Martin 和 MapLibre 的离线地图数据构建、MBTiles 生成与发布流程。

适用于以下场景：

- 国家、省、市级地图数据构建
- 离线地图服务部署
- 地图数据扩展与区域合并
- MBTiles 矢量瓦片生成与发布
- 内网或无网络环境地图服务部署

---

# 1. 系统架构

本项目采用 OpenMapTiles 数据处理链路生成矢量瓦片，并通过 Martin 提供瓦片服务，最终由 MapLibre 完成地图渲染。

架构如下：

```text
OpenStreetMap (PBF)
        │
        ▼
 OpenMapTiles
        │
        ▼
   MBTiles
        │
        ▼
    Martin
        │
        ▼
     Nginx
        │
        ▼
   MapLibre GL
```

组件说明：

| 组件 | 功能 |
|--------|--------|
| OpenStreetMap | 原始地图数据 |
| OpenMapTiles | 地图数据处理与矢量瓦片生成 |
| MBTiles | 矢量瓦片存储格式 |
| Martin | 矢量瓦片服务 |
| Nginx | 前端静态资源服务 |
| MapLibre GL JS | 地图渲染引擎 |

---


# 2. 项目结构

初始化后目录结构如下：

```text
.
├── client
│   ├── docker-compose.yaml
│   ├── docker_image
│   ├── frontend
│   ├── martin
│   └── nginx
│
├── host
│   └── openmaptiles
│
└── Makefile
```

目录说明：

| 目录 | 说明 |
|--------|--------|
| client | 地图服务发布环境 |
| host | OpenMapTiles 数据处理环境 |
| client/martin | MBTiles 与 Martin 配置 |
| client/frontend | MapLibre 前端资源 |
| host/openmaptiles | OpenMapTiles 工作目录 |

---

# 3. 环境初始化（联网环境）

首次使用时需要联网下载：

- Docker 镜像
- OpenMapTiles 源码
- 字体资源（Glyphs）

执行：

```bash
make all
```

执行内容：

1. 下载 Martin 镜像
2. 下载 Nginx 镜像
3. 保存镜像到本地归档文件
4. 克隆 OpenMapTiles 仓库
5. 下载字体资源
6. 同步字体到前端目录

执行完成后即可进行地图数据处理。

---

# 4. 最大缩放级别（Max Zoom Level）配置

## 4.1 功能说明

OpenMapTiles 默认生成的最大缩放级别通常为：

```text
14
```

提高 Zoom Level 会显著增加：

- MBTiles 文件大小
- 数据生成时间
- 磁盘占用
- 内存消耗

---

## 4.2 配置 Zoom Level

执行：

```bash
make set-max-zoom zoom_level=<ZOOM_LEVEL>
```

示例：

```bash
make set-max-zoom zoom_level=20
```

该命令会同步修改：

```text
host/openmaptiles/.env
```

以及：

```text
host/openmaptiles/openmaptiles.yaml
```

中的最大缩放级别配置。

---

## 4.3 构建时指定 Zoom Level

也可以在数据构建过程中直接指定：

```bash
make download-data area=asia/china zoom_level=20
```

或：

```bash
make pbf-to-mbtiles area=china zoom_level=20
```

Makefile 将自动更新配置后再执行数据生成流程。

---

# 5. 在线下载并构建地图数据

适用于首次构建指定区域地图。

---

## 5.1 下载并生成 MBTiles

执行：

```bash
make download-data area=<AREA>
```

示例：

```bash
make download-data area=china
```

```bash
make download-data area=asia/china/sichuan
```

---

## 5.2 参数说明

| 参数 | 说明 |
|--------|--------|
| area | OpenMapTiles 支持的区域路径 |
| zoom_level | 可选，最大缩放级别 |

示例：

```bash
make download-data \
    area=asia/china \
    zoom_level=12
```

---

## 5.3 执行流程

系统将自动执行：

```text
下载区域 PBF
      ↓
导入 OSM 数据
      ↓
导入 Wikidata
      ↓
生成 SQL 数据
      ↓
生成 Bounding Box
      ↓
生成矢量瓦片
      ↓
输出 MBTiles
```

---

## 5.4 输出结果

生成文件：

```text
client/martin/area.mbtiles
```

该文件可直接用于 Martin 发布。

---

# 6. 使用已有 PBF 文件生成 MBTiles

当已经拥有 OSM PBF 文件时，可跳过下载流程。

---

## 6.1 准备数据

将 PBF 文件放置到 OpenMapTiles 数据目录。

例如：

```text
host/openmaptiles/data/china.osm.pbf
```

---

## 6.2 执行构建

```bash
make pbf-to-mbtiles area=<AREA>
```

示例：

```bash
make pbf-to-mbtiles area=china
```

---

## 6.3 Wikidata 下载控制

如果需要重新下载 Wikidata：

```bash
make pbf-to-mbtiles \
    area=china \
    download=true
```

如果已有 Wikidata 数据：

```bash
make pbf-to-mbtiles \
    area=china \
    download=false
```

---

## 6.4 参数说明

| 参数 | 说明 |
|--------|--------|
| area | PBF 数据名称（不含扩展名） |
| download | 是否下载 Wikidata |
| zoom_level | 最大缩放级别 |

示例：

```bash
make pbf-to-mbtiles \
    area=china \
    zoom_level=12 \
    download=false
```

---

# 7. 区域扩展与数据合并

当需要增加新的行政区域时，可利用 Osmium 对现有数据进行裁剪与合并。

> Osmium 工具不包含在本项目中，需要单独安装。

---

## 7.1 目录结构

```text
.
├── full_area.osm.pbf
├── orig_area.osm.pbf
└── config.json
```

---

## 7.2 提取新增区域

```bash
osmium extract \
    -c config.json \
    full_area.osm.pbf
```

---

## 7.3 合并区域数据

```bash
osmium merge \
    orig_area.osm.pbf \
    new_area_1.osm.pbf \
    new_area_2.osm.pbf \
    -o output.osm.pbf
```

输出：

```text
output.osm.pbf
```

---

## 7.4 提取配置示例

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

支持：

- Bounding Box
- Polygon
- Multipolygon

---

## 7.5 重新生成 MBTiles

数据合并完成后重新生成瓦片：

```bash
make pbf-to-mbtiles area=<AREA>
```

如果 Wikidata 已存在：

```bash
make pbf-to-mbtiles \
    area=<AREA> \
    download=false
```

推荐流程：

```text
区域提取
    ↓
区域合并
    ↓
生成新的 PBF
    ↓
重新生成 MBTiles
```

---

# 8. 发布 MBTiles 服务（离线）

生成 MBTiles 后即可在离线环境部署。

---

## 8.1 发布目录

MBTiles 文件位置：

```text
client/martin/area.mbtiles
```

---

## 8.2 启动服务

执行：

```bash
make publish-mbtiles
```

系统将自动：

1. 加载 Docker 镜像
2. 应用 Martin 配置
3. 应用前端样式配置
4. 启动 Martin 服务
5. 启动 Nginx 服务

---

## 8.3 停止服务

```bash
make stop
```

---

# 9. 服务验证

## 9.1 Martin 服务验证

访问：

```text
http://localhost:3000/catalog
```

检查：

- 服务正常响应
- MBTiles 已加载
- 数据集名称正确

---

## 9.2 地图服务验证

访问：

```text
http://localhost:8088
```

验证项：

| 项目 | 验证要求 |
|--------|--------|
| 地图加载 | 正常显示 |
| 瓦片请求 | HTTP 200 |
| Glyphs | 正常加载 |
| Sprite | 正常加载 |
| 浏览器控制台 | 无错误日志 |