---
name: sea-repo-sync
description: 在这台机器上把 sea 仓库同步到远程最新点或把本地提交推上去。用于 github.com 被墙、git fetch 反复 early EOF、git push 报无写权限时的拉取与推送，包含缺对象补齐、大文件分块下载和 API 重放推送。
---

# sea 仓库拉取与推送

## 先认清这台机器的通道

- `github.com` **直连和走会话代理都不可靠**，经常回 502；`git push` 走 SSH 一律被拒（`summercard` 这个身份没有本仓库写权限）。
- `api.github.com` 与 `raw.githubusercontent.com` 能通，但很慢，大响应会中途断（`IncompleteRead` / `early EOF`）。代理端口每次会话都可能变，先 `env | grep -i proxy` 看清当前值，不要硬编码。
- 凭据管理器里的 token 有写权限，所以**推送走 API**，不走 git 协议。
- 仓库是 promisor/部分克隆：`--filter=blob:none` 拉下来的提交与树里，文件内容（blob）是缺的，要单独补。

## 拉取

先看差多少，别盲目 `git fetch`：

```bash
git rev-parse HEAD
timeout 30 curl -s "https://api.github.com/repos/summercards/sunken-city-3d/branches/codex%2Ffeature-controlled-structure" \
  | python -c "import json,sys;c=json.load(sys.stdin)['commit'];print(c['sha'][:8], c['commit']['message'].splitlines()[0][:60])"
```

拿提交与树（几秒到几分钟；服务器有时忽略 filter 直接回全量包，那更快，别打断）：

```bash
git fetch --no-tags git@github.com:summercards/sunken-city-3d.git \
  codex/feature-controlled-structure:refs/remotes/origin/codex/feature-controlled-structure
```

列缺的文件对象（**必须带 `GIT_NO_LAZY_FETCH=1`**，否则 `rev-list` 会当场懒加载、看起来像卡死）：

```bash
export GIT_NO_LAZY_FETCH=1
git rev-list --objects --missing=print <base>..<tip> | grep '^?' | sed 's/^?//' > /tmp/miss.txt
```

分两类补：

- **小对象**（源码、json、uid、png）：16 路并行触发懒加载，每轮重新跑上面的命令统计剩余，直到 0。
  `cat /tmp/miss.txt | xargs -P 16 -I{} sh -c 'timeout 60 git cat-file -s {} >/dev/null 2>&1'`
- **大对象**（`.blend` 十几 MB 以上）：懒加载必然 early EOF，改分块下载 `sea-work/tmp/pull_sunken_v2.py`（改文件里的 `TARGETS` 与 `COMMIT`）。
  它做四件事：raw 按 **128 KB** 分块、4 路并发、按「全零块」识别空洞做断点续传、每块校验长度；下完用 `git hash-object -w --no-filters` 校对 sha，一致才入库。

缺对象归零后才合并：`git merge --ff-only origin/<branch>`。**不要 `git pull`**，冲突时它会留下 merge 状态和锁。

## 合并前的三个坑

1. **残留锁**：中断的合并会留 `.git/index.lock`，`git reset --hard` 会直接报错。先 `mv .git/index.lock sea-work/tmp/`，再 reset。
2. **半截检出**：被中断的 checkout 会留下十几个 `D` 状态文件，`reset --hard` 一并复位。
3. **工作区改动要分类**，别一股脑提交：
   - 实质改动：工作区字节与 `git show HEAD:<path>` 不同，且把 `\r\n` 换成 `\n` 后仍不同；
   - CRLF 幻影：规范化后相同（本机 `core.autocrlf=true`，`git checkout` 会把文本写成 CRLF），还原行尾即可，**不要重算哈希**；
   - 引擎噪音：`.glb.import` 多出导入器字段、`ocean_sky.tres` 被重写成 `[gd_resource]`、Godot 把 `main.tscn` 烘成 1.2 MB。

## 推送

`git push` 不用试，直接走 API 重放：`python sea-work/tmp/push_via_api.py <远程当前 sha>`（脚本自己读凭据，按 tree→commit→PATCH ref 提交，author/committer/date 原样照抄）。重放出来的 sha 与本地逐个相同，推完两边是同一个点。推完核对并同步本地 ref：

```bash
timeout 30 curl -s "https://api.github.com/repos/summercards/sunken-city-3d/branches/codex%2Ffeature-controlled-structure" \
  | python -c "import json,sys;print(json.load(sys.stdin)['commit']['sha'][:8])"
git update-ref refs/remotes/origin/codex/feature-controlled-structure <sha>
```

## 不要做

- 不要在代理上跑 `git fetch --refetch` 全量：实测 ~130 KB/s，几十分钟只下几 MB。
- 不要用 `git checkout -- <文件>` 批量还原资源：这个仓库长期有未提交的渲染资源改动，会连未提交内容一起丢掉。要还原先 `git diff --stat` 看清。
- 不要把引擎重写产物（`.import`、被 Godot 重存的 `.tres`、膨胀的 `main.tscn`）提交上去，否则各机器之间来回抖动。
