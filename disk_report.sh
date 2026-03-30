#!/usr/bin/env bash
# =============================================================================
# disk_report.sh — 服务器硬盘用户存储占用分析报告生成器
# 用法: sudo bash disk_report.sh [输出文件名]
# 示例: sudo bash disk_report.sh report_server1.md
# =============================================================================

# 注意：不使用 set -e，改为局部错误处理，避免 du 权限错误导致脚本退出

# ── 配置 ──────────────────────────────────────────────────────────────────────
CANDIDATE_MOUNTS=(
    /data
    /data1
    /data2
    /data3
    /mnt
    /home
    /home/mnt
    /home/data
)

HOSTNAME=$(hostname)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="${1:-disk_report_${HOSTNAME}_${TIMESTAMP}.md}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ── 工具函数 ──────────────────────────────────────────────────────────────────

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

progress_bar() {
    local pct=$1
    local width=20
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar=""
    local i
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    echo "$bar"
}

get_df_info() {
    local mount=$1
    df --block-size=1 "$mount" 2>/dev/null | tail -1
}

# ── 主扫描逻辑 ────────────────────────────────────────────────────────────────

scan_mount() {
    local mount=$1

    echo "   → 正在扫描 $mount ..."

    local df_output
    df_output=$(get_df_info "$mount")
    if [[ -z "$df_output" ]]; then
        echo "     ⚠ 无法获取 $mount 的磁盘信息，跳过"
        return 1
    fi

    local device total used avail use_pct
    device=$(echo  "$df_output" | awk '{print $1}')
    total=$(echo   "$df_output" | awk '{print $2}')
    used=$(echo    "$df_output" | awk '{print $3}')
    avail=$(echo   "$df_output" | awk '{print $4}')
    use_pct=$(echo "$df_output" | awk '{print $5}' | tr -d '%')

    # 去重：避免 /home 和 /home/mnt 等同一设备被重复统计
    local dup_check_file="$TMP_DIR/processed_devices.txt"
    touch "$dup_check_file"
    if grep -qF "$device:$total" "$dup_check_file" 2>/dev/null; then
        echo "     ↩ $mount 与已扫描设备 $device 重复，跳过"
        return 1
    fi
    echo "$device:$total" >> "$dup_check_file"

    # 扫描用户目录
    local user_tmp="$TMP_DIR/users_$(echo "$mount" | tr '/' '_').txt"
    > "$user_tmp"

    local dir_count=0
    for user_dir in "$mount"/*/; do
        [[ -d "$user_dir" ]] || continue
        local username
        username=$(basename "$user_dir")

        case "$username" in
            lost+found|proc|sys|dev|tmp|var|etc|usr|bin|sbin|lib|lib64|boot|run|snap|root) continue ;;
        esac

        local size_bytes
        size_bytes=$(du -sb "$user_dir" 2>/dev/null | awk '{print $1}')
        [[ -z "$size_bytes" ]] && size_bytes=0

        echo "${size_bytes} ${username} ${user_dir}" >> "$user_tmp"
        (( dir_count++ )) || true
    done

    echo "     ✓ 发现 $dir_count 个用户目录"

    [[ -s "$user_tmp" ]] && sort -rn "$user_tmp" -o "$user_tmp"

    local info_file="$TMP_DIR/mount_$(echo "$mount" | tr '/' '_').info"
    {
        echo "MOUNT=$mount"
        echo "DEVICE=$device"
        echo "TOTAL=$total"
        echo "USED=$used"
        echo "AVAIL=$avail"
        echo "USE_PCT=$use_pct"
    } > "$info_file"

    return 0
}

# ── 生成 Markdown 报告 ────────────────────────────────────────────────────────

generate_report() {
    local report_file=$1
    local date_str
    date_str=$(date "+%Y-%m-%d %H:%M:%S")

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
        [[ -d "$mount" ]] || continue

        local info_file="$TMP_DIR/mount_$(echo "$mount" | tr '/' '_').info"
        [[ -f "$info_file" ]] || continue

        local MOUNT DEVICE TOTAL USED AVAIL USE_PCT
        while IFS='=' read -r key val; do
            case "$key" in
                MOUNT)   MOUNT="$val"   ;;
                DEVICE)  DEVICE="$val"  ;;
                TOTAL)   TOTAL="$val"   ;;
                USED)    USED="$val"    ;;
                AVAIL)   AVAIL="$val"   ;;
                USE_PCT) USE_PCT="$val" ;;
            esac
        done < "$info_file"

        local total_hr used_hr avail_hr bar
        total_hr=$(human_readable "$TOTAL")
        used_hr=$(human_readable  "$USED")
        avail_hr=$(human_readable "$AVAIL")
        bar=$(progress_bar "$USE_PCT")

        (( mount_count++ )) || true

        cat >> "$report_file" << EOF
## 📂 挂载点: \`${MOUNT}\`

### 磁盘概况

| 设备 | 总空间 | 已用 | 可用 | 使用率 |
|------|--------|------|------|--------|
| \`${DEVICE}\` | ${total_hr} | ${used_hr} | ${avail_hr} | ${USE_PCT}% \`${bar}\` |

EOF

        local user_tmp="$TMP_DIR/users_$(echo "$mount" | tr '/' '_').txt"

        if [[ -s "$user_tmp" ]]; then
            cat >> "$report_file" << EOF
### 👤 用户存储占用（按大小排序）

| 排名 | 用户 | 目录 | 占用空间 | 占磁盘比 |
|------|------|------|----------|---------|
EOF
            local rank=0
            while IFS=' ' read -r size_bytes username user_dir; do
                (( rank++ )) || true
                local size_hr pct_of_disk
                size_hr=$(human_readable "$size_bytes")
                if (( TOTAL > 0 )); then
                    pct_of_disk=$(awk "BEGIN {printf \"%.1f\", $size_bytes*100/$TOTAL}")
                else
                    pct_of_disk="N/A"
                fi
                echo "| ${rank} | \`${username}\` | \`${user_dir}\` | **${size_hr}** | ${pct_of_disk}% |" >> "$report_file"
            done < "$user_tmp"

            echo "" >> "$report_file"

            local top_user_total=0
            while IFS=' ' read -r size_bytes _rest; do
                top_user_total=$(( top_user_total + size_bytes ))
            done < "$user_tmp"
            local top_total_hr
            top_total_hr=$(human_readable "$top_user_total")
            echo "> 📊 该挂载点下所有用户目录合计占用：**${top_total_hr}**" >> "$report_file"
            echo "" >> "$report_file"

        else
            echo "> ℹ️  该挂载点下未发现用户目录（可能是空目录或无读取权限）。" >> "$report_file"
            echo "" >> "$report_file"
        fi

        echo "---" >> "$report_file"
        echo "" >> "$report_file"
    done

    if (( mount_count == 0 )); then
        echo "> ⚠️  **未生成任何挂载点报告。** 请检查扫描日志。" >> "$report_file"
    fi

    cat >> "$report_file" << EOF
---
*报告由 \`disk_report.sh\` 自动生成 · ${date_str}*
EOF
}

# ── 主流程 ────────────────────────────────────────────────────────────────────

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "⚠  警告: 建议以 sudo 运行以获取完整读取权限。" >&2
        echo "" >&2
    fi

    echo "🔍 正在扫描挂载点..."
    for m in "${CANDIDATE_MOUNTS[@]}"; do
        if [[ -d "$m" ]]; then
            echo "   ✓ 发现: $m"
        else
            echo "   ✗ 跳过: $m（不存在）"
        fi
    done
    echo ""

    echo "📊 正在统计用户目录占用（可能需要几分钟）..."
    echo ""

    for mount in "${CANDIDATE_MOUNTS[@]}"; do
        [[ -d "$mount" ]] || continue
        scan_mount "$mount" || true
    done

    echo ""
    echo "📝 正在生成报告..."
    generate_report "$OUTPUT_FILE"

    echo "✅ 报告已生成: $OUTPUT_FILE"
    echo ""
    echo "── 报告预览（前50行）────────────────────────────"
    head -50 "$OUTPUT_FILE"
    echo "..."
    echo "────────────────────────────────────────────────"
}

main "$@"
