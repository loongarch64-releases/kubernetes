#!/bin/bash

# compile-plugins.sh - CNI plugins 编译脚本
# 用法: ./compile-plugins.sh <tag版本号>
# 示例: ./compile-plugins.sh v1.5.1

set -e

# 颜色输出
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_header() { echo -e "${PURPLE}========================================${NC}"; echo -e "${PURPLE}  $1${NC}"; echo -e "${PURPLE}========================================${NC}"; }

# ==================== 全局变量 ====================
TAG_VERSION=""
SOURCE_DIR="$HOME/k8s-Factory/sources/plugins"
PATCH_FILE="0001-plugins-add-version-info.patch"
BANDWIDTH_BIN=""

# 获取脚本所在目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# ==================== 函数：清理工作区 ====================
clean_workspace() {
    local source_dir=$1
    log_info "清理工作区: $source_dir"
    
    cd "$source_dir"
    
    # 重置所有修改
    log_info "重置本地修改..."
    git reset --hard HEAD >/dev/null 2>&1 || log_warning "git reset 失败"
    
    # 清理未跟踪的文件和目录
    log_info "清理未跟踪文件..."
    git clean -fd >/dev/null 2>&1 || log_warning "git clean 失败"
    
    log_success "工作区清理完成"
}

# ==================== 切tag ====================
switch_to_tag() {
    local tag=$1
    log_info "切换到标签: $tag"
    cd "$SOURCE_DIR"
 
    # 先清理工作区
    clean_workspace "$SOURCE_DIR"

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
        git checkout "$tag" || log_error "切换到 $tag 失败"
        log_success "已切换到标签: $tag (detached HEAD状态)"
    fi 
}

# ==================== 打patch ====================
apply_patch() {
    log_info "应用patch: $PATCH_FILE"
    cd "$SOURCE_DIR"
    
    # patch文件位置：项目根目录/patches/
    local patch_file="$ROOT_DIR/patches/$PATCH_FILE"
    
    if [ ! -f "$patch_file" ]; then
        log_error "找不到patch文件: $patch_file"
    fi
    
    log_info "使用patch: $patch_file"
    
    # 检查patch是否已应用
    if git apply --check "$patch_file" 2>/dev/null; then
        git apply "$patch_file"
        log_success "patch应用成功"
    elif git apply --reverse --check "$patch_file" 2>/dev/null; then
        log_info "patch已应用，跳过"
    else
        log_warning "patch检查失败，尝试强制应用..."
        git apply --reject "$patch_file" 2>/dev/null || log_error "patch应用失败"
    fi
}

# ==================== 编译 ====================
build_plugins() {
    log_info "开始编译"
    cd "$SOURCE_DIR"
    
    export GOARCH="loong64"
    export GOOS="linux"
    
    [ -f "./build_linux.sh" ] || log_error "找不到 build_linux.sh"
    chmod +x "./build_linux.sh"
    
    if ./build_linux.sh; then
        log_success "编译成功"
    else
        log_error "编译失败"
    fi
}

# ==================== 冒烟测试 ====================
smoke_test() {
    log_info "执行冒烟测试"
    cd "$SOURCE_DIR"
    
    # 找bandwidth
    if [ -f "$SOURCE_DIR/bin/bandwidth" ]; then
        BANDWIDTH_BIN="$SOURCE_DIR/bin/bandwidth"
    else
        BANDWIDTH_BIN=$(find "$SOURCE_DIR" -name "bandwidth" -type f -executable 2>/dev/null | head -1)
    fi
    
    [ -n "$BANDWIDTH_BIN" ] || log_error "找不到bandwidth"
    
    # 测试
    log_info "执行: $BANDWIDTH_BIN --version"
    $BANDWIDTH_BIN --version || log_error "冒烟测试失败"
    log_success "冒烟测试通过"
}

# ==================== 主函数 ====================
main() {
    log_info "=== CNI plugins 编译脚本 ==="
    
    [ $# -eq 1 ] || log_error "用法: $0 <tag版本号>"
    TAG_VERSION="$1"
    
    [ -d "$SOURCE_DIR" ] || log_error "源码目录不存在: $SOURCE_DIR"
    
    switch_to_tag "$TAG_VERSION"
    apply_patch
    build_plugins
    smoke_test
    
    log_success "编译完成: $SOURCE_DIR/bin/"
    ls -lh "$SOURCE_DIR/bin/" 2>/dev/null || true
}

trap 'log_error "脚本被中断"' INT TERM
main "$@"
