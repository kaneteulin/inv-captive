# InvCaptive (불편한 동거) - Paper 26.3

모든 플레이어가 **하나의 인벤토리를 공유**하고, 인벤토리 칸이 방벽으로 잠긴 상태에서
**특정 블록을 부술 때마다 칸이 하나씩 해금**되는 마인크래프트 서버 플러그인입니다.

원작: [monun/inv-captive](https://github.com/monun/inv-captive) (Noonmaru, 1.16.5) 를 Paper 26.3 용으로 이식했습니다.

## 서버 실행

1. [Java 25 이상](https://adoptium.net/) 설치
2. 이 저장소의 `server.ps1`, `server.bat` 을 빈 폴더에 받기
3. `server.bat` 더블클릭

Paper 서버, ProtocolLib, InvCaptive 플러그인(Releases 의 최신 버전), `reset.bat` 이 자동으로 설치되고 서버가 시작됩니다.
(`server.ps1` 옆에 `inv-captive` 소스 폴더가 있으면 Releases 대신 직접 빌드하며, 이때는 JDK 25 이상이 필요합니다.)
서버가 켜지면 OP 가 `/invcaptive` 를 입력해 인벤토리 잠금을 시작합니다.

## 명령어

| 명령어 | 권한 | 설명 |
|---|---|---|
| `/invcaptive` | OP | 인벤토리 잠금 초기화 |
| `/invcaptive list` | OP | 슬롯별 해금 블록 목록 (사용 기록이 월드에 남음) |
| `/invcaptive status` | 모두 | 관리자가 목록을 확인했는지 표시 |

## 월드 초기화

서버를 끈 상태에서 `.server\plugins\InvCaptive\reset.bat` 실행
→ 월드, 해금 블록 시드, 공유 인벤토리를 `.server\backup` 으로 옮기고 다음 실행 때 새로 시작합니다.

## 원본(0.2.0)과 다른 점

- Paper 26.3 / Java 25+ 대응 (서버 내부 인벤토리 구조 변경 반영), Kotlin 대신 Java
- Kotlin, ProtocolLib 플러그인 의존성 제거
- `/invcaptive list`, `/invcaptive status` 추가
- 플레이어 퇴장 시 인벤토리가 실제로 저장되도록 수정

## 릴리스 (개발자용)

`v` 로 시작하는 태그를 푸시하면 GitHub Actions 가 플러그인을 빌드해 Releases 에 올립니다.

```
git tag v0.3.0
git push origin v0.3.0
```

## 저작권 및 출처

이 저장소는 [monun/inv-captive](https://github.com/monun/inv-captive) 0.2.0 (Noonmaru, GPL-3.0) 의 수정본입니다.
2026-11-20 kaneteulin 이 아래와 같이 수정했습니다. 각 파일 상단에도 출처와 수정 내용이 적혀 있습니다.

| 파일 | 출처 | 수정 내용 |
|---|---|---|
| `inv-captive/src/.../InvCaptive.java` | 원작 `InvCaptive.kt` | Kotlin → Java, Paper 26.3 내부 인벤토리 구조에 맞게 이식 |
| `inv-captive/src/.../InvCaptivePlugin.java` | 원작 `InvCaptivePlugin.kt` | Kotlin → Java, `list` / `status` 명령 추가, 퇴장 시 저장 |
| `inv-captive/src/main/resources/plugin.yml` | 원작 `plugin.yml` | 의존성 제거, 권한 추가 |
| `server.ps1` | 원작 `server.ps1` | Paper 26.3 다운로드 방식, 플러그인 빌드/다운로드, 각종 수정 |
| `inv-captive/build.ps1`, `inv-captive/reset.bat`, `server.bat`, `.github/` | 새로 작성 | - |

## 라이선스

GPL-3.0 - 원작의 라이선스를 따릅니다. [LICENSE.md](LICENSE.md)
