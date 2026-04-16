#!/bin/bash

# download-k8s-srpm.sh - 下载Kubernetes SRPM包脚本
# 用法: ./download-k8s-srpm.sh <全量版本号>
# 示例: ./download-k8s-srpm.sh v1.33.2
# 输出: 返回 cri-tools 和 kubernetes-cni 的版本号，格式为 "CRI_VERSION CNI_VERSION"

set -e

# 颜色输出（所有日志输出到stderr，不影响返回值）
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# ==================== 下载函数（带重试机制）====================
download_with_retry() {
    local file_url="$1"
    local output_file="$2"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if [ $retry_count -gt 0 ]; then
            log_warning "  第 $retry_count 次重试下载: $(basename "$output_file")"
        fi
        
        if curl -L -# -f --retry 1 --retry-delay 2 --connect-timeout 30 --max-time 600 -o "$output_file" "$file_url"; then
            if [ -s "$output_file" ]; then
                if file "$output_file" | grep -q "RPM"; then
                    log_success "  下载成功，文件格式验证通过"
                    return 0
                else
                    log_warning "  文件格式验证失败，可能是不完整的下载"
                    rm -f "$output_file"
                fi
            else
                log_warning "  下载的文件为空，删除"
                rm -f "$output_file"
            fi
        else
            local curl_exit_code=$?
            log_warning "  curl下载失败，退出码: $curl_exit_code"
            
            case $curl_exit_code in
                35) log_warning "    错误 35: SSL/TLS连接失败（连接被对方重设）" ;;
                56) log_warning "    错误 56: 接收网络数据失败" ;;
                18) log_warning "    错误 18: 文件传输不完整" ;;
                *) log_warning "    未知错误，请参考curl文档" ;;
            esac
            
            rm -f "$output_file"
        fi
        
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -lt $max_retries ]; then
            local wait_time=$((retry_count * 3))
            log_info "  等待 ${wait_time} 秒后重试..."
            sleep $wait_time
        fi
    done
    
    log_error "  下载失败，已重试 ${max_retries} 次: $(basename "$output_file")"
    return 1
}

# ==================== 主函数 ====================
main() {
    log_info "=== Kubernetes SRPM包下载脚本启动 ==="
    
    # 1. 参数检查
    [ $# -eq 1 ] || log_error "请提供全量版本号参数\n用法: $0 <全量版本号>\n例如: $0 v1.33.2"
    FULL_VERSION_ARG="$1"
    [[ "$FULL_VERSION_ARG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || log_error "版本号格式错误，应为类似 'v1.33.2' 的格式"
    
    # 2. 从全量版本号中提取主版本号 (例如从 v1.33.2 提取 v1.33)
    MAIN_VERSION=$(echo "$FULL_VERSION_ARG" | grep -oE '^v[0-9]+\.[0-9]+')
    log_info "输入的全量版本号: $FULL_VERSION_ARG"
    log_info "提取的主版本号: $MAIN_VERSION"
    
    # 3. 定义常量
    BASE_URL="https://download.opensuse.org/repositories/isv:/kubernetes:/core:/stable:/${MAIN_VERSION}/rpm/src/"
    
    # 定义两类包的处理方式
    LATEST_PACKAGES=("cri-tools" "kubernetes-cni")      # 只下载最新版本的包
    SPECIFIC_VERSION_PACKAGES=("kubeadm" "kubectl" "kubelet") # 下载指定全量版本的包
    
    LOCAL_DIR="$HOME/k8s-Factory/srpms-origin"
    
    log_info "下载源: $BASE_URL"
    log_info "本地目录: $LOCAL_DIR"
    log_info "只下载最新版本的包: ${LATEST_PACKAGES[*]}"
    log_info "下载指定版本 ($FULL_VERSION_ARG) 的包: ${SPECIFIC_VERSION_PACKAGES[*]}"
    
    # 4. 清空本地目录
    log_info "清空本地目录: $LOCAL_DIR"
    if [ -d "$LOCAL_DIR" ]; then
        rm -rf "${LOCAL_DIR:?}"/*
        log_success "本地目录已清空"
    fi
    mkdir -p "$LOCAL_DIR"
    
    # 5. 获取远程文件列表
    log_info "获取远程仓库文件列表..."
    REMOTE_HTML=$(curl -s -L -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" "$BASE_URL")
    [ -n "$REMOTE_HTML" ] || log_error "无法获取远程仓库内容，请检查: $BASE_URL"
    
    REMOTE_FILES=$(echo "$REMOTE_HTML" | grep -oE 'href="[^"]+\.src\.rpm"' | sed 's/href="//;s/"$//' | sed 's|^\./||' | sort -V)
    [ -n "$REMOTE_FILES" ] || log_error "未找到任何.src.rpm文件，请检查仓库是否可访问"
    
    TOTAL_FILES=$(echo "$REMOTE_FILES" | wc -l)
    log_info "远程仓库中找到 $TOTAL_FILES 个SRPM包"
    
    # 6. 初始化变量
    DOWNLOADED=()
    CRI_VERSION=""; CNI_VERSION=""
    
    # 提取全量版本号中的数字部分（用于精确匹配）
    FULL_VERSION_NUM=$(echo "$FULL_VERSION_ARG" | sed 's/^v//')
    log_info "用于精确匹配的版本号: $FULL_VERSION_NUM"
    
    # ========== 7.1 处理只下载最新版本的包 (cri-tools, kubernetes-cni) ==========
    log_info "=== 处理只下载最新版本的包 ==="
    for pkg in "${LATEST_PACKAGES[@]}"; do
        log_info "处理包: $pkg (只下载最新版本)"
        
        PKG_FILES=$(echo "$REMOTE_FILES" | grep -E "^${pkg}-[0-9]+\.[0-9]+" || true)
        if [ -z "$PKG_FILES" ]; then
            log_warning "  包 $pkg 在远程仓库中未找到"
            continue
        fi
        
        LATEST_FILE=$(echo "$PKG_FILES" | sort -V | tail -1)
        log_info "  最新版本: $LATEST_FILE"
        
        FULL_VERSION=$(echo "$LATEST_FILE" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
        log_info "  全量版本: $FULL_VERSION"
        
        if [ "$pkg" = "cri-tools" ]; then
            CRI_VERSION="$FULL_VERSION"
            log_info "  记录 cri-tools 版本: $CRI_VERSION"
        elif [ "$pkg" = "kubernetes-cni" ]; then
            CNI_VERSION="$FULL_VERSION"
            log_info "  记录 kubernetes-cni 版本: $CNI_VERSION"
        fi
        
        log_info "  开始下载: $LATEST_FILE"
        if download_with_retry "${BASE_URL}${LATEST_FILE}" "$LOCAL_DIR/$LATEST_FILE"; then
            DOWNLOADED+=("$LATEST_FILE")
        fi
    done
    
    # ========== 7.2 处理下载指定全量版本的包 (kubeadm, kubectl, kubelet) ==========
    log_info "=== 处理下载指定全量版本的包 ==="
    for pkg in "${SPECIFIC_VERSION_PACKAGES[@]}"; do
        log_info "处理包: $pkg (下载版本 $FULL_VERSION_NUM)"
        
        # 精确匹配指定版本的包
        # 匹配模式: pkg-全量版本号-其他部分.src.rpm
        # 例如: kubeadm-1.33.2-150500.1.1.src.rpm
        TARGET_FILE=$(echo "$REMOTE_FILES" | grep -E "^${pkg}-${FULL_VERSION_NUM}-[0-9]+.*\.src\.rpm$" | head -1)
        
        if [ -z "$TARGET_FILE" ]; then
            log_warning "  警告: 包 $pkg 的版本 $FULL_VERSION_NUM 在远程仓库中未找到"
            log_warning "  尝试模糊匹配..."
            
            # 模糊匹配：如果精确匹配失败，尝试匹配以该版本开头的包
            TARGET_FILE=$(echo "$REMOTE_FILES" | grep -E "^${pkg}-${FULL_VERSION_NUM}" | head -1)
            
            if [ -z "$TARGET_FILE" ]; then
                log_warning "  模糊匹配也失败，跳过包 $pkg"
                continue
            else
                log_info "  模糊匹配找到: $TARGET_FILE"
            fi
        else
            log_info "  精确匹配找到: $TARGET_FILE"
        fi
        
        log_info "  开始下载: $TARGET_FILE"
        if download_with_retry "${BASE_URL}${TARGET_FILE}" "$LOCAL_DIR/$TARGET_FILE"; then
            DOWNLOADED+=("$TARGET_FILE")
        fi
    done
    
    # 8. 显示下载摘要
    log_success "=========================================="
    log_success "下载任务完成"
    log_success "=========================================="
    
    if [ ${#DOWNLOADED[@]} -gt 0 ]; then
        log_info "下载的包清单 (共 ${#DOWNLOADED[@]} 个):"
        printf '  - %s\n' "${DOWNLOADED[@]}" >&2
    fi
    
    log_success "所有SRPM包已保存在: $LOCAL_DIR" >&2
    
    # 9. 检查版本号完整性并返回结果
    if [ -z "$CRI_VERSION" ] || [ -z "$CNI_VERSION" ]; then
        log_warning "警告: 未能完整获取 cri-tools 和 kubernetes-cni 的版本号"
        echo "${CRI_VERSION:-unknown} ${CNI_VERSION:-unknown}"
    else
        echo "$CRI_VERSION $CNI_VERSION"
    fi
}

# ==================== 脚本入口 ====================
trap 'log_error "脚本被中断"' INT TERM
main "$@"
exit 0
