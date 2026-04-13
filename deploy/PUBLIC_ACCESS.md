# Health AI 公网接入一期操作手册

这套材料对应一期方案：

- 公司局域网服务器作为主站
- 本地开发机作为备站
- 首期公网入口通过 Cloudflare Tunnel 暴露
- 不做双活，同一时刻只允许一个实例承接正式公网流量

## 仓库内新增的部署材料

- `deploy/env/health-primary.env.example`
- `deploy/env/health-backup.env.example`
- `deploy/env/cloudflared-primary.env.example`
- `deploy/env/cloudflared-backup.env.example`
- `deploy/deploy.sh`
- `deploy/install-cloudflared-service.sh`
- `deploy/install-cloudflared-backup-launchd.sh`
- `scripts/run-cloudflared-tunnel.sh`
- `scripts/generate-health-jwt-secret.sh`

## 0. 先准备域名和密钥

### 0.1 域名怎么选

推荐优先级：

- 如果目标是“先尽快上线，再考虑中国大陆正式生产”：优先买 `.com`
- 如果未来明确要做中国大陆主体备案：仍可优先买 `.com`，也可以考虑 `.cn`
- 不建议一期先买冷门后缀，先保证可记忆、可信度和后续迁移灵活性

命名建议：

- 尽量短，优先 6 到 12 个字符
- 避免生僻拼写
- 尽量让用户一眼知道和健康管理相关
- 示例：`healthopsxxx.com`、`healthaixxx.com`

### 0.2 推荐购买路径

方案 A，推荐给你当前场景：

- 在腾讯云或阿里云购买域名
- 完成实名
- 继续把 DNS 托管到 Cloudflare
- 后续如果改走中国大陆服务器 / ICP 备案，这条路径更稳妥

方案 B，仅适合“先快速上线海外公网入口”：

- 直接在 Cloudflare Registrar 购买域名
- 优点是接 Cloudflare DNS 最省事
- 但 Cloudflare Registrar 下的域名固定使用 Cloudflare nameservers，且不支持国际化域名（IDN）

### 0.3 购买后的固定规划

无论你在哪里买，后续都统一规划为：

- `app.wellai.online`：正式入口
- `backup.wellai.online`：备站入口

### 0.4 现在的建议

对于你这个项目，我建议：

- 现在已经有了 `wellai.online`
- 下一步把域名加到 Cloudflare
- 再按本文后续步骤配置 Tunnel

### 0.5 腾讯云购买域名的最短步骤

1. `wellai.online` 已经在腾讯云注册完成
2. 确认域名实名认证状态正常
3. 保留域名在腾讯云注册商，后续仅把 DNS 切到 Cloudflare

### 0.6 买完域名后，立刻做这 3 步

1. 登录 Cloudflare Dashboard，选择 “Add a domain / Add a site”
2. 把 `wellai.online` 以 `Full setup` 加入 Cloudflare
3. 复制 Cloudflare 分配给你的两条 nameserver，并到腾讯云域名控制台把 nameserver 改成 Cloudflare 提供的值

只有当域名在 Cloudflare 里变成 `Active` 后，后面的 Tunnel hostname 才能正式绑定成功。

1. 把 `wellai.online` 托管到 Cloudflare。
2. 规划两个子域名：
   - `app.wellai.online`：正式入口
   - `backup.wellai.online`：备站入口
3. 生成一个 32 位以上随机 JWT secret：

```bash
./scripts/generate-health-jwt-secret.sh
```

4. 轮换旧的 LLM API Key，使用新的运行时密钥写入本地私有 env 文件。

## 1. 配置并部署主站

先在仓库里准备一个不会提交到 Git 的主站 env 文件：

```bash
cp deploy/env/health-primary.env.example deploy/.env.primary.local
```

至少要填写这些值：

- `PUBLIC_BASE_URL=https://app.wellai.online`
- `SYNC_SERVER_URL=https://app.wellai.online`
- `HEALTH_JWT_SECRET=<随机密钥>`
- `HEALTH_LLM_API_KEY=<新的运行时密钥>`

然后把主站部署到公司服务器：

```bash
DEPLOY_ENV_FILE=deploy/.env.primary.local ./deploy/deploy.sh user@your-server
```

部署完成后先做内网健康检查：

```bash
ssh user@your-server 'curl -fsS http://127.0.0.1:3001/api/health'
```

## 2. 给主站接 Cloudflare Tunnel

在 Cloudflare Dashboard 里：

1. 创建 named tunnel：`health-primary`
2. 选择 token-based 运行方式
3. 添加 public hostname：
   - hostname: `app.wellai.online`
   - service: `http://127.0.0.1:3001`
4. 复制 tunnel token

在公司服务器上准备 cloudflared env 文件：

```bash
sudo mkdir -p /etc/health-ai
sudo cp /opt/vital-command/deploy/env/cloudflared-primary.env.example /etc/health-ai/cloudflared-primary.env
sudo nano /etc/health-ai/cloudflared-primary.env
```

至少填写：

- `TUNNEL_TOKEN=<health-primary 的 token>`

如果服务器 PATH 里没有 `cloudflared`，再补：

- `CLOUDFLARED_BIN=/usr/local/bin/cloudflared`

如果日志里持续出现 `Failed to dial a quic connection`，通常是当前网络把 UDP / QUIC 挡掉了。此时在 cloudflared env 文件里补：

- `TUNNEL_TRANSPORT_PROTOCOL=http2`

并确保主机允许访问 Cloudflare Tunnel 出站端口 `7844/TCP`。

安装并启动 systemd 服务：

```bash
ssh user@your-server 'cd /opt/vital-command && sudo ./deploy/install-cloudflared-service.sh primary /etc/health-ai/cloudflared-primary.env'
```

查看 tunnel 日志：

```bash
ssh user@your-server 'sudo journalctl -u cloudflared-health-primary -f'
```

## 3. 配置备站

本地开发机也准备一份不会提交到 Git 的备站 env：

```bash
cp deploy/env/health-backup.env.example deploy/.env.backup.local
```

至少填写：

- `PUBLIC_BASE_URL=https://backup.wellai.online`
- `SYNC_SERVER_URL=https://backup.wellai.online`
- `HEALTH_JWT_SECRET=<与主站一致>`
- `HEALTH_LLM_API_KEY=<新的运行时密钥>`

启动本地备站：

```bash
cp deploy/.env.backup.local .env
PORT=3001 ./scripts/start-health-server.sh
curl -fsS http://127.0.0.1:3001/api/health
```

然后在 Cloudflare Dashboard 里：

1. 创建 named tunnel：`health-backup`
2. 添加 public hostname：
   - hostname: `backup.wellai.online`
   - service: `http://127.0.0.1:3001`
3. 复制 tunnel token

本地创建 tunnel env 文件：

```bash
mkdir -p "$HOME/.config/health-ai"
cp deploy/env/cloudflared-backup.env.example "$HOME/.config/health-ai/cloudflared-backup.env"
```

填入：

- `TUNNEL_TOKEN=<health-backup 的 token>`

如果当前网络里 QUIC 不通，再加：

- `TUNNEL_TRANSPORT_PROTOCOL=http2`

然后安装 launchd 常驻任务：

```bash
./deploy/install-cloudflared-backup-launchd.sh "$HOME/.config/health-ai/cloudflared-backup.env"
```

查看状态：

```bash
launchctl print "gui/$(id -u)/com.healthai.cloudflared-backup"
```

如果主站机器是 macOS，且你偶尔会打开第三方 VPN，请额外安装主站 tunnel 守护：

```bash
./deploy/install-primary-tunnel-guard-launchd.sh
```

它会在主站 `cloudflared` 因 VPN / DNS 劫持而掉线时，自动优先恢复公网入口，避免 `app.wellai.online` 长时间不可用。

## 4. 正式流量和切换规则

默认规则：

- `app.wellai.online` 只指向 `health-primary`
- `backup.wellai.online` 只指向 `health-backup`
- 统一以 `10.8.144.16` 为写入主库，备站仅做灾备承接，不做长期双写

### 4.1 备站数据定时同步（推荐）

如果备站和主站分别维护 SQLite，切换时会看到不同账号与数据。建议启用主库定时同步：

```bash
# 在备站机器执行，默认每 10 分钟同步一次
./deploy/install-backup-db-sync-launchd.sh

# 手动触发一次立即同步
./scripts/sync-primary-db-to-backup.sh
```

同步脚本逻辑：

1. 在主站（`10.8.144.16`）创建 SQLite 快照；
2. 拉取快照到备站本地；
3. 原子替换备站数据库；
4. 重启备站服务。

主站故障时的切换步骤：

1. 确认本地备站健康：

```bash
curl -fsS http://127.0.0.1:3001/api/health
```

2. 在 Cloudflare 里把 `app.wellai.online` 改为指向 `health-backup`
3. 用手机 4G/5G 从公网验证首页、登录和核心接口
4. 主站恢复后，把 `app.wellai.online` 切回 `health-primary`

禁止事项：

- 不要把主站和备站同时挂到同一个正式 hostname
- 不要让两个实例同时承接写流量，否则 SQLite 会分叉

## 5. 推荐验证清单

内网验证：

```bash
curl -fsS http://127.0.0.1:3001/api/health
```

公网验证：

- 手机 4G/5G 访问 `https://app.wellai.online`
- 家庭宽带访问 `https://app.wellai.online`
- App 默认服务地址填写 `https://app.wellai.online`
- 分别验证首页、登录、报告页、AI 接口

安全验证：

- 仓库中不再保存生产密钥
- 生产 env 只保留在本地或目标机器
- 未登录请求受保护接口时返回 401

## 6. 中国区长期方案

一期方案优先“尽快公网可用”。如果后续要面向中国用户长期稳定运营，建议第二阶段迁移到：

- 香港云服务器
- 或中国大陆云服务器 + 域名实名 + ICP 备案

Cloudflare Tunnel 适合首版验证和外网接入，但不等于中国大陆正式合规生产架构。
