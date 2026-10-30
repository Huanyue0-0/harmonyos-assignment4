/**
 * 全局配置常量（集中管理，避免硬编码散落各处）。
 * 供 NetworkService / FileService / CryptoService 统一引用。
 */
export class AppConfig {
  /** 网络示例接口地址 */
  static readonly SAMPLE_URL: string = 'http://httpbin.org/get';
  /** 示例接口访问令牌（服务端联调时填入） */
  static readonly SAMPLE_API_TOKEN: string = 'sk-live-7d91f2c3a8e4b5d6e0f1a2b3c4d5';
  /** AES 加密使用的固定密钥（十六进制，16 字节） */
  static readonly FIXED_AES_KEY_HEX: string = '00112233445566778899aabbccddeeff';
  /** 笔记沙箱文件名（固定文件名，用户输入绝不参与路径拼接） */
  static readonly NOTE_FILE_NAME: string = 'encrypted_note.json';
  /** PBKDF2 密钥派生迭代次数（业界常规安全值） */
  static readonly PBKDF2_ITERATIONS: number = 10000;
  /** 盐长度（字节，CSRNG 生成） */
  static readonly SALT_LEN: number = 16;
  /** AES-GCM 初始向量长度（字节，CSRNG 生成） */
  static readonly IV_LEN: number = 12;
  /** GCM 认证标签长度（字节） */
  static readonly TAG_LEN: number = 16;
  /** 派生密钥长度（字节，对应 AES-256） */
  static readonly KEY_SIZE: number = 32;
  /** HTTP 连接/读取超时（毫秒） */
  static readonly HTTP_TIMEOUT_MS: number = 10000;
}
