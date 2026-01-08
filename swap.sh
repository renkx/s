#!/usr/bin/env bash

Green="\033[32m"
Font="\033[0m"
Red="\033[31m"
Yellow="\033[33m"

#root权限
root_need(){
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Red}请以 root 权限运行此脚本。${Font}"
        exit 1
    fi
}

#检测ovz
ovz_no(){
    if [[ -d "/proc/vz" ]]; then
        echo -e "${Red}Your VPS is based on OpenVZ，not supported!${Font}"
        exit 1
    fi
}

# 显示内存和 swap，区分 swap 分区和 /swapfile
show_mem_swap(){
  # 物理内存
  mem_info=$(free -b | awk 'NR==2{printf "%.2f/%.2f MB (%.2f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')
  echo -e "当前物理内存: ${Green}$mem_info${Font}"

  # 总 swap
  swap_total=$(free -m | awk '/Swap/ {print $2}')
  swap_used=$(free -m | awk '/Swap/ {print $3}')
  swap_percentage=$(( swap_used * 100 / (swap_total==0?1:swap_total) ))

  # 列出每个 swap
  echo -e "当前 swap 状态:"
  if [ "$swap_total" -eq 0 ]; then
      echo -e "  ${Yellow}无 swap${Font}"
  else
      # 遍历 /proc/swaps
      awk 'NR>1 {printf "  %-15s %-8s MB  已用 %-8s MB\n", $1, $2/1024, $3/1024}' /proc/swaps
      echo -e "  总计: ${swap_used}/${swap_total} MB (${swap_percentage}%)"
  fi
}

# 清理所有 swap
clear_all_swap(){
  echo -e "${Red}正在关闭并清理所有 swap...${Font}"

  # 关闭所有 swap
  swapoff -a

  # 清理 /etc/fstab 中的 swap 条目
  sed -ri 's|^(.*/swap.*)|#\1|' /etc/fstab

  # 清理物理 swap 分区（可选 wipefs，如果你确定要彻底清空）
  swap_partitions=$(grep -E '^/dev/' /proc/swaps | awk '{print $1}')
  for partition in $swap_partitions; do
      mkswap -f "$partition" >/dev/null 2>&1
      echo -e "已清理 swap 分区: $partition"
  done

  # 删除旧 /swapfile
  if [ -f /swapfile ]; then
      rm -f /swapfile
      echo -e "已删除旧 /swapfile"
  fi

  echo -e "${Green}所有 swap 已清理完毕。${Font}"
}

# 创建新的 /swapfile
create_swapfile(){
  read -p "请输入新的虚拟内存大小(MB): " new_swap

  if ! [[ "$new_swap" =~ ^[0-9]+$ ]]; then
      echo -e "${Red}输入无效，请输入数字。${Font}"
      exit 1
  fi

  # 检测磁盘可用空间
  available_space=$(df --output=avail -m / | tail -1)
  if [ "$new_swap" -ge "$available_space" ]; then
      echo -e "${Red}错误：可用磁盘空间不足！可用空间 ${available_space} MB，无法创建 ${new_swap} MB 的 swap。${Font}"
      exit 1
  fi

  echo "正在创建 /swapfile..."
  dd if=/dev/zero of=/swapfile bs=1M count="$new_swap" status=progress
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile

  # 写入 fstab
  echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

  # Alpine 额外处理
  if [ -f /etc/alpine-release ]; then
      if ! grep -q "swapon /swapfile" /etc/local.d/swap.start 2>/dev/null; then
          echo "nohup swapon /swapfile" >> /etc/local.d/swap.start
      fi
      chmod +x /etc/local.d/swap.start
      rc-update add local
  fi

  # 确认挂载成功
  if swapon --show=NAME | grep -q "/swapfile"; then
      echo -e "${Green}/swapfile 已成功挂载并可在开机自动启用。${Font}"
  else
      echo -e "${Red}警告：/swapfile 挂载失败，请检查。${Font}"
  fi

  echo -e "虚拟内存大小已调整为 ${Green}${new_swap}${Font} MB"

  # 显示最新内存和 swap 使用情况
  echo -e "\n${Green}=== 当前内存和 swap 状态 ===${Font}"
  show_mem_swap
  echo -e "================================\n"
}

# 主菜单
main(){
    root_need
    ovz_no
    show_mem_swap

    read -p "是否清理所有 swap 并重新定义 /swapfile?(Y/N): " choice
    case "$choice" in
        [Yy])
            clear_all_swap
            create_swapfile
            ;;
        [Nn])
            echo "已取消"
            ;;
        *)
            echo -e "无效选择，请输入 ${Green}Y${Font} 或 ${Green}N${Font}。"
            ;;
    esac
}

main