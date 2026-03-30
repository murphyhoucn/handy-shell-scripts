#!/usr/bin/env bash
# =============================================================================
# disk_report.sh — 服务器硬盘用户存储占用分析报告生成器
# 用法: sudo bash disk_report.sh [输出文件名]
# 示例: sudo bash disk_report.sh report_server1.md
# =============================================================================

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────────────────────────────
# 要扫描的挂载点候选列表（脚本会自动跳过不存在的）
CANDIDATE_MOUNTS=(
    /data
    /data1
    /data2
    /data3
    /mnt
    /home
)

# 输出文件（默认含主机名和时间戳）
HOSTNAME=$(hostname)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="${1:-disk_report_${HOSTNAME}_${TIMESTAMP}.md}"

# 临时文件
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ── 工具函数 ──────────────────────────────────────────────────────────────────

# 将 du/df 的原始字节数转换为人类可读格式（GiB / MiB / KiB）
human_readable() {
    local bytes=$1
    if   (( bytes >= 1073741824 )); then
        awk "BEGIN {printf \"%.1f GiB\", $bytes/1073741824}"
    elif (( bytes >= 1048576 )); then
        awk "BEGIN {printf \"%.1f MiB\", $bytes/1048576}"
    elif (( bytes >= 1024 )); then
        awk "BEGIN {printf \"%.1f KiB\", $bytes/1024}"
    else
        echo "${bytes} B"
    fi
}

# 百分比进度条（宽度20字符）
progress_bar() {
    local pct=$1   # 0-100 整数
    local width=20
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    printf '%s%s' "$(printf '█%.0s' $(seq 1 $filled 2>/dev/null || true))" \
                  "$(printf '░%.0s' $(seq 1 $empty  2>/dev/null || true))"
}

# 检查是否以 root 或 sudo 运行
check_privilege() {
    if [[ $EUID -ne 0 ]]; then
        echo "⚠  警告: 建议以 sudo 运行以获取完整的用户目录读取权限。" >&2
        echo "   部分用户目录可能因权限不足而被跳过。" >&2
        echo "" >&2
    fi
}

# ── 扫描挂载点 ────────────────────────────────────────────────────────────────

collect_mount_info() {
    local mount=$1
    local out_file="$TMP_DIR/mount_$(echo "$mount" | tr '/' '_').txt"

    # 获取挂载点的磁盘信息（字节单位）
    local df_output
    df_output=$(df --block-size=1 "$mount" 2>/dev/null | tail -1) || return 1

    local device total used avail use_pct
    device=$(echo "$df_output" | awk '{print $1}')
    total=$(echo  "$df_output" | awk '{print $2}')
    used=$(echo   "$df_output" | awk '{print $3}')
    avail=$(echo  "$df_output" | awk '{print $4}')
    use_pct=$(echo "$df_output" | awk '{print $5}' | tr -d '%')

    # 写入挂载点基本信息
    {
        echo "MOUNT=$mount"
        echo "DEVICE=$device"
        echo "TOTAL=$total"
        echo "USED=$used"
        echo "AVAIL=$avail"
        echo "USE_PCT=$use_pct"
    } > "$out_file"

    # 扫描该挂载点下的一级子目录（即用户目录）
    local user_tmp="$TMP_DIR/users_$(echo "$mount" | tr '/' '_').txt"
    > "$user_tmp"

    if [[ -d "$mount" ]]; then
        # 遍历挂载点下的直接子目录
        for user_dir in "$mount"/*/; do
            [[ -d "$user_dir" ]] || continue
            local username
            username=$(basename "$user_dir")

            # 跳过常见系统目录
            case "$username" in
                lost+found|proc|sys|dev|tmp|var|etc|usr|bin|sbin|lib|lib64|boot|run|snap) continue ;;
            esac

            # 获取目录大小（字节）
            local size_bytes
            size_bytes=$(du -sb "$user_dir" 2>/dev/null | awk '{print $1}') || size_bytes=0

            echo "${size_bytes} ${username} ${user_dir}" >> "$user_tmp"
        done

        # 按大小降序排序
        sort -rn "$user_tmp" -o "$user_tmp"
    fi

    echo "$out_file"
}

# ── 生成 Markdown 报告 ────────────────────────────────────────────────────────

generate_report() {
    local report_file=$1
    local date_str
    date_str=$(date "+%Y-%m-%d %H:%M:%S")

    # ── 报告头部
    cat > "$report_file" << EOF
# 💾 磁盘存储占用分析报告

| 项目 | 值 |
|------|-----|
| **服务器主机名** | \`${HOSTNAME}\` |
| **生成时间** | ${date_str} |
| **运行用户** | \`$(whoami)\` |

---

EOF

    local mount_count=0

    for mount in "${CANDIDATE_MOUNTS[@]}"; do
        # 跳过不存在的挂载点
        [[ -d "$mount" ]] || continue

        # 跳过不是真实挂载点的目录（可选，取消注释以严格过滤）
        # mountpoint -q "$mount" || continue

        local info_file
        info_file=$(collect_mount_info "$mount") || continue

        # 读取挂载点信息
        source "$info_file"

        local total_hr used_hr avail_hr bar
        total_hr=$(human_readable "$TOTAL")
        used_hr=$(human_readable  "$USED")
        avail_hr=$(human_readable  "$AVAIL")
        bar=$(progress_bar "$USE_PCT")

        (( mount_count++ ))

        # ── 挂载点章节
        cat >> "$report_file" << EOF
## 📂 挂载点: \`${MOUNT}\`

### 磁盘概况

| 设备 | 总空间 | 已用 | 可用 | 使用率 |
|------|--------|------|------|--------|
| \`${DEVICE}\` | ${total_hr} | ${used_hr} | ${avail_hr} | ${USE_PCT}% \`${bar}\` |

EOF

        # ── 用户存储排名
        local user_tmp="$TMP_DIR/users_$(echo "$mount" | tr '/' '_').txt"

        if [[ -s "$user_tmp" ]]; then
            cat >> "$report_file" << EOF
### 👤 用户存储占用（按大小排序）

| 排名 | 用户 | 目录 | 占用空间 | 占磁盘比 |
|------|------|------|----------|---------|
EOF
            local rank=0
            while IFS=' ' read -r size_bytes username user_dir; do
                (( rank++ ))
                local size_hr pct_of_disk
                size_hr=$(human_readable "$size_bytes")
                # 计算占总磁盘的百分比（避免除零）
                if (( TOTAL > 0 )); then
                    pct_of_disk=$(awk "BEGIN {printf \"%.1f\", $size_bytes*100/$TOTAL}")
                else
                    pct_of_disk="N/A"
                fi
                echo "| ${rank} | \`${username}\` | \`${user_dir}\` | **${size_hr}** | ${pct_of_disk}% |" >> "$report_file"
            done < "$user_tmp"

            echo "" >> "$report_file"

            # ── 用户占用小结（Top 用户占用总量）
            local top_user_total=0
            while IFS=' ' read -r size_bytes _rest; do
                top_user_total=$(( top_user_total + size_bytes ))
            done < "$user_tmp"

            local top_total_hr
            top_total_hr=$(human_readable "$top_user_total")
            echo "> 📊 该挂载点下所有用户目录合计占用：**${top_total_hr}**" >> "$report_file"
            echo "" >> "$report_file"

        else
            echo "> ℹ️  该挂载点下未发现用户目录，或当前用户无权限读取。" >> "$report_file"
            echo "" >> "$report_file"
        fi

        echo "---" >> "$report_file"
        echo "" >> "$report_file"
    done

    # ── 报告尾部
    if (( mount_count == 0 )); then
        cat >> "$report_file" << EOF
> ⚠️  **未找到任何有效挂载点。** 请检查候选列表或手动指定路径。

EOF
    fi

    cat >> "$report_file" << EOF
---
*报告由 \`disk_report.sh\` 自动生成 · ${date_str}*
EOF
}

# ── 主流程 ────────────────────────────────────────────────────────────────────

main() {
    check_privilege

    echo "🔍 正在扫描挂载点..."
    for m in "${CANDIDATE_MOUNTS[@]}"; do
        [[ -d "$m" ]] && echo "   ✓ 发现: $m" || echo "   ✗ 跳过: $m（不存在）"
    done
    echo ""

    echo "📊 正在统计用户目录占用（可能需要几分钟）..."
    generate_report "$OUTPUT_FILE"

    echo ""
    echo "✅ 报告已生成: $OUTPUT_FILE"
    echo ""

    # 打印报告预览（前30行）
    echo "── 报告预览 ──────────────────────────────────────"
    head -40 "$OUTPUT_FILE"
    echo "..."
    echo "──────────────────────────────────────────────────"
}

main "$@"
