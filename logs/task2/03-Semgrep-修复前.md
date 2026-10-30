[Semgrep] 工程: /Users/annya/Documents/ustc/harmonyOS/assignment4/task2-vulnerable
[Semgrep] 规则: /Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/rules/arkts-security.yml
[Semgrep] 结果: 发现 13 处问题，解析错误 0 个
  ERROR   arkts-http-plaintext               common/AppConfig.ets:7
          static readonly SAMPLE_URL: string = 'http://httpbin.org/get';
  ERROR   arkts-hardcoded-secret             common/AppConfig.ets:9
          static readonly SAMPLE_API_TOKEN: string = 'sk-live-7d91f2c3a8e4b5d6e0f1a2b3c4d5';
  ERROR   arkts-hardcoded-secret             common/AppConfig.ets:11
          static readonly FIXED_AES_KEY_HEX: string = '00112233445566778899aabbccddeeff';
  ERROR   arkts-ability-exported-true        module.json5:40
          "name": "NoteDetailAbility",
  ERROR   arkts-insecure-cipher-mode         service/CryptoService.ets:46
          const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
  ERROR   arkts-insecure-cipher-mode         service/CryptoService.ets:82
          const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
  ERROR   arkts-unsecure-random              service/CryptoService.ets:108
          bytes[i] = Math.floor(Math.random() * 256);
  ERROR   arkts-weak-hash                    service/CryptoService.ets:115
          const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
  ERROR   arkts-plaintext-password-persisted service/CryptoService.ets:140
          plainPassword: password
  WARNING arkts-file-path-trust-input        service/FileService.ets:28
          return context.filesDir + '/' + title + '.json';
  WARNING arkts-token-in-header-over-http    service/NetworkService.ets:27
          header: { 'Authorization': 'Bearer ' + AppConfig.SAMPLE_API_TOKEN },
  ERROR   arkts-sensitive-log                viewmodel/NoteViewModel.ets:48
          console.log(`save note ok, title=${title}, password=${password}, content=${content}`);
  ERROR   arkts-sensitive-log                viewmodel/NoteViewModel.ets:79
          console.log(`load note ok, password=${password}, content=${content}`);
