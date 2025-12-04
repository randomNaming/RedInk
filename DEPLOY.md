# RedInk 一键部署指南

本指南说明如何使用自动化脚本部署 RedInk 应用，包括 SSL 证书配置和自动续期。

## 功能特性

- ✅ 自动检测并安装 Docker
- ✅ 交互式域名和邮箱配置
- ✅ 自动申请 Let's Encrypt SSL 证书
- ✅ 自动配置 Nginx 反向代理
- ✅ 自动设置证书续期任务

## 系统要求

- Linux 操作系统（Ubuntu/Debian/CentOS/RHEL/Fedora）
- Root 权限
- 域名已解析到服务器 IP
- 防火墙开放 80 和 443 端口

## 快速开始

### 1. 上传文件到服务器

将项目文件上传到服务器，确保包含：
- `docker-compose.yml`
- `deploy.sh`
- `nginx/` 目录及配置文件

### 2. 运行部署脚本

```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

### 3. 按提示输入信息

脚本会交互式询问：
- **域名**：默认 `xhs.snjyw.net`，可按 Enter 使用默认值或输入其他域名
- **邮箱**：用于 Let's Encrypt 证书到期通知
- **测试环境**：是否使用 Let's Encrypt 测试环境（建议首次测试时选择 yes）

### 4. 等待部署完成

脚本会自动：
1. 检查并安装 Docker（如需要）
2. 创建必要的目录结构
3. 启动 Nginx 服务（HTTP only）
4. 申请 SSL 证书
5. 配置 Nginx HTTPS
6. 启动所有服务
7. 设置证书自动续期

## 部署后操作

### 查看服务状态

```bash
docker compose ps
```

### 查看日志

```bash
# 查看所有服务日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f redink
docker compose logs -f nginx
```

### 重启服务

```bash
docker compose restart
```

### 停止服务

```bash
docker compose down
```

### 手动续期证书

```bash
./renew-cert.sh
```

## 目录结构

部署后会生成以下目录结构：

```
.
├── docker-compose.yml
├── deploy.sh
├── renew-cert.sh              # 证书续期脚本
├── nginx/
│   ├── nginx.conf            # Nginx 主配置
│   ├── conf.d/
│   │   └── default.conf      # 站点配置（自动生成）
│   ├── conf.d/
│   │   └── default.conf.template  # 配置模板
│   ├── ssl/                  # SSL 证书目录
│   │   └── live/
│   │       └── <域名>/
│   └── html/                 # Web 根目录（用于证书验证）
└── output/                   # 应用输出目录
```

## SSL 证书续期

证书会在以下情况自动续期：
- 证书剩余有效期少于 30 天
- 每天凌晨 3 点自动检查

续期日志保存在：`/var/log/certbot-renew.log`

### 测试证书续期

```bash
# 使用测试环境测试续期（不会影响现有证书）
docker run --rm \
    -v $(pwd)/nginx/ssl:/etc/letsencrypt \
    -v $(pwd)/nginx/html:/var/www/certbot \
    certbot/certbot renew \
    --webroot \
    --webroot-path=/var/www/certbot \
    --dry-run
```

## 故障排查

### 证书申请失败

**可能原因：**
1. 域名 DNS 未正确解析到服务器
2. 防火墙未开放 80/443 端口
3. 域名无法从外网访问

**解决方法：**
```bash
# 检查 DNS 解析
nslookup xhs.snjyw.net

# 检查端口开放
sudo netstat -tlnp | grep -E ':(80|443)'

# 检查防火墙
sudo ufw status
# 如需开放端口
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### Nginx 启动失败

```bash
# 检查 Nginx 配置语法
docker compose exec nginx nginx -t

# 查看 Nginx 错误日志
docker compose logs nginx
```

### 证书续期失败

```bash
# 手动运行续期脚本查看详细错误
./renew-cert.sh

# 检查证书状态
docker run --rm \
    -v $(pwd)/nginx/ssl:/etc/letsencrypt \
    certbot/certbot certificates
```

## 修改域名

如果需要修改域名：

1. 编辑 `docker-compose.yml` 和服务配置
2. 重新运行 `./deploy.sh`
3. 或手动更新配置文件和证书

## 安全建议

1. **定期更新**：定期更新 Docker 镜像
   ```bash
   docker compose pull
   docker compose up -d
   ```

2. **备份证书**：定期备份 SSL 证书目录
   ```bash
   tar -czf ssl-backup-$(date +%Y%m%d).tar.gz nginx/ssl/
   ```

3. **监控日志**：定期检查应用和证书续期日志

4. **防火墙配置**：只开放必要的端口（80, 443, 22）

## 支持的操作系统

- Ubuntu 18.04+
- Debian 10+
- CentOS 7+
- RHEL 7+
- Fedora 30+

## 注意事项

1. **首次部署**：建议使用 Let's Encrypt 测试环境进行首次部署，避免触发速率限制
2. **证书限制**：Let's Encrypt 对每个域名每周有证书申请次数限制（生产环境）
3. **DNS 配置**：确保域名已正确解析到服务器 IP，否则证书申请会失败
4. **端口冲突**：确保 80 和 443 端口未被其他服务占用

## 更多信息

- [Docker 文档](https://docs.docker.com/)
- [Let's Encrypt 文档](https://letsencrypt.org/docs/)
- [Nginx 文档](https://nginx.org/en/docs/)

## 常见问题


**Q: 如何查看证书到期时间？**

A: 运行以下命令：
```bash
docker run --rm -v $(pwd)/nginx/ssl:/etc/letsencrypt certbot/certbot certificates
```

