#!/bin/bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
IMAGE_NAME="histonemax/redink"
IMAGE_TAG="latest"
CONTAINER_NAME="redink"
PORT="12398"

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

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    print_success "Docker 已安装: $(docker --version)"
}

# 检查 Docker Compose 是否可用
check_docker_compose() {
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose 不可用"
        exit 1
    fi
    print_success "Docker Compose 可用"
}

# 停止并删除旧容器
cleanup_old_container() {
    print_info "检查并清理旧容器..."
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_warning "发现旧容器 ${CONTAINER_NAME}，正在停止并删除..."
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME} 2>/dev/null || true
        print_success "旧容器已清理"
    else
        print_info "未发现旧容器"
    fi
}

# 构建 Docker 镜像
build_image() {
    print_info "开始构建 Docker 镜像: ${IMAGE_NAME}:${IMAGE_TAG}"
    
    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
    
    if [ $? -eq 0 ]; then
        print_success "镜像构建成功: ${IMAGE_NAME}:${IMAGE_TAG}"
    else
        print_error "镜像构建失败"
        exit 1
    fi
}

# 创建输出目录
create_output_dir() {
    if [ ! -d "output" ]; then
        print_info "创建输出目录..."
        mkdir -p output
        print_success "输出目录已创建"
    fi
}

# 启动容器
start_container() {
    print_info "启动容器 ${CONTAINER_NAME}..."
    
    # 使用 docker-compose 只启动 redink 服务
    docker compose up -d redink
    
    if [ $? -eq 0 ]; then
        print_success "容器启动成功"
    else
        print_error "容器启动失败"
        exit 1
    fi
}

# 检查容器状态
check_container_status() {
    print_info "检查容器状态..."
    sleep 3
    
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_success "容器运行中"
        echo ""
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        print_error "容器未运行，请检查日志: docker logs ${CONTAINER_NAME}"
        exit 1
    fi
}

# 显示部署信息
show_deployment_info() {
    echo ""
    print_success "=== 部署完成 ==="
    echo ""
    print_info "容器名称: ${CONTAINER_NAME}"
    print_info "镜像: ${IMAGE_NAME}:${IMAGE_TAG}"
    print_info "端口映射: ${PORT}:${PORT}"
    print_info "本地访问: http://localhost:${PORT}"
    echo ""
    print_info "宝塔 Nginx 反向代理配置:"
    echo "  location /mozi {"
    echo "      proxy_pass http://127.0.0.1:${PORT};"
    echo "      proxy_set_header Host \$host;"
    echo "      proxy_set_header X-Real-IP \$remote_addr;"
    echo "      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
    echo "      proxy_set_header X-Forwarded-Proto \$scheme;"
    echo "      rewrite ^/mozi(.*)\$ \$1 break;"
    echo "  }"
    echo ""
    print_info "常用命令:"
    echo "  查看日志: docker logs -f ${CONTAINER_NAME}"
    echo "  停止容器: docker stop ${CONTAINER_NAME}"
    echo "  重启容器: docker restart ${CONTAINER_NAME}"
    echo "  删除容器: docker rm -f ${CONTAINER_NAME}"
    echo ""
}

# 主函数
main() {
    print_info "=== RedInk 一键构建和启动脚本 ==="
    echo ""
    
    # 检查 Docker
    check_docker
    check_docker_compose
    
    # 清理旧容器
    cleanup_old_container
    
    # 构建镜像
    build_image
    
    # 创建输出目录
    create_output_dir
    
    # 启动容器
    start_container
    
    # 检查状态
    check_container_status
    
    # 显示信息
    show_deployment_info
}

# 运行主函数
main

