#!/bin/bash

# env.sh - Kubernetes 工厂环境设置和验证脚本
# 功能：检查目录结构、验证依赖软件包、设置 Go 编译环境
# 注意：由 main.sh 调用，确保只执行一次，用于自动化流水线

set -e

# 颜色输出定义 - 与其他脚本保持一致
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'

# 日志函数 - 与其他脚本完全一致
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_header() { echo -e "${PURPLE}========================================${NC}"; echo -e "${PURPLE}  $1${NC}"; echo -e "${PURPLE}========================================${NC}"; }

# 基础目录
BASE_DIR="$HOME/k8s-Factory"
SRPM_DIR="$BASE_DIR/srpms-origin"
PRODUCTS_DIR="$BASE_DIR/Products"
RPM_DIR="$PRODUCTS_DIR/k8s-rpm"
SRPM_BUILD_DIR="$PRODUCTS_DIR/k8s-srpm"
SOURCES_DIR="$BASE_DIR/sources"

# Git 仓库 URL
CRI_TOOLS_REPO="https://github.com/kubernetes-sigs/cri-tools.git"
KUBERNETES_REPO="https://github.com/kubernetes/kubernetes.git"
PLUGINS_REPO="https://github.com/containernetworking/plugins.git"

# Go 版本配置 - 修改为 loong64 版本
GO_VERSION="1.26.1"
GO_TAR="go${GO_VERSION}.linux-loong64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TAR}"
GO_INSTALL_DIR="$HOME"
GO_ROOT_DIR="$HOME/go${GO_VERSION}"

# 需要的软件包列表 (基于 RHEL/CentOS/Fedora)
REQUIRED_PACKAGES=(
    "git"
    "make"
    "gcc"
    "gcc-c++"
    "rpm-build"
    "rpmlint"
    "rpmdevtools"
    "createrepo_c"
    "wget"
    "tar"
    "rsync"
    "which"
    "bash-completion"
)

# 标记文件路径
ENV_FLAG_FILE="$BASE_DIR/.env_setup_completed"

# 函数：检查环境是否已设置且在有效期内
check_env_status() {
    log_info "检查环境初始化状态"
    
    # 标记文件有效期（15天）
    local max_age_days=15
    local max_age_seconds=$((max_age_days * 24 * 60 * 60))
    
    # 检查标记文件是否存在且是否在有效期内
    if [ -f "$ENV_FLAG_FILE" ]; then
        # 获取文件修改时间
        local file_time=$(stat -c %Y "$ENV_FLAG_FILE")
        local current_time=$(date +%s)
        local age=$((current_time - file_time))
        
        if [ $age -lt $max_age_seconds ]; then
            local days_left=$(( (max_age_seconds - age) / 86400 ))
            local hours_left=$(( ((max_age_seconds - age) % 86400) / 3600 ))
            log_success "环境初始化有效（上次执行: $(date -d @$file_time '+%Y-%m-%d %H:%M:%S')，剩余有效期: ${days_left}天${hours_left}小时）"
            return 0
        else
            log_warning "环境初始化已超过 ${max_age_days} 天有效期（上次执行: $(date -d @$file_time '+%Y-%m-%d %H:%M:%S')），需要重新执行"
            rm -f "$ENV_FLAG_FILE"
            return 1
        fi
    fi
    
    log_info "首次运行，需要执行环境初始化"
    return 1
}

# 函数：检查并创建目录
check_and_create_dir() {
    local dir=$1
    local description=$2
    
    if [ ! -d "$dir" ]; then
        log_info "创建目录: $description ($dir)"
        mkdir -p "$dir"
        if [ $? -eq 0 ]; then
            log_success "目录创建成功: $dir"
        else
            log_error "无法创建目录: $dir"
        fi
    else
        log_success "目录已存在: $dir"
    fi
}

# 函数：检查目录结构
check_directory_structure() {
    log_info "检查目录结构..."
    
    check_and_create_dir "$BASE_DIR" "Kubernetes 工厂基础目录"
    check_and_create_dir "$SRPM_DIR" "上游 SRPM 包目录"
    check_and_create_dir "$PRODUCTS_DIR" "构建产品目录"
    check_and_create_dir "$RPM_DIR" "构建后的 RPM 包目录"
    check_and_create_dir "$SRPM_BUILD_DIR" "构建后的 SRPM 包目录"
    check_and_create_dir "$SOURCES_DIR" "源码二进制编译目录"
    
    # 检查 Bin 目录下的子项目
    log_info "检查源码目录下的项目..."
    
    # 检查 cri-tools
    if [ ! -d "$SOURCES_DIR/cri-tools" ]; then
        log_info "cri-tools 项目不存在，开始下载..."
        git clone "$CRI_TOOLS_REPO" "$SOURCES_DIR/cri-tools"
        if [ $? -eq 0 ]; then
            log_success "cri-tools 下载完成"
        else
            log_error "cri-tools 下载失败"
        fi
    else
        log_success "cri-tools 项目已存在"
    fi
    
    # 检查 kubernetes
    if [ ! -d "$SOURCES_DIR/kubernetes" ]; then
        log_info "kubernetes 项目不存在，开始下载..."
        git clone "$KUBERNETES_REPO" "$SOURCES_DIR/kubernetes"
        if [ $? -eq 0 ]; then
            log_success "kubernetes 下载完成"
        else
            log_error "kubernetes 下载失败"
        fi
    else
        log_success "kubernetes 项目已存在"
    fi
    
    # 检查 plugins
    if [ ! -d "$SOURCES_DIR/plugins" ]; then
        log_info "containernetworking/plugins 项目不存在，开始下载..."
        git clone "$PLUGINS_REPO" "$SOURCES_DIR/plugins"
        if [ $? -eq 0 ]; then
            log_success "plugins 下载完成"
        else
            log_error "plugins 下载失败"
        fi
    else
        log_success "plugins 项目已存在"
    fi
}

# 函数：检查软件包是否已安装
check_packages() {
    log_info "检查所需软件包..."
    
    local missing_packages=()
    
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
	if rpm -q "$pkg" &> /dev/null; then
            log_success "已安装: $pkg"
        else
            missing_packages+=("$pkg")
            log_warning "未安装: $pkg"
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log_warning "以下软件包未安装: ${missing_packages[*]}"
        log_info "正在自动安装缺失的软件包..."
        
        if command -v dnf &> /dev/null; then
            sudo dnf install -y "${missing_packages[@]}"
        elif command -v yum &> /dev/null; then
            sudo yum install -y "${missing_packages[@]}"
        else
            log_error "未找到包管理器 (dnf 或 yum)"
        fi
        
        log_success "软件包安装完成"
    fi
}

# 函数：安装和配置 Go
setup_go() {
    log_info "检查 Go 编译器..."
    
    # 检查系统 Go
    if command -v go &> /dev/null; then
        local current_go_version=$(go version | awk '{print $3}')
        log_success "系统 Go 已安装: $current_go_version"
    fi
    
    # 检查目标 Go 是否已安装
    if [ -d "$GO_ROOT_DIR" ] && [ -f "$GO_ROOT_DIR/bin/go" ]; then
        log_success "目标 Go 已安装: $GO_ROOT_DIR"
        return 0
    fi
    
    # 下载并安装 Go
    log_info "准备下载 Go ${GO_VERSION} (loong64)..."
    
    # 创建临时目录用于解压
    local temp_dir="/tmp/go-install-$$"
    mkdir -p "$temp_dir"
    log_info "使用临时目录: $temp_dir"
    
    # 如果本地已存在下载文件，先删除它
    if [ -f "$GO_TAR" ]; then
        log_warning "本地已存在 $GO_TAR，正在删除..."
        rm -f "$GO_TAR"
    fi
    
    # 下载 Go，带重试机制
    log_info "正在下载 Go ${GO_VERSION} (loong64)..."
    local max_retries=3
    local retry_count=0
    local download_success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$download_success" = false ]; do
        if [ $retry_count -gt 0 ]; then
            log_warning "第 $retry_count 次重试下载..."
            rm -f "$GO_TAR"
        fi
        
        if wget --timeout=30 --tries=3 --retry-connrefused "$GO_URL" -O "$GO_TAR"; then
            if [ -f "$GO_TAR" ]; then
                log_info "验证下载文件的完整性..."
                if gzip -t "$GO_TAR" 2>/dev/null; then
                    log_success "文件完整性验证通过"
                    download_success=true
                    break
                else
                    log_warning "下载的文件不是有效的 gzip 格式，可能已损坏"
                    rm -f "$GO_TAR"
                fi
            else
                log_warning "下载后文件不存在"
            fi
        else
            log_warning "wget 下载失败"
        fi
        
        retry_count=$((retry_count + 1))
    done
    
    if [ "$download_success" = false ]; then
        log_error "Go 下载失败，已重试 $max_retries 次"
    fi
    
    log_info "正在解压 Go 到临时目录..."
    
    if tar -C "$temp_dir" -xzf "$GO_TAR"; then
        log_success "Go 解压成功"
    else
        log_error "Go 解压失败，压缩包可能已损坏"
        rm -f "$GO_TAR"
        rm -rf "$temp_dir"
    fi
    
    if [ ! -d "$temp_dir/go" ]; then
        log_error "解压后未找到 go 目录"
        rm -f "$GO_TAR"
        rm -rf "$temp_dir"
    fi
    
    # 删除旧的 Go 安装目录
    if [ -d "$GO_ROOT_DIR" ]; then
        log_warning "删除旧版 Go 目录: $GO_ROOT_DIR"
        rm -rf "$GO_ROOT_DIR"
    fi
    
    # 将临时目录中的 go 移动到目标位置
    log_info "移动 Go 到目标位置: $GO_ROOT_DIR"
    mv "$temp_dir/go" "$GO_ROOT_DIR"
    log_success "已将 go 移动到 $GO_ROOT_DIR"
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    # 删除下载的压缩包
    if [ -f "$GO_TAR" ]; then
        rm -f "$GO_TAR"
        log_success "已删除下载的压缩包"
    fi
    
    # 创建 GOPATH 目录
    mkdir -p "$HOME/go-projects/src" "$HOME/go-projects/bin" "$HOME/go-projects/pkg"
    
    log_success "Go ${GO_VERSION} (loong64) 安装完成"
}

# 函数：验证环境
validate_environment() {
    log_info "验证环境..."
    
    # 检查目录权限
    local dirs=("$BASE_DIR" "$SRPM_DIR" "$RPM_DIR" "$SRPM_BUILD_DIR" "$SOURCES_DIR")
    for dir in "${dirs[@]}"; do
        if [ -w "$dir" ]; then
            log_success "目录可写: $dir"
        else
            log_error "目录不可写: $dir"
        fi
    done
    
    # 检查必要的命令
    local commands=("git" "make" "gcc" "rpmbuild" "wget" "tar")
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            log_success "命令可用: $cmd"
        else
            log_error "命令不可用: $cmd"
        fi
    done
    
    log_success "基础环境验证通过"
}

# 函数：显示环境摘要
show_summary() {
    log_header "环境设置完成"
    
    echo -e "${BLUE}目录结构:${NC}"
    echo -e "  基础目录:                $BASE_DIR"
    echo -e "  SRPM 源目录:             $SRPM_DIR"
    echo -e "  RPM 输出目录:            $RPM_DIR"
    echo -e "  SRPM 输出目录:           $SRPM_BUILD_DIR"
    echo -e "  源码二进制构建目录:      $SOURCES_DIR"
    echo -e ""
    echo -e "${BLUE}Git 项目状态:${NC}"
    
    # 获取 Git 项目信息
    if [ -d "$SOURCES_DIR/cri-tools" ]; then
        local cri_hash=$(cd "$SOURCES_DIR/cri-tools" && git rev-parse --short HEAD 2>/dev/null || echo "未知")
        echo -e "  cri-tools:      $cri_hash"
    else
        echo -e "  cri-tools:      未下载"
    fi
    
    if [ -d "$SOURCES_DIR/kubernetes" ]; then
        local k8s_hash=$(cd "$SOURCES_DIR/kubernetes" && git rev-parse --short HEAD 2>/dev/null || echo "未知")
        echo -e "  kubernetes:     $k8s_hash"
    else
        echo -e "  kubernetes:     未下载"
    fi
    
    if [ -d "$SOURCES_DIR/plugins" ]; then
        local plugins_hash=$(cd "$SOURCES_DIR/plugins" && git rev-parse --short HEAD 2>/dev/null || echo "未知")
        echo -e "  plugins:        $plugins_hash"
    else
        echo -e "  plugins:        未下载"
    fi
    
    echo -e ""
    echo -e "${BLUE}Go 安装状态:${NC}"
    if [ -d "$GO_ROOT_DIR" ] && [ -f "$GO_ROOT_DIR/bin/go" ]; then
        echo -e "  Go 已安装:      $GO_ROOT_DIR"
        echo -e "  版本:           ${GO_VERSION} (loong64)"
    else
        echo -e "  ${YELLOW}Go 未安装${NC}"
    fi
    
    echo -e ""
    echo -e "${BLUE}工具版本:${NC}"
    echo -e "  Git:            $(git --version 2>/dev/null || echo "未安装")"
    echo -e "  Make:           $(make --version 2>/dev/null | head -1 || echo "未安装")"
    echo -e ""
    echo -e "${YELLOW}下一步:${NC}"
    echo -e "  1. 将上游 SRPM 包放入: $SRPM_DIR"
    echo -e "  2. 运行 main.sh 开始编译（会自动设置 Go 环境变量）"
    echo -e "  3. 构建结果将在: $RPM_DIR 和 $SRPM_BUILD_DIR"
    echo -e ""
    log_success "环境设置完成！"
    echo -e "${PURPLE}========================================${NC}"
}

# 函数：显示帮助信息
show_help() {
    log_header "Kubernetes 工厂环境设置脚本"
    echo -e "用法: $0"
    echo -e ""
    echo -e "功能:"
    echo -e "  1. 创建 Kubernetes 工厂目录结构"
    echo -e "  2. 下载必要的 Git 项目"
    echo -e "  3. 检查并安装依赖软件包"
    echo -e "  4. 安装和配置 Go 编译器"
    echo -e ""
    echo -e "有效期:"
    echo -e "  环境初始化完成后，标记文件有效期为15天"
    echo -e "  15天内再次运行脚本会自动跳过"
}

# 主函数
main() {
    # 如果带有 -h 或 --help 参数，显示帮助信息
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    log_header "Kubernetes 工厂环境设置"
    
    # 检查环境是否已设置且在有效期内
    if check_env_status; then
        log_success "环境初始化有效，无需重复执行"
        exit 0
    fi
    
    # 执行环境初始化
    log_info "开始执行环境初始化..."
    
    # 检查目录结构并下载项目
    check_directory_structure
    
    # 检查并安装软件包
    check_packages
    
    # 设置 Go
    setup_go
    
    # 验证环境
    validate_environment
    
    # 创建标记文件（记录当前时间）
    touch "$ENV_FLAG_FILE"
    local current_time=$(date +%s)
    local expire_time=$((current_time + 15*24*60*60))
    log_success "已创建环境初始化标记（有效期至: $(date -d @$expire_time '+%Y-%m-%d %H:%M:%S')）"
    
    # 显示摘要
    show_summary
    
    log_success "环境设置完成！"
}

# 执行主函数
main "$@"
