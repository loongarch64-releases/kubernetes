#!/bin/bash

# compile-k8s.sh - Kubernetes编译脚本
# 用法: ./compile-k8s.sh <tag版本号>
# 示例: ./compile-k8s.sh v1.35.2

set -e

# 颜色输出
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ==================== 全局变量 ====================
CURRENT_DIR="$(pwd)"                    # 记录执行脚本时的当前目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # 脚本所在目录
TAG_VERSION=""
SOURCE_DIR="$HOME/k8s-Factory/sources/kubernetes"
KUBEADM_BIN=""

# ==================== 辅助函数：版本比较 ====================
version_ge() {
    local version1=$1
    local version2=$2
    
    version1=${version1#v}
    version2=${version2#v}
    
    local v1_parts=(${version1//./ })
    local v2_parts=(${version2//./ })
    
    for i in 0 1 2; do
        if [ ${v1_parts[$i]} -gt ${v2_parts[$i]} ]; then
            return 0
        elif [ ${v1_parts[$i]} -lt ${v2_parts[$i]} ]; then
            return 1
        fi
    done
    return 0
}

# ==================== 函数1：清理工作区 ====================
clean_workspace() {
    log_info "清理工作区: $SOURCE_DIR"
    
    cd "$SOURCE_DIR"
    
    local current_branch=$(git branch --show-current 2>/dev/null || echo "detached")
    log_info "当前分支: $current_branch"
    
    log_info "重置本地修改..."
    git reset --hard HEAD >/dev/null 2>&1 || log_warning "git reset 失败"
    
    log_info "清理未跟踪文件..."
    git clean -fd >/dev/null 2>&1 || log_warning "git clean 失败"
    
    if [ -f ".go-version.bak" ]; then
        rm -f ".go-version.bak"
    fi
    
    log_success "工作区清理完成"
}

# ==================== 函数2：切换到指定tag ====================
switch_to_tag() {
    local tag=$1
    log_info "切换到标签: $tag"
    
    cd "$SOURCE_DIR"
    
    # 清理工作区
    clean_workspace
    
    # 检查tag是否存在
    if ! git tag | grep -q "^$tag$"; then
        log_warning "标签 $tag 不存在，尝试fetch所有tags"
        git fetch --tags
        git tag | grep -q "^$tag$" || log_error "标签 $tag 仍然不存在"
    fi
    
    local branch_name="build-$tag"
    
    # 获取当前分支
    local current_branch=$(git branch --show-current)
    log_info "当前分支: $current_branch"
    
    # 如果当前在要删除的分支上，先切换到master/main
    if [ "$current_branch" = "$branch_name" ]; then
        log_warning "当前在 $branch_name 分支上，先切换到其他分支"
        if git show-ref --verify --quiet refs/heads/master; then
            git checkout master
        elif git show-ref --verify --quiet refs/heads/main; then
            git checkout main
        else
            git checkout -b "temp-branch-$$"
        fi
    fi
    
    # 删除旧分支
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        log_warning "删除已存在的分支: $branch_name"
        git branch -D "$branch_name"
    fi
    
    # 切换到tag创建新分支
    if git checkout "tags/$tag" -b "$branch_name" 2>/dev/null; then
        log_success "已切换到标签: $tag (新分支: $branch_name)"
    else
        git checkout "$tag"
        log_success "已切换到标签: $tag (detached HEAD状态)"
    fi
}

# ==================== 函数3：版本特定处理 ====================
apply_version_specific_fixes() {
    local tag=$1
    log_info "应用版本特定修复"
    
    cd "$SOURCE_DIR"
    
    # 修改 .go-version 文件为 1.26.1
    log_info "修改 .go-version 文件为 1.26.1"
    local go_version_file="$SOURCE_DIR/.go-version"
    
    if [ -f "$go_version_file" ]; then
        cp "$go_version_file" "$go_version_file.bak"
        echo "1.26.1" > "$go_version_file"
        log_success ".go-version 文件已修改为 1.26.1"
        log_info "当前 .go-version 内容: $(cat "$go_version_file")"
    else
        log_warning ".go-version 文件不存在"
    fi
    
    # v1.32.0+ 不需要打 patch
    log_success "版本 $tag >= v1.32.0，无需打 patch"
}

# ==================== 函数4：执行构建 ====================
build_kubernetes() {
    log_info "开始执行make all构建（可能需要较长时间）"
    
    cd "$SOURCE_DIR"
    
    export KUBE_BUILD_PLATFORMS="linux/loong64"
    export GOARCH="loong64"
    export GOOS="linux"
    
    log_info "构建配置:"
    log_info "  - KUBE_BUILD_PLATFORMS: $KUBE_BUILD_PLATFORMS"
    log_info "  - GOARCH: $GOARCH"
    log_info "  - GOOS: $GOOS"
    
    local start_time=$(date +%s)
    
    if make all; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "make all 构建成功完成，耗时: ${duration}秒"
    else
        log_error "make all 构建失败"
    fi
}

# ==================== 函数5：冒烟测试 ====================
smoke_test() {
    log_info "执行冒烟测试"
    
    cd "$SOURCE_DIR"
    
    local kubeadm_bin=$(find "$SOURCE_DIR/_output" -name "kubeadm" -type f 2>/dev/null | head -1)
    
    if [ -z "$kubeadm_bin" ]; then
        kubeadm_bin=$(find "$SOURCE_DIR" -path "*/_output/*" -name "kubeadm" -type f 2>/dev/null | head -1)
    fi
    
    [ -n "$kubeadm_bin" ] || log_error "找不到kubeadm二进制文件"
    
    log_info "找到kubeadm: $kubeadm_bin"
    log_info "文件信息:"
    file "$kubeadm_bin" || true
    log_info "文件大小: $(du -h "$kubeadm_bin" | cut -f1)"
    
    log_info "执行: $kubeadm_bin version"
    if $kubeadm_bin version; then
        log_success "冒烟测试通过"
        KUBEADM_BIN="$kubeadm_bin"
    else
        log_error "冒烟测试失败"
    fi
}

# ==================== 主函数 ====================
main() {
    log_info "=== Kubernetes编译脚本启动 ==="
    
    # 参数检查
    [ $# -eq 1 ] || log_error "请提供tag版本号参数\n用法: $0 <tag版本号>\n例如: $0 v1.35.2"
    
    TAG_VERSION="$1"
    
    # 检查版本是否 >= v1.32.0
    if ! version_ge "$TAG_VERSION" "v1.32.0"; then
        log_error "版本 $TAG_VERSION < v1.32.0，不再支持构建（旧版本已构建完成）"
    fi
    
    # 检查源码目录
    [ -d "$SOURCE_DIR" ] || log_error "源码目录不存在: $SOURCE_DIR"
    [ -d "$SOURCE_DIR/.git" ] || log_error "$SOURCE_DIR 不是git仓库"
    
    log_info "版本标签: $TAG_VERSION"
    log_info "源码目录: $SOURCE_DIR"
    log_info "当前目录: $CURRENT_DIR"
    log_info "脚本目录: $SCRIPT_DIR"
    
    # 执行主要步骤
    switch_to_tag "$TAG_VERSION"
    apply_version_specific_fixes "$TAG_VERSION"
    build_kubernetes
    smoke_test
    
    # 显示结果摘要
    log_success "=========================================="
    log_success "Kubernetes $TAG_VERSION 编译完成"
    log_success "构建产物: $SOURCE_DIR/_output"
    log_success "kubeadm: $KUBEADM_BIN"
    log_success "=========================================="
    
    if [ -d "$SOURCE_DIR/_output" ]; then
        log_info "构建产物列表:"
        ls -lh "$SOURCE_DIR/_output/local/bin/linux/loong64/" 2>/dev/null | while read -r line; do
            echo "  $line"
        done
    fi
}

# ==================== 脚本入口 ====================
trap 'log_error "脚本被中断"' INT TERM
main "$@"
exit 0
