# OpenMapTiles + Martin 离线地图数据构建与发布指南

## 文档说明

本文档描述基于 OpenStreetMap（OSM）、OpenMapTiles、Martin、Nginx 和 MapLibre GL JS 的离线地图数据构建、MBTiles 生成与发布流程。

项目采用统一的 Makefile 管理环境初始化、地图数据构建、MBTiles 发布及服务管理，可实现从数据下载到地图服务启动的一键化流程。

适用于以下场景：

- 国家、省、市级地图数据构建
- 离线地图服务部署
- 地图数据扩展与区域合并
- MBTiles 矢量瓦片生成与发布
- 内网或无网络环境地图服务部署

---

# 1. 系统架构

本项目采用 OpenMapTiles 数据处理链路生成矢量瓦片，并通过 Martin 提供瓦片服务，最终由 MapLibre GL JS 完成地图渲染。

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
 MapLibre GL JS
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

初始化完成后目录结构如下：

```text
.
├── client
│   ├── docker-compose.yaml
│   ├── docker_image
│   ├── frontend
│   ├── martin
│   │   ├── *.mbtiles
│   │   └── config.yaml
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
| client/docker_image | Docker 镜像缓存目录 |
| client/frontend | MapLibre GL JS 前端资源 |
| client/martin | Martin 配置及 MBTiles 数据 |
| client/nginx | Nginx 配置 |
| host | 数据处理环境 |
| host/openmaptiles | OpenMapTiles 工作目录 |
| Makefile | 工程统一入口 |

---

# 3. 环境初始化

首次部署或重新初始化工程时执行：

```bash
make init
```

初始化流程如下：

1. 检查 Docker、Git、GNU Make 是否安装。
2. 检查本地是否存在 Martin 与 Nginx Docker 镜像。
3. 缺失镜像时自动执行 `docker pull`。
4. 将镜像保存至：

```text
client/docker_image/
├── martin.tar
└── nginx.tar
```

5. 检查 `host/openmaptiles` 是否存在。
6. 不存在时自动克隆 OpenMapTiles 仓库。
7. 已存在时自动执行 `git pull` 更新。
8. 检查 OpenMapTiles 依赖环境。
9. 任一步骤失败立即退出并输出错误信息。

初始化完成后即可进行地图数据构建或地图服务发布。

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
make set-max-zoom zoom_level=16
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

# 5. 在线构建并发布地图

适用于联网环境，根据 OpenMapTiles 支持的区域名称自动下载 OSM 数据并完成地图发布。

## 5.1 执行命令

```bash
make online-publish area=<AREA>
```

例如：

```bash
make online-publish area=china
```

或

```bash
make online-publish area=asia/china/sichuan
```

---

## 5.2 参数说明

| 参数 | 说明 |
|--------|--------|
| area | OpenMapTiles 支持的区域名称 |

---

## 5.3 执行流程

系统依次执行：

```text
环境检查
      │
      ▼
OpenMapTiles 初始化
      │
      ▼
下载 OSM 数据
      │
      ▼
导入 OSM
      │
      ▼
导入 Wikidata
      │
      ▼
生成 SQL 数据
      │
      ▼
生成 Bounding Box
      │
      ▼
生成 MBTiles
      │
      ▼
复制到 client/martin
      │
      ▼
发布 Martin 服务
```

对应 OpenMapTiles 命令如下：

```text
make clean
make
make start-db
make import-data
make download area=$(area)
make import-osm area=$(area)
make import-wikidata area=$(area)
make import-sql
make generate-bbox-file area=$(area)
make generate-tiles-pg
```

生成完成后：

```text
host/openmaptiles/data/tiles.mbtiles
```

将自动复制为：

```text
client/martin/<AREA>.mbtiles
```

随后自动调用：

```bash
make publish-mbtiles area=<AREA>
```

完成地图发布。

---

# 6. 使用已有 PBF 文件离线构建

适用于已拥有 OSM PBF 数据文件的场景。

---

## 6.1 准备数据

将数据放置到：

```text
host/openmaptiles/data/<AREA>.osm.pbf
```

例如：

```text
host/openmaptiles/data/china.osm.pbf
```

---

## 6.2 执行命令

```bash
make offline-publish area=<AREA>
```

例如：

```bash
make offline-publish area=china
```

---

## 6.3 执行流程

系统首先检查：

```text
host/openmaptiles/data/<AREA>.osm.pbf
```

是否存在。

随后依次执行：

```text
make clean
make
make start-db
make import-data
make import-osm area=$(area)
make import-wikidata area=$(area)
make import-sql
make generate-bbox-file area=$(area)
make generate-tiles-pg
```

生成完成后：

```text
host/openmaptiles/data/tiles.mbtiles
```

将自动复制至：

```text
client/martin/<AREA>.mbtiles
```

随后自动发布地图服务。

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

# 8. 发布已有 MBTiles

若已存在 MBTiles 文件，可直接发布，无需重新构建。

---

## 8.1 数据准备

将 MBTiles 放置到：

```text
client/martin/<AREA>.mbtiles
```

---

## 8.2 执行命令

```bash
make publish-mbtiles area=<AREA>
```

例如：

```bash
make publish-mbtiles area=china
```

系统将自动：

1. 检查环境是否已初始化。
2. 检查 MBTiles 是否存在。
3. 检查 Docker 镜像。
4. 若本地镜像不存在，则从：

```text
client/docker_image/
```

自动加载镜像。
5. 检查 Martin 与 Nginx 服务是否已运行。

Docker Compose 将自动挂载：

```text
client/martin/
```

目录下全部 MBTiles 文件。

---

# 9. 服务管理

## 9.1 停止服务

```bash
make stop
```

停止 Martin 与 Nginx 服务。

---

## 9.2 清理生成数据

```bash
make clean
```

用于清理工程生成的 MBTiles 等临时数据，不影响 Docker 镜像缓存及 OpenMapTiles 源码。

---

# 10. 服务验证

## 10.1 Martin 服务验证

访问：

```text
http://<服务器地址>:3000/catalog
```

检查：

- Martin 服务正常启动
- MBTiles 已正确加载
- 数据集名称正确

---

## 10.2 地图服务验证

访问：

```text
http://<服务器地址>:8088
```

验证以下内容：

| 项目 | 验证要求 |
|--------|--------|
| 地图加载 | 正常显示 |
| 矢量瓦片 | HTTP 200 |
| Sprite | 正常加载 |
| Glyphs | 正常加载 |
| 浏览器控制台 | 无错误日志 |

若地图能够正常显示且 Martin Catalog 中存在对应数据集，则说明地图服务部署成功。