#!/bin/bash

# 启用严格模式
set -euo pipefail
IFS=$'\n\t'

# 获取脚本所在目录的绝对路径
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# 配置日志记录（存放到脚本目录）
LOG_FILE="$SCRIPT_DIR/cert_update.log"
touch "$LOG_FILE" || {
    echo "错误: 无法创建日志文件 $LOG_FILE"
    exit 1
}
exec > >(tee -a "$LOG_FILE") 2>&1
echo -e "\n====== 证书更新开始 $(date) ======"

# 检查执行权限
if [ ! -x "$0" ]; then
    echo "错误: 脚本没有执行权限"
    echo "请执行: chmod +x $0"
    exit 1
fi

# 检查必要命令
REQUIRED_CMDS=("systemctl" "journalctl" "openssl" "readlink" "mkdir" "cat" "chmod" "find")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "错误: 缺少必要命令 $cmd"
        exit 1
    fi
done

# 读取配置文件
CONFIG_FILE="$SCRIPT_DIR/config"
if [ -f "$CONFIG_FILE" ]; then
    if ! . "$CONFIG_FILE"; then
        echo "错误: 配置文件加载失败"
        exit 1
    fi
else
    echo "错误: 配置文件不存在: $CONFIG_FILE"
    exit 1
fi

# 验证DOMAIN变量
if [ -z "${DOMAIN:-}" ]; then
    echo "错误: 配置文件中缺少 DOMAIN 变量"
    exit 1
fi

# 定义证书路径
CERT_DIR="$SCRIPT_DIR/acme.sh/$DOMAIN"
KEY_PATH="$CERT_DIR/$DOMAIN.key"
CER_PATH="$CERT_DIR/$DOMAIN.cer"
CA_PATH="$CERT_DIR/ca.cer"

# 验证证书文件
check_cert_file() {
    local file_path=$1
    local file_type=$2
    
    if [ ! -f "$file_path" ]; then
        echo "错误: $file_type 文件不存在: $file_path"
        exit 1
    fi

    case $file_type in
        "私钥")
            if ! openssl rsa -in "$file_path" -check -noout 2>/dev/null; then
                echo "错误: 私钥文件无效"
                exit 1
            fi
            ;;
        "证书")
            if ! openssl x509 -in "$file_path" -noout 2>/dev/null; then
                echo "错误: 证书文件无效"
                exit 1
            fi
            ;;
        "CA证书")
            if ! openssl x509 -in "$file_path" -noout 2>/dev/null; then
                echo "警告: CA证书验证失败，但将继续处理"
            fi
            ;;
    esac
}

echo "正在验证证书文件..."
check_cert_file "$KEY_PATH" "私钥"
check_cert_file "$CER_PATH" "证书"
check_cert_file "$CA_PATH" "CA证书"

# 证书安装目标路径
TARGET_PARENT_DIR="/usr/trim/var/trim_connect/ssls/$DOMAIN"

# 检查是否是初次安装（检查目标目录下是否有子文件夹）
echo "正在检查证书目录..."
if [ ! -d "$TARGET_PARENT_DIR" ] || [ -z "$(find "$TARGET_PARENT_DIR" -mindepth 1 -maxdepth 1 -type d)" ]; then
    echo "错误: 初次安装证书，请手动导入"
    echo "提示: 请先在设备管理界面手动导入证书一次"
    exit 1
fi

# 获取第一个子目录名（通常只有一个）
TARGET_SUBDIR=$(find "$TARGET_PARENT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
TARGET_DIR="$TARGET_SUBDIR"

if [ -z "$TARGET_DIR" ]; then
    echo "错误: 无法获取证书子目录名"
    echo "调试信息: 目录内容: $(ls -la "$TARGET_PARENT_DIR" 2>/dev/null || true)"
    exit 1
fi

echo "检测到证书目录: $TARGET_DIR"

# 创建备份目录
BACKUP_DIR="$SCRIPT_DIR/backup"
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR" || {
        echo "错误: 无法创建备份目录 $BACKUP_DIR"
        exit 1
    }
fi

# 备份现有证书
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BACKUP_NAME="${DOMAIN}_${TIMESTAMP}"
echo "正在备份现有证书到: $BACKUP_DIR/$BACKUP_NAME"
if ! cp -r "$TARGET_PARENT_DIR" "$BACKUP_DIR/$BACKUP_NAME"; then
    echo "错误: 证书备份失败"
    exit 1
fi

# 证书文件复制和重命名操作
echo "开始部署证书文件..."

# 1. 复制并重命名CA证书
echo "- 处理CA证书..."
cp -f "$CA_PATH" "$TARGET_DIR/issuer_certificate.crt"

# 2. 复制私钥文件
echo "- 处理私钥文件..."
cp -f "$KEY_PATH" "$TARGET_DIR/$DOMAIN.key"

# 3. 复制证书文件
echo "- 处理证书文件..."
cp -f "$CER_PATH" "$TARGET_DIR/$DOMAIN.crt"

# 4. 合并证书链
echo "- 创建fullchain证书..."
cat "$CER_PATH" "$CA_PATH" > "$TARGET_DIR/fullchain.crt"

# 设置文件权限
echo "设置文件权限..."
chmod 600 "$TARGET_DIR/$DOMAIN.key"
chmod 644 "$TARGET_DIR/$DOMAIN.crt"
chmod 644 "$TARGET_DIR/issuer_certificate.crt"
chmod 644 "$TARGET_DIR/fullchain.crt"

# 验证部署结果
echo "验证部署结果..."
for file in "$TARGET_DIR/$DOMAIN.key" "$TARGET_DIR/$DOMAIN.crt" \
            "$TARGET_DIR/issuer_certificate.crt" "$TARGET_DIR/fullchain.crt"; do
    if [ ! -f "$file" ]; then
        echo "错误: 文件未正确创建: $file"
        exit 1
    fi
done

echo -e "\n证书部署成功!"
echo "文件位置: $TARGET_DIR"
ls -l "$TARGET_DIR"

# 服务重启部分
echo -e "\n开始重启相关服务..."

SERVICES=("webdav.service" "smbftpd.service" "trim_nginx.service")
FAILED_SERVICES=()

for SERVICE in "${SERVICES[@]}"; do
    echo -n "处理 $SERVICE ... "
    
    # 检查服务状态
    if ! systemctl is-enabled "$SERVICE" >/dev/null 2>&1; then
        echo "[跳过] 服务未启用"
        continue
    fi
    
    # 执行重启
    if systemctl restart "$SERVICE"; then
        STATUS=$(systemctl is-active "$SERVICE")
        echo "[成功] 状态: $STATUS"
    else
        ERROR_CODE=$?
        echo "[失败] 错误码: $ERROR_CODE"
        FAILED_SERVICES+=("$SERVICE")
        
        # 获取日志
        echo "最后10条日志:"
        journalctl -u "$SERVICE" -n 10 --no-pager 2>/dev/null || true
    fi
done

# 处理失败的服务
if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo -e "\n警告: 以下服务重启失败: ${FAILED_SERVICES[*]}"
    echo "可能需要手动检查"
fi

echo -e "\n所有操作完成! 详细日志已记录到: $LOG_FILE"
echo "备份目录: $BACKUP_DIR/$BACKUP_NAME"
echo "如需查看日志，请执行: cat $LOG_FILE"
exit ${#FAILED_SERVICES[@]}
