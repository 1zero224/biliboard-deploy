# 生产部署文档（更新版：Promotion → Deploy）

本文档描述当前 `biliboard` 在 **单机 `docker-compose`** 场景下的生产部署流程，满足以下目标：

- **生产必须人工审批后上线**（GitHub Environments required reviewers）
- **版本发布原子性**：前后端一起 Promotion，避免“半更新窗口”
- **权限收口**：前/后端仓库只负责构建推镜像；部署仓库负责发布编排与上线
- **取消服务器入站 webhook**：生产机通过 GitHub self-hosted runner 主动执行部署（无需对外暴露 webhook 端口）
- **镜像可追溯且可回滚**：生产引用使用 `image@sha256:digest` 固定

---

## 1. 仓库职责与发布产物

### 1.1 仓库拆分

- `Biliboard-backend`：CI 构建并推送后端镜像到 GHCR
- `Biliboard-frontend`：CI 构建并推送前端镜像到 GHCR
- `biliboard-deploy`：GitOps 部署仓库，维护生产环境期望状态（`.env.versions` + `docker-compose.yml`），并在生产 runner 上执行部署

### 1.2 生产环境“期望状态”

`biliboard-deploy/.env.versions` 记录生产使用的镜像引用（固定 digest）：

- `BACKEND_REF=ghcr.io/<owner>/biliboard-backend:<tag>@sha256:<digest>`
- `FRONTEND_REF=ghcr.io/<owner>/biliboard-frontend:<tag>@sha256:<digest>`

`biliboard-deploy/docker-compose.yml` 使用 `${BACKEND_REF}` / `${FRONTEND_REF}` 拉取并启动服务。

---

## 2. 前置条件（一次性配置）

### 2.1 生产服务器软件依赖

在生产服务器安装：

- Docker Engine
- Docker Compose v2（确保 `docker compose version` 可用）
- `curl`

### 2.2 自建 Runner（Self-hosted runner）

1) 创建运行用户并授予 Docker 权限（示例：`deploy` 用户）：

```bash
sudo useradd -m -s "/bin/bash" "deploy"
sudo usermod -aG "docker" "deploy"
```

2) 在 GitHub：`biliboard-deploy` 仓库 → `Settings → Actions → Runners → New self-hosted runner`

按页面指引在服务器安装并注册 runner。

3) 给 runner 添加 label：`biliboard-prod`

> 说明：`biliboard-deploy/.github/workflows/deploy.yml` 使用 `runs-on: [self-hosted, biliboard-prod]`，label 不匹配会导致 workflow 无法调度到生产机。

### 2.3 GitHub Environments：生产审批

在 GitHub：`biliboard-deploy` 仓库 → `Settings → Environments → production`

- 开启 `Required reviewers`（必须审批后 job 才会继续执行）
- 可选：添加 Variables / Secrets（供 `docker compose` 与健康检查使用）

推荐添加的 Variables（按需）：

- `HTTP_PORT`（默认 `80`）
- `HTTPS_PORT`（默认 `443`）
- `MQTT_HOST`、`MQTT_PORT`
- `PROMETHEUS_PORT`（默认 `9090`）
- `GRAFANA_PORT`（默认 `3000`）
- `GRAFANA_USER`、`GRAFANA_PASSWORD`、`GRAFANA_ROOT_URL`

> `docker compose` 会继承 workflow 进程的环境变量，因此这些变量会在部署时生效。

### 2.4 GHCR 镜像拉取权限

Deploy workflow 会在生产 runner 上执行 `docker login ghcr.io` 并拉取镜像。

- 默认使用 `GITHUB_TOKEN` 登录（见 `biliboard-deploy/.github/workflows/deploy.yml`）
- 如果你将 GHCR package 设为私有，请确保 `biliboard-deploy` 仓库对 `biliboard-backend`/`biliboard-frontend` 的 package 有读取权限（或将 package 设为 public/internal）

如遇到 GHCR 拉取权限问题（常见报错：`denied: requested access to the resource is denied`），可选方案：

- 将相关 GHCR packages 调整为允许 `biliboard-deploy` 仓库读取
- 或创建 **只读** token（packages:read），作为 `production` 环境 secret（例如 `GHCR_TOKEN`），并在 deploy workflow 里改用该 token 登录

---

## 3. 日常发布流程（Promotion → Deploy）

### 3.1 构建镜像（前/后端仓库自动）

开发者 push 到 `main` 分支后：

- `Biliboard-backend/.github/workflows/ci.yml` 构建并推送镜像到 GHCR
- `Biliboard-frontend/.github/workflows/ci.yml` 构建并推送镜像到 GHCR

两边 CI 的 job summary 会输出可用于生产发布的 “Full ref”（含 digest）。

### 3.2 Promotion：生成“发布 PR”（一次更新前后端）

在 GitHub：`biliboard-deploy` → `Actions` → `Promote (Prepare Deploy PR)` → `Run workflow`

填入：

- `backend_ref`：从后端 CI summary 复制的 `Full ref`
- `frontend_ref`：从前端 CI summary 复制的 `Full ref`

运行成功后：

- 自动创建一个 PR，内容仅为更新 `biliboard-deploy/.env.versions`
- 该 PR 即为“本次 production release 的变更单”

### 3.3 审核并合并 Promotion PR

建议的合并策略：

- 只允许通过 Promotion workflow 生成的 PR 修改 `.env.versions`
- PR Review 重点检查：
  - 两个 ref 均为 `ghcr.io/...@sha256:...`（digest 固定）
  - 前后端 ref 是否对应同一轮发布（由发布人确认）

合并到 `master` 后，会触发下一步 Deploy。

### 3.4 Deploy：生产审批 + 上线执行

Promotion PR 合并后：

- `biliboard-deploy/.github/workflows/deploy.yml` 自动触发
- 因 job 绑定 `environment: production`：
  - 如果配置了 `Required reviewers`，workflow 会在 GitHub 页面进入等待审批状态

审批通过后，生产 runner 会执行：

1. 校验并导出 `.env.versions` 中的 `BACKEND_REF` / `FRONTEND_REF`
2. `docker compose pull`
3. `docker compose up -d --remove-orphans`
4. 健康检查：`http://127.0.0.1:${HTTP_PORT}/health`（重试）
5. 更新 GitHub Deployment Status（success/failure）

---

## 4. 回滚流程

### 4.1 推荐：Git revert Promotion PR

1) 对 `master` 上的 Promotion 合并提交执行 revert（会生成一个回滚 PR / 直接提交，取决于你的保护策略）
2) 合并后触发 Deploy
3) 走同样的 `production` 审批并上线

该方式优点：

- 审计链完整（可追溯“回滚原因”和“回滚到哪个版本”）
- 行为与正常发布一致（同样需要生产审批）

### 4.2 或：重新 Promotion 到旧 digest

从历史 PR 或 GHCR 中找到旧版本的 `backend_ref` / `frontend_ref`，再次运行 Promote 工作流生成新 PR 并合并。

---

## 5. 故障排查（常见问题）

### 5.1 Workflow 一直排队 / 不运行

- 检查生产 runner 是否在线
- 检查 runner label 是否包含 `biliboard-prod`

### 5.2 GHCR 拉取失败

- 检查镜像是否存在对应 tag/digest
- 检查 `biliboard-deploy` 对 GHCR package 的读取权限
- 必要时使用只读 token 登录（见 2.4）

### 5.3 健康检查失败（/health 不通）

- 确认 `HTTP_PORT`（默认 80）是否与你实际对外端口一致
- 检查 Nginx/后端容器状态：
  - `docker ps`
  - `docker logs "biliboard-backend"`
  - `docker logs "biliboard-frontend"`

---

## 6. 迁移清理（可选）

旧方案的服务器入站 webhook 相关文件仍保留在仓库：

- `biliboard-deploy/scripts/deploy-webhook.sh`
- `biliboard-deploy/scripts/deploy-webhook.service`
- `biliboard-deploy/scripts/webhook-config.json`

这些文件已不再被 GitHub Actions 使用，仅作为历史方案参考。你可以在生产服务器上自行停用旧 service（若曾启用）。

