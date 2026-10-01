#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
泡泡单词 E2E 回归测试报告邮件推送模块
使用阿里云邮件推送 (DirectMail) API 发送 HTML 测试报告
"""

import os
import sys
import argparse
import subprocess
import urllib.request
import urllib.parse
import hmac
import hashlib
import base64
import datetime
import uuid
import json

def get_env_var(name: str) -> str:
    """获取环境变量，若当前进程未导出则从 ~/.zprofile 加载"""
    val = os.environ.get(name)
    if val:
        return val
    try:
        cmd = f"source ~/.zprofile 2>/dev/null && echo ${name}"
        res = subprocess.run(["zsh", "-c", cmd], capture_output=True, text=True)
        return res.stdout.strip()
    except Exception:
        return ""

def percent_encode(s: str) -> str:
    res = urllib.parse.quote(str(s), safe="")
    res = res.replace("+", "%20").replace("*", "%2A").replace("%7E", "~")
    return res

def send_email_report(to_email: str, subject: str, html_content: str) -> bool:
    """调用阿里云邮件推送 SingleSendMail 接口"""
    ak = get_env_var("aliyun_access_key_id")
    sk = get_env_var("aliyun_access_key_secret")
    
    if not ak or not sk:
        print("[!] 错误: 未检测到 aliyun_access_key_id 或 aliyun_access_key_secret")
        return False
        
    from_address = "pp@nnbdc.com"
    from_alias = "泡泡单词"
    
    params = {
        "Format": "JSON",
        "Version": "2015-11-23",
        "AccessKeyId": ak,
        "SignatureMethod": "HMAC-SHA1",
        "Timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "SignatureVersion": "1.0",
        "SignatureNonce": uuid.uuid4().hex,
        "Action": "SingleSendMail",
        "AccountName": from_address,
        "ReplyToAddress": "false",
        "AddressType": "1",
        "ToAddress": to_email.strip(),
        "Subject": subject,
        "HtmlBody": html_content,
        "FromAlias": from_alias
    }
    
    # 构造规范化查询字符串并签名
    sorted_params = sorted(params.items(), key=lambda x: x[0])
    can_query = "&".join([f"{percent_encode(k)}={percent_encode(v)}" for k, v in sorted_params])
    string_to_sign = f"POST&%2F&{percent_encode(can_query)}"
    key = (sk + "&").encode("utf-8")
    sig = base64.b64encode(hmac.new(key, string_to_sign.encode("utf-8"), hashlib.sha1).digest()).decode("utf-8")
    params["Signature"] = sig
    
    data = urllib.parse.urlencode(params).encode("utf-8")
    req = urllib.request.Request("https://dm.aliyuncs.com/", data=data, method="POST")
    
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            resp_body = resp.read().decode("utf-8")
            resp_json = json.loads(resp_body)
            request_id = resp_json.get("RequestId", "unknown")
            print(f"[+] 邮件发送成功！收件人: {to_email} (RequestId: {request_id})")
            return True
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8")
        print(f"[!] 邮件发送失败 HTTP {e.code}: {err_msg}")
        return False
    except Exception as e:
        print(f"[!] 发送邮件异常: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description="发送泡泡单词 E2E 回归测试报告")
    parser.add_argument("--to", default="mmyybb3000@icloud.com", help="收件人邮箱")
    parser.add_argument("--report", default="/Volumes/ssd/ppdc/tmp/e2e_report/report.html", help="HTML 报告路径")
    parser.add_argument("--subject", default=None, help="邮件标题")
    args = parser.parse_args()
    
    if not os.path.exists(args.report):
        print(f"[!] 报告文件不存在: {args.report}")
        sys.exit(1)
        
    with open(args.report, "r", encoding="utf-8") as f:
        html = f.read()
        
    subject = args.subject or f"泡泡单词 Android E2E 全量自动化回归测试报告 ({datetime.datetime.now().strftime('%Y-%m-%d %H:%M')})"
    ok = send_email_report(args.to, subject, html)
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
