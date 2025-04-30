#!/bin/bash

# DroseraNode.sh
# Скрипт для автоматической настройки узла Drosera Network и развертывания Trap
# Основано на гайде: https://github.com/0xmoei/Drosera-Network
# Рекомендуемые системные требования: 2 ядра CPU, 4 ГБ RAM, 20 ГБ дискового пространства, Ubuntu 22.04+
# Автор: Адаптировано для Drosera Network
# Дата последнего обновления: 1 мая 2025

# Выход при любой ошибке
set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Без цвета

# Функции логирования
info() { echo -e "${GREEN}[ИНФО]${NC} $1"; }
warn() { echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1"; }
error() { echo -e "${RED}[ОШИБКА]${NC} $1"; exit 1; }

# Проверка, запущен ли скрипт от имени root
if [ "$EUID" -ne 0 ]; then
  error "Скрипт должен быть запущен от имени root. Используйте sudo."
fi

# Баннер
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}          Скрипт настройки узла Drosera Network             ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo "Этот скрипт установит зависимости, Drosera CLI, Foundry, Bun,"
echo "Docker, развернет Trap и настроит узел Operator."
echo "Убедитесь, что у вас есть кошелек с Holesky ETH и RPC для Holesky."
echo -e "${GREEN}============================================================${NC}"
sleep 2

# Запрос пользовательских данных
echo -e "${YELLOW}Пожалуйста, укажите следующие данные:${NC}"
read -p "Введите приватный ключ вашего EVM-кошелька (для Trap и Operator): " EVM_PRIVATE_KEY
read -p "Введите URL вашего Ethereum Holesky RPC (например, от Alchemy/QuickNode): " ETH_RPC_URL
read -p "Введите публичный IP-адрес вашего VPS: " VPS_IP
read -p "Введите ваш email для GitHub: " GITHUB_EMAIL
read -p "Введите ваше имя пользователя GitHub: " GITHUB_USERNAME

# Проверка введенных данных
[ -z "$EVM_PRIVATE_KEY" ] && error "Приватный ключ EVM обязателен."
[ -z "$ETH_RPC_URL" ] && error "URL Ethereum Holesky RPC обязателен."
[ -z "$VPS_IP" ] && error "IP-адрес VPS обязателен."
[ -z "$GITHUB_EMAIL" ] && error "Email для GitHub обязателен."
[ -z "$GITHUB_USERNAME" ] && error "Имя пользователя GitHub обязательно."

info "Начало настройки узла Drosera Network..."

# 1. Обновление системы и установка зависимостей
info "Обновление системы и установка зависимостей..."
apt-get update && apt-get upgrade -y
apt install -y curl ufw iptables build-essential git wget lz4 jq make gcc nano \
  automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev \
  libleveldb-dev tar clang bsdmainutils ncdu unzip

# 2. Установка Docker
info "Установка Docker..."
apt update -y && apt upgrade -y
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  apt-get remove -y $pkg || true
done
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(source /etc/os-release && echo $VERSION_CODENAME) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update -y && apt upgrade -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
info "Проверка установки Docker..."
docker run hello-world || error "Установка Docker не удалась."

# 3. Установка Drosera CLI
info "Установка Drosera CLI..."
curl -L https://app.drosera.io/install | bash
info "Обновление PATH для Drosera CLI..."
export PATH=$PATH:/root/.drosera/bin
source /root/.bashrc
# Проверка доступности droseraup
if ! command -v droseraup &> /dev/null; then
  warn "Команда droseraup не найдена, пытаемся исправить..."
  echo 'export PATH=$PATH:/root/.drosera/bin' >> /root/.bashrc
  source /root/.bashrc
  sleep 2
fi
if ! command -v droseraup &> /dev/null; then
  error "Drosera CLI не установлен или команда droseraup недоступна."
fi
droseraup || error "Выполнение droseraup не удалось."
info "Drosera CLI установлен. Версия: $(drosera --version)"

# 4. Установка Foundry CLI
info "Установка Foundry CLI..."
curl -L https://foundry.paradigm.xyz | bash
source /root/.bashrc
foundryup || error "Установка Foundry CLI не удалась."
info "Foundry CLI установлен. Версия: $(forge --version)"

# 5. Установка Bun
info "Установка Bun..."
curl -fsSL https://bun.sh/install | bash
source /root/.bashrc
info "Bun установлен. Версия: $(bun --version)"

# 6. Настройка брандмауэра
info "Настройка брандмауэра..."
ufw allow ssh
ufw allow 22
ufw allow 31313/tcp
ufw allow 31314/tcp
ufw enable
ufw status

# 7. Развертывание Trap
info "Настройка и развертывание Trap..."
mkdir -p /root/my-drosera-trap
cd /root/my-drosera-trap

info "Настройка Git..."
git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "$GITHUB_USERNAME"

info "Инициализация проекта Trap..."
forge init -t drosera-network/trap-foundry-template
bun install

info "Компиляция Trap с использованием Docker..."
docker run -v $(pwd):/app -w /app ghcr.io/foundry-rs/foundry:latest forge build || \
  warn "Предупреждения во время компиляции ожидаемы и могут быть проигнорированы."

info "Проверка доступности RPC..."
curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$ETH_RPC_URL" | grep -q "result" || \
  error "RPC URL недоступен или некорректен. Проверьте ваш Holesky RPC."

info "Развертывание Trap..."
export DROSERA_PRIVATE_KEY="$EVM_PRIVATE_KEY"
for attempt in {1..3}; do
  if drosera apply --eth-rpc-url "$ETH_RPC_URL"; then
    break
  else
    warn "Попытка $attempt: Развертывание Trap не удалось, повтор через 5 секунд..."
    sleep 5
    if [ $attempt -eq 3 ]; then
      error "Развертывание Trap не удалось после 3 попыток. Проверьте RPC и кошелек."
    fi
  fi
done
echo "ofc" | drosera apply --eth-rpc-url "$ETH_RPC_URL"

info "Trap развернут. Проверьте ваш Trap на https://app.drosera.io/ в разделе 'Traps Owned'."
info "Пожалуйста, посетите панель управления, подключите ваш EVM-кошелек и отправьте Bloom Boost с Holesky ETH."

# 8. Добавление Operator в белый список
info "Добавление адреса Operator в белый список..."
EVM_PUBLIC_ADDRESS=$(drosera-operator address --eth-private-key "$EVM_PRIVATE_KEY")
echo -e "\nprivate_trap = true\nwhitelist = [\"$EVM_PUBLIC_ADDRESS\"]" >> drosera.toml
drosera apply --eth-rpc-url "$ETH_RPC_URL" || error "Не удалось обновить конфигурацию Trap."
info "Адрес Operator добавлен в белый список."

# 9. Установка Drosera Operator CLI
info "Установка Drosera Operator CLI..."
cd /root
curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
cp drosera-operator /usr/bin
drosera-operator --version || error "Установка Drosera Operator CLI не удалась."
info "Drosera Operator CLI установлен. Версия: $(drosera-operator --version)"

# 10. Загрузка Docker-образа
info "Загрузка Docker-образа Drosera Operator..."
docker pull ghcr.io/drosera-network/drosera-operator:latest

# 11. Регистрация Operator
info "Регистрация Operator..."
drosera-operator register --eth-rpc-url "$ETH_RPC_URL" --eth-private-key "$EVM_PRIVATE_KEY" || \
  error "Регистрация Operator не удалась."

# 12. Настройка и запуск Operator с Docker
info "Настройка Drosera Operator с использованием Docker..."
cd /root
git clone https://github.com/0xmoei/Drosera-Network
cd Drosera-Network
cp .env.example .env

info "Настройка файла .env..."
sed -i "s|ETH_PRIVATE_KEY=.*|ETH_PRIVATE_KEY=$EVM_PRIVATE_KEY|" .env
sed -i "s|VPS_IP=.*|VPS_IP=$VPS_IP|" .env

info "Настройка файла docker-compose.yaml..."
sed -i "s|--eth-rpc-url .* --|--eth-rpc-url $ETH_RPC_URL --|" docker-compose.yaml

info "Запуск узла Operator..."
docker compose up -d || error "Не удалось запустить узел Operator."
sleep 10
info "Проверка состояния узла Operator..."
docker logs -f drosera-node | tail -n 20
warn "Примечание: предупреждения 'Failed to gossip message: InsufficientPeers' являются нормальными."

# 13. Подключение к Trap
info "Пожалуйста, посетите https://app.drosera.io/, войдите с вашим EVM-кошельком и нажмите 'Opt-in' для подключения Operator к Trap."
info "Либо вы можете подключиться через CLI после проверки в панели управления."
read -p "Введите адрес вашего Trap (из панели управления) для подключения через CLI (или нажмите Enter, чтобы пропустить): " TRAP_ADDRESS
if [ -n "$TRAP_ADDRESS" ]; then
  drosera-operator optin --eth-rpc-url "$ETH_RPC_URL" --eth-private-key "$EVM_PRIVATE_KEY" --trap-config-address "$TRAP_ADDRESS" || \
    warn "Подключение через CLI не удалось. Пожалуйста, выполните подключение через панель управления."
fi

# 14. Финальные инструкции
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}          Настройка узла Drosera завершена!                 ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo "Ваш узел Drosera Operator запущен."
echo "Проверьте активность узла на https://app.drosera.io/ (ищите зеленые блоки)."
echo "Полезные команды:"
echo "  - Остановить узел: cd ~/Drosera-Network && docker compose down -v"
echo "  - Перезапустить узел: cd ~/Drosera-Network && docker compose up -d"
echo "  - Проверить логи: docker logs -f drosera-node"
echo "Если вы столкнулись с белыми блоками или проблемами, обратитесь к гайду:"
echo "https://github.com/0xmoei/Drosera-Network"
echo -e "${GREEN}============================================================${NC}"

exit 0
