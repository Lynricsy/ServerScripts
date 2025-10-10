#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# 光标控制
SAVE_CURSOR='\033[s'
RESTORE_CURSOR='\033[u'
CLEAR_LINE='\033[2K'
HIDE_CURSOR='\033[?25l'
SHOW_CURSOR='\033[?25h'

# 清理函数
cleanup() {
    echo -e "${SHOW_CURSOR}"
    if [ -n "$TEMP_ZIP" ] && [ -f "$TEMP_ZIP" ]; then
        rm -f "$TEMP_ZIP"
    fi
}
trap cleanup EXIT INT TERM

# 打印标题
print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}${BOLD}           📦 智能文件压缩工具 📦                     ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 生成随机后缀
generate_random_suffix() {
    cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 4 | head -n 1
}

# 格式化文件大小
format_size() {
    local size=$1
    if [ $size -lt 1024 ]; then
        echo "${size}B"
    elif [ $size -lt 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $size/1024}")KB"
    elif [ $size -lt 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $size/1048576}")MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $size/1073741824}")GB"
    fi
}

# 格式化时间
format_time() {
    local timestamp=$1
    date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$timestamp" "+%Y-%m-%d %H:%M:%S"
}

# 选择文件或文件夹
select_target() {
    print_header
    echo -e "${YELLOW}📂 当前目录下的文件和文件夹：${NC}\n"
    
    local items=()
    local index=1
    
    # 列出所有文件和文件夹（排除隐藏文件和当前脚本）
    while IFS= read -r item; do
        if [ -d "$item" ]; then
            echo -e "${BLUE}  [$index]${NC} 📁 ${GREEN}$item/${NC}"
        else
            echo -e "${BLUE}  [$index]${NC} 📄 ${WHITE}$item${NC}"
        fi
        items+=("$item")
        ((index++))
    done < <(ls -1A | grep -v "^$(basename "$0")$")
    
    if [ ${#items[@]} -eq 0 ]; then
        echo -e "${RED}❌ 当前目录下没有可压缩的文件或文件夹！${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    while true; do
        echo -ne "${YELLOW}请输入序号选择要压缩的目标 [1-${#items[@]}]: ${NC}"
        read selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#items[@]} ]; then
            TARGET="${items[$((selection-1))]}"
            break
        else
            echo -e "${RED}❌ 无效的选择，请重新输入！${NC}"
        fi
    done
}

# 检查并处理重名
handle_duplicate() {
    local zip_name=$1
    
    if [ -f "$zip_name" ]; then
        local size=$(stat -f%z "$zip_name" 2>/dev/null || stat -c%s "$zip_name" 2>/dev/null)
        local mtime=$(stat -f%m "$zip_name" 2>/dev/null || stat -c%Y "$zip_name" 2>/dev/null)
        
        echo ""
        echo -e "${YELLOW}⚠️  检测到同名压缩包已存在！${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${WHITE}文件名：${NC}${MAGENTA}$zip_name${NC}"
        echo -e "${WHITE}大  小：${NC}${GREEN}$(format_size $size)${NC}"
        echo -e "${WHITE}修改时间：${NC}${BLUE}$(format_time $mtime)${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        while true; do
            echo -ne "${YELLOW}是否替换现有文件？[y/N]: ${NC}"
            read -r response
            case "$response" in
                [yY][eE][sS]|[yY])
                    rm -f "$zip_name"
                    echo "$zip_name"
                    return
                    ;;
                [nN][oO]|[nN]|"")
                    local base="${zip_name%.zip}"
                    local suffix=$(generate_random_suffix)
                    local new_name="${base}_${suffix}.zip"
                    echo -e "${GREEN}✓ 新文件将命名为：${MAGENTA}$new_name${NC}"
                    echo "$new_name"
                    return
                    ;;
                *)
                    echo -e "${RED}❌ 请输入 y 或 n${NC}"
                    ;;
            esac
        done
    else
        echo "$zip_name"
    fi
}

# 压缩文件
compress_with_progress() {
    local target=$1
    local output=$2
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}🚀 开始压缩...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 计算总文件数
    local total_files
    if [ -d "$target" ]; then
        total_files=$(find "$target" -type f | wc -l)
    else
        total_files=1
    fi
    
    echo -e "${WHITE}📊 总文件数：${YELLOW}$total_files${NC}"
    echo ""
    
    # 隐藏光标
    echo -e "${HIDE_CURSOR}"
    
    # 保存进度条位置
    local progress_line=$(($(tput lines) - 10))
    
    # 创建临时文件用于存储zip输出
    TEMP_ZIP="${output}.tmp"
    local current_file=0
    local last_percentage=-1
    
    # 使用zip命令并捕获输出
    (
        if [ -d "$target" ]; then
            zip -r "$TEMP_ZIP" "$target" 2>&1
        else
            zip "$TEMP_ZIP" "$target" 2>&1
        fi
    ) | while IFS= read -r line; do
        if [[ $line =~ adding:\ (.+)\ \(.*\)$ ]]; then
            local file="${BASH_REMATCH[1]}"
            ((current_file++))
            
            # 计算百分比
            local percentage=$((current_file * 100 / total_files))
            
            # 只在百分比变化时更新进度条
            if [ $percentage -ne $last_percentage ]; then
                last_percentage=$percentage
                
                # 绘制进度条
                local bar_width=50
                local filled=$((percentage * bar_width / 100))
                local empty=$((bar_width - filled))
                
                # 保存当前位置，移动到进度条位置
                tput sc
                tput cup $progress_line 0
                
                # 清空进度条区域
                echo -e "${CLEAR_LINE}"
                
                # 绘制进度条
                echo -ne "${WHITE}进度: [${GREEN}"
                printf '%*s' "$filled" '' | tr ' ' '█'
                echo -ne "${DIM}"
                printf '%*s' "$empty" '' | tr ' ' '░'
                echo -ne "${NC}${WHITE}] ${YELLOW}${percentage}%${NC} ${CYAN}(${current_file}/${total_files})${NC}"
                
                # 恢复光标位置
                tput rc
            fi
            
            # 显示当前文件（限制长度）
            local display_file="$file"
            if [ ${#display_file} -gt 60 ]; then
                display_file="...${display_file: -57}"
            fi
            echo -e "${CLEAR_LINE}${DIM}${CYAN}📄 正在压缩:${NC} ${WHITE}$display_file${NC}"
        fi
    done
    
    # 确保进度条显示100%
    tput cup $progress_line 0
    echo -e "${CLEAR_LINE}"
    echo -e "${WHITE}进度: [${GREEN}$(printf '%*s' 50 '' | tr ' ' '█')${NC}${WHITE}] ${YELLOW}100%${NC} ${CYAN}(${total_files}/${total_files})${NC}"
    
    # 移动临时文件到最终位置
    if [ -f "$TEMP_ZIP" ]; then
        mv "$TEMP_ZIP" "$output"
    fi
    
    # 显示光标
    echo -e "${SHOW_CURSOR}"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ -f "$output" ]; then
        local final_size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null)
        echo -e "${GREEN}${BOLD}✅ 压缩完成！${NC}"
        echo ""
        echo -e "${WHITE}📦 输出文件：${NC}${MAGENTA}$output${NC}"
        echo -e "${WHITE}📊 文件大小：${NC}${GREEN}$(format_size $final_size)${NC}"
        echo -e "${WHITE}✨ 压缩文件数：${NC}${YELLOW}$total_files${NC}"
    else
        echo -e "${RED}❌ 压缩失败！${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 主程序
main() {
    # 检查zip命令
    if ! command -v zip &> /dev/null; then
        echo -e "${RED}❌ 错误：未找到 zip 命令，请先安装！${NC}"
        exit 1
    fi
    
    # 选择目标
    select_target
    
    # 生成压缩包名称
    local zip_name="${TARGET}.zip"
    
    # 处理重名
    zip_name=$(handle_duplicate "$zip_name")
    
    # 执行压缩
    compress_with_progress "$TARGET" "$zip_name"
    
    echo ""
    echo -e "${GREEN}${BOLD}🎉 所有操作完成！${NC}"
    echo ""
}

# 运行主程序
main
