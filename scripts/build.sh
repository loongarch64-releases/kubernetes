#!/bin/bash
set -euo pipefail

UPSTREAM_OWNER=kubernetes
UPSTREAM_REPO=kubernetes
echo "   🏢 Org:   ${UPSTREAM_OWNER}"
echo "   📦 Proj:  ${UPSTREAM_REPO}"
echo "   🏷️  Ver:   ${VERSION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DISTS="${ROOT_DIR}/dists"
SRCS="${ROOT_DIR}/srcs"

mkdir -p "${DISTS}/${VERSION}" "${SRCS}"

# ==========================================
# 👇 CI 构建逻辑（只处理单个最新版本）
# ==========================================

# 全局变量
PRODUCTS_DIR="$HOME/k8s-Factory/Products"
RPM_DEST_DIR="$PRODUCTS_DIR/k8s-rpm"
SRPM_DEST_DIR="$PRODUCTS_DIR/k8s-srpm"

# 颜色输出
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 设置 Go 环境
setup_go_environment() {
    local go_root="$HOME/go1.26.1"
    if [ -d "$go_root" ]; then
        export GOROOT="$go_root"
        export PATH="$GOROOT/bin:$PATH"
        export GOARCH="loong64"
        export GOOS="linux"
        export CGO_ENABLED=0
        export GO111MODULE=on
        log_success "Go 环境: $(go version)"
    else
        log_error "找不到 Go: $go_root"
    fi
}

# 准备阶段
prepare() {
    log_info "=== 准备阶段 ==="
    
    # 执行环境初始化
    if [ -f "$SCRIPT_DIR/env.sh" ]; then
        "$SCRIPT_DIR/env.sh"
    fi
    
    setup_go_environment
    
    # 确保 VERSION 已设置
    if [ -z "${VERSION:-}" ]; then
        log_error "VERSION 未设置"
    fi
    
    # 检查版本是否 >= v1.32.0
    if [[ "$(printf '%s\n' "v1.32.0" "$VERSION" | sort -V | head -1)" != "$VERSION" ]]; then
        log_error "版本 $VERSION < v1.32.0，不再支持"
    fi
    
    log_success "准备阶段完成"
}

# 构建阶段
build() {
    log_info "=== 构建阶段 ==="
    log_info "构建版本: $VERSION"
    
    # 清理
    rm -rf ~/rpmbuild/
    
    # 下载 SRPM 并获取组件版本
    local version_output
    version_output=$("$SCRIPT_DIR/download-k8s-srpm.sh" "$VERSION")
    local cri_version=$(echo "$version_output" | cut -d' ' -f1)
    local cni_version=$(echo "$version_output" | cut -d' ' -f2)
    
    [[ "$cri_version" != v* ]] && cri_version="v$cri_version"
    [[ "$cni_version" != v* ]] && cni_version="v$cni_version"
    
    # 编译组件
    "$SCRIPT_DIR/compile-cri-tools.sh" "$cri_version"
    "$SCRIPT_DIR/compile-plugins.sh" "$cni_version"
    "$SCRIPT_DIR/compile-k8s.sh" "$VERSION"
    
    log_success "构建阶段完成"
}

# 打包阶段
post_build() {
    log_info "=== 打包阶段 ==="
    
    local rpm_target_dir="$RPM_DEST_DIR/$VERSION"
    local srpm_target_dir="$SRPM_DEST_DIR/$VERSION"
    mkdir -p "$rpm_target_dir" "$srpm_target_dir"
    
    # 构建 cri-tools RPM
    local srpm_path=$(find "$HOME/k8s-Factory/srpms-origin" -name "cri-tools-*.src.rpm" | head -1)
    local crictl_bin="$HOME/k8s-Factory/sources/cri-tools/build/bin/linux/loong64/crictl"
    if [ -f "$srpm_path" ] && [ -f "$crictl_bin" ]; then
        "$SCRIPT_DIR/build-rpm.sh" "$srpm_path" "$crictl_bin"
        find "$HOME/rpmbuild/RPMS" -name "cri-tools-*.rpm" -exec mv {} "$rpm_target_dir/" \;
    fi
    
    # 构建 kubernetes-cni RPM
    srpm_path=$(find "$HOME/k8s-Factory/srpms-origin" -name "kubernetes-cni-*.src.rpm" | head -1)
    local cni_bin_dir="$HOME/k8s-Factory/sources/plugins/bin"
    if [ -f "$srpm_path" ] && [ -d "$cni_bin_dir" ]; then
        "$SCRIPT_DIR/build-rpm.sh" "$srpm_path" "$cni_bin_dir"
        find "$HOME/rpmbuild/RPMS" -name "kubernetes-cni-*.rpm" -exec mv {} "$rpm_target_dir/" \;
    fi
    
    # 构建 kube 组件 RPM
    local k8s_bin_dir="$HOME/k8s-Factory/sources/kubernetes/_output/local/go/bin/"
    for component in kubelet kubeadm kubectl; do
        srpm_path=$(find "$HOME/k8s-Factory/srpms-origin" -name "${component}-*.src.rpm" | head -1)
        local component_bin="$k8s_bin_dir/$component"
        if [ -f "$srpm_path" ] && [ -f "$component_bin" ]; then
            "$SCRIPT_DIR/build-rpm.sh" "$srpm_path" "$component_bin"
            find "$HOME/rpmbuild/RPMS" -name "${component}-*.rpm" -exec mv {} "$rpm_target_dir/" \;
        fi
    done
    
    # 创建仓库
    if command -v createrepo &> /dev/null; then
        createrepo "$rpm_target_dir"
    fi
    
    # 打包结果
    local tarball_name="k8s-rpm-${VERSION}-$(date +%Y%m%d_%H%M%S).tar.gz"
    tar czf "$DISTS/${VERSION}/$tarball_name" -C "$RPM_DEST_DIR" "${VERSION}"
    
    log_success "打包完成: $DISTS/${VERSION}/$tarball_name"
    log_success "后处理阶段完成"
}

# 主入口
main() {
    prepare
    build
    post_build
}

main

# ==========================================
# 👆 CI 逻辑结束
# ==========================================

echo "✅ Build completed for version: ${VERSION}"
ls -lh "${DISTS}/${VERSION}"
