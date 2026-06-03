# Telegram 群发布消息

v0.5.2 发布了，主要是性能和稳定性优化：

**性能改进：**

- 消息窗口上限 200 — 长时间挂机不再卡顿
- 退出 Neovim 不再卡 — close_chat 非阻塞 + SIGTERM 立即退出
- CursorMoved 防抖 — 快速滚动不卡
- curl 超时从 15s 降到 5s，重试从 4 次降到 2 次
- 修复多处 timer 泄漏

**缓存同步：**

- _users / _chats / _pinnedMessageIds 三个缓存加了上限和淘汰策略
- 所有 TDLib 更新事件（改标题、改权限、已读、pin 等）实时同步到缓存
- 远程注销时自动清空缓存

安装/更新：`build = "npm i"` 即可。

GitHub: https://github.com/ChuYanLon/telegram.nvim
