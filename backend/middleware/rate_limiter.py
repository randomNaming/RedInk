"""IP访问速率限制中间件"""
import json
import logging
import os
from datetime import datetime, timedelta
from functools import wraps
from pathlib import Path
from flask import request, jsonify

logger = logging.getLogger(__name__)

# ==================== 配置参数（写死在代码中） ====================
DAILY_LIMIT = 2  # 每天最多使用次数
RATE_LIMIT_FILE = "ip_rate_limit.json"  # 存储IP访问记录的文件


class IPRateLimiter:
    """IP访问速率限制器"""
    
    def __init__(self, daily_limit=DAILY_LIMIT):
        """
        初始化IP限制器
        
        Args:
            daily_limit: 每天允许的最大访问次数
        """
        self.daily_limit = daily_limit
        self.data_file = self._get_data_file_path()
        self._ensure_data_file()
    
    def _get_data_file_path(self):
        """获取数据文件路径"""
        # 将数据文件保存在项目根目录
        backend_dir = Path(__file__).parent.parent.parent
        return backend_dir / RATE_LIMIT_FILE
    
    def _ensure_data_file(self):
        """确保数据文件存在"""
        if not self.data_file.exists():
            self._save_data({})
    
    def _load_data(self):
        """加载IP访问记录"""
        try:
            if self.data_file.exists():
                with open(self.data_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            return {}
        except Exception as e:
            logger.error(f"加载IP限制数据失败: {e}")
            return {}
    
    def _save_data(self, data):
        """保存IP访问记录"""
        try:
            with open(self.data_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.error(f"保存IP限制数据失败: {e}")
    
    def _get_client_ip(self):
        """
        获取客户端真实IP地址
        考虑反向代理的情况（如Nginx）
        """
        # 优先从 X-Forwarded-For 获取（适配 Nginx、CDN 等反向代理）
        if request.headers.get('X-Forwarded-For'):
            # X-Forwarded-For 可能包含多个IP，取第一个
            ip = request.headers.get('X-Forwarded-For').split(',')[0].strip()
        # 其次从 X-Real-IP 获取
        elif request.headers.get('X-Real-IP'):
            ip = request.headers.get('X-Real-IP')
        # 最后使用 remote_addr
        else:
            ip = request.remote_addr
        
        return ip
    
    def _get_today_key(self):
        """获取今天的日期键（格式：YYYY-MM-DD）"""
        return datetime.now().strftime('%Y-%m-%d')
    
    def _clean_old_records(self, data):
        """清理过期的记录（保留最近7天的数据）"""
        today = datetime.now()
        cutoff_date = (today - timedelta(days=7)).strftime('%Y-%m-%d')
        
        cleaned = {}
        for ip, records in data.items():
            # 过滤掉7天前的记录
            cleaned_records = {
                date: count for date, count in records.items()
                if date >= cutoff_date
            }
            if cleaned_records:
                cleaned[ip] = cleaned_records
        
        return cleaned
    
    def check_rate_limit(self, ip=None):
        """
        检查IP是否超过访问限制
        
        Args:
            ip: IP地址（如果不提供则自动获取）
        
        Returns:
            tuple: (是否允许访问, 剩余次数, 错误消息)
        """
        if ip is None:
            ip = self._get_client_ip()
        
        today = self._get_today_key()
        
        # 加载数据
        data = self._load_data()
        
        # 清理旧记录并保存
        data = self._clean_old_records(data)
        self._save_data(data)  # 保存清理后的数据
        
        # 获取该IP今天的访问次数
        ip_records = data.get(ip, {})
        today_count = ip_records.get(today, 0)
        
        # 检查是否超限
        if today_count >= self.daily_limit:
            logger.warning(f"IP {ip} 今天已达到访问上限 {self.daily_limit} 次")
            return False, 0, f"您今天的使用次数已达上限（{self.daily_limit}次/天），请明天再来！"
        
        # 未超限，返回剩余次数
        remaining = self.daily_limit - today_count
        return True, remaining, None
    
    def record_access(self, ip=None):
        """
        记录一次访问
        
        Args:
            ip: IP地址（如果不提供则自动获取）
        """
        if ip is None:
            ip = self._get_client_ip()
        
        today = self._get_today_key()
        
        # 加载数据
        data = self._load_data()
        
        # 清理旧记录
        data = self._clean_old_records(data)
        
        # 记录访问
        if ip not in data:
            data[ip] = {}
        
        data[ip][today] = data[ip].get(today, 0) + 1
        
        # 保存数据
        self._save_data(data)
        
        # 记录日志
        remaining = self.daily_limit - data[ip][today]
        logger.info(f"记录IP访问: {ip}, 今日已使用 {data[ip][today]} 次, 剩余 {remaining} 次")


# 全局限制器实例
_rate_limiter = IPRateLimiter()


def ip_rate_limit(f):
    """
    IP访问速率限制装饰器
    
    用法:
        @api_bp.route('/outline', methods=['POST'])
        @ip_rate_limit
        def generate_outline():
            ...
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # 检查是否超限
        allowed, remaining, error_msg = _rate_limiter.check_rate_limit()
        
        if not allowed:
            # 超过限制，返回错误
            return jsonify({
                "success": False,
                "error": error_msg,
                "rate_limit": {
                    "daily_limit": DAILY_LIMIT,
                    "remaining": 0
                }
            }), 429  # 429 Too Many Requests
        
        # 记录这次访问
        _rate_limiter.record_access()
        
        # 继续处理请求
        response = f(*args, **kwargs)
        
        # 在响应头中添加速率限制信息（可选）
        if hasattr(response, 'headers'):
            response.headers['X-RateLimit-Limit'] = str(DAILY_LIMIT)
            response.headers['X-RateLimit-Remaining'] = str(remaining - 1)  # 减1因为已经使用了一次
        
        return response
    
    return decorated_function

