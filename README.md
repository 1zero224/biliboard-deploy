# Biliboard Deploy Repository

GitOps 部署仓库：以 `.env.versions` 作为生产环境“期望状态”（镜像引用使用 digest 固定）。

生产发布推荐采用 **Promotion → Deploy** 两阶段：

1. **Promotion（人工选择版本）**：手动触发 `Promote (Prepare Deploy PR)` 工作流，生成一个更新 `.env.versions` 的 PR（同时更新前后端，避免“半更新窗口”）。
2. **Deploy（生产审批 + 实际上线）**：PR 合并到 `master` 后触发 `Deploy` 工作流，在生产服务器上的 **GitHub self-hosted runner** 上执行 `docker compose pull/up`。该 job 绑定 `environment: production`，可在 GitHub Environments 中配置 required reviewers 作为上线审批。

详细步骤见 `biliboard-deploy/DEPLOYMENT.md`。

## 快速开始

### 服务器配置（Self-hosted runner）

1. 安装 Docker + Docker Compose v2（确保 `docker compose` 可用）
2. 创建 runner 用户并加入 docker 组（使 workflow 能执行 Docker 命令）
3. 仓库 `Settings → Actions → Runners → New self-hosted runner`，按 GitHub 指引在生产服务器安装并注册 runner
4. 给 runner 添加 label：`biliboard-prod`（与 `biliboard-deploy/.github/workflows/deploy.yml` 的 `runs-on` 保持一致）
5. 确保服务器可访问 `ghcr.io`，并安装 `curl`（用于健康检查）

## GitHub Secrets 配置

### Environments: production（推荐）

在 Deploy 仓库 `Settings → Environments → production`：

- 开启 `Required reviewers`（实现“生产必须人工审批后上线”）
- 可选配置 Variables / Secrets（例如 `HTTP_PORT`、`HTTPS_PORT`、`MQTT_HOST`、`MQTT_PORT` 等），供 `docker compose` 变量替换与健康检查使用

### Deploy 仓库
- 默认无需额外 Secrets（使用 `GITHUB_TOKEN` 拉取 GHCR 镜像并更新 Deployment Status）
- 若 GHCR 镜像为私有且默认权限不足，可添加只读 token（`packages:read`）并在 workflow 中替换登录凭据（默认未启用）

## 工作流程

```
1. 开发者 push 代码到 backend/frontend
2. CI 构建镜像并推送到 GHCR
3. 手动触发 deploy 仓库 Promote 工作流，生成 PR 更新 .env.versions（同时更新前后端）
4. 审核并合并 PR
5. Deploy workflow 在 production 环境等待人工审批
6. 生产服务器上的 self-hosted runner 执行 `docker compose pull/up`
7. 健康检查 → 更新 GitHub Deployment Status
```

## 手动 Promotion（推荐）

到 deploy 仓库 `Actions → Promote (Prepare Deploy PR)`：

- 从前后端 CI 的 job summary 复制 `Full ref`（含 digest）
- 填入 `backend_ref` / `frontend_ref`，运行后会自动创建一个 promotion PR

## 回滚

```bash
# 推荐：Git revert promotion PR
git revert HEAD
git push

# 或：手动指定旧 digest
vim .env.versions  # 修改为旧版本的 BACKEND_REF / FRONTEND_REF
git add . && git commit -m "rollback" && git push
```
