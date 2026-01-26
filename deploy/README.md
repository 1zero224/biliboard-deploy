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

## 快速开始

### 1. 环境准备

```bash
# 安装 Docker & Docker Compose
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# 克隆项目
git clone <repository-url>
cd biliboard
```

### 2. 配置环境变量

```bash
cp .env.example .env
vim .env  # 修改必要配置
```

**必须修改的配置：**
- `GRAFANA_PASSWORD`: Grafana 管理员密码
- `MQTT_HOST`: MQTT 服务器地址（如需修改）

### 3. 启动服务

```bash
# 构建并启动所有服务
docker-compose up -d --build

# 查看日志
docker-compose logs -f

# 查看服务状态
docker-compose ps
```

### 4. 访问服务

| 服务 | 地址 | 说明 |
|------|------|------|
| 前端应用 | http://localhost | 主应用 |
| Grafana | http://localhost:3000 | 监控面板 |
| Prometheus | http://localhost:9090 | 指标查询 |

## SSL/HTTPS 配置

### 使用 Let's Encrypt

```bash
# 安装 certbot
apt install certbot

# 获取证书
certbot certonly --standalone -d your-domain.com

# 复制证书到部署目录
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem deploy/ssl/
cp /etc/letsencrypt/live/your-domain.com/privkey.pem deploy/ssl/
```

### 启用 HTTPS

编辑 `deploy/nginx/conf.d/default.conf`，取消 SSL 相关注释：

```nginx
listen 443 ssl http2;
ssl_certificate /etc/nginx/ssl/fullchain.pem;
ssl_certificate_key /etc/nginx/ssl/privkey.pem;
```

## 运维操作

### 日常管理

```bash
# 重启服务
docker-compose restart backend

# 查看特定服务日志
docker-compose logs -f backend

# 进入容器调试
docker-compose exec backend sh

# 停止所有服务
docker-compose down

# 停止并删除数据卷（危险！）
docker-compose down -v
```

### 数据备份

```bash
# 备份 SQLite 数据库
docker-compose exec backend cp /app/data/prod.db /app/data/backup_$(date +%Y%m%d).db

# 导出到宿主机
docker cp biliboard-backend:/app/data/prod.db ./backup/

# 备份 Grafana 配置
docker cp biliboard-grafana:/var/lib/grafana ./backup/grafana/
```

### 更新部署

```bash
# 拉取最新代码
git pull

# 重新构建并部署
docker-compose up -d --build

# 仅重建特定服务
docker-compose up -d --build backend
```

## 监控告警

### Prometheus 告警规则

预配置的告警规则位于 `deploy/prometheus/rules/alerts.yml`：

| 告警名称 | 触发条件 | 严重级别 |
|----------|----------|----------|
| BackendDown | 后端服务宕机 > 1分钟 | Critical |
| HighErrorRate | 错误率 > 10% 持续5分钟 | Warning |
| HighResponseTime | P95响应时间 > 1秒 | Warning |
| HighMemoryUsage | 内存使用 > 90% | Warning |
| HighCPUUsage | CPU使用 > 80% | Warning |
| DiskSpaceLow | 磁盘空间 < 10% | Critical |

### Grafana Dashboard

预配置的 Dashboard 包含：
- 服务状态概览
- CPU/内存/磁盘使用率
- 请求速率 (QPS)
- 响应时间分布 (P50/P95)

## 后端 Metrics 端点

**注意**：当前后端需要添加 `/metrics` 端点以支持 Prometheus 采集。

推荐使用 `metrics-rs` 或手动实现：

```rust
// 示例：添加 /health 和 /metrics 端点
#[handler]
async fn health() -> &'static str {
    "OK"
}

#[handler]
async fn metrics() -> String {
    // 返回 Prometheus 格式的指标
    format!(
        "# HELP http_requests_total Total HTTP requests\n\
         # TYPE http_requests_total counter\n\
         http_requests_total{{method=\"GET\"}} {}\n",
        REQUEST_COUNT.load(Ordering::Relaxed)
    )
}
```

## 故障排查

### 常见问题

**1. 后端无法连接数据库**
```bash
# 检查数据卷
docker volume inspect biliboard_backend-data

# 检查权限
docker-compose exec backend ls -la /app/data/
```

**2. Nginx 502 Bad Gateway**
```bash
# 检查后端是否启动
docker-compose ps backend
docker-compose logs backend

# 检查网络连通性
docker-compose exec frontend ping backend
```

**3. Prometheus 无法采集指标**
```bash
# 检查目标状态
curl http://localhost:9090/api/v1/targets

# 手动测试指标端点
docker-compose exec prometheus wget -qO- http://backend:5800/metrics
```

## 目录结构

```
biliboard/
├── docker-compose.yml          # 服务编排
├── .env.example                # 环境变量模板
├── Biliboard-backend/
│   └── Dockerfile              # 后端镜像
├── Biliboard-frontend/
│   └── Dockerfile              # 前端镜像
└── deploy/
    ├── nginx/
    │   ├── nginx.conf          # Nginx 主配置
    │   └── conf.d/
    │       └── default.conf    # 站点配置
    ├── prometheus/
    │   ├── prometheus.yml      # Prometheus 配置
    │   └── rules/
    │       └── alerts.yml      # 告警规则
    ├── grafana/
    │   ├── provisioning/
    │   │   ├── datasources/    # 数据源配置
    │   │   └── dashboards/     # Dashboard 配置
    │   └── dashboards/
    │       └── biliboard-overview.json
    └── ssl/                    # SSL 证书目录
```

## 生产环境检查清单

- [ ] 修改 Grafana 默认密码
- [ ] 配置 SSL/HTTPS
- [ ] 设置防火墙规则（仅开放 80/443）
- [ ] 配置日志轮转
- [ ] 设置自动备份
- [ ] 配置告警通知（邮件/Slack/钉钉）
- [ ] 压力测试
- [ ] 配置 CDN（可选）
