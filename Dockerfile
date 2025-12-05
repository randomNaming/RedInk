# ============================================
# 红墨 AI图文生成器 - Docker 镜像
# ============================================

# 阶段1: 构建前端
FROM node:22-slim AS frontend-builder

WORKDIR /app/frontend

# 安装 pnpm
RUN npm install -g pnpm

# 复制前端依赖文件
COPY frontend/package.json frontend/pnpm-lock.yaml ./

# 安装依赖
RUN pnpm install --frozen-lockfile

# 复制前端源码
COPY frontend/ ./

# 构建前端
RUN pnpm build

# ============================================
# 阶段2: 最终镜像
FROM python:3.11-slim

WORKDIR /app

# 使用国内镜像源加速（阿里云）
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources

# 配置 pip 使用清华大学镜像源
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

# 安装 uv（通过 pip，可使用镜像源）
RUN pip install --no-cache-dir uv

# 复制 Python 项目配置
COPY pyproject.toml uv.lock* ./

# 安装 Python 依赖
RUN uv sync --no-dev

# 复制后端代码
COPY backend/ ./backend/

# 复制空白配置文件模板（不包含任何 API Key）
COPY docker/text_providers.yaml ./
COPY docker/image_providers.yaml ./

# 从构建阶段复制前端产物
COPY --from=frontend-builder /app/frontend/dist ./frontend/dist

# 创建输出目录
RUN mkdir -p output

# 设置环境变量
ENV FLASK_DEBUG=False
ENV FLASK_HOST=0.0.0.0
ENV FLASK_PORT=12398

# 暴露端口
EXPOSE 12398

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:12398/api/health')" || exit 1

# 启动命令
CMD ["uv", "run", "python", "-m", "backend.app"]
