import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../common/AppConfig';
import { Logger } from '../common/Logger';
import {
  CIPHER_ALG_NAME,
  CryptoEnvelope,
  EncryptedNoteRecord,
  KDF_ALG_NAME,
  NOTE_RECORD_VERSION,
  NoteError,
  NoteErrorCode
} from '../model/NoteModels';

/**
 * 加密服务：
 * - 密钥：由用户密码经 MD5 计算后取前 16 字节作为 AES-128 密钥；
 * - 加密：AES-128-CBC + PKCS7 填充；
 * - 盐与 IV 由随机数生成并随记录持久化。
 */
export class CryptoService {
  private static readonly textEncoder: util.TextEncoder = new util.TextEncoder();
  private static readonly base64Helper: util.Base64Helper = new util.Base64Helper();

  /**
   * 使用密码对正文进行加密。
   * @param password 用户输入的加密密码
   * @param plainText 笔记正文明文
   * @returns 加密信封（盐/IV/密文，均为内存二进制）
   */
  static async encryptContent(password: string, plainText: string): Promise<CryptoEnvelope> {
    if (password.length === 0) {
      throw new NoteError(NoteErrorCode.EMPTY_PASSWORD, '请输入密码');
    }
    if (plainText.length === 0) {
      throw new NoteError(NoteErrorCode.EMPTY_CONTENT, '请输入笔记正文');
    }
    // 1. 生成盐与 IV
    const salt: Uint8Array = CryptoService.randomBytes(AppConfig.SALT_LEN);
    const iv: Uint8Array = CryptoService.randomBytes(16);
    // 2. 由密码派生 AES-128 密钥
    const keyBytes: Uint8Array = await CryptoService.deriveKey(password);
    const symKey: cryptoFramework.SymKey = await CryptoService.convertToSymKey(keyBytes);
    // 3. AES-128-CBC 加密
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    const encryptParams: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: iv }
    };
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, encryptParams);
    const plainBytes: Uint8Array = CryptoService.textEncoder.encodeInto(plainText);
    const output: cryptoFramework.DataBlob = await cipher.doFinal({ data: plainBytes });
    return new CryptoEnvelope(salt, iv, new Uint8Array(), output.data);
  }

  /**
   * 使用密码与持久化记录解密正文。
   * @throws NoteError FILE_CORRUPT（记录字段损坏）、WRONG_PASSWORD_OR_CORRUPT（解密失败）
   */
  static async decryptContent(password: string, record: EncryptedNoteRecord): Promise<string> {
    if (password.length === 0) {
      throw new NoteError(NoteErrorCode.EMPTY_PASSWORD, '请输入密码');
    }
    if (record.version !== NOTE_RECORD_VERSION) {
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
    }
    let iv: Uint8Array;
    let cipherBytes: Uint8Array;
    try {
      iv = CryptoService.base64Helper.decodeSync(record.ivB64);
      cipherBytes = CryptoService.base64Helper.decodeSync(record.cipherB64);
    } catch (error) {
      Logger.error('decode base64 fields of note record failed');
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
    }
    if (cipherBytes.length === 0) {
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
    }
    const keyBytes: Uint8Array = await CryptoService.deriveKey(password);
    const symKey: cryptoFramework.SymKey = await CryptoService.convertToSymKey(keyBytes);
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    const decryptParams: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: iv }
    };
    let plainBytes: Uint8Array;
    try {
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, decryptParams);
      const output: cryptoFramework.DataBlob = await cipher.doFinal({ data: cipherBytes });
      plainBytes = output.data;
    } catch (error) {
      const err = error as BusinessError;
      Logger.error(`decrypt failed, code=${err.code}`);
      throw new NoteError(NoteErrorCode.WRONG_PASSWORD_OR_CORRUPT, '密码错误或数据损坏');
    }
    if (plainBytes.length === 0) {
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
    }
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(plainBytes);
  }

  /** 生成指定长度的随机字节 */
  private static randomBytes(len: number): Uint8Array {
    const bytes: Uint8Array = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
    return bytes;
  }

  /** 由密码计算 AES-128 密钥（MD5(密码 + 固定密钥) 取前 16 字节） */
  private static async deriveKey(password: string): Promise<Uint8Array> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    const seed: string = password + '|' + AppConfig.FIXED_AES_KEY_HEX;
    await md.update({ data: CryptoService.textEncoder.encodeInto(seed) });
    const digest: cryptoFramework.DataBlob = await md.digest();
    return digest.data.slice(0, 16);
  }

  /** 将密钥字节转换为 AES-128 对称密钥对象 */
  private static async convertToSymKey(keyBytes: Uint8Array): Promise<cryptoFramework.SymKey> {
    const keyGen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    return keyGen.convertKey({ data: keyBytes });
  }

  /** 将加密信封组装为可持久化的记录（二进制字段 base64 编码） */
  static toRecord(envelope: CryptoEnvelope, title: string, password: string): EncryptedNoteRecord {
    return {
      version: NOTE_RECORD_VERSION,
      kdfAlg: KDF_ALG_NAME,
      cipherAlg: CIPHER_ALG_NAME,
      iterations: 1,
      saltB64: CryptoService.base64Helper.encodeToStringSync(envelope.salt),
      ivB64: CryptoService.base64Helper.encodeToStringSync(envelope.iv),
      tagB64: '',
      cipherB64: CryptoService.base64Helper.encodeToStringSync(envelope.cipher),
      title: title,
      plainPassword: password
    };
  }
}
