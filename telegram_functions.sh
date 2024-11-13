#!/usr/bin/env bash
upload_file()
{
    local file="$1"
    local msg="$2"

    if [[ -f "$file" ]]; then
        chmod 777 "$file"
    else
        echo "[ERROR] file $file doesn't exist"
        exit 1
    fi

    curl -s -F document=@"$file" "https://api.telegram.org/bot$token/sendDocument" \
        -F chat_id="$chat_id" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=markdown" \
        -F caption="$msg" \
        -o /dev/null
}

send_msg()
{
local msg="$1"
curl -s -X POST "https://api.telegram.org/bot$token/sendMessage" \
    -d chat_id="$chat_id" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=markdown" \
    -d text="$msg" \
    -o /dev/null
}