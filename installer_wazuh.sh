#!/bin/bash
sudo apt update && sudo apt upgrade -y
#sudo apt install -y git curl apt-transport-https ca-certificates gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
#curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
#echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
#sudo apt update
#sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin


git clone https://github.com/wazuh/wazuh-docker.git -b v4.9.0
cd wazuh-docker/single-node
sudo docker compose -f generate-indexer-certs.yml run --rm generator
rm -rf docker-compose.yml
curl -O https://raw.githubusercontent.com/DDFR-sysadmin/Wazuh-SOC-Lab/main/docker-compose.yml

# ====================================================================
# НАЧАЛО БЛОКА НАСТРОЙКИ БЕЗОПАСНОСТИ И КРЕДЕНШЕНОВ
# ====================================================================
echo ""
echo "========================================================="
echo "         Настройка безопасности Wazuh SOC Lab            "
echo "========================================================="
echo ""

# 1. Запрос пароля администратора с маскировкой ввода и проверкой совпадения
while true; do
    read -s -p "Введите новый пароль для панели управления (Wazuh Admin): " WAZUH_PASS
    echo ""
    read -s -p "Повторите пароль для подтверждения: " WAZUH_PASS_CONFIRM
    echo ""
    
    if [ "$WAZUH_PASS" = "$WAZUH_PASS_CONFIRM" ]; then
        if [ ${#WAZUH_PASS} -lt 8 ]; then
            echo "[-] Ошибка: Пароль должен быть не менее 8 символов!"
            echo ""
            continue
        fi
        break
    else
        echo "[-] Ошибка: Пароли не совпадают! Попробуйте снова."
        echo ""
    fi
done

echo "[+] Пароль принят."




# 3. Создание файла .env (переменные окружения)
cat << EOF > .env
# Секреты лабораторного окружения Wazuh
INDEXER_PASSWORD=${WAZUH_PASS}
EOF

chmod 600 .env
echo "[+] Файл .env успешно создан и защищен правами доступа."

# 4. Замена жестко прописанных паролей в docker-compose.yml на переменные
# Меняем дефолтный SecretPassword на переменную индоксера
sed -i 's/INDEXER_PASSWORD=SecretPassword/INDEXER_PASSWORD=${INDEXER_PASSWORD}/g' docker-compose.yml

echo "[+] Конфигурация docker-compose.yml переведена на безопасные переменные."

# 5. Генерация Bcrypt хэша для СУБД с помощью родного контейнера Wazuh Indexer
echo "[*] Генерация криптографического хэша для базы данных (это займет пару секунд)..."
# Запускаем контейнер в рантайме только ради одной встроенной утилиты хэширования
HASH=$(sudo docker run --rm -e JAVA_HOME=/usr/share/wazuh-indexer/jdk --entrypoint /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh wazuh/wazuh-indexer:4.9.0 -p "$WAZUH_PASS" | tail -n 1 | tr -d '\r')
# 6. Безопасная подстановка хэша в internal_users.yml через Python (чтобы не сломать YAML синтаксис)
export NEW_HASH="$HASH"
python3 -c '
import os, re

new_hash = os.environ.get("NEW_HASH")
file_path = "./config/wazuh_indexer/internal_users.yml"

if os.path.exists(file_path):
    with open(file_path, "r") as f:
        text = f.read()
    
    # Регулярка ищет блок "admin:" и заменяет значение "hash" под ним
    pattern = r"(admin:\s*\n\s*hash:\s*)([^\n]+)"
    text = re.sub(pattern, r"\1" + f"\"{new_hash}\"", text, count=1)
    
    with open(file_path, "w") as f:
        f.write(text)
    print("[+] Хэш нового пароля успешно интегрирован в internal_users.yml.")
else:
    print("[-] КРИТИЧЕСКАЯ ОШИБКА: Файл ./config/wazuh_indexer/internal_users.yml не найден!")
    exit(1)
'

echo ""
echo "[+] Настройка безопасности завершена"
echo "========================================================="
echo ""
# ====================================================================
# КОНЕЦ БЛОКА НАСТРОЙКИ БЕЗОПАСНОСТИ
# ====================================================================

# ====================================================================
# НАЧАЛО БЛОКА ИНТЕГРАЦИИ КАСТОМНОГО OSSEC.CONF
# ====================================================================
echo ""
echo "========================================================="
echo "         Настройка конфигурации Wazuh Manager            "
echo "========================================================="
echo ""

# 1. Ссылка на RAW-файл твоей конфигурации
OSSEC_RAW_URL="https://raw.githubusercontent.com/DDFR-sysadmin/Wazuh-SOC-Lab/main/configs/ossec.conf"

# 2. Превентивно создаем структуру папок для рабочей директории, чтобы curl не упал
mkdir -p ./wazuh_data/wazuh_etc

# 3. Скачиваем конфиг в шаблон кластера (откуда его заберет докер при инициализации)
if curl -sSL "$OSSEC_RAW_URL" -o ./config/wazuh_cluster/wazuh_manager.conf; then
    echo "[+] Шаблон конфигурации ./config/wazuh_cluster/wazuh_manager.conf успешно заменен."
else
    echo "[-] ОШИБКА: Не удалось скачать ossec.conf с GitHub! Будет использован дефолтный конфиг."
fi

echo ""
echo "========================================================="
# ====================================================================
# КОНЕЦ БЛОКА ИНТЕГРАЦИИ КАСТОМНОГО OSSEC.CONF
# ====================================================================

sudo docker compose up -d
