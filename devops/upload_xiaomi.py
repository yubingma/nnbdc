#!/usr/bin/env python3
"""小米应用商店「应用自动发布接口」客户端。

接口文档: https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1134
  - 应用包查询: POST https://api.developer.xiaomi.com/devupload/dev/query
  - 应用推送:   POST https://api.developer.xiaomi.com/devupload/dev/push

SIG 签名三步：
  1. 计算每个参与参数的 MD5（文件算整个文件的 MD5，小写 32 位）；
  2. 拼成 {"sig":[{"name":...,"hash":...}],"password":私钥}；
  3. 用小米下发的公钥证书做 RSA/ECB/PKCS1Padding 分段加密，输出小写 16 进制字符串。

传输使用 curl：RequestData/SIG 用 --form-string 传（不做 @、; 等字符解释），
apk 等文件用 -F 传。小米服务端会丢弃不带 Expect: 100-continue 的大文件 multipart 请求体，
curl 默认对 multipart 发送该头，且这正是小米文档给出的官方示例客户端。
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys

API_BASE = "https://api.developer.xiaomi.com/devupload"
CURL_MAX_TIME = str(130 * 60)

# 文档「4、常见错误码」中与正常发布相关的部分
ERROR_HINTS = {
    -10000: "参数格式或公钥加密方式不对，请对照文档示例检查",
    -2: "appInfo.packageName 与 APK 内解析出的包名不一致",
    -20014: "私钥错误。请在「自动发布接口」页面点击获取私钥，重置后旧私钥立即失效",
    -32: "该包名尚未在小米开放平台创建，需先创建包名/完成应用认领后才能上传 APK",
    -92: "APK 不满足要求（例如同版本同 APK 重复更新）",
    -20002: "数字签名异常，请检查 SIG 明文拼接与公钥是否正确",
    -20029: "RequestData 不是合法 JSON",
    -20030: "SIG 的明文参数不是合法 JSON",
}


def md5_text(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest()


def md5_file(path):
    digest = hashlib.md5()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def compact_json(value):
    """生成参与 MD5 的 JSON 字符串：必须与实际发送的字符串完全一致。"""
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def rsa_encrypt(plain_text, cert_path):
    """用小米下发的公钥证书做 PKCS1 分段加密，返回小写 16 进制字符串。"""
    from cryptography import x509
    from cryptography.hazmat.primitives.asymmetric import padding

    with open(cert_path, "rb") as f:
        raw = f.read()
    try:
        certificate = x509.load_pem_x509_certificate(raw)
    except ValueError:
        certificate = x509.load_der_x509_certificate(raw)

    public_key = certificate.public_key()
    block_size = public_key.key_size // 8 - 11  # PKCS1 填充固定占用 11 字节
    data = plain_text.encode("utf-8")
    encrypted = b"".join(
        public_key.encrypt(data[i:i + block_size], padding.PKCS1v15())
        for i in range(0, len(data), block_size)
    )
    return encrypted.hex()


def call_api(path, request_data_json, private_key, public_key_path, files=None):
    """按小米协议调用一个接口，返回解析后的 JSON。"""
    entries = [("RequestData", md5_text(request_data_json))]
    for name, file_path in (files or {}).items():
        entries.append((name, md5_file(file_path)))
    sig = rsa_encrypt(compact_json({"sig": [{"name": n, "hash": h} for n, h in entries],
                                    "password": private_key}), public_key_path)

    cmd = ["curl", "-sS", "--connect-timeout", "30", "--max-time", CURL_MAX_TIME,
           "--form-string", f"RequestData={request_data_json}",
           "--form-string", f"SIG={sig}"]
    for name, file_path in (files or {}).items():
        cmd += ["-F", f"{name}=@{file_path}"]
    cmd.append(f"{API_BASE}{path}")

    result = subprocess.run(cmd, capture_output=True, text=True)
    body = result.stdout.strip()
    if result.returncode != 0 or not body:
        raise SystemExit(f"❌ 调用 {path} 失败 (curl 退出码 {result.returncode}): {result.stderr.strip()}")
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        raise SystemExit(f"❌ 调用 {path} 返回了非 JSON 内容: {body[:500]}")


def check_result(response, action):
    code = response.get("result")
    message = response.get("message") or "无返回消息"
    if code != 0:
        hint = ERROR_HINTS.get(code)
        detail = f"\n   排查提示: {hint}" if hint else ""
        raise SystemExit(f"❌ {action}失败: {message} (result={code}){detail}")
    print(f"✅ {action}成功: {message}")


def query_app(args):
    request_data = compact_json({"packageName": args.package_name, "userName": args.account})
    response = call_api("/dev/query", request_data, args.private_key, args.public_key)
    check_result(response, "查询应用")

    package_info = response.get("packageInfo") or {}
    print(f"   应用名称: {package_info.get('appName', '(未推送过)')}")
    print(f"   商店版本: {package_info.get('versionName', '-')} ({package_info.get('versionCode', '-')})")
    print(f"   允许新增: {response.get('create')} / 允许版本更新: {response.get('updateVersion')} "
          f"/ 允许信息更新: {response.get('updateInfo')}")
    return response


def build_app_info(args, synchro_type, fallback_app_name):
    app_info = {"appName": args.app_name or fallback_app_name, "packageName": args.package_name}

    if synchro_type == 0:
        required = [("--app-name", args.app_name), ("--category", args.category),
                    ("--keywords", args.keywords), ("--desc", args.desc),
                    ("--brief", args.brief), ("--privacy-url", args.privacy_url),
                    ("--icon", args.icon)]
        missing = [name for name, value in required if not value]
        if missing:
            raise SystemExit(f"❌ 首次新增应用缺少上架素材参数: {', '.join(missing)}")
        if len(args.screenshot) < 3:
            raise SystemExit("❌ 首次新增应用至少需要 3 张手机截图 (--screenshot，可重复传入)")
        app_info.update({
            "category": int(args.category),
            "keyWords": args.keywords,
            "desc": args.desc,
            "brief": args.brief,
            "privacyUrl": args.privacy_url,
        })
    else:
        if not args.update_desc:
            raise SystemExit("❌ 更新版本必须提供 --update-desc（更新说明，会展示给商店用户）")
        app_info["updateDesc"] = args.update_desc

    return app_info


def push_app(args, synchro_type, app_name):
    if not args.apk or not os.path.isfile(args.apk):
        raise SystemExit(f"❌ 找不到待推送的安装包: {args.apk}")

    app_info = build_app_info(args, synchro_type, app_name)
    files = {"apk": args.apk}
    if synchro_type == 0:
        files["icon"] = args.icon
        for index, path in enumerate(args.screenshot, start=1):
            files[f"screenshot_{index}"] = path

    request_data = compact_json({"userName": args.account, "synchroType": synchro_type, "appInfo": app_info})
    print(f"   同步类型: {synchro_type} ({'新增应用' if synchro_type == 0 else '更新版本'})")
    print(f"   安装包: {args.apk} ({os.path.getsize(args.apk) / (1024 * 1024):.2f} MB)，开始上传...")

    response = call_api("/dev/push", request_data, args.private_key, args.public_key, files)
    check_result(response, "推送应用")


def main():
    parser = argparse.ArgumentParser(description="小米应用商店自动发布接口客户端")
    parser.add_argument("--account", required=True, help="登录小米开放平台的邮箱账号")
    parser.add_argument("--private-key", required=True,
                        help="「自动发布接口」页面分配的私钥（访问密码），不是登录密码")
    parser.add_argument("--public-key", required=True, help="小米下发的公钥证书文件（.cer）路径")
    parser.add_argument("--package-name", required=True, help="应用包名")
    parser.add_argument("--apk", help="待推送的 APK 路径")
    parser.add_argument("--update-desc", default="", help="更新说明，更新版本时必填")
    parser.add_argument("--query-only", action="store_true", help="仅查询应用信息，不推送")
    parser.add_argument("--app-name", help="应用名称，首次新增时必填")
    parser.add_argument("--category", help="应用分类 id，首次新增时必填（可用 /dev/category 查询）")
    parser.add_argument("--keywords", help="搜索关键字（空格分隔），首次新增时必填")
    parser.add_argument("--desc", help="应用介绍，首次新增时必填")
    parser.add_argument("--brief", help="一句话简介，首次新增时必填")
    parser.add_argument("--privacy-url", help="隐私政策链接，首次新增时必填")
    parser.add_argument("--icon", help="应用图标文件，首次新增时必填")
    parser.add_argument("--screenshot", action="append", default=[],
                        help="手机截图文件，首次新增时至少 3 张，可重复传入")
    args = parser.parse_args()

    response = query_app(args)
    if args.query_only:
        return

    if response.get("updateVersion"):
        push_app(args, 1, (response.get("packageInfo") or {}).get("appName") or args.package_name)
    elif response.get("create"):
        push_app(args, 0, args.app_name)
    else:
        raise SystemExit("❌ 该账号当前既不允许版本更新也不允许新增该包名的应用，请先到小米开放平台处理包名归属/认领")

    print("\n---------------------------------------------------")
    print("推送完成！请到小米开放平台「应用管理」确认审核状态。")


if __name__ == "__main__":
    main()
