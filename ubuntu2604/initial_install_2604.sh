#!/usr/bin/env bash
set -eu

# =========================================================================
# Ubuntu 26.04 LTS 통합 초기 설정 스크립트
# (기본 도구 + Sticky + Docker + Sublime + Samba + BRLTTY 제거 + ROS 2 WS + Tailscale)
# =========================================================================

# 루트 권한 확인
if [ "$(id -u)" -ne 0 ]; then
  echo "[오류] 이 스크립트는 루트(sudo) 권한으로 실행해야 합니다."
  echo "       예: sudo ./setup_ubuntu2604_full.sh"
  exit 1
fi

# 실행 사용자 및 홈 디렉터리 자동 감지
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

echo "========================================================================="
echo " Ubuntu 26.04 통합 환경 설정 시작"
echo " 대상 사용자: ${TARGET_USER} (${TARGET_HOME})"
echo "========================================================================="

# 1. 시스템 최신화
echo "[단계 1/10] 시스템 패키지 업데이트 및 업그레이드..."
apt-get update
apt-get upgrade -y
apt-get autoremove --purge -y

# 2. 필수 빌드 도구, 유틸리티 및 PPA 관리 도구 설치
echo "[단계 2/10] 기본 개발 도구 및 유틸리티(Terminator, GParted, Samba 등) 설치..."
apt-get install -y \
    curl \
    wget \
    git \
    lsb-release \
    build-essential \
    libssl-dev \
    ca-certificates \
    gnupg \
    software-properties-common \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-argcomplete \
    python3-colcon-common-extensions \
    terminator \
    gparted \
    samba

# 3. Sticky Notes (PPA) 설치
echo "[단계 3/10] Sticky Notes (PPA: kelebek333/mint-tools) 설치..."
add-apt-repository -y ppa:kelebek333/mint-tools
apt-get update
apt-get install -y sticky
echo " * Sticky Notes 설치 완료."

# 4. Docker Engine 설치 및 사용자 그룹 추가
echo "[단계 4/10] Docker 공식 저장소 등록 및 Docker Engine 설치..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker 실행 권한 부여 (sudo 없이 사용)
usermod -aG docker "$TARGET_USER"
systemctl enable --now docker
echo " * Docker 설치 및 ${TARGET_USER} 계정 그룹 추가 완료."

# 5. Sublime Text 설치 (Snap)
echo "[단계 5/10] Sublime Text 설치 (Snap)..."
if ! command -v subl &> /dev/null; then
    snap install sublime-text --classic
    echo " * Sublime Text 설치 완료."
else
    echo " * Sublime Text가 이미 설치되어 있습니다."
fi

# 6. BRLTTY 비활성화 및 제거 (USB 시리얼 충돌 방지)
echo "[단계 6/10] BRLTTY 서비스 및 충돌 udev 규칙 제거..."
systemctl mask brltty.path || true
if dpkg -s brltty &> /dev/null; then
    apt-get remove -y brltty
fi
for f in /usr/lib/udev/rules.d/*brltty*.rules; do
    if [ -e "$f" ]; then
        ln -sf /dev/null "/etc/udev/rules.d/$(basename "$f")"
    fi
done
udevadm control --reload-rules

# 7. Python 가상환경(venv) 생성 및 수치 연산 라이브러리 설치
echo "[단계 7/10] Python 가상환경(venv) 설정 및 NumPy/SciPy 설치..."
VENV_DIR="${TARGET_HOME}/venvs/default_env"
if [ ! -d "$VENV_DIR" ]; then
    sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/venvs"
    sudo -u "$TARGET_USER" python3 -m venv "$VENV_DIR"
    sudo -u "$TARGET_USER" "$VENV_DIR/bin/pip" install --upgrade pip
    sudo -u "$TARGET_USER" "$VENV_DIR/bin/pip" install numpy scipy
    echo " * 가상환경 생성 완료: ${VENV_DIR}"
fi

# 8. ROS 2 워크스페이스 디렉터리 생성
echo "[단계 8/10] ROS 2 워크스페이스(~/ros2_ws/src) 생성..."
sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/ros2_ws/src"
echo " * ${TARGET_HOME}/ros2_ws/src 디렉터리 생성 완료."

# 9. Samba 파일 공유 설정
echo "[단계 9/10] Samba 서버 공유 디렉터리 구성..."
SHARE_NAME="ubuntu_share"
SAMBA_CONFIG="/etc/samba/smb.conf"

if ! grep -q "^\s*\[${SHARE_NAME}\]" "$SAMBA_CONFIG"; then
    cat <<EOF >> "$SAMBA_CONFIG"

[${SHARE_NAME}]
    comment = Ubuntu Share for ${TARGET_USER}
    path = ${TARGET_HOME}
    create mask = 0777
    directory mask = 0777
    writable = yes
    read only = no
    browsable = yes
    valid users = ${TARGET_USER}
    force user = ${TARGET_USER}
EOF
    echo " * ${SAMBA_CONFIG}에 [${SHARE_NAME}] 설정 추가 완료."
fi

systemctl enable smbd nmbd
systemctl restart smbd nmbd

# 10. Tailscale VPN 설치 (선택 사항)
echo "[단계 10/10] Tailscale VPN 설치..."
read -r -p " * Tailscale VPN을 설치하시겠습니까? (y/N): " INSTALL_TAILSCALE || true
case "${INSTALL_TAILSCALE:-n}" in
    [Yy]|[Yy][Ee][Ss])
        curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).noarmor.gpg" | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).tailscale-keyring.list" | tee /etc/apt/sources.list.d/tailscale.list
        apt-get update
        apt-get install -y tailscale
        systemctl enable --now tailscaled
        echo " * Tailscale 설치 완료."
        ;;
    *)
        echo " * Tailscale 설치 건너뜀."
        ;;
esac

# 11. .bashrc 통합 환경 변수 설정
echo "--- .bashrc 환경 변수 및 단축 설정 추가 ---"
BASHRC="${TARGET_HOME}/.bashrc"
ENV_TAG="# --- Added by Ubuntu 26.04 Setup Script ---"

if ! grep -qF "$ENV_TAG" "$BASHRC"; then
    cat <<'EOF' >> "$BASHRC"

# --- Added by Ubuntu 26.04 Setup Script ---
# Python Default Venv Auto-Activation
if [ -f ~/venvs/default_env/bin/activate ]; then
    source ~/venvs/default_env/bin/activate
fi

docker ps

# export ROS_DOMAIN_ID=100

if [ -f /opt/ros/lyrical/setup.bash ]; then
    source /opt/ros/lyrical/setup.bash
fi

if [ -f /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash ]; then
    source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash
fi

if [ -f ~/ros2_ws/install/setup.bash ]; then
    source ~/ros2_ws/install/setup.bash
fi
# ------------------------------------------
EOF
    echo " * .bashrc 설정 등록 완료."
fi

echo "========================================================================="
echo " 모든 초기 설정이 완료되었습니다!"
echo "========================================================================="
echo " [안내 및 후속 조치]"
echo " 1. Docker 그룹 적용: 현재 세션을 로그아웃 후 다시 로그인하세요."
echo " 2. Samba 비밀번호 설정: sudo smbpasswd -a ${TARGET_USER}"
echo " 3. ROS 2 Lyrical 환경: 'colcon build' 완료 후 ~/ros2_ws 패키지가 자동 인식됩니다."
echo "========================================================================="