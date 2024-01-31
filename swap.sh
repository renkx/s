#!/usr/bin/env bash

Green="\033[32m"
Font="\033[0m"
Red="\033[31m" 

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

#开始菜单
main() {
  root_need
  ovz_no
  clear

  # 获取当前交换空间信息
  swap_used=$(free -m | awk 'NR==3{print $3}')
  swap_total=$(free -m | awk 'NR==3{print $2}')


  if [ "$swap_total" -eq 0 ]; then
    swap_percentage=0
  else
    swap_percentage=$((swap_used * 100 / swap_total))
  fi

  mem_info=$(free -b | awk 'NR==2{printf "%.2f/%.2f MB (%.2f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')
  swap_info="${swap_used}MB/${swap_total}MB (${swap_percentage}%)"

  echo "当前物理内存: ${Green}$mem_info${Font}"
  echo "当前虚拟内存: ${Green}$swap_info${Font}"

  read -p "是否调整虚拟内存大小?(Y/N): " choice

  case "$choice" in
    [Yy])
      # 输入新的虚拟内存大小
      read -p "请输入虚拟内存大小${Green}MB${Font}: " new_swap

      # 获取当前系统中所有的 swap 分区
      swap_partitions=$(grep -E '^/dev/' /proc/swaps | awk '{print $1}')

      # 遍历并删除所有的 swap 分区
      for partition in $swap_partitions; do
        swapoff "$partition"
        wipefs -a "$partition"  # 清除文件系统标识符
        mkswap -f "$partition"
        echo "已删除并重新创建 swap 分区: $partition"
      done

      # 确保 /swapfile 不再被使用
      swapoff /swapfile

      # 删除旧的 /swapfile
      rm -f /swapfile

      # 创建新的 swap 分区
      dd if=/dev/zero of=/swapfile bs=1M count=$new_swap
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile

      if [ -f /etc/alpine-release ]; then
          echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
          echo "nohup swapon /swapfile" >> /etc/local.d/swap.start
          chmod +x /etc/local.d/swap.start
          rc-update add local
      else
          echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
      fi

      echo "虚拟内存大小已调整为${Green}${new_swap}${Font}MB"
      ;;
    [Nn])
      echo "已取消"
      ;;
    *)
      echo "无效的选择，请输入 ${Green}Y${Font} 或 ${Green}N${Font}。"
      ;;
  esac
}
main