#!/bin/bash

# 颜色输出函数
red() { echo -e "\e[91m$*\e[0m"; }
green() { echo -e "\e[92m$*\e[0m"; }
yellow() { echo -e "\e[93m$*\e[0m"; }
magenta() { echo -e "\e[95m$*\e[0m"; }
cyan() { echo -e "\e[96m$*\e[0m"; }
info() { echo -e "\e[97m$*\e[0m"; }

# 检查root权限
[[ $(id -u) != 0 ]] && red "\n 错误：请使用root用户运行本脚本\n" && exit 1

# 全局配置
cmd="apt-get"
author="ADS"
_repo="shadowsocks/go-shadowsocks2"
_bin_name="shadowsocks2-linux"
_cache_dir="/tmp/ss-download"
# 安装目录
_dir='/usr/bin/shadowsocks-go'
_file="${_dir}/shadowsocks-go"
_sh="/usr/local/sbin/ssgo"
# 其它
_log="${_dir}/shadowsocks-go.log"
_backup="${_dir}/backup.conf"
_pid=$(pgrep -f "$_file")
_status="$(systemctl is-active shadowsocks-go >/dev/null 2>&1 && green "运行中" || red "未运行")"

# GitHub API配置
_github_api="https://api.github.com/repos/$_repo/releases"
_user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 创建缓存目录
mkdir -p "$_cache_dir"
chmod 700 "$_cache_dir"

# 检测系统兼容性
if [[ -f /usr/bin/apt-get || -f /usr/bin/yum ]] && [[ -f /bin/systemctl ]]; then
    [[ -f /usr/bin/yum ]] && cmd="yum"
else
    red "\n不支持的操作系统\n" && exit 1
fi

# 加密协议列表
ciphers=(
    AEAD_AES_128_GCM
    AEAD_AES_256_GCM
    AEAD_CHACHA20_POLY1305
)

# 加载备份配置
if [[ -f $_backup ]]; then
    source "$_backup"
else
    [[ $1 != "install" ]] && red "\n未找到安装配置，请先运行 *.sh install\n" && exit 1
fi

# 版本比较函数
version_compare() {
    local v1=$(echo "$1" | sed 's/^v//')
    local v2=$(echo "$2" | sed 's/^v//')

    if [[ "$v1" == "$v2" ]]; then
        return 0
    fi

    local IFS=.
    local i ver1=($v1) ver2=($v2)

    # 填充空版本号为0
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

# 获取IP地址
get_ip() {
    ip=$(curl -s4m8 https://ipinfo.io/ip)
    [[ -z $ip ]] && red "\n无法获取服务器IP地址\n" && exit 1
}

# 错误处理
error() {
    red "\n输入错误！\n"
    sleep 1
}

# 暂停等待用户确认
pause() {
    read -rsp "$(info "按$(green "Enter")继续或$(red "Ctrl+C")取消")" -d $'\n'
    echo
}

# 显示配置信息
show_info() {
    [[ -z $ip ]] && get_ip
    local ss_uri="ss://$(echo -n "${ssciphers}:${sspass}@${ip}:${ssport}" | base64 -w 0)#${author}_ss"

    green "\n════════ Shadowsocks 配置信息 ════════"
    info "服务器地址: $(cyan "$ip")"
    info "服务器端口: $(cyan "$ssport")"
    info "密码: $(cyan "$sspass")"
    info "加密协议: $(cyan "$ssciphers")"
    info "SS链接: $(cyan "$ss_uri")"
    info "\n提示: 使用 $(cyan "ssgo qr") 生成二维码"
    green "══════════════════════════════════\n"
}

# 获取所有可用版本
get_all_versions() {
    green "\n▶ 获取可用版本..."

    # 获取JSON数据
    local releases_json=$(curl -H 'Cache-Control: no-cache' -H "User-Agent: $_user_agent" -fsSL "$_github_api")
    [[ -z $releases_json ]] && red "获取版本信息失败" && return 1

    # 解析版本信息
    local versions=()
    local download_urls=()
    local count=1

    # 使用jq处理JSON数据
    while IFS=$'\t' read -r tag_name download_url; do
        versions+=("$tag_name")
        download_urls+=("$download_url")
        info " $(yellow "$count.") $(cyan "$tag_name")"
        ((count++))
    done < <(echo "$releases_json" | jq -r '.[] | select(.assets[]?.name | contains("linux")) | "\(.tag_name)\t\(.assets[] | select(.name | contains("linux")) | .browser_download_url)"')

    [[ ${#versions[@]} -eq 0 ]] && red "没有找到可用版本" && return 1

    # 选择版本
    while :; do
        read -p "请选择版本 [1-${#versions[@]}]: " ver_choice
        [[ -z $ver_choice ]] && continue
        if [[ $ver_choice =~ ^[0-9]+$ ]] && (( ver_choice >= 1 && ver_choice <= ${#versions[@]} )); then
            selected_ver=${versions[$((ver_choice-1))]}
            download_url=${download_urls[$((ver_choice-1))]}
            break
        fi
        red "无效选择! 请输入1到${#versions[@]}之间的数字"
    done

    green "\n已选择版本: $(cyan "$selected_ver")"
    yellow "下载链接: $(cyan "$download_url")"
    yellow "可手动上传 ${_bin_name}-${selected_ver}.gz 至${_cache_dir}目录下\n"
    ver="$selected_ver"
    _download_url="$download_url"
    return 0
}

# 下载并验证核心
download_and_verify() {
    local version="$1"
    local download_url="$2"
    local output_file="$3"

    # 准备临时文件
    local tmp_gz="${_cache_dir}/${_bin_name}-${version}.gz"
    local tmp_bin="${_cache_dir}/${_bin_name}-${version}"

    # 检查本地缓存是否存在且完整
    if [[ -f "$tmp_gz" ]]; then
        green "发现本地缓存文件，将使用缓存安装"
        if ! gzip -t "$tmp_gz" 2>/dev/null; then
            yellow "缓存文件损坏，将重新下载..."
            rm -f "$tmp_gz"
        fi
    fi

    # 如果本地没有有效缓存，则下载
    if [[ ! -f "$tmp_gz" ]]; then
        yellow "\n从以下链接下载:\n$(cyan "$download_url")"
        if ! wget --no-check-certificate --show-progress -q --connect-timeout 30 -O "$tmp_gz" "$download_url"; then
            red "下载失败"
            return 1
        fi

        # 验证下载的文件
        if ! gzip -t "$tmp_gz" 2>/dev/null; then
            red "下载的文件已损坏"
            rm -f "$tmp_gz"
            return 1
        fi

        green "下载完成"
    fi

    info "\n解压中..."

    # 解压文件
    if ! gzip -d "$tmp_gz" || [[ ! -f "$tmp_bin" ]]; then
        red "解压失败"
        return 1
    fi

    green "解压完成"

    # 移动到目标位置
    if ! mv -f "$tmp_bin" "$output_file"; then
        red "移动文件失败"
        return 1
    fi

    chmod +x "$output_file"

    return 0
}

# 安装核心
install_core() {
    green "\n▶ 正在安装Shadowsocks核心 $ver..."

    mkdir -p "$_dir"

    if ! download_and_verify "$ver" "$_download_url" "$_file"; then
        return 1
    fi

    return 0
}

# 更新核心
update_core() {
    if ! get_all_versions; then
        return 1
    fi

    # 获取当前版本
    local current_ver=$($_file -version 2>/dev/null | awk '{print $2}' || echo "0.0.0")
    local selected_ver="$ver"

    # 版本比较
    version_compare "$selected_ver" "$current_ver"
    case $? in
        0) yellow "已经是最新版本" && return 0 ;;
        1) yellow "将升级到新版本 $selected_ver" ;;
        2) yellow "警告: 将降级到旧版本 $selected_ver" ;;
    esac

    yellow "\n▶ 开始更新到 $selected_ver ..."
    pause

    # 停止服务
    systemctl stop shadowsocks-go >/dev/null 2>&1

    # 备份旧版本
    local backup_file="${_file}_backup_$(date +%Y%m%d)"
    [[ -f $_file ]] && cp -f "$_file" "$backup_file" && yellow "已备份: $backup_file"

    # 下载和安装
    if ! download_and_verify "$ver" "$_download_url" "$_file"; then
        red "更新失败，正在恢复..."
        [[ -f "$backup_file" ]] && mv -f "$backup_file" "$_file"
        systemctl start shadowsocks-go
        return 1
    fi

    # 更新配置版本号
    [[ -f $_backup ]] && sed -i "1s/=$current_ver/=$ver/" "$_backup"

    # 重启服务
    systemctl start shadowsocks-go
    sleep 1

    # 验证安装
    local installed_ver=$($_file -version 2>/dev/null | awk '{print $2}')
    if [[ "$installed_ver" == "$selected_ver" ]]; then
        green "\n✔ 成功更新到 $selected_ver\n"
        _status="$(green "运行中")"
    else
        red "\n✘ 更新失败，正在恢复..."
        [[ -f "$backup_file" ]] && mv -f "$backup_file" "$_file"
        systemctl start shadowsocks-go
        return 1
    fi
}

# 服务管理
service_management() {
    # 确保日志目录权限正确
    mkdir -p "$(dirname "$_log")"
    touch "$_log"
    chown nobody:nogroup "$_log"
    chmod 644 "$_log"

    cat >/lib/systemd/system/shadowsocks-go.service <<-EOF
[Unit]
Description=Shadowsocks-Go Service
After=network.target

[Service]
Type=simple
PIDFile=/var/run/shadowsocks-go.pid
ExecStart=/bin/bash -c "exec $_file -s 'ss://${ssciphers}:${sspass}@:${ssport}' -verbose &>> $_log"
User=nobody
Group=nogroup
Restart=always
RestartSec=3
LimitNOFILE=1048576

# 显式声明日志输出路径（systemd v240+版本支持）
StandardOutput=append:$_log
StandardError=append:$_log

# 如果系统版本较旧，改用以下方式
# ExecStartPre=/bin/bash -c "echo 'Service starting at \$(date)' >> $_log"
# ExecStart=$_file -s 'ss://${ssciphers}:${sspass}@:${ssport}' -verbose >> $_log 2>&1

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now shadowsocks-go
}

# 获取用户配置
get_user_config() {
    # 端口配置
    local default_port=$(shuf -i 20000-60000 -n1)
    while :; do
        read -p "输入端口 [1-65535] (默认: $default_port): " ssport
        [[ -z $ssport ]] && ssport=$default_port
        [[ $ssport =~ ^[0-9]+$ ]] && (( ssport >= 1 && ssport <= 65535 )) && break
        red "无效端口号!"
    done

    # 密码配置
    local default_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    while :; do
        read -p "输入密码 (默认: $default_pass): " sspass
        [[ -z $sspass ]] && sspass=$default_pass
        [[ "$sspass" =~ [^/$] ]] && break
        red "密码不能包含 / 或 $ 字符!"
    done

    # 加密协议选择
    info "\n选择加密协议:"
    for i in "${!ciphers[@]}"; do
        info "  $((i+1)). ${ciphers[$i]}"
    done
    while :; do
        read -p "选择 [1-${#ciphers[@]}] (默认 3): " ssciphers_opt
        [[ -z $ssciphers_opt ]] && ssciphers_opt=3
        [[ $ssciphers_opt =~ ^[1-3]$ ]] && break
        red "无效选择!"
    done
    ssciphers=${ciphers[$((ssciphers_opt-1))]}
}

# 创建备份配置
create_backup() {
    cat >"$_backup" <<-EOF
ver=$ver
ssport=$ssport
sspass=$sspass
ssciphers=$ssciphers
EOF
}

# 生成二维码
generate_qr() {
    [[ -z $ip ]] && get_ip
    local ss_uri="ss://$(echo -n "${ssciphers}:${sspass}@${ip}:${ssport}" | base64 -w 0)"
    local qr_url="https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=$ss_uri"

    green "\nShadowsocks 二维码:"
    cyan "$qr_url"
    info "\n扫描二维码或手动输入以下配置:"
    show_info
}

# 启动服务
start_service() {
	systemctl daemon-reload
    systemctl start shadowsocks-go
    if systemctl is-active --quiet shadowsocks-go; then
        green "服务已启动"
        _status="$(green "运行中")"
    else
        red "服务启动失败"
        _status="$(red "未运行")"
    fi
    sleep 1
}

# 重启服务
restart_service() {
	systemctl daemon-reload
	systemctl restart shadowsocks-go
	if systemctl is-active --quiet shadowsocks-go; then
        green "服务已启动"
        _status="$(green "运行中")"
    else
        red "服务启动失败"
        _status="$(red "未运行")"
    fi
    sleep 1
}

# 停止服务
stop_service() {
    systemctl stop shadowsocks-go
    if ! systemctl is-active --quiet shadowsocks-go; then
        yellow "服务已停止"
        _status="$(yellow "已停止")"
    else
        red "服务停止失败"
    fi
    sleep 1
}

# 状态检查
status_check() {
    if systemctl is-active --quiet shadowsocks-go; then
        _status="$(green "运行中")"
        local pid=$(pgrep -f "$_file")
        local mem_usage=$(ps -p $pid -o %mem --no-headers)
        local cpu_usage=$(ps -p $pid -o %cpu --no-headers)
        local runtime=$(ps -p $pid -o etime --no-headers)
        
        green "\n════════ Shadowsocks 服务状态 ════════"
        info " 状态: $_status"
        info " PID: $(cyan "$pid")"
        info " 内存占用: $(cyan "${mem_usage}%")"
        info " CPU占用: $(cyan "${cpu_usage}%")"
        info " 运行时间: $(cyan "$runtime")"
        green "══════════════════════════════════\n"
        
        # 显示最近日志
        green "════════ 最近日志 (最后10行) ════════"
        if [[ -f $_log ]]; then
            tail -n 10 "$_log" | while read -r line; do
                info " $line"
            done
        else
            yellow " 未找到日志文件"
        fi
        green "══════════════════════════════════\n"
        return 0
    else
        _status="$(red "未运行")"
        red "\nShadowsocks 服务未运行\n"
        return 1
    fi
}

# 修改配置
modify_config() {
    [[ ! -f $_backup ]] && red "\n未找到安装配置\n" && return 1

    green "\n════════ 修改 Shadowsocks 配置 ════════"
    
    # 显示当前配置
    info "当前配置:"
    info "1. 端口: $(cyan "$ssport")"
    info "2. 密码: $(cyan "$sspass")"
    info "3. 加密协议: $(cyan "$ssciphers")"
    green "══════════════════════════════════"
    
    # 选择要修改的项
    while :; do
        read -p "选择要修改的项 [1-3] (0取消): " config_choice
        case $config_choice in
            0) yellow "\n取消修改\n"; return 1 ;;
            1|2|3) break ;;
            *) error ;;
        esac
    done

    # 修改端口
    if [[ $config_choice == 1 ]]; then
        local default_port=$(shuf -i 20000-60000 -n1)
        while :; do
            read -p "输入新端口 [1-65535] (默认: $default_port): " new_port
            [[ -z $new_port ]] && new_port=$default_port
            [[ $new_port =~ ^[0-9]+$ ]] && (( new_port >= 1 && new_port <= 65535 )) && break
            red "无效端口号!"
        done
        ssport=$new_port
    fi

    # 修改密码
    if [[ $config_choice == 2 ]]; then
        local default_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
        while :; do
            read -p "输入新密码 (默认: $default_pass): " new_pass
            [[ -z $new_pass ]] && new_pass=$default_pass
            [[ "$new_pass" =~ [^/$] ]] && break
            red "密码不能包含 / 或 $ 字符!"
        done
        sspass=$new_pass
    fi

    # 修改加密协议
    if [[ $config_choice == 3 ]]; then
        info "\n选择加密协议:"
        for i in "${!ciphers[@]}"; do
            info "  $((i+1)). ${ciphers[$i]}"
        done
        while :; do
            read -p "选择 [1-${#ciphers[@]}] (当前 ${ssciphers}): " new_cipher
            [[ -z $new_cipher ]] && continue
            [[ $new_cipher =~ ^[1-3]$ ]] && break
            red "无效选择!"
        done
        ssciphers=${ciphers[$((new_cipher-1))]}
    fi

    # 确认修改
    green "\n════════ 新配置确认 ════════"
    info "端口: $(cyan "$ssport")"
    info "密码: $(cyan "$sspass")"
    info "加密协议: $(cyan "$ssciphers")"
    green "════════════════════════════"
    
    while :; do
        read -p "$(info "确认修改配置? [$(red "Y")/$(green "N")]") " confirm
        case $confirm in
            [Yy])
                # 更新备份文件
                create_backup
                
                # 重启服务应用新配置
                systemctl restart shadowsocks-go
                sleep 1
                
                green "\n✔ 配置已更新\n"
                show_info
                return 0
                ;;
            [Nn])
                yellow "\n取消修改\n"
                return 1
                ;;
            *) error ;;
        esac
    done
}

# 安装
install() {
    [[ -f $_backup ]] && yellow "已经安装过Shadowsocks" && return 1

    green "\n════════ Shadowsocks 安装向导 ════════"

    # 选择版本
    if ! get_all_versions; then
        return 1
    fi

    get_user_config

    # 确认安装
    green "\n════════ 安装信息确认 ════════"
    info "版本: $(cyan "$ver")"
    info "端口: $(cyan "$ssport")"
    info "密码: $(cyan "$sspass")"
    info "加密协议: $(cyan "$ssciphers")"
    green "════════════════════════════"
    pause

    # 执行安装
    if ! install_core; then
        red "核心安装失败"
        return 1
    fi

    create_backup

    # 创建管理脚本链接
    script_path=$(readlink -f "$0")
    ln -sf "$script_path" "$_sh"
    chmod +x "$_sh"

    # 设置服务
    service_management

    green "\n✔ 安装完成\n"
    show_info
}

# 重新安装
reinstall() {
    green "\n════════ Shadowsocks 重新安装向导 ════════"
    
    # 检查是否已安装
    if [[ ! -f $_backup ]]; then
        red "\n未找到安装配置，请先运行 install 安装\n"
        return 1
    fi

    # 询问是否保留配置
    local keep_config="N"
    while :; do
        read -p "$(info "是否保留当前配置? [$(green "Y")/$(red "N")]") " keep_config
        case $keep_config in
            [Yy]|[Nn]) break ;;
            *) error ;;
        esac
    done

    # 停止服务
    systemctl stop shadowsocks-go >/dev/null 2>&1

    # 备份旧配置
    local backup_file="${_backup}_$(date +%Y%m%d%H%M%S).bak"
    cp -f "$_backup" "$backup_file" 2>/dev/null
    yellow "\n已备份配置到: $backup_file"

    # 选择版本
    if ! get_all_versions; then
        return 1
    fi

    # 如果需要新配置，获取用户输入
    if [[ $keep_config =~ [Nn] ]]; then
        get_user_config
    fi

    # 确认信息
    green "\n════════ 重新安装信息确认 ════════"
    info "版本: $(cyan "$ver")"
    info "端口: $(cyan "$ssport")"
    info "密码: $(cyan "$sspass")"
    info "加密协议: $(cyan "$ssciphers")"
    green "════════════════════════════"
    pause

    # 下载并安装新版本
    if ! download_and_verify "$ver" "$_download_url" "$_file"; then
        red "重新安装失败"
        return 1
    fi

    # 更新配置
    create_backup

    # 重新设置服务
    service_management

    green "\n✔ 重新安装完成\n"
    show_info
}

# 卸载
uninstall() {
    while :; do
        read -p "$(info "确定要卸载Shadowsocks吗？[$(red "Y")/$(green "N")]") " confirm
        case $confirm in
            [Yy])
                systemctl stop shadowsocks-go
                systemctl disable shadowsocks-go >/dev/null 2>&1
                rm -rf "$_dir" /lib/systemd/system/shadowsocks-go.service
                [[ -L "$_sh" ]] && rm -f "$_sh"
                green "\n✔ 卸载完成\n"
                return 0
                ;;
            [Nn])
                yellow "\n取消卸载\n"
                return 1
                ;;
            *) error ;;
        esac
    done
}

# 查看日志
view_log() {
    if [[ ! -f $_log ]]; then
        red "\n未找到日志文件\n"
        return 1
    fi

    local choice=""
    local lines=20
    
    green "\n════════ 日志查看选项 ════════"
    info " 1. 查看最后20行日志"
    info " 2. 查看最后50行日志"
    info " 3. 查看最后100行日志"
    info " 4. 实时查看日志 (Ctrl+C退出)"
    info " 5. 清空日志文件"
    info " 0. 返回主菜单"
    green "══════════════════════════════════"
    
    while :; do
        read -p "请选择操作 [0-5]: " choice
        case $choice in
            1) lines=20; break ;;
            2) lines=50; break ;;
            3) lines=100; break ;;
            4) lines="follow"; break ;;
            5) lines="clear"; break ;;
            0) return 0 ;;
            *) error ;;
        esac
    done

    case $lines in
        "follow")
            green "\n开始实时日志查看 (按Ctrl+C退出)...\n"
            tail -f "$_log"
            ;;
        "clear")
            echo "" > "$_log"
            green "\n日志文件已清空\n"
            ;;
        *)
            green "\n════════ 最后${lines}行日志 ════════"
            tail -n $lines "$_log" | while read -r line; do
                info " $line"
            done
            green "══════════════════════════════════\n"
            ;;
    esac
    
    pause
}

# 显示帮助信息
show_help() {
    green "════════ Shadowsocks 管理脚本帮助 ════════"
    info " 命令:"
    info "  install       - 安装Shadowsocks"
    info "  reinstall     - 重新安装Shadowsocks"
    info "  update        - 更新Shadowsocks核心"
    info "  start         - 启动服务"
    info "  stop          - 停止服务"
    info "  restart       - 重启服务"
    info "  status | S    - 查看服务状态"
    info "  info   | I    - 显示配置信息"
    info "  config        - 修改配置"
	info "  log    | L    - 查看日志"
    info "  qr            - 生成二维码"
    info "  uninstall     - 卸载Shadowsocks"
    info "  menu          - 显示交互式菜单"
    info "  help          - 显示此帮助信息"
    green "══════════════════════════════════"
}

# 主菜单
menu() {
    while :; do
        clear
        green "════════ Shadowsocks 管理菜单 ════════"
        info " 状态: $_status"
        green "══════════════════════════════════"
        info " 1. 查看状态"
        info " 2. 查看配置"
        info " 3. 修改配置"
        info " 4. 启动服务"
        info " 5. 停止服务"
        info " 6. 重启服务"
        info " 7. 查看日志"
        info " 8. 更新核心"
        info " 9. 生成二维码"
        info "10. 重新安装"
        info "11. 卸载"
        info " 0. 退出"
        green "══════════════════════════════════"
        read -p "请选择 [0-11]: " choice

        case $choice in
            1) status_check; pause ;;
            2) show_info; pause ;;
            3) modify_config ;;
            4) start_service ;;
            5) stop_service ;;
            6) restart_service ;;
            7) view_log ;;
            8) update_core; pause ;;
            9) generate_qr; pause ;;
            10) reinstall; pause ;;
            11) uninstall; break ;;
            0) exit 0 ;;
            *) error ;;
        esac
    done
}


# 主程序
case $1 in
    install) install;;
    reinstall) reinstall;;
    update) update_core;;
    start) start_service;;
    stop) stop_service;;
    restart) restart_service;;
    status | S) status_check;;
    info | I) show_info;;
    config) modify_config;;
    log | L) view_log;;
    qr) generate_qr;;
    menu|"") menu;;
    help) show_help;;
    *) show_help;;
esac