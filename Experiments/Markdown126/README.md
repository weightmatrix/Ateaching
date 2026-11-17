# #126 Markdown内核对照

正式编辑器不切换到CodeMirror；index.html为独立实验，不保存原文件。

## 重现

```sh
npm ci --prefix Experiments/Markdown126
npm run build --prefix Experiments/Markdown126
swiftc -parse-as-library Experiments/Markdown126/Benchmark.swift -o /tmp/126-benchmark -framework AppKit -framework WebKit
/tmp/126-benchmark "$PWD/Experiments/Markdown126" /absolute/path/to/sample.md
python3 Experiments/Markdown126/check-pipeline.py
```

运行器读取真实文件及400KB、2MB、10MB合成Markdown，各引擎在中间连续插入40字符。结果写results.json，不修改原文件。用macOS WKWebView运行CodeMirror，本地加载打包脚本，无CDN。

## 2026-11-17初测

|文件UTF8大小|TK1纯文本编辑P95同步耗时|TK2纯文本编辑P95同步耗时|CodeMirror变更提交P95|CodeMirror渲染行数|
|---|---:|---:|---:|---:|
|455433字节真实文件|18.52ms|2.71ms|3ms|78|
|400014字节合成文件|39.34ms|2.69ms|2ms|79|
|2000070字节合成文件|30.02ms|1.64ms|2ms|79|
|10000066字节合成文件|39.78ms|3.40ms|2ms|79|

这是单次40编辑内核筛选，不是正式编辑器端到端基准。原生测量同步编辑/强制绘制，CodeMirror测量dispatch，另报告两个animation frame后的耗时；两种同步指标不能严格横向排名。原生不包含本项目Markdown高亮/附件/双栏，CodeMirror带Markdown语法与行折叠换行；没有真人IME、撤销、多窗口、搜索、保存和断网同步验收。样本含冷启动及初次滚动影响；打开时间不等于完成全文排版。合成文件为短行，无超长段落、巨型代码块与图片压力，不声称性能与文件大小完全无关。

真实文件只记录大小和性能，不复制正文进仓库。check-pipeline.py提取生产代码两处方法，实际创建TK2视图，在可见范围查询、同步滚动、中文文本替换后断言未退回TK1；文本替换不等同真实中文输入法验收。

## 依赖与许可

锁定版本见package-lock.json；CodeMirror及Lezer依赖MIT，esbuild为MIT。打包产物用于本地实验，原始许可见THIRD_PARTY_NOTICES.txt。实验不接入正式App资源或构建依赖。

后续按同一操作分别测正式App源码/双栏/即时模式，并记录输入到绘制、滚动、全文投影及预览。当前优先保留原生TK2；只有正式编辑器仍无法达到体验目标时才考虑接入CodeMirror。真实中文输入、图片/公式、快捷输入、撤销、查找替换、跨窗口及iCloud写入必须验收后才能替换。
