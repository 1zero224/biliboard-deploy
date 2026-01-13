# Public Read API Contract（v0）

本文档用于冻结新前端对后端 **公共只读接口**（`/api/public/*`）的最小数据契约，目标是降低前后端反复返工成本。

## 版本策略（v0）

- v0 允许 **仅新增字段**（保持向后兼容）；任何字段的删除/重命名/语义变更属于破坏性变更，必须通过新版本（例如 v1）交付。
- 前端必须对 **可选字段缺失** 与 **空数组** 做容错（不可白屏）。

## 通用约定

### 命名与类型

- JSON 字段命名：`camelCase`
- `issueId`：`number`（对应后端现有 `periodcal: i64` 的语义与取值，v0 冻结为同一个键，避免早期映射成本）
- 统计值（播放/赞/币/藏等）统一使用 **原始数值**：`number`（由前端负责格式化为 `1.2M` 等展示形式）

### `coverUrl` 返回策略（v0）

`coverUrl` 必须是可直接用于 `<img src="...">` 的 URL 字符串。

v0 推荐实现策略（可回滚且无需落库图片 URL）：

- `coverUrl = "/api/provider/biliimg/bvid/{bvid}"`

该路由返回图片 bytes（由后端代理与缓存）；前端如与后端分离部署，应使用 `VITE_API_BASE_URL` 拼接完整 URL。

### 空值与错误码（v0）

- **列表类接口**：资源存在但无数据 → `200` + `[]`
- **资源不存在**（例如未知 `issueId`）→ `404`
- v0 不强制规定错误 body 的 JSON envelope（后端当前错误风格以 `text/plain` 为主），但必须保证状态码语义清晰且不返回 200 掩盖错误。

## 数据模型

### `Issue`

用于「期数下拉/切换周榜」与其它公共展示入口。

```ts
export interface Issue {
  issueId: number;
  label: string;
  url: string;
  bvid: string;
  coverUrl: string;
  publishedAt?: string; // RFC3339/ISO8601（可选）
}
```

### `RankingEntry`

用于某期榜单条目展示（v0 最小字段）。

```ts
export interface RankingEntry {
  rank: number;
  title: string;
  producer: string;
  vocalist: string;
  bvid: string;
  coverUrl: string;

  // v0 可缺省：后端未补齐时可不返回；前端必须容错
  stats?: {
    views?: number;
    likes?: number;
    coins?: number;
    favorites?: number;
  };
  score?: number;
  lastRank?: number;
  weeksOnBoard?: number;
  peakRank?: number;
}
```

### About

About 页的数据应可由配置驱动（优先 JSON 文件），避免早期 DB 迁移。

```ts
export interface AboutWork {
  title: string;
  url: string;
  coverUrl?: string;
}

export interface AboutMember {
  name: string;
  role: string;
  color?: string;
  initials?: string;
}

export interface AboutLink {
  name: string;
  url: string;
}
```

## 端点草案（用于对齐，不作为 OpenAPI 的强约束）

> 具体实现以 `/api/public/*` 为准；此处用于冻结返回结构与语义。

- `GET /api/public/issues` → `Issue[]`
- `GET /api/public/issues/{issueId}/rankings` → `RankingEntry[]`
- `GET /api/public/about/works` → `AboutWork[]`
- `GET /api/public/about/members` → `AboutMember[]`
- `GET /api/public/about/links` → `AboutLink[]`

