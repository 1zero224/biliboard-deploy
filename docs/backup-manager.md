# Biliboard 备份管理脚本使用文档

## 概述

`backup-manager.sh` 是 Biliboard 项目的数据库备份管理工具，提供备份创建、列表查看、恢复、下载等功能。

## 前置条件

- Docker 环境已安装并运行
- 备份容器已启动（带有 `com.biliboard.service=backup` 标签）
- 用户具有 Docker 命令执行权限

## 命令参考

```bash
./backup-manager.sh [command]
```

### now - 立即执行备份

```bash
./backup-manager.sh now
```

手动触发一次即时备份，备份文件将保存到容器内 `/backups/` 目录。

### list - 列出所有备份

```bash
./backup-manager.sh list
```

显示当前可用的所有备份文件及其大小。

### restore - 恢复数据库

```bash
./backup-manager.sh restore
```

交互式恢复流程：
1. 显示可用备份列表
2. 输入要恢复的备份文件名（如 `biliboard_20240101_120000.db.gz`）
3. 确认操作（输入 `yes` 确认）

⚠️ **警告**：恢复操作会替换当前数据库。执行前会自动创建 `pre_restore_*.db` 备份。

### download - 下载备份

```bash
./backup-manager.sh download
```

将备份文件从容器下载到本地 `./backups/` 目录。

### status - 查看服务状态

```bash
./backup-manager.sh status
```

显示：
- 备份服务运行状态
- 计划任务配置（crontab）

### logs - 查看日志

```bash
./backup-manager.sh logs
```

显示备份服务最近 50 条日志。

## 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `COMPOSE_DIR` | `/home/deploy/_work/biliboard-deploy/biliboard-deploy` | docker-compose 配置目录 |
| `COMPOSE_PROJECT_NAME` | `biliboard` | Docker Compose 项目名 |

示例：

```bash
COMPOSE_DIR=/opt/biliboard ./backup-manager.sh list
```

## 使用示例

```bash
# 查看帮助
./backup-manager.sh help

# 执行即时备份
./backup-manager.sh now

# 查看备份列表
./backup-manager.sh list

# 恢复到指定备份
./backup-manager.sh restore

# 下载备份到本地
./backup-manager.sh download

# 检查服务状态
./backup-manager.sh status
```

## 注意事项

1. **恢复操作不可逆**：虽然会创建预恢复备份，但仍需谨慎操作
2. **服务中断**：恢复过程中 backend 服务会短暂停止
3. **备份命名规则**：自动备份文件名格式为 `biliboard_YYYYMMDD_HHMMSS.db.gz`
4. **权限要求**：需要 Docker 执行权限
