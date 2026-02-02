# Biliboard Deploy Repository

GitOps 部署仓库 - 通过修改 `.env.versions` 触发自动部署。

## 快速开始

### 服务器配置

1. **安装 webhook 工具**
```bash
# Ubuntu/Debian
sudo apt-get install webhook

# 或从 GitHub 下载
# https://github.com/adnanh/webhook/releases
```

2. **部署脚本和配置**
```bash
sudo mkdir -p /opt/biliboard-deploy
sudo cp -r . /opt/biliboard-deploy/
sudo chmod +x /opt/biliboard-deploy/scripts/deploy-webhook.sh
```

3. **配置 Secrets 文件**
```bash
# 创建 secrets 文件 (chmod 600)
sudo cat > /etc/biliboard-deploy.env << 'EOF'
WEBHOOK_SECRET=your-webhook-secret
GITHUB_PAT=ghp_xxxxxxxxxxxx
GITHUB_REPO=1zero224/biliboard-deploy
GHCR_USER=1zero224
GHCR_TOKEN=<YOUR_GHCR_PAT>
DEPLOY_DIR=/opt/biliboard-deploy
EOF
sudo chmod 600 /etc/biliboard-deploy.env
```

4. **更新 webhook-config.json**
```bash
# 替换占位符为实际 secret
sudo sed -i 's/REPLACE_WITH_YOUR_SECRET/your-webhook-secret/' /opt/biliboard-deploy/scripts/webhook-config.json
```

5. **启动服务**
```bash
sudo cp scripts/deploy-webhook.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable deploy-webhook
sudo systemctl start deploy-webhook
```

6. **配置 Nginx 反向代理 (推荐)**
```nginx
location /hooks/ {
    proxy_pass http://127.0.0.1:9000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

## GitHub Secrets 配置

### Backend/Frontend 仓库
| Secret | 用途 |
|--------|-----|
| `DEPLOY_REPO_TOKEN` | Fine-grained PAT，仅 `biliboard-deploy` 仓库的 `Contents: Read/Write` + `Pull requests: Read/Write` |

### Deploy 仓库
| Secret | 用途 |
|--------|-----|
| `WEBHOOK_SECRET` | 验证 webhook 请求 |
| `DEPLOY_WEBHOOK_URL` | 服务器 webhook 地址，如 `https://your-server/hooks/deploy` |

## 工作流程

```
1. 开发者 push 代码到 backend/frontend
2. CI 构建镜像并推送到 GHCR
3. CI 自动创建 PR 更新 .env.versions
4. 维护者合并 PR
5. Deploy workflow 发送 webhook
6. 服务器拉取新镜像并滚动更新
7. 健康检查 → 回传 Deployment Status
```

## 手动部署

```bash
# 触发部署
cd /opt/biliboard-deploy
git pull
docker compose pull
docker compose up -d
```

## 回滚

```bash
# 方法 1: Git revert
git revert HEAD
git push

# 方法 2: 手动指定版本
vim .env.versions  # 修改为旧版本
git add . && git commit -m "rollback" && git push
```
