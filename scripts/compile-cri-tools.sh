#!/bin/bash

# compile-cri-tools.sh - cri-tools 编译脚本
# 用法: ./compile-cri-tools.sh <tag版本号>
# 示例: ./compile-cri-tools.sh v1.34.0

set -e

# 颜色输出
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ==================== 全局变量 ====================
TAG_VERSION=""
SOURCE_DIR="$HOME/k8s-Factory/sources/cri-tools"
CRICTL_BIN=""

# ==================== 函数1：切换到指定tag ====================
switch_to_tag() {
    local tag=$1
    log_info "切换到标签: $tag"
    
    cd "$SOURCE_DIR"
    
    # 检查是否为git仓库
    [ -d ".git" ] || log_error "$SOURCE_DIR 不是git仓库"
    
    # 检查tag是否存在
    if ! git tag | grep -q "^$tag$"; then
        log_warning "标签 $tag 不存在，尝试fetch所有tags"
        git fetch --tags
        git tag | grep -q "^$tag$" || log_error "标签 $tag 仍然不存在"
    fi
    
    local branch_name="build-$tag"
    
    # 获取当前分支名
    local current_branch=$(git branch --show-current)
    log_info "当前分支: $current_branch"
    
    # 如果当前不在master分支，先切换到master分支
    if [ "$current_branch" != "master" ] && [ "$current_branch" != "main" ]; then
        log_info "当前不在master/main分支，尝试切换到master分支"
        
        # 尝试切换到master，如果失败则尝试main
        if git show-ref --verify --quiet refs/heads/master; then
            git checkout master
            log_success "已切换到master分支"
        elif git show-ref --verify --quiet refs/heads/main; then
            git checkout main
            log_success "已切换到main分支"
        else
            # 如果既没有master也没有main，尝试切换到第一个可用的分支
            local first_branch=$(git branch | head -1 | tr -d ' *')
            log_warning "找不到master/main分支，切换到: $first_branch"
            git checkout "$first_branch"
        fi
    fi
    
    # 删除可能存在的旧构建分支
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        log_warning "删除已存在的分支: $branch_name"
        git branch -D "$branch_name"
    fi
    
    # 切换到tag创建新分支
    if git checkout "tags/$tag" -b "$branch_name" 2>/dev/null; then
        log_success "已切换到标签: $tag (新分支: $branch_name)"
    else
        # 如果无法创建新分支，直接切换到tag（detached HEAD状态）
        git checkout "$tag"
        log_success "已切换到标签: $tag (detached HEAD状态)"
    fi
}

# ==================== 函数2：执行构建 ====================
build_crictl() {
    log_info "开始执行 make crictl 构建"
    
    # 设置构建环境变量
    export GOARCH="loong64"
    export GOOS="linux"
    
    log_info "构建配置:"
    log_info "  - GOARCH: $GOARCH"
    log_info "  - GOOS: $GOOS"
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行构建
    if make crictl; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "make crictl 构建成功完成，耗时: ${duration}秒"
    else
        log_error "make crictl 构建失败"
    fi
}

# ==================== 函数3：冒烟测试 ====================
smoke_test() {
    log_info "执行冒烟测试"
    
    # 查找crictl二进制文件
    local possible_paths=(
        "$SOURCE_DIR/build/bin/linux/loong64/crictl"
        "$SOURCE_DIR/_output/bin/crictl"
        "$SOURCE_DIR/crictl"
    )
    
    for path in "${possible_paths[@]}"; do
        if [ -f "$path" ] && [ -x "$path" ]; then
            CRICTL_BIN="$path"
            break
        fi
    done
    
    # 如果没找到，使用find命令搜索
    if [ -z "$CRICTL_BIN" ]; then
        CRICTL_BIN=$(find "$SOURCE_DIR" -name "crictl" -type f -executable 2>/dev/null | head -1)
    fi
    
    [ -n "$CRICTL_BIN" ] || log_error "找不到crictl二进制文件"
    
    log_info "找到crictl: $CRICTL_BIN"
    
    # 显示文件信息
    log_info "文件信息:"
    file "$CRICTL_BIN"
    log_info "文件大小: $(du -h "$CRICTL_BIN" | cut -f1)"
    
    # 执行version命令做冒烟测试
    log_info "执行: $CRICTL_BIN --version"
    
    if $CRICTL_BIN --version; then
        log_success "冒烟测试通过"
    else
        log_error "冒烟测试失败"
    fi
}

# ==================== 主函数 ====================
main() {
    log_info "=== cri-tools 编译脚本启动 ==="
    
    # 参数检查
    [ $# -eq 1 ] || log_error "请提供tag版本号参数\n用法: $0 <tag版本号>\n例如: $0 v1.34.0"
    
    TAG_VERSION="$1"
    
    # 检查源码目录
    [ -d "$SOURCE_DIR" ] || log_error "源码目录不存在: $SOURCE_DIR\n请先执行env.sh脚本下载源码"
    
    log_info "版本标签: $TAG_VERSION"
    log_info "源码目录: $SOURCE_DIR"
    
    # 执行三个主要步骤
    switch_to_tag "$TAG_VERSION"
    build_crictl
    smoke_test
    
    # 显示结果摘要
    log_success "=========================================="
    log_success "cri-tools $TAG_VERSION 编译完成"
    log_success "crictl路径: $CRICTL_BIN"
    log_success "=========================================="
}

# ==================== 脚本入口 ====================
trap 'log_error "脚本被中断"' INT TERM
main "$@"
exit 0
