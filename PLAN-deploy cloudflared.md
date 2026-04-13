# Health AI 公网接入一期方案

## Summary
- 采用 `公司局域网服务器为主站 + 本地开发机为备站` 的主备方案。
- 首期公网入口使用 `Cloudflare Tunnel`，域名建议用 `app.<你的域名>`，备站用 `backup.<你的域名>`。
- 不做双活。同一时刻只让一个实例承接正式公网流量，因为当前项目使用本地 `SQLite`，双活会导致数据分叉和登录状态不一致。
- 当前应用不适合直接迁到 Cloudflare Pages/Workers：项目依赖 `Node server + 本地 SQLite`，且 Cloudflare 官方 FAQ 截至 `2025-10-24` 仍说明 `Pages` 在中国大陆不可用。

## Key Changes
- 先处理安全阻塞项，再开放公网：
  - 立即轮换并移除仓库中明文 LLM Key；当前 [deploy/.env.production](/Users/xmly/Projects/MyCodex/Health/deploy/.env.production) 含真实密钥，不能继续作为部署材料。
  - 生产环境补齐 `HEALTH_JWT_SECRET`；认证开启但缺少该值时会报错，见 [auth-service.ts:123](/Users/xmly/Projects/MyCodex/Health/src/server/services/auth-service.ts#L123)。
- 业务服务部署默认定为：
  - 公司服务器运行主站，监听 `3001`，健康检查使用 `GET /api/health`。
  - 本地开发机保留同版本备站，仅用于手动切换，不参与正式流量。
  - 生产环境变量默认：`NODE_ENV=production`、`HOSTNAME=0.0.0.0`、`PORT=3001`、`HEALTH_AUTH_ENABLED=true`、`HEALTH_JWT_SECRET=<32位以上>`、`PUBLIC_BASE_URL=https://app.<domain>`。
- Tunnel 拓扑固定为两条独立命名隧道：
  - `health-primary` 绑定公司服务器，服务指向 `http://127.0.0.1:3001`
  - `health-backup` 绑定本地开发机，服务指向本地备站
  - DNS 先将 `app.<domain>` 指向 `health-primary`
  - `backup.<domain>` 指向 `health-backup`，只用于演练和故障接管验证
- 切换策略固定为手动主备切换：
  - 平时仅主站对外提供正式服务
  - 主站故障时，将 `app.<domain>` 切到备隧道，恢复后再切回
  - 不允许主备同时挂到同一正式域名
- 实施形态优先采用 Cloudflare Dashboard 的 token-based tunnel：
  - 便于集中管理 hostname、token、日志和切换
  - 公司服务器用 `systemd` 常驻 `cloudflared`
  - 本地开发机用 `launchd` 或手动启动作为备用
  - 当前这台机器里未发现 `cloudflared` 可执行文件和 `~/.cloudflared/config.yml`，实施时要在实际承载机器上分别核实安装状态

## Interfaces / Config
- 新增公网入口：
  - `https://app.<domain>`：正式入口
  - `https://backup.<domain>`：备站入口
- 部署配置需要标准化：
  - 生产 `.env` 不再入库，只保留脱敏模板
  - 新增主站/备站 `cloudflared` 配置样例和切换文档
  - 服务健康探针统一使用 `/api/health`

## Test Plan
- 内网验证：
  - 主站本机 `curl http://127.0.0.1:3001/api/health`
  - 确认登录、首页、报告页、AI 接口都正常
- 公网验证：
  - 用手机 4G/5G 和家庭宽带从外部访问 `app.<domain>`
  - 分别验证中国电信/联通/移动网络下首页、登录、核心接口
- 容灾演练：
  - 主站停服后，把正式域名切到 `health-backup`
  - 验证外部访问恢复
  - 切回主站后再次验证数据和登录流程
- 安全验证：
  - 确认仓库、部署目录、日志中不再出现明文 API Key
  - 确认未登录用户无法访问受保护 API

## Assumptions
- 现在先以“尽快公网可用”为目标，长期中国区生产稳定性放到第二阶段。
- 第二阶段默认推荐迁移到香港云服务器；如果未来改为中国大陆节点，则按接入商要求完成域名实名与 ICP 备案。
- 若未来一定要自动切换或双活，必须先把 `SQLite` 改为共享数据库，并统一会话/上传存储；这不属于本次一期方案。
