# 普通Markdown一轮优化回归

运行（仓库根目录）：

- `python3 Experiments/Markdown128/check-syntax.py`：复制实际语法源，使用项目同版swift-markdown 0.9.0，在隔离临时Swift包比较增量结果与强制完整解析。覆盖Unicode、CRLF、段落分裂、围栏、引用定义、公式、列表、HTML、连续修改、百万字符单块；比较目录、所有样式范围、字面量、预览块和源行号。输出syntax-results.json。
- `python3 Experiments/Markdown128/check-native.py`：提取实际Mac源码投影/字符编辑监听/图片解码缓存，在真实TK2 NSTextView及临时图片上检查相邻附件源码、输入、UndoManager撤销重做、marked-text API、TK2保留、后台降采样和同请求合并。输入法API合成调用不等于真人候选窗口测试。工作区真实文件不参与。
- `python3 Experiments/Markdown128/check-preview.py`：真实WKWebView加载仓库脚本，沿用一万块预览回归，追加巨型代码/纯文本/强调链接段落、Unicode和实体、近似源行跳转、完整渲染恢复、公式缓存重挂载。输出preview-results.json。
- 既有TK2路由/封存检查及生产可见区同步滚动检查仍适用：Experiments/Markdown126/check-all-tk2.py、check-pipeline.py。

syntax-results.json为一次后台合成计算，运行时可能与编译争用资源。它不包含真实打字、SwiftUI发布、TK2排版、保存或跨设备同步。所有结果索引仍更新数组，差异定位仍比较源码，因此不能推导任意大小恒速。

安全与已知边界：

- 不能证明语义独立时完整重算；含引用定义、数学边界、跨块与复杂容器保留完整解析路径。
- 巨型预览块仅对可安全分片的纯文本/内联段落、围栏代码使用分片。HTML、图片/公式混排、复杂嵌套保持原语义块；单个巨大公式仍可能昂贵。
- 分片的段落间距/软换行、代码块分片外观可能与完整导出略有差别；源行定位按局部高度近似。完整打印、全选及导出保持原语义块、包含全文。
- 图片缓存64MB/128项，按文件签名后台复查，短时间内最多约两秒看到旧缓存。HTML/KaTeX片段缓存2MB/96项；不适合缓存的巨大块不入缓存。
- 本轮保持原保存协议，完整打开/保存有大小相关成本；中文候选、触控/辅助功能、超长段落TK2实际帧率和跨设备iCloud仍需真机验收。

回退标签：codex/pre-normal-md-complete-20261118。原始文本/学生数据没有直接修改。
