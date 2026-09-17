import os
import json
import time
import urllib.request
import urllib.error

DS_KEY = os.environ.get('DEEPSEEK_API_KEY') or 'sk-44175b8b19d44d33a4571ee3237223da'
DASH_KEY = os.environ.get('dashscope_api_key') or 'sk-85471cdc7ac24bd196a6ebb54e4c1cd0'

# 1. 查询数据库中 spring 的所有真实释义
meanings_raw = [
    {"ci_xing": "n.", "meaning": "春天，春季"},
    {"ci_xing": "n.", "meaning": "泉水，泉眼"},
    {"ci_xing": "n.", "meaning": "弹簧，发条"},
    {"ci_xing": "vi.", "meaning": "跳，跃，蹦"},
    {"ci_xing": "vt.", "meaning": "突然提出，使突然发生；触发，引爆"},
    {"ci_xing": "adj.", "meaning": "春天的"}
]

SYSTEM_PROMPT = """你是一位深谙认知语言学与词源学的英语教学大师，同时精通 AI 生图视觉构图。
你的任务是为单词 spring 提炼最本质的【核心动态意象（Core Image Schema）】，并完成两项任务：
1. 深入剖析每个释义如何从该核心意象自然引申演变；
2. 专门为 AI 文生图模型（如通义万相 Wanx）编写一段画面感极强、空间动势充沛的【英文生图 Prompt】。

【生图 Prompt 要求】
- 必须将核心意象（向上弹涌的动势）融为一体，涵盖弹簧势能、涌泉水体、春天生机三个隐喻的视觉融合；
- 风格：3D 概念艺术、现代超现实极简、高级暗色背景、电影级光影；
- 严禁任何文字（no text, no letters, no watermark）。

输出必须为纯合法的 JSON 格式。"""

USER_PROMPT = """【单词】：spring
【真实释义列表】：
- [n.] 春天，春季
- [n.] 泉水，泉眼
- [n.] 弹簧，发条
- [vi.] 跳，跃，蹦
- [vt.] 突然触发，引爆
- [adj.] 春天的

请按以下 JSON 格式输出：
{
  "spell": "spring",
  "phonetic": "/sprɪŋ/",
  "core_image": "核心动态意象（15字以内）",
  "image_schema_desc": "核心原点动势阐释（40字以内）",
  "wanx_image_prompt": "专供通义万相绘制概念图的高质量英文 Prompt",
  "branches": [
    {
      "pos": "词性",
      "meaning": "具体释义",
      "relation": "一句话引申纽带（12字以内）",
      "desc": "深入剖析为什么从核心意象引申至该释义",
      "example": "简短地道的英文例句，包含 spring"
    }
  ]
}"""

print(">>> [步骤 1/3] 调用 DeepSeek 提炼核心意象与生成生图 Prompt...")
ds_req = urllib.request.Request(
    'https://api.deepseek.com/chat/completions',
    headers={'Authorization': f'Bearer {DS_KEY}', 'Content-Type': 'application/json'},
    data=json.dumps({
        'model': 'deepseek-chat',
        'messages': [
            {'role': 'system', 'content': SYSTEM_PROMPT},
            {'role': 'user', 'content': USER_PROMPT}
        ],
        'response_format': {'type': 'json_object'},
        'temperature': 0.2
    }).encode('utf-8')
)

with urllib.request.urlopen(ds_req, timeout=60) as resp:
    ds_json = json.loads(resp.read().decode())
    result_data = json.loads(ds_json['choices'][0]['message']['content'])

print(">>> DeepSeek 输出完毕！")
print(f"核心意象: {result_data['core_image']}")
print(f"生图 Prompt: {result_data['wanx_image_prompt']}")

# 2. 调用通义万相 Wanx-v1 生成概念图
print("\n>>> [步骤 2/3] 提交通义万相 wanx-v1 生图任务...")
wanx_url = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis'
wanx_headers = {
    'Authorization': f'Bearer {DASH_KEY}',
    'X-DashScope-Async': 'enable',
    'Content-Type': 'application/json'
}
wanx_body = {
    'model': 'wanx-v1',
    'input': {'prompt': result_data['wanx_image_prompt']},
    'parameters': {'size': '1024*1024', 'n': 1}
}

submit_req = urllib.request.Request(wanx_url, headers=wanx_headers, data=json.dumps(wanx_body).encode())
with urllib.request.urlopen(submit_req) as submit_resp:
    submit_res = json.loads(submit_resp.read().decode())
    task_id = submit_res['output']['task_id']
    print(f"生图任务已提交，Task ID: {task_id}，正在轮询等待生成...")

image_url = None
poll_url = f'https://dashscope.aliyuncs.com/api/v1/tasks/{task_id}'
for attempt in range(30):
    time.sleep(3)
    p_req = urllib.request.Request(poll_url, headers={'Authorization': f'Bearer {DASH_KEY}'})
    with urllib.request.urlopen(p_req) as p_resp:
        p_res = json.loads(p_resp.read().decode())
        status = p_res['output']['task_status']
        print(f"轮询状态 ({attempt+1}): {status}")
        if status == 'SUCCEEDED':
            image_url = p_res['output']['results'][0]['url']
            print("通义万相生图成功！URL:", image_url)
            break
        elif status in ('FAILED', 'CANCELED'):
            print("通义万相生图失败:", p_res)
            break

# 3. 下载图片到本地
if image_url:
    print("\n>>> [步骤 3/3] 下载图片并保存到本地资产库...")
    local_img_path = '/Volumes/ssd/ppdc/design/ui/assets/spring_wanx_real.png'
    urllib.request.urlretrieve(image_url, local_img_path)
    result_data['local_image_path'] = local_img_path
    result_data['image_url'] = image_url
    print("图片已保存至:", local_img_path)

# 保存最终完整 JSON 结果
out_json_file = '/Volumes/ssd/ppdc/design/ui/assets/spring_core_result.json'
with open(out_json_file, 'w', encoding='utf-8') as f:
    json.dump(result_data, f, ensure_ascii=False, indent=2)

print("\n>>> 全部完成！完整生成结果已持久化保存。")
