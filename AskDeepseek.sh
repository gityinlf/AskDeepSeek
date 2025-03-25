#!/bin/bash

# 定义历史记录路径和文件
HISTORY_PATH="$HOME"  # 历史记录存放目录，默认为用户根目录
# 请按照以下步骤获取并设置您的DeepSeek API密钥:
# 1. 访问 https://platform.deepseek.com/
# 2. 登录您的账号
# 3. 进入API密钥管理页面
# 4. 创建新的API密钥或复制现有密钥
# 5. 将密钥粘贴到下方引号中替换YOUR_API_KEY
DeepSeekAPIKey="YOUR_API_KEY"
MaXTime=60 # 最大等待时间，单位为秒

# 检查API密钥
if [ -z "${DeepSeekAPIKey}" ] || [ "${DeepSeekAPIKey}" == "YOUR_API_KEY" ]; then
    echo "错误: 请先设置有效的DeepSeek API密钥"
    echo "1. 访问DeepSeek官网获取API密钥"
    echo "2. 编辑本脚本，修改DeepSeekAPIKey变量的值"
    exit 1
fi


# 确保目录存在
mkdir -p "$HISTORY_PATH"

# 检查参数
if [ "$1" == "new" ]; then
    # 创建新的历史记录文件
    HISTORY_FILE="$HISTORY_PATH/.deepseek_history_$(date +%Y%m%d_%H%M%S).txt"
    echo "创建新的对话记录: $HISTORY_FILE"
    > "$HISTORY_FILE"
else
    # 查找最新的历史文件
    HISTORY_FILE=$(find "$HISTORY_PATH" -maxdepth 1 -name '.deepseek_history_*' -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d' ')
    
    # 如果没有找到历史文件，创建默认的
    if [ -z "$HISTORY_FILE" ]; then
        HISTORY_FILE="$HISTORY_PATH/.deepseek_history_$(date +%Y%m%d).txt"
        > "$HISTORY_FILE"
    fi
fi

# 读取用户输入
read -p "请输入您的问题: " user_input

# 读取历史文件内容作为上下文
messages=""
if [ -f "$HISTORY_FILE" ]; then
    messages=$(cat "$HISTORY_FILE")
fi

# 准备消息历史
messages_json='{"role": "system", "content": "You are a helpful assistant."}'

# 转换历史记录格式
if [ -f "$HISTORY_FILE" ]; then
    while IFS= read -r line; do
        if [[ "$line" == "用户: "* ]]; then
            content=${line#用户: }
            messages_json+=",{\"role\": \"user\", \"content\": \"${content//\"/\\\"}\"}"
        elif [[ "$line" == "AI: "* ]]; then
            content=${line#AI: }
            messages_json+=",{\"role\": \"assistant\", \"content\": \"${content//\"/\\\"}\"}"
        fi
    done < "$HISTORY_FILE"
fi

# 添加当前用户输入
messages_json+=",{\"role\": \"user\", \"content\": \"${user_input//\"/\\\"}\"}"


# 调用DeepSeek API
echo "正在调用API..."
echo $messages_json
response=$(curl -s --max-time ${MaXTime} https://api.deepseek.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DeepSeekAPIKey}" \
  -d '{
        "model": "deepseek-chat",
        "messages": ['"$messages_json"'],
        "stream": false
      }')

echo "API调用完成，处理响应..."

# 解析API响应
if [ $? -eq 0 ]; then
    if command -v jq &> /dev/null; then
        answer=$(echo "$response" | jq -r '.choices[0].message.content')
    else
        answer=$(echo "$response" | grep -ozP '"content":\s*"\K[^\x22]*' | tr -d '\0')
    fi
    
    if [ -n "$answer" ]; then
        clean_answer=$(echo "$answer" | tr -d '\n' | sed 's/\\n/\n/g')
        echo "$clean_answer"
    else
        echo "错误: 无法解析API响应"
        echo "原始响应:"
        echo "$response"
        exit 1
    fi
else
    echo "错误: API调用失败"
    exit 1
fi

# 保存当前对话到历史文件
echo "用户: $user_input" >> "$HISTORY_FILE"
echo "AI: $answer" >> "$HISTORY_FILE"

echo "对话已保存到 $HISTORY_FILE"
