from flask import Flask, request, jsonify
import json

app = Flask(__name__)

# 全局变量存储服务函数
services = {}

def register_service(route, service_func, methods=['GET']):
    """注册服务函数到Flask路由"""
    services[route] = service_func
    
    # 为每个路由生成唯一的函数名
    route_name = route.replace('/', '_').replace('-', '_').lstrip('_')
    function_name = f"dynamic_route_{route_name}"
    
    # 创建动态函数
    def route_handler():
        try:
            if request.method == 'GET':
                # GET请求处理
                return service_func(request.args)
            elif request.method == 'POST':
                # POST请求处理
                data = request.get_json()
                if not data:
                    return jsonify({"error": "请求体必须包含JSON数据"}), 400
                return service_func(data)
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    
    # 设置函数名称
    route_handler.__name__ = function_name
    
    # 注册路由
    app.route(route, methods=methods)(route_handler)

def start_server(host='0.0.0.0', port=5001, debug=True):
    """启动HTTP服务器"""
    print("启动API服务器...")
    print("已注册的服务:")
    for route in services.keys():
        print(f"  {route}")
    print(f"服务器将在 http://{host}:{port} 启动")
    
    app.run(host=host, port=port, debug=debug)

if __name__ == '__main__':
    print("HTTP服务器框架 - 请使用 main_server.py 启动服务器")
    print("或者先注册服务再运行此文件")
    if services:
        start_server()
    else:
        print("当前没有注册任何服务")
