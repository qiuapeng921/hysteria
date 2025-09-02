#!/bin/bash
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


# 下载并解压
rm -f hysteria.tar.gz
rm -rf hysteria
wget -O hysteria.tar.gz http://epay.phpher.top/hysteria.tar.gz
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
EOF

# 写 systemd 服务（覆盖）
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

rm -rf hysteria*

echo "Hysteria2 安装完成并已启动"