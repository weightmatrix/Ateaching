# TK2滚动反弹隔离回放

`python3 Experiments/MarkdownScrollRebound/check.py /absolute/path/to/copy.md`

脚本把输入复制进临时目录，只读副本；不要把用户正文提交到仓库。Probe.swift是AppKit/TK2原生滚动与样式控制适配器，脚本运行时替换其GuardedView，提取当前生产代码的视口完成回调、导航与编辑退出方法。不是完整SwiftUI应用UI回归，也不模拟实际鼠标驱动/触控板全部行为。

已使用报告中2653 UTF16的文档副本验证：

- 冻结滚动时的样式刷新仍发生稳定画面反弹（3次），不是只有样式重置才可触发。
- 同一原生轮滚回放加入生产保护：两轮向上稳定反弹均0；向下0且保护不误触发；显式定位和编辑退出断言通过。
- 该文档原始内容在结束时不变。超类内部临时移动随后同回调恢复，通知统计仍可出现短暂正向位移；results.json里的settledJumps才是每轮滚动间隔的稳定画面变化，不能用原始jumps直接判定保护无效。
- 调用栈证据为textViewportLayoutControllerDidLayout调用NSClipView.scrollToPoint。修复是针对系统锚点校正反向滚动的局部兼容处理，不是对Apple内部算法实现的根因证明。

手动验收：原应用即时模式原位置向上滚动、向下滚动、目录/搜索跳转、键盘/鼠标定位、输入和撤销；另需实际触控板惯性、窗口缩放和辅助功能验收。生产不做全文布局，不改源文件格式，不引入TK1。
