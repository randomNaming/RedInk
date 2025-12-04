#!/bin/bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
DOMAIN=""
EMAIL=""
STAGING=0  # 0=生产环境, 1=测试环境

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "请使用 sudo 运行此脚本"
        exit 1
    fi
}

# 检查并安装 Docker
check_and_install_docker() {
    print_info "检查 Docker 安装状态..."
    
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        print_success "Docker 已安装: $DOCKER_VERSION"
        return 0
    fi
    
    print_warning "未检测到 Docker，开始安装..."
    
    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "无法检测操作系统类型"
        exit 1
    fi
    
    print_info "检测到操作系统: $OS $VER"
    
    case $OS in
        ubuntu|debian)
            install_docker_debian
            ;;
        centos|rhel|fedora)
            install_docker_centos
            ;;
        *)
            print_error "不支持的操作系统: $OS"
            print_info "请手动安装 Docker: https://docs.docker.com/get-docker/"
            exit 1
            ;;
    esac
}

# 在 Debian/Ubuntu 上安装 Docker
install_docker_debian() {
    print_info "在 Debian/Ubuntu 上安装 Docker..."
    
    # 更新包索引
    apt-get update
    
    # 安装必要的依赖
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # 添加 Docker 官方 GPG 密钥
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${OS}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # 设置 Docker 仓库
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 安装 Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # 启动 Docker 服务
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker 安装完成"
}

# 在 CentOS/RHEL/Fedora 上安装 Docker
install_docker_centos() {
    print_info "在 CentOS/RHEL/Fedora 上安装 Docker..."
    
    # 安装必要的依赖
    yum install -y yum-utils
    
    # 添加 Docker 仓库
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # 安装 Docker Engine
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # 启动 Docker 服务
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker 安装完成"
}

# 检查并安装 Docker Compose
check_docker_compose() {
    print_info "检查 Docker Compose..."
    
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        print_success "Docker Compose 已安装: $COMPOSE_VERSION"
        return 0
    fi
    
    print_error "Docker Compose 未安装或不可用"
    exit 1
}

# 交互式输入域名和邮箱
get_domain_info() {
    print_info "=== 域名和邮箱配置 ==="
    
    # 读取域名
    read -p "请输入域名 [默认: xhs.snjyw.net]: " input_domain
    DOMAIN=${input_domain:-xhs.snjyw.net}
    
    print_success "域名设置为: $DOMAIN"
    
    # 读取邮箱
    read -p "请输入邮箱地址（用于 Let's Encrypt 通知）: " input_email
    EMAIL=${input_email}
    
    # 验证邮箱格式
    if [[ ! $EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "邮箱格式不正确: $EMAIL"
        exit 1
    fi
    
    print_success "邮箱设置为: $EMAIL"
    
    # 询问是否使用测试环境
    read -p "是否使用 Let's Encrypt 测试环境？(y/N): " use_staging
    if [[ $use_staging =~ ^[Yy]$ ]]; then
        STAGING=1
        print_warning "使用测试环境（证书不会受速率限制）"
    else
        STAGING=0
        print_info "使用生产环境"
    fi
}

# 创建必要的目录
create_directories() {
    print_info "创建必要的目录..."
    
    mkdir -p nginx/conf.d
    mkdir -p nginx/ssl
    mkdir -p nginx/html/.well-known/acme-challenge
    mkdir -p output
    
    # 确保验证目录权限正确
    chmod -R 755 nginx/html
    
    print_success "目录创建完成"
}

# 生成初始 nginx 配置（HTTP only）
generate_initial_nginx_config() {
    print_info "生成初始 Nginx 配置（HTTP only）..."
    
    cat > nginx/conf.d/default.conf <<EOF
# HTTP 服务器 - 用于证书验证
server {
    listen 80;
    server_name ${DOMAIN};

    # Let's Encrypt 验证目录
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 临时：等待证书申请完成后会配置 HTTPS 重定向
    location / {
        proxy_pass http://redink:12398;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    print_success "初始 Nginx 配置已生成"
}

# 申请 SSL 证书
request_ssl_certificate() {
    print_info "开始申请 SSL 证书..."
    
    # 启动 nginx（HTTP only）以进行验证
    print_info "启动 Nginx 服务以进行域名验证..."
    docker compose up -d nginx
    
    # 等待 nginx 启动
    sleep 5
    
    # 准备 certbot 命令
    CERTBOT_CMD="docker run --rm \
        -v $(pwd)/nginx/ssl:/etc/letsencrypt \
        -v $(pwd)/nginx/html:/var/www/certbot \
        certbot/certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email ${EMAIL} \
        --agree-tos \
        --no-eff-email \
        -d ${DOMAIN}"
    
    if [ $STAGING -eq 1 ]; then
        CERTBOT_CMD="${CERTBOT_CMD} --staging"
        print_info "使用测试环境申请证书..."
    else
        print_info "使用生产环境申请证书..."
    fi
    
    # 执行证书申请
    print_info "正在申请证书，请稍候..."
    if eval $CERTBOT_CMD; then
        print_success "SSL 证书申请成功！"
        return 0
    else
        print_error "SSL 证书申请失败"
        print_info "请检查："
        print_info "1. 域名 DNS 是否已正确解析到本服务器 IP"
        print_info "2. 防火墙是否开放了 80 和 443 端口"
        print_info "3. 域名是否可以正常访问"
        exit 1
    fi
}

# 生成完整的 nginx 配置（包含 HTTPS）
generate_ssl_nginx_config() {
    print_info "生成完整的 Nginx 配置（包含 HTTPS）..."
    
    # 检查证书是否存在
    if [ ! -f "nginx/ssl/live/${DOMAIN}/fullchain.pem" ]; then
        print_error "SSL 证书文件不存在，请先申请证书"
        exit 1
    fi
    
    # 使用模板生成配置
    sed "s/\${DOMAIN}/${DOMAIN}/g" nginx/conf.d/default.conf.template > nginx/conf.d/default.conf
    
    # 重载 nginx 配置
    print_info "重载 Nginx 配置..."
    docker compose exec -T nginx nginx -s reload || docker compose restart nginx
    
    print_success "Nginx SSL 配置已生成并应用"
}

# 设置证书自动续期
setup_cert_renewal() {
    print_info "设置证书自动续期..."
    
    # 创建续期脚本
    cat > renew-cert.sh <<EOFSCRIPT
#!/bin/bash
# SSL 证书续期脚本

cd "$(dirname "\$0")"

echo "[\$(date)] 开始续期 SSL 证书..."

docker run --rm \\
    -v \$(pwd)/nginx/ssl:/etc/letsencrypt \\
    -v \$(pwd)/nginx/html:/var/www/certbot \\
    certbot/certbot renew \\
    --webroot \\
    --webroot-path=/var/www/certbot

# 重载 nginx 配置
if docker compose ps | grep -q "redink-nginx.*Up"; then
    docker compose exec -T nginx nginx -s reload
    echo "[\$(date)] Nginx 配置已重载"
fi

echo "[\$(date)] 证书续期完成"
EOFSCRIPT
    
    chmod +x renew-cert.sh
    
    # 设置 cron 任务（每天凌晨 3 点检查续期）
    CRON_JOB="0 3 * * * cd $(pwd) && ./renew-cert.sh >> /var/log/certbot-renew.log 2>&1"
    
    # 检查是否已存在相同的 cron 任务
    (crontab -l 2>/dev/null | grep -v "renew-cert.sh"; echo "$CRON_JOB") | crontab -
    
    print_success "证书自动续期已设置（每天凌晨 3 点检查）"
}

# 启动所有服务
start_services() {
    print_info "启动所有服务..."
    
    docker compose up -d
    
    print_success "所有服务已启动"
    
    # 等待服务就绪
    print_info "等待服务就绪..."
    sleep 10
    
    # 检查服务状态
    docker compose ps
}

# 显示部署信息
show_deployment_info() {
    print_success "=== 部署完成 ==="
    echo ""
    print_info "域名: https://${DOMAIN}"
    print_info "HTTP: http://${DOMAIN} (自动重定向到 HTTPS)"
    echo ""
    print_info "服务状态:"
    docker compose ps
    echo ""
    print_info "查看日志:"
    echo "  docker compose logs -f"
    echo ""
    print_info "停止服务:"
    echo "  docker compose down"
    echo ""
    print_info "重启服务:"
    echo "  docker compose restart"
    echo ""
    print_info "手动续期证书:"
    echo "  ./renew-cert.sh"
}

# 主函数
main() {
    print_info "=== RedInk 一键部署脚本 ==="
    echo ""
    
    # 检查 root 权限
    check_root
    
    # 检查并安装 Docker
    check_and_install_docker
    
    # 检查 Docker Compose
    check_docker_compose
    
    # 获取域名和邮箱信息
    get_domain_info
    
    # 创建必要目录
    create_directories
    
    # 生成初始 nginx 配置
    generate_initial_nginx_config
    
    # 申请 SSL 证书
    request_ssl_certificate
    
    # 生成完整的 nginx 配置
    generate_ssl_nginx_config
    
    # 启动所有服务
    start_services
    
    # 设置证书自动续期
    setup_cert_renewal
    
    # 显示部署信息
    show_deployment_info
}

# 运行主函数
main
