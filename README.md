## 사전 준비

- 루트 계정으로 전환한 뒤 스크립트 실행한다.
```bash
su root
```
- 스크립트 실행 시 필요한 의존성 패키지를 설치한다.
```bash
apt install -y debootstrap squashfs-tools xorriso
```

## 파일 개요

### 주요 스크립트

- `package_common.sh`: 공통 스크립트
- `package_env_setup.sh`: ISO 빌드 환경 설정 (chroot, squashfs 등)
- `package_iso.sh`: ISO 이미지 생성

### 설정 파일

- `pvepackage/`: ISO 빌드 시 포함할 `.deb` 파일을 복사할 디렉토리
- `pvetheme/`
    - `logo.png`: ISO 로고 이미지
    - `theme.txt`: ISO 테마 설정
- `.cd-info`: ISO 메타 데이터 (릴리즈 버전, 커널, 미러 등)
- `grub.cfg`: GRUB 부트로더 설정

## 사용 방법

### 1. 환경 설정

스크립트를 실행하여 빌드 환경을 설정한다.

```bash
./package_env_setup.sh
```

- ISO 파일 시스템 디렉토리 생성
- Proxmox VE 패키지 다운로드
- 기본 squashfs 파일 생성

### 2. 추가 패키지 복사 (선택)

ISO 빌드 시 포함할 `.deb` 패키지를 `/pvepackage` 폴더에 복사한다.

```bash
# 예시
cd /d/pve-iso-builder
cp /d/proxmox/pve-manager/*.deb ./pvepackage/
```

### 3. ISO 빌드

스크립트를 실행하여 최종 ISO 이미지를 생성한다.

```bash
./package_iso.sh
```

- GRUB 부트로더 설치 및 설정
- EFI 이미지 생성
- 최종 ISO 파일 생성

스크립트 실행이 완료되면 다음 경로에 ISO 파일이 생성된다.

```bash
/tmp/pve-<REALEASE>/proxmox-ve-<RELEASE>-<ISORELEASE>-<ARCH>-<DATE>.iso
```

### 4. 패키지 목록 생성 (선택)

스크립트를 실행하여 Proxmox VE 패키지 목록을 생성한다.

```bash
./genpackage.sh
```
