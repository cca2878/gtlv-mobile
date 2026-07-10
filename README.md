# gtlv-mobile · gtlv-go 的 gomobile 适配层（Android AAR）

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](./LICENSE)

把 [gtlv-go](https://github.com/cca2878/gtlv-go)（极验验证码求解库，纯 WASM、无 CGO）经 [gomobile](https://pkg.go.dev/golang.org/x/mobile/cmd/gomobile) 封装成 **Android AAR**，供 Java/Kotlin 直接调用。

## 为什么单独一个仓库

gtlv-go 是一个**纯 Go-native 库**，公开 API 用到了 context、functional options、类型化错误、切片等——这些 gomobile **绑定不了**。本仓库只做一件事：把它的 API **压平**成 gomobile 能绑定的极小类型面（`string` 进、`string` 出、`error`），并承担 gomobile 引入的 cgo/NDK/AAR 全部负担。

这样上游库保持纯净、可被普通 `go get` 使用、离线可测；移动端的复杂度全部隔离在这里，两边发布节奏各自独立。

```
Android App ──(Gradle aar)──▶ gtlv-mobile（本仓，扁平 API + gomobile bind）
                                   └─(go get)─▶ gtlv-go（纯 Go 求解 + 协议）
```

## 安装（Android 消费方）

发布在 **GitHub Packages（Maven）**，用干净的坐标 `com.cca2878:gtlv:<version>` 引入，享受 Gradle 的版本/依赖管理。GitHub Packages 的 Maven 仓即便是公开包也要求认证，故消费方需一个具 `read:packages` 权限的 GitHub token。

`settings.gradle.kts`（dependencyResolutionManagement）或模块的 `repositories`：

```kotlin
maven {
    url = uri("https://maven.pkg.github.com/cca2878/gtlv-mobile")
    credentials {
        username = providers.gradleProperty("gpr.user").orElse(providers.environmentVariable("GITHUB_ACTOR")).get()
        password = providers.gradleProperty("gpr.token").orElse(providers.environmentVariable("GITHUB_TOKEN")).get()
    }
}
```

`app/build.gradle.kts`：

```kotlin
dependencies {
    implementation("com.cca2878:gtlv:0.1.0")
}
```

在 `~/.gradle/gradle.properties` 放凭据（不要提交进仓库）：

```properties
gpr.user=<你的 GitHub 用户名>
gpr.token=<具 read:packages 的 PAT>
```

> 消费方**不需要**安装 Go / gomobile / NDK——AAR 已是编好的二进制（含 arm64-v8a 与 x86_64 两个 ABI）。此外每次 CI 也会把 `gtlv.aar` 作为 **workflow 制品**上传，可直接从任意一次运行下载拿去真机测（见 [CI](#ci)）。

## 使用（Kotlin）

```kotlin
import com.cca2878.gtlv.Client
import com.cca2878.gtlv.Gtlv

// 1) 把两个模型文件从 assets 释放到 App 私有目录（首次）：
//    yolo26n_gt_v2_384.onnx 与 siamese_feature.nnef.tgz
val modelDir = File(filesDir, "gtlv-models").apply { extractModelsIfNeeded(this) }
// 2) 编译缓存目录（持久、可写；首启冷、之后暖）
val cacheDir = File(filesDir, "gtlv-cache").apply { mkdirs() }

// 建一次，反复用（并发安全）。maxAttempts<=0 用库默认。
val client: Client = Gtlv.newClient(modelDir.absolutePath, cacheDir.absolutePath, 3)
try {
    // gt / challenge 来自你自己的业务接口（如 B 站登录下发）
    val validate: String = client.getValidate(gt, challenge) // 自动分派点选/滑动
    // 提交 validate 给业务后端
} catch (e: Exception) {
    // 识别未通过或网络/配置错误，信息在 e.message
} finally {
    client.close()
}
```

在耗时上：`getValidate` 内部要跑 wasm 推理并遵守极验「签发→提交 ≥2s」的反机器时延，**务必放到子线程**（不要在主线程调用）。

## 自行构建 AAR

需先装 **Android SDK + NDK**（CI 用 `android-actions/setup-android` 提供）：

```bash
make deps          # 安装 gomobile/gobind 并 gomobile init
make bind-android  # → gtlv.aar（+ gtlv-sources.jar）
```

只绑定 **arm64-v8a 与 x86_64** 两个 ABI：wazero 的编译器后端只支持 arm64/amd64，上游库在其它架构上按设计**编译期即报错**（`pkg/solver/unsupported.go`），故 armeabi-v7a / x86 明确不含。与 gtlv-go 的平台支持表一致。

## ⚠️ 上线前必须在真机验证：wazero 可执行内存

gtlv-go 用 wazero 的**优化编译器**在运行时把 wasm AOT 成机器码，这需要**可执行内存**。Android 对 `W^X`/`execmem` 有 SELinux 约束，**部分设备/系统版本可能不允许匿名可执行内存**。这是本适配层**唯一的运行期未知数**，无法在 CI 或桌面复现，必须在**真实 Android 设备**上冒烟：

- 若编译器后端可用 → 与桌面同速（首启冷、之后暖）。
- 若不可用 → 需在**上游库**侧切到 wazero 的**解释器后端**（纯 Go、不需可执行内存，但推理慢很多，可能压不进 2s 预算）。该开关在 `pkg/solver`（wazero runtime config），不在本仓。

建议发首个正式 tag 前，先用一台真机把 `getValidate` 跑通一次再定。

## CI

分支模型：日常提交到 **dev**，PR 合入 **main** 出正式版。

- **ci.yml**（push 到 dev/main、PR 到 main）：`check`（纯 Go gofmt/vet/build，快）；`bind`（完整 `gomobile bind` 校验，dev 上跳过——snapshot 已构建）。bind 产物作为 workflow 制品上传，可下载真机测。
- **snapshot.yml**（push 到 dev）：bind 出 AAR，发 `com.cca2878:gtlv:<VERSION>-SNAPSHOT` 到 GitHub Packages（`VERSION` 文件是当前开发版本号）。Gradle 用 `0.1.0-SNAPSHOT` 即可拉最新 dev 构建。
- **release.yml**（在 main 上打 `v*` tag）：bind 出 AAR，发**不可变正式版** `com.cca2878:gtlv:<tag 去 v>`。发版：`git tag v0.1.0 && git push origin v0.1.0`，随后把 `VERSION` bump 到下一个开发版号。

## 许可

**[AGPL-3.0](./LICENSE)**，与上游 [gtlv-go](https://github.com/cca2878/gtlv-go) 保持一致（本仓链接了 AGPL 库）。
