# SwiftMath 离线内置方案（ATeaching）

本方案目标：**不依赖运行时网络**，把公式渲染依赖作为源码内置到仓库。

---

## 1) 总体原则

- 只在“拿依赖”这一步需要联网（可由任意一台有网机器完成）。
- 依赖文件进入仓库后，后续开发、构建、运行都可离线。
- 依赖固定放在：`Vendor/SwiftMath/`。

---

## 2) 有网机器执行（一次）

### 方式 A（推荐）

```bash
git clone --depth 1 https://github.com/mgriebling/SwiftMath.git
cd SwiftMath
git rev-parse HEAD
```

记录提交号（用于版本备注），然后打包：

```bash
cd ..
tar -czf SwiftMath-offline.tgz SwiftMath
```

把 `SwiftMath-offline.tgz` 拷到你的离线开发机。

### 方式 B（GitHub 网页下载 ZIP）

- 下载仓库 ZIP。
- 解压后重命名目录为 `SwiftMath`。
- 再压缩成 `SwiftMath-offline.tgz` 传到离线机。

---

## 3) 离线机内置（本仓库执行）

把 `SwiftMath-offline.tgz` 放到仓库根目录，然后执行：

```bash
bash Scripts/install_swiftmath_offline.sh SwiftMath-offline.tgz
```

完成后会得到：

- `Vendor/SwiftMath/...`
- `Vendor/SWIFTMATH_VERSION.txt`（安装时间与来源包名）

---

## 4) Xcode 接入（离线）

内置完成后，在 Xcode 手动接入一次（离线可做）：

1. `File` → `Add Package Dependencies...`
2. 点 `Add Local...`
3. 选择本地目录：`<repo>/Vendor/SwiftMath`
4. 选中 package product（通常为 `SwiftMath`）
5. 勾选 target：`ATeaching`

---

## 5) 版本备注（建议）

在你们的变更记录里备注：

- `SwiftMath` 来源（URL）
- 提交号（commit hash）
- 内置日期
- 是否修改过上游源码（一般不改）

---

## 6) 升级与回滚

### 升级

- 用新包重新执行一次脚本，会覆盖 `Vendor/SwiftMath`。

### 回滚

```bash
rm -rf Vendor/SwiftMath Vendor/SWIFTMATH_VERSION.txt
```

然后在 Xcode 的 Package Dependencies 里移除本地 `SwiftMath` 依赖即可。

---

## 7) 备注

- 当前 Codex 运行环境无法联网解析 `github.com`，所以无法直接替你下载。
- 但上面流程可保证你项目最终是“依赖内置、离线可开发”的状态。
