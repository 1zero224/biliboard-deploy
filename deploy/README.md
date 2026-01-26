# Biliboard 生产部署指南

## 架构概览

```
                    ┌─────────────────────────────────────┐
                    │           Internet                   │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │     Nginx (反向代理 + SSL)           │
                    │     Port: 80/443                     │
                    └──────────────┬──────────────────────┘
                                   │
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
          ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │    │    Backend      │    │   Prometheus    │
│   (静态资源)     │    │   (Rust API)    │    │   Port: 9090    │
│                 │    │   Port: 5800    │    └────────┬────────┘
└─────────────────┘    └────────┬────────┘             │
                                │                      │
                       ┌────────▼────────┐    ┌────────▼────────┐
                       │     SQLite      │    │     Grafana     │
                       │   (Volume)      │    │   Port: 3000    │
                       └─────────────────┘    └─────────────────┘
```

---

## 部署前准备

### 服务器要求

| 项目 | 最低配置 | 推荐配置 |
|------|---------|---------|
| CPU | 1 核 | 2+ 核 |
| 内存 | 1 GB | 2+ GB |
| 磁盘 | 10 GB | 20+ GB |
| 系统 | Ubuntu 20.04+ / Debian 11+ | Ubuntu 22.04 LTS |

### 安装 Docker

```bash
# 一键安装
curl -fsSL https://get.docker.com | sh

# 将当前用户加入 docker 组
sudo usermod -aG docker $USER

# 重新登录或执行
newgrp docker

# 验证
docker --version
docker compose version
```

---

## 场景一：全新部署（从零开始）

适用于：首次部署项目，服务器上没有任何现有数据。

### 步骤 1：生成 SQLx 离线编译数据（开发机器上）

**为什么需要这一步？**

后端使用 SQLx 进行数据库操作。SQLx 在编译时会验证 SQL 查询的正确性，这需要连接数据库。在 Docker 构建阶段没有数据库可用，因此需要预先生成 `.sqlx` 目录，让 SQLx 使用"离线模式"编译。

**在你的开发机器上执行：**

```bash
cd Biliboard-backend

# 1. 安装 sqlx-cli 工具
cargo install sqlx-cli --no-default-features --features sqlite

# 2. 设置数据库连接（指向本地开发数据库）
mkdir -p data
export DATABASE_URL="sqlite:./data/dev.db"

# 3. 创建数据库并运行迁移
sqlx database create
sqlx migrate run

# 4. 生成离线编译元数据
cargo sqlx prepare

# 5. 验证生成成功（应看到多个 .json 文件）
ls -la .sqlx/

# 6. 提交到版本控制
git add .sqlx
git commit -m "Add sqlx offline compilation data"
git push
```

**常见问题：**

- **报错 "DATABASE_URL must be set"**：确保执行了 `export DATABASE_URL="sqlite:./data/dev.db"`
- **报错 "migration failed"**：检查 `migrations/` 目录是否存在且包含 SQL 文件
- **Windows 用户**：使用 `set DATABASE_URL=sqlite:./data/dev.db` 或在 PowerShell 中使用 `$env:DATABASE_URL="sqlite:./data/dev.db"`

### 步骤 2：在服务器上克隆代码

```bash
cd /opt  # 或你选择的部署目录
git clone <your-repository-url> biliboard
cd biliboard
```

### 步骤 3：配置环境变量

```bash
# 复制模板
cp .env.example .env

# 编辑配置
nano .env
```

**必须修改的配置项：**

```env
# Grafana 管理员密码（必改！默认 admin 不安全）
GRAFANA_PASSWORD=你的安全密码

# 如果使用自定义 MQTT 服务器
MQTT_HOST=your-mqtt-server.com
MQTT_PORT=1883
```

### 步骤 4：创建 SSL 证书目录

```bash
mkdir -p deploy/ssl
```

如果暂时不需要 HTTPS，可以跳过证书配置，服务会使用 HTTP。

### 步骤 5：构建并启动

```bash
# 构建所有镜像并启动服务（首次需要 5-15 分钟）
docker compose up -d --build

# 实时查看构建和启动日志
docker compose logs -f

# 检查服务状态（所有服务应显示 Up）
docker compose ps
```

### 步骤 6：验证部署

```bash
# 检查后端健康状态
curl http://localhost:5800/health

# 检查前端是否可访问
curl -I http://localhost
```

访问地址：
- 前端应用：`http://服务器IP`
- Grafana：`http://服务器IP:3000`（用户名 admin，密码为你设置的值）
- Prometheus：`http://服务器IP:9090`

---

## 场景二：迁移部署（带现有数据）

适用于：从旧服务器迁移，或需要恢复备份数据。

### 步骤 1-4：同场景一

完成代码克隆、环境配置等基础步骤。

### 步骤 5：准备数据文件

**情况 A：有 SQLite 数据库文件**

```bash
# 将数据库文件放到临时位置
cp /path/to/your/existing.db ./prod.db
```

**情况 B：有备份压缩包**

```bash
# 解压备份
gunzip biliboard_20240101_120000.db.gz
mv biliboard_20240101_120000.db ./prod.db
```

### 步骤 6：启动服务并导入数据

```bash
# 先启动服务（会创建空数据库）
docker compose up -d --build

# 等待后端启动完成
sleep 30

# 停止后端
docker compose stop backend

# 将数据库复制到容器卷中
docker cp ./prod.db biliboard-backend:/app/data/prod.db

# 修复权限
docker compose run --rm backend chown appuser:appuser /app/data/prod.db

# 重新启动后端
docker compose start backend

# 验证数据
docker compose logs backend
```

---

## 场景三：更新部署（已有运行中的服务）

适用于：代码更新后重新部署。

### 情况 A：仅更新代码，无数据库变更

```bash
cd /opt/biliboard

# 拉取最新代码
git pull

# 重新构建并部署（数据不会丢失）
docker compose up -d --build
```

### 情况 B：包含数据库迁移

```bash
cd /opt/biliboard

# 先备份数据库！
./backup-manager.sh now

# 拉取代码
git pull

# 如果 .sqlx 有更新，需要在开发机器上重新生成
# 然后在服务器上：
git pull  # 获取更新的 .sqlx

# 重建后端（迁移会在启动时自动运行）
docker compose up -d --build backend

# 检查迁移日志
docker compose logs backend | grep -i migrat
```

### 情况 C：仅更新前端

```bash
docker compose up -d --build frontend
```

---

## 数据库管理

### 数据库位置

- **容器内路径**：`/app/data/prod.db`
- **Docker 卷**：`biliboard_backend-data`

### 手动查看数据库

```bash
# 进入后端容器
docker compose exec backend sh

# 使用 sqlite3 查看
sqlite3 /app/data/prod.db

# 常用命令
.tables              # 列出所有表
.schema table_name   # 查看表结构
SELECT * FROM xxx LIMIT 10;  # 查询数据
.quit                # 退出
```

### 数据库迁移说明

迁移文件位于 `Biliboard-backend/migrations/`，命名格式为 `NNNN_description.sql`。

后端启动时会自动检测并运行未执行的迁移。如果迁移失败，查看日志：

```bash
docker compose logs backend | grep -i error
```

---

## 自动备份

项目内置自动备份服务，默认每 6 小时备份一次。

### 备份管理命令

```bash
# 赋予脚本执行权限（首次）
chmod +x backup-manager.sh

# 立即执行备份
./backup-manager.sh now

# 查看所有备份
./backup-manager.sh list

# 从备份恢复（交互式，会先备份当前数据）
./backup-manager.sh restore

# 下载备份到本地
./backup-manager.sh download

# 查看备份服务状态
./backup-manager.sh status

# 查看备份日志
./backup-manager.sh logs
```

### 自定义备份策略

编辑 `.env` 文件：

```env
# 备份计划（Cron 格式）
BACKUP_SCHEDULE=0 */6 * * *     # 每 6 小时（默认）
# BACKUP_SCHEDULE=0 2 * * *     # 每天凌晨 2 点
# BACKUP_SCHEDULE=0 */1 * * *   # 每小时（测试用）
# BACKUP_SCHEDULE=*/5 * * * *   # 每 5 分钟（仅调试）

# 备份保留天数
BACKUP_RETENTION_DAYS=7         # 保留 7 天（默认）
# BACKUP_RETENTION_DAYS=30      # 保留 30 天
```

修改后重启备份服务：

```bash
docker compose up -d backup
```

### 手动备份（不使用脚本）

```bash
# 导出到宿主机
docker cp biliboard-backend:/app/data/prod.db ./backup_$(date +%Y%m%d_%H%M%S).db

# 压缩
gzip ./backup_*.db
```

### 异地备份建议

将备份同步到云存储：

```bash
# 安装 rclone
curl https://rclone.org/install.sh | sudo bash

# 配置云存储（如 S3、阿里云 OSS）
rclone config

# 定期同步备份
rclone sync /var/lib/docker/volumes/biliboard_backup-data/_data remote:biliboard-backups
```

---

## SSL/HTTPS 配置

### 使用 Let's Encrypt（免费证书）

```bash
# 安装 certbot
apt install certbot

# 停止 nginx（释放 80 端口）
docker compose stop frontend

# 获取证书
certbot certonly --standalone -d your-domain.com

# 复制证书
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem deploy/ssl/
cp /etc/letsencrypt/live/your-domain.com/privkey.pem deploy/ssl/

# 重启服务
docker compose up -d frontend
```

### 启用 HTTPS

编辑 `deploy/nginx/conf.d/default.conf`，取消 SSL 相关注释。

### 自动续期

```bash
# 添加 crontab
crontab -e

# 添加以下行（每月 1 号凌晨 3 点续期）
0 3 1 * * certbot renew --quiet && docker compose restart frontend
```

---

## 防火墙配置

### Ubuntu (ufw)

```bash
# 基础端口
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS

# 监控端口（可选，建议仅内网访问）
sudo ufw allow 3000/tcp    # Grafana
sudo ufw allow 9090/tcp    # Prometheus

# 启用防火墙
sudo ufw enable
```

### 生产环境建议

仅开放 80/443，监控端口通过 VPN 或 SSH 隧道访问：

```bash
# 通过 SSH 隧道访问 Grafana
ssh -L 3000:localhost:3000 user@server

# 然后本地访问 http://localhost:3000
```

---

## 故障排查

### 后端无法启动

```bash
# 查看详细日志
docker compose logs backend

# 常见原因：
# 1. .sqlx 目录缺失 → 在开发机器上执行 cargo sqlx prepare
# 2. 数据库权限问题 → docker compose exec backend ls -la /app/data/
# 3. 端口冲突 → netstat -tlnp | grep 5800
```

### 前端 502 Bad Gateway

```bash
# 检查后端是否运行
docker compose ps backend

# 检查后端健康状态
docker compose exec backend curl -f http://localhost:5800/health

# 检查 nginx 配置
docker compose exec frontend nginx -t
```

### 数据库损坏

```bash
# 检查数据库完整性
docker compose exec backend sqlite3 /app/data/prod.db "PRAGMA integrity_check;"

# 如果损坏，从备份恢复
./backup-manager.sh restore
```

### 磁盘空间不足

```bash
# 查看 Docker 占用
docker system df

# 清理未使用的镜像和容器
docker system prune -a

# 清理旧备份
find /var/lib/docker/volumes/biliboard_backup-data/_data -name "*.db.gz" -mtime +30 -delete
```

---

## 目录结构

```
biliboard/
├── docker-compose.yml          # 服务编排
├── .env.example                # 环境变量模板
├── .env                        # 环境变量（不提交到 Git）
├── backup-manager.sh           # 备份管理脚本
├── Biliboard-backend/
│   ├── Dockerfile              # 后端镜像构建
│   ├── .sqlx/                  # SQLx 离线编译数据（需提交）
│   └── migrations/             # 数据库迁移文件
├── Biliboard-frontend/
│   └── Dockerfile              # 前端镜像构建
└── deploy/
    ├── README.md               # 本文档
    ├── backup/
    │   ├── Dockerfile          # 备份服务镜像
    │   └── backup.sh           # 备份脚本
    ├── nginx/
    │   ├── nginx.conf          # Nginx 主配置
    │   └── conf.d/
    │       └── default.conf    # 站点配置
    ├── prometheus/
    │   ├── prometheus.yml      # Prometheus 配置
    │   └── rules/
    │       └── alerts.yml      # 告警规则
    ├── grafana/
    │   ├── provisioning/       # 自动配置
    │   └── dashboards/         # 预置仪表盘
    └── ssl/                    # SSL 证书（不提交到 Git）
```

---

## 生产环境检查清单

- [ ] 修改 Grafana 默认密码
- [ ] 生成并提交 .sqlx 目录
- [ ] 配置 SSL/HTTPS
- [ ] 设置防火墙规则
- [ ] 验证自动备份正常运行
- [ ] 配置异地备份
- [ ] 测试备份恢复流程
- [ ] 配置告警通知
- [ ] 进行压力测试
