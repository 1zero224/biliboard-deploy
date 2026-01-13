---
mode: plan
cwd: D:/work/biliboard/biliboard
task: 基于 report.md 的前后端改造执行计划（新前端数据接入）
complexity: complex
planning_method: builtin
created_at: 2026-01-13T20:21:32.7295892+08:00
---

# Plan: 新前端数据接入（后端公共 API + 数据模型补齐）

🎯 任务概述

当前 `Biliboard-frontend/` 主要依赖 mock 数据（周榜 `WEEKLY_SONGS`、About `BUBBLES`、提名页 stub）。目标是在不破坏旧后端管理能力（鉴权/导入/写入）的前提下，为新前端补齐**公共读 API**与必要的数据模型，使前端逐步移除 mock 并接入真实数据。计划以“先跑通 + 可回滚”为原则，分阶段交付。

📋 执行计划

1. 冻结 v0 数据契约（API Contract）
   - 决策点：`issueId` 是否复用 `periodcal`；封面 `coverUrl` 的返回方式（建议先使用 `/api/provider/biliimg/bvid/<bvid>` 作为 URL）；统计字段统一为 `number`（前端负责格式化）。
   - 产物：API 契约（文档或 types），涵盖 `Issue`、`RankingEntry`、`AboutWorks/Member/Link`。
   - 验证：前后端对字段命名、类型、可空性达成一致（避免“写完接口又返工改字段”）。

2. 前端接入前置整理（最小阻塞修复）
   - 修复 `npx tsc --noEmit` 的阻塞错误（`HeroPlayer`/`RankList` props 不匹配），保证类型检查可用。
   - 新增最小 `api` 层（`fetch` 封装 + `VITE_API_BASE_URL` 配置 + 错误处理约定）。
   - 验证：`npx tsc --noEmit` 通过；`npm run build` 通过。

3. 后端新增“公共读 API”路由分组（不走鉴权中间件）
   - 新增 `GET /api/public/*` 路由组（独立于现有鉴权路由），用于前端公开展示数据读取。
   - 验证：不带 cookie 访问可成功；现有鉴权路由行为不变。

4. About 页面数据：后端配置化 + 前端去 hardcode
   - 后端：提供 `GET /api/public/about/works|members|links`（建议先使用 JSON 配置文件驱动，避免 DB 迁移）。
   - 前端：将 `BUBBLES` 中 works/team/links 的数据数组从 `constants.tsx` 移除，改为组件在运行时拉取并渲染。
   - 验证：About 页三块数据来自 API；前端仍保留 bubble 布局/动画逻辑（只替换数据来源）。

5. Issue（期数/周榜入口）元数据：后端提供 issue 列表
   - 后端：提供 `GET /api/public/issues`，输出期数列表（`issueId/label/url/bvid/coverUrl/(可选)publishedAt`）。
   - 数据源建议：先用 JSON 配置维护（有明确负责人可后续迁入 DB），确保排序与展示稳定。
   - 验证：前端可以用该接口构建“期数下拉/切换周榜”的数据源，而不是从 `Song.date` 推导。

6. 周榜条目 v0：后端提供某期榜单条目（基础字段）
   - 后端：提供 `GET /api/public/issues/<issueId>/rankings`，先基于现有 `Rank + Tracing` join 返回：
     - `rank/title/producer(author)/vocalist(singer)/bvid/coverUrl`
     - stats/score/历史指标可先缺省或返回 0（由前端容错）。
   - 前端：RankingPage 改为 API 驱动，逐步替换 `WEEKLY_SONGS`（可保留 mock fallback 作为降级开关）。
   - 验证：主页榜单可展示、筛选可用、切换期数可刷新数据。

7. 指标快照 + 评分（v1）：补齐新前端核心展示字段
   - 后端新增统计快照表（建议 `periodcal + avid` 联合唯一），固化 view/like/coin/favorite 与 score，避免请求时高并发 fan-out 拉 B 站。
   - 增加采集/更新机制：定时任务（或管理端手动触发）生成本期快照；score 计算需版本化（最少记录 score_version 或固定公式版本）。
   - 验证：榜单条目返回真实 `stats/score`；接口响应稳定、可重复（历史榜单不会被新公式“重算”）。

8. 历史指标（lastRank/weeksOnBoard/peakRank）
   - 后端实现历史指标计算（SQL 聚合/窗口查询/预计算均可，优先 KISS：先 SQL 聚合满足正确性，再考虑性能优化）。
   - 增加必要索引，避免跨期计算导致响应退化。
   - 验证：抽样对比 Rank 历史数据，指标正确；常用期数查询响应时间可接受。

9. 集成验证、回滚/降级与发布路径
   - 可重复验证清单（建议从仓库根目录执行）：
     - 后端：`cd Biliboard-backend && cargo build && cargo run`（默认监听 `127.0.0.1:5800`）
     - 前端：`cd Biliboard-frontend && npx tsc --noEmit && npm run build`
     - public API smoke（后端运行后）：
       - `curl http://127.0.0.1:5800/api/public/ping`
       - `curl http://127.0.0.1:5800/api/public/issues`
       - `curl http://127.0.0.1:5800/api/public/issues/<issueId>/rankings`
       - `curl http://127.0.0.1:5800/api/public/about/works` / `members` / `links`
     - 鉴权边界 smoke（无 cookie）：`curl -i http://127.0.0.1:5800/api/user`（期望 401/403，需与现有行为一致）
     - 浏览器 smoke：`cd Biliboard-frontend && npm run dev`（Ranking/About 至少各浏览一次）
   - 回滚/降级：
     - 前端：`VITE_USE_MOCK_DATA=1` 强制 mock；API 请求失败时也会自动降级到 mock（不白屏）
     - 前端：`VITE_API_BASE_URL=http://127.0.0.1:5800` 指定后端地址（不设则同源）
     - 后端：`BILIBOARD_DISABLE_PUBLIC_API=1` 在路由层禁用 `/api/public/*`（不影响鉴权/写接口）
       - PowerShell 示例：`$env:BILIBOARD_DISABLE_PUBLIC_API=1; cargo run`
       - bash 示例：`BILIBOARD_DISABLE_PUBLIC_API=1 cargo run`
   - 验证：降级路径可用；旧后端管理侧能力不受影响（public 关闭时鉴权路由仍受限）。

⚠️ 风险与注意事项

- 数据源不确定：issue（期数/链接/封面）目前没有后端权威来源，需要确定“由谁维护、如何更新”的流程，否则容易长期漂移。
- B 站接口与风控：直接在请求链路实时抓取统计存在风控/限流风险；必须用快照/缓存策略，避免高并发 fan-out。
- 鉴权边界：public 读接口必须与鉴权写接口严格隔离，避免误开放管理能力；建议同时审视 `aid` bypass 的处理策略。
- About 页当前 `BubbleData.content` 以 JSX 常量形式存在，数据抽离会涉及一定的组件重构，需控制改动范围（只抽数据，不重做布局）。
- DB 迁移风险：新增表/索引需考虑已有数据与备份策略（尤其是生产环境）。

📎 参考

- `report.md`
- `Biliboard-frontend/constants.tsx:3`（`WEEKLY_SONGS` mock）
- `Biliboard-frontend/constants.tsx:160`（`BUBBLES` hardcode）
- `Biliboard-frontend/App.tsx:10`（导入 `WEEKLY_SONGS`）
- `Biliboard-backend/src/router/mod.rs:30`（`/api` 路由入口）
- `Biliboard-backend/src/router/mod.rs:35`（鉴权中间件 `authorization`）
- `Biliboard-backend/src/router/mod.rs:36`（鉴权中间件 `session_check`）
- `Biliboard-backend/src/router/rank/get.rs:34`（`get_by_periodcal_with_info`）
