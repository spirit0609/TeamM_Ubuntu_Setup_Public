#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN} 🚀 SSH 서버 단독 설치 스크립트를 시작합니다.${NC}"
echo -e "${BLUE}=====================================================${NC}"

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] 이 스크립트는 sudo 권한으로 실행해야 합니다.${NC}"
  echo -e "사용법: sudo bash $0"
  exit 1
fi

echo -e "${YELLOW}[1/3] 패키지 목록 업데이트 중...${NC}"
apt-get update -y || { echo -e "${YELLOW}일부 저장소 업데이트 실패, 설치를 계속 진행합니다.${NC}"; }

echo -e "${YELLOW}[2/3] openssh-server 패키지 설치 중...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server

echo -e "${YELLOW}[3/3] SSH 서비스 활성화 및 방화벽(UFW) 설정 중...${NC}"

# systemd 지원 환경 체크 및 서비스 시작
if pidof systemd > /dev/null 2>&1 || [ -d /run/systemd/system ]; then
    systemctl enable ssh
    systemctl restart ssh
else
    service ssh restart
fi

# 방화벽(UFW) 활성화 여부 확인
if command -v ufw &> /dev/null; then
    if ufw status | grep -qw "active"; then
        echo -e "${BLUE}💡 UFW 방화벽이 활성화되어 있어 SSH(Port 22) 규칙을 추가합니다.${NC}"
        ufw allow ssh
    fi
fi

echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN} 🎉 SSH 서버 설치 및 설정이 성공적으로 완료되었습니다!${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo -e "💡 외부에서 이 PC로 원격 접속이 가능합니다. (명령어: ssh 계정명@IP주소)"
echo -e "현재 SSH 서비스 상태:"

if pidof systemd > /dev/null 2>&1 || [ -d /run/systemd/system ]; then
    systemctl status ssh --no-pager | grep "Active:" || true
else
    service ssh status || true
fi