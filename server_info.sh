#!/bin/bash

# 服务器信息收集脚本
# 作者: AI Assistant
# 用途: 收集系统、GPU、CUDA等关键信息

echo "=========================================="
echo "           服务器信息收集报告"
echo "=========================================="
echo "收集时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "主机名: $(hostname)"
echo ""

# 1. 系统信息
echo "【系统信息】"
echo "----------------------------------------"
if [ -f /etc/os-release ]; then
    echo "操作系统: $(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)"
elif command -v lsb_release >/dev/null 2>&1; then
    echo "操作系统: $(lsb_release -d | cut -f2)"
else
    echo "操作系统: $(cat /etc/issue | head -n1 | tr -d '\n')"
fi
echo "内核版本: $(uname -r)"
echo "系统架构: $(uname -m)"
echo "运行时间: $(uptime -p 2>/dev/null || uptime | cut -d',' -f1 | cut -d' ' -f3-)"
echo ""

# 2. CPU信息
echo "【CPU信息】"
echo "----------------------------------------"
if [ -f /proc/cpuinfo ]; then
    echo "CPU型号: $(grep 'model name' /proc/cpuinfo | head -n1 | cut -d':' -f2 | sed 's/^ *//')"
    echo "CPU核心数: $(grep -c '^processor' /proc/cpuinfo)"
    echo "CPU频率: $(grep 'cpu MHz' /proc/cpuinfo | head -n1 | cut -d':' -f2 | sed 's/^ *//' | cut -d'.' -f1) MHz"
fi
echo ""

# 3. 内存信息
echo "【内存信息】"
echo "----------------------------------------"
if [ -f /proc/meminfo ]; then
    total_mem=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    available_mem=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "0")
    echo "总内存: $(echo "scale=2; $total_mem / 1024 / 1024" | bc 2>/dev/null || echo "$(($total_mem / 1024 / 1024))") GB"
    if [ "$available_mem" != "0" ]; then
        echo "可用内存: $(echo "scale=2; $available_mem / 1024 / 1024" | bc 2>/dev/null || echo "$(($available_mem / 1024 / 1024))") GB"
    fi
    echo "内存使用率: $(echo "scale=1; (1 - $available_mem / $total_mem) * 100" | bc 2>/dev/null || echo "N/A")%"
fi
echo ""

# 4. GPU信息
echo "【GPU信息】"
echo "----------------------------------------"
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "GPU数量: $(nvidia-smi --list-gpus | wc -l)"
    echo "GPU详情:"
    nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free,utilization.gpu,temperature.gpu --format=csv,noheader,nounits | while IFS=',' read -r index name total used free util temp; do
        echo "  GPU $index: $name"
        echo "    显存: ${used}MB/${total}MB (空闲: ${free}MB)"
        echo "    利用率: ${util}%"
        echo "    温度: ${temp}°C"
        echo ""
    done
else
    echo "NVIDIA驱动未安装或nvidia-smi不可用"
fi
echo ""

# 5. NVIDIA驱动版本
echo "【NVIDIA驱动信息】"
echo "----------------------------------------"
if command -v nvidia-smi >/dev/null 2>&1; then
    driver_version=$(nvidia-smi | grep 'Driver Version' | awk '{print $3}')
    echo "驱动版本: $driver_version"
else
    echo "NVIDIA驱动未安装"
fi
echo ""

# 6. CUDA信息
echo "【CUDA信息】"
echo "----------------------------------------"
if command -v nvcc >/dev/null 2>&1; then
    cuda_version=$(nvcc --version | grep 'release' | awk '{print $6}' | cut -c2-)
    echo "CUDA版本: $cuda_version"
    echo "CUDA安装路径: $(which nvcc | sed 's|/bin/nvcc||')"
else
    echo "CUDA未安装或nvcc不在PATH中"
fi

# 检查cuDNN版本
cudnn_paths=(
    "/usr/local/cuda/include/cudnn.h"
    "/usr/include/cudnn.h"
    "/usr/local/cuda/include/cudnn_version.h"
    "/usr/include/cudnn_version.h"
)

for cudnn_path in "${cudnn_paths[@]}"; do
    if [ -f "$cudnn_path" ]; then
        if grep -q "CUDNN_MAJOR" "$cudnn_path"; then
            major=$(grep "#define CUDNN_MAJOR" "$cudnn_path" | awk '{print $3}')
            minor=$(grep "#define CUDNN_MINOR" "$cudnn_path" | awk '{print $3}')
            patch=$(grep "#define CUDNN_PATCHLEVEL" "$cudnn_path" | awk '{print $3}')
            echo "cuDNN版本: $major.$minor.$patch"
            break
        elif grep -q "CUDNN_VERSION" "$cudnn_path"; then
            version=$(grep "#define CUDNN_VERSION" "$cudnn_path" | awk '{print $3}' | sed 's/"//g')
            echo "cuDNN版本: $version"
            break
        fi
    fi
done

if ! grep -q "cuDNN版本" <<< "$(echo)"; then
    echo "cuDNN未安装或未找到版本信息"
fi
echo ""

# 7. 编译器信息
echo "【编译器信息】"
echo "----------------------------------------"
if command -v gcc >/dev/null 2>&1; then
    gcc_version=$(gcc --version | head -n1 | awk '{print $NF}')
    echo "GCC版本: $gcc_version"
else
    echo "GCC未安装"
fi

if command -v g++ >/dev/null 2>&1; then
    gpp_version=$(g++ --version | head -n1 | awk '{print $NF}')
    echo "G++版本: $gpp_version"
else
    echo "G++未安装"
fi

if command -v python3 >/dev/null 2>&1; then
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    echo "Python3版本: $python_version"
else
    echo "Python3未安装"
fi
echo ""

# 8. 磁盘信息
echo "【磁盘信息】"
echo "----------------------------------------"
df -h | grep -E '^/dev/' | while read -r filesystem size used avail use_percent mount; do
    echo "$filesystem: $used/$size ($use_percent) 挂载在 $mount"
done
echo ""

# 9. 网络信息
echo "【网络信息】"
echo "----------------------------------------"
echo "网络接口:"
ip addr show | grep -E '^[0-9]+:' | while read -r line; do
    interface=$(echo "$line" | cut -d':' -f2 | sed 's/^ *//')
    ip_addr=$(ip addr show "$interface" | grep 'inet ' | head -n1 | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$ip_addr" ]; then
        echo "  $interface: $ip_addr"
    fi
done
echo ""

echo "=========================================="
echo "           信息收集完成"
echo "=========================================="

