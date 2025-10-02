#!/bin/sh
set -e

# 初始化为空
APIHOST=""
APIKEY=""
NODEID=""

# 解析参数
for arg in "$@"; do
    case $arg in
        --apiHost=*)
            APIHOST="${arg#*=}"
            shift
            ;;
        --apiKey=*)
            APIKEY="${arg#*=}"
            shift
            ;;
        --nodeID=*)
            NODEID="${arg#*=}"
            shift
            ;;
        *)
            echo "未知参数: $arg"
            echo "用法: $0 --apiHost=xxx --apiKey=yyy --nodeID=zzz"
            exit 1
            ;;
    esac
done

# 校验
if [ -z "$APIHOST" ] || [ -z "$APIKEY" ] || [ -z "$NODEID" ]; then
    echo "错误: 所有参数都不能为空"
    echo "用法: $0 --apiHost=xxx --apiKey=yyy --nodeID=zzz"
    exit 1
fi

echo "使用配置:"
echo "apiHost = ${APIHOST}"
echo "apiKey  = ${APIKEY}"
echo "nodeID  = ${NODEID}"

# 检测系统类型
if command -v systemctl >/dev/null 2>&1; then
    SYSTEM_TYPE="systemd"
elif command -v rc-service >/dev/null 2>&1; then
    SYSTEM_TYPE="openrc"
else
    echo "错误: 不支持的系统（未检测到 systemd 或 OpenRC）"
    exit 1
fi

echo "检测到系统类型: $SYSTEM_TYPE"

# 安装必要工具
if [ "$SYSTEM_TYPE" = "openrc" ]; then
    apk update
    apk add --no-cache wget tar curl
else
    # systemd 系统，区分 yum / apt
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y wget tar curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y wget tar curl
    else
        echo "错误: 未找到合适的包管理器 (apt-get 或 yum)"
        exit 1
    fi
fi

# 下载并解压
rm -f hysteria.tar.gz
rm -rf hysteria
wget -O hysteria.tar.gz https://github.com/qiuapeng921/hysteria/raw/refs/heads/master/hysteria.tar.gz
tar -xvf hysteria.tar.gz

# 确保目录存在，强制覆盖
mkdir -p /etc/hysteria
cp -f hysteria/server.crt /etc/hysteria/
cp -f hysteria/server.key /etc/hysteria/

# 移动二进制（覆盖）
cp -f hysteria/hysteria /usr/local/bin/
chmod +x /usr/local/bin/hysteria

# 写入配置文件（覆盖）
cat > /etc/hysteria/config.yaml <<EOF
v2board:
  apiHost: ${APIHOST}
  apiKey: ${APIKEY}
  nodeID: ${NODEID}
tls:
  type: tls
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: v2board
trafficStats:
  listen: 127.0.0.1:7653
acl:
  inline: 
    - reject(10.0.0.0/8)
    - reject(172.16.0.0/12)
    - reject(192.168.0.0/16)
    - reject(127.0.0.0/8)
    - reject(fc00::/7)
masquerade:
  type: proxy
  proxy:
    url: https://herobrave.top/
    rewriteHost: true    
EOF

# 根据系统类型配置服务
if [ "$SYSTEM_TYPE" = "systemd" ]; then
    # 写入 systemd 服务（覆盖）
    cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria -c /etc/hysteria/config.yaml server
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd 并启动
    systemctl daemon-reload
    systemctl enable hysteria
    systemctl restart hysteria
else
    # 写入 OpenRC 服务文件（覆盖）
    cat > /etc/init.d/hysteria <<EOF
#!/sbin/openrc-run

name="hysteria"
description="Hysteria2 Server"
command="/usr/local/bin/hysteria"
command_args="-c /etc/hysteria/config.yaml server"
pidfile="/var/run/hysteria.pid"
command_background="yes"

depend() {
    need net
}

EOF

    # 设置服务文件权限并启用
    chmod +x /etc/init.d/hysteria
    rc-update add hysteria default
    rc-service hysteria restart
fi

# 清理临时文件
rm -rf hysteria*

echo "Hysteria2 安装完成并已启动"
