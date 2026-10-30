// 子任务 3.2 规则样例：服务端地址被写死为 IPv4 字面量（应命中 arkts-hardcoded-ip）
const serverIp = "192.168.1.100";

export function getServerIp(): string {
  return serverIp;
}
