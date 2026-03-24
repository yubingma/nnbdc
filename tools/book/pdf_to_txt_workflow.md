# PDF 词汇书提取与清洗标准化流程 (Standard PDF to TXT Workflow)

本方案旨在解决从各种排版格式的 PDF 词书（尤其是带编号、多排、粘连错版的词汇表）中提取纯净单词列表时，所面临的漏词、标点杂质、以及空格消失（连字）等痛点。核心思想是：**“机器提取数据底板，字典白名单修正排版，NLTK纯只读兜底复核。”** 绝不让机器学习算法直接篡改原本正确的单字。

## 核心工作流 (The Pipeline)

### Step 1: 结构化防御性提取 (Defensive Raw Extraction)

不要简单地按行全选文本。必须利用 PDF 自身的排版物理规律：

- **表格类 PDF（如高考3500）**：强推荐使用 `pdfplumber.extract_tables()`，利用表格的物理列阻断音标和释义跨界混入。
- **纯文本/双列类 PDF（如红宝书、专升本）**：利用 `(\d+)\.\s*([A-Za-z\-]+)` 或类似的镜像定界符（如 `25 judge 25`）的正则特性锁死单词区间。
- **验证漏字法**：提取时必须在内存中建立 `{序号: 单词}` 的 Hash 表。循环判断 `1` 到 `最大序号` 是否存在断层，确保真正意义上的 **0 漏词**。

### Step 2: 物理去余与词目去重 (Physical Trimming & Deduplication)

针对初步提取的脏数据进行无脑的物理切割：

1. **词性剥离**：使用正则掐除紧贴单词的 `adj.`, `n.`, `v.`, `adv.`, `prep.`, `conj.`。
2. **括号斩断**：直接通过 `re.split(r'[\(（\[【]', word)[0].strip()` 砍掉单词后带有的任何英文/中文全半角括号及内部内容（如 `swell(swelled)` -> `swell`，`zipcode(美)` -> `zipcode`）。
3. **全局去重**：清除因为不同词汇变体拆开分列、但褫夺括号后长得一模一样的纯重复词（如 `break (v.)` 和 `break (n.)` 全部合并为 `break`）。

### Step 3: 分词白名单勘探 (Whitelist NLP Scouting)

由于 PDF 在排版时经常不敲入物理空格（导致 `bring home to` 在图层中变为死字 `bringhometo`），必须把藏起来的短语救出来。

- **方法**：编写一个侦查脚本。引入 `nltk.corpus.words`（标准英语词典）和 `wordninja` 暴力分词器。
- **探测逻辑**：遍历上述 TXT 的所有无空格单字。如果该词长度 > 4 且 **不在** NLTK 合法词典中，就让 `wordninja` 尝试切开它。如果切开后有明确的介词/动词副词（如 `up`, `to`, `for`, `with`, `about`, `on`, `across` 等），则将这段原词和切分建议打印到屏幕/日志，**不要直接修改文件**。

### Step 4: 人工审查与硬字典替换 (Curated Dictionary Replacement)

- 取出 Step 3 打印出的分词建议日志，人工肉眼扫一遍。
- 剔除其中的 **NLTK 词库盲区误杀词**：比如英式拼写（`waggon`, `appetising`）、合成词或派生词（`workmate`, `spokesman`, `Tibetan`, `transgene`, `jobseeker`）。
- 将剩余 100% 确定为 PDF 连字排版故障的短语（常为 300 多个由动词+介词组成的固定搭配，如 `catch up with`, `according to`），写成一个死板的 Python Map 表（如 `{"bringhometo": "bring home to"}`）。
- 用此纯静态白名单字典跑一遍总 TXT 文件做定点替换。至此既恢复了空格，又保全了所有单字原貌。

### Step 5: 原生拼写错位纠音校正 (Auto Spell Checking)

除了解决“没敲空格”的黏连，原作者的排版失误也经常引入纯拼写错误（如少印一个字母的 `federa`，或乱打成 `spokenman`）。

- **拦截方案**：引入 `pyspellchecker` 这种专业的英语纠错容错库。
- 将不在 NLTK 标准词典中的词扔给 Spell Checker，由算法计算出**汉明距离最近的正确英语单词拼写**（它会明确告诉你 `spokenman` 其实是错字，建议替换为 `spokesman`）。对于置信度极高的错词（汉明距离为 1）可加入自动矫正队列，人工拍板应用。

### Step 6: 终极只读质检 (Final Read-Only NLTK Audit)

所有的处理程序结束后，跑最后一个只读的 Python 断言/预警脚本做品控：

1. 装载最庞大的组合语料库：`nltk.corpus.words` + `nltk.corpus.brown`。
2. 将刚才被定性（且跳过字典）的所有长单字送进去查字典。
3. 如果此时还有单字**既不包含任何空格、又查不到任何字典收录，却可以被 wordninja 合理肢解为两个合法单词**，直接在控制台标红打出（例：`informsb.ofsth.`, `sendsb.for`, 或原生 PDF 拼写遗漏 `federa` (应为 `federal`)）。
4. 针对最后的零星几条警报，人工判定并补充修正。整个系统即可宣告无菌出厂，达成最高质量导入格式！
