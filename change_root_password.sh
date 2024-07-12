#!/bin/bash

# 设置版本号
VERSION="0.17"

# 设置工作目录
WORK_DIR="/root/change-root-password"

# 检查并创建工作目录
if [ ! -d "$WORK_DIR" ]; then
    mkdir -p "$WORK_DIR"
    echo "创建工作目录: $WORK_DIR"
fi

# 检查脚本是否需要更新
SCRIPT_PATH="$WORK_DIR/change_root_password.sh"
TEMP_SCRIPT_PATH="$WORK_DIR/temp_change_root_password.sh"

# 下载最新的脚本
curl -s https://api.github.com/repos/sdars/change-root-password/contents/change_root_password.sh | jq -r .content | base64 -d > "$TEMP_SCRIPT_PATH"

# 比较版本号
NEW_VERSION=$(grep "^VERSION=" "$TEMP_SCRIPT_PATH" | cut -d'"' -f2)

if [ ! -f "$SCRIPT_PATH" ] || [ "$NEW_VERSION" != "$VERSION" ]; then
    mv "$TEMP_SCRIPT_PATH" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo "脚本已更新到版本 $NEW_VERSION"
    exec "$SCRIPT_PATH"
else
    rm "$TEMP_SCRIPT_PATH"
fi

echo "版本：$VERSION"
echo "本脚本只适用于快速改root密码抢别人送的vps，不适宜用于自用机子，更不适用于生产环境，如果你在自用机子和生产环境上使用本脚本导致无法连接上ssh，后果自负！！！"

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
   echo "脚本必须以root用户运行" 1>&2
   exit 1
fi

# 修改 SSH 配置的函数
modify_ssh_config() {
    local main_config="/etc/ssh/sshd_config"
    local include_dir="/etc/ssh/sshd_config.d"
    local config_files=("$main_config")

    # 检查是否有 include 指令
    if grep -q "^Include $include_dir/\*.conf" "$main_config"; then
        config_files+=("$include_dir"/*.conf)
    fi

    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            # 修改 PermitRootLogin
            if grep -q "^#*PermitRootLogin" "$file"; then
                sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$file"
            elif [ "$file" == "$main_config" ]; then
                echo "PermitRootLogin yes" >> "$file"
            fi

            # 修改 PasswordAuthentication
            if grep -q "^#*PasswordAuthentication" "$file"; then
                sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$file"
            elif [ "$file" == "$main_config" ]; then
                echo "PasswordAuthentication yes" >> "$file"
            fi
        fi
    done

    echo "SSH 配置已修改，现在允许使用密码进行 root SSH 登录。"
}

# 检查SSH设置并提供警告
check_root_login() {
    echo "当前SSH root登录设置:"
    
    local main_config="/etc/ssh/sshd_config"
    local include_dir="/etc/ssh/sshd_config.d"
    local config_files=("$main_config")
    
    if grep -q "^Include $include_dir/\*.conf" "$main_config"; then
        config_files+=("$include_dir"/*.conf)
    fi
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            grep -H -E "^#?PermitRootLogin|^#?PasswordAuthentication" "$file"
        fi
    done

    local permitRootLogin=$(grep -h "^#*PermitRootLogin" "${config_files[@]}" 2>/dev/null | tail -n1)
    local passwordAuthentication=$(grep -h "^#*PasswordAuthentication" "${config_files[@]}" 2>/dev/null | tail -n1)

    echo "解释："
    if [[ $permitRootLogin == \#* ]]; then
        echo "- PermitRootLogin: 被注释或未设置，使用默认值 (通常为 prohibit-password)"
    else
        permitRootLoginValue=${permitRootLogin#PermitRootLogin }
        case "$permitRootLoginValue" in
            "yes") echo "- PermitRootLogin yes: 允许root用户通过SSH登录" ;;
            "prohibit-password") echo "- PermitRootLogin prohibit-password: 禁止root用户使用密码登录SSH，但允许使用其他方式（如密钥）" ;;
            "no") echo "- PermitRootLogin no: 完全禁止root用户通过SSH登录" ;;
            *) echo "- PermitRootLogin: 未找到有效设置，使用默认值 (通常为 prohibit-password)" ;;
        esac
    fi

    if [[ $passwordAuthentication == \#* ]]; then
        echo "- PasswordAuthentication: 被注释或未设置，使用默认值 (通常为 yes)"
    else
        passwordAuthenticationValue=${passwordAuthentication#PasswordAuthentication }
        case "$passwordAuthenticationValue" in
            "yes") echo "- PasswordAuthentication yes: 允许使用密码进行SSH认证" ;;
            "no") echo "- PasswordAuthentication no: 禁止使用密码进行SSH认证，只能使用密钥等其他方式" ;;
            *) echo "- PasswordAuthentication: 未找到有效设置，使用默认值 (通常为 yes)" ;;
        esac
    fi

   echo "总结："
    if [[ $permitRootLogin != \#* && "${permitRootLogin#PermitRootLogin }" == "yes" ]] && 
       [[ $passwordAuthentication == \#* || "${passwordAuthentication#PasswordAuthentication }" != "no" ]]; then
        echo "当前设置可能允许使用密码进行root SSH登录。"
        return 0
    else
        echo "警告：当前设置可能不允许使用密码进行root SSH登录。"
        echo "修改root密码可能对SSH登录没有实际影响。"
        echo "按 Enter 键修改 SSH 配置以允许密码登录，或按任意其他键退出脚本。"
        read -n 1 -s -r key
        if [ -z "$key" ]; then
            modify_ssh_config
            return 0
        else
            echo "脚本已退出。"
            exit 0
        fi
    fi
}

# 执行检查
check_root_login

# 生成随机密码的函数
generate_password() {
    tr -dc A-Za-z0-9_\!\@\#\$\%\^\&\*\(\)-+= < /dev/urandom | head -c 16
}

# 提示用户选择
echo "按 Enter 键生成随机密码，或按任意其他键自定义密码。"
read -n 1 -s -r key

# 替换原来的 read 命令
if [ -t 0 ]; then
    # 终端是交互式的
    read -n 1 -s -r -t 60 key
else
    # 非交互式环境，等待一段时间给用户机会输入
    read -n 1 -s -r -t 10 key
fi

if [ -z "$key" ]; then
    # 生成随机密码
    new_password=$(generate_password)
    echo "生成了新的root密码:$new_password"
else
    # 使用自定义密码
    echo -e "\n请输入新的root密码：（输入不显示内容是正常的）"
    read -s new_password
    echo "请再次输入新的root密码：（输入不显示内容是正常的）"
    read -s new_password_confirm
    
    if [ "$new_password" != "$new_password_confirm" ]; then
        echo "两次输入的密码不匹配，请重新运行脚本。"
        exit 1
    fi
fi


# 更改 root 密码
echo "root:$new_password" | chpasswd

# 检查密码是否成功更改
if [ $? -eq 0 ]; then
    echo "root密码已经被成功更改为:$new_password"
else
    echo "更改root密码失败，请重试"
    exit 1
fi

# 重启SSH服务
restart_ssh() {
    if systemctl is-active --quiet ssh; then
        systemctl restart ssh
    elif systemctl is-active --quiet sshd; then
        systemctl restart sshd
    else
        echo "警告：无法自动重启 SSH 服务。请手动重启 SSH 服务以应用更改。"
        echo "您可以尝试运行以下命令之一："
        echo "  sudo systemctl restart ssh"
        echo "  sudo systemctl restart sshd"
        echo "  sudo service ssh restart"
        echo "  sudo service sshd restart"
        return 1
    fi
    return 0
}

# 调用重启函数
if restart_ssh; then
    echo "SSH 服务已重启。"
else
    echo "请在重启 SSH 服务后，使用新密码尝试登录。"
fi

echo "SSH服务已重启，请确保你已经保存了这个新的root密码:$new_password"
echo "建议不要直接断开ssh重连，而是新开一个ssh窗口连接尝试新密码是否生效，这样更安全！"
